#!/usr/bin/env bash
# sync-hermes-context.sh — mirror SRC -> DST (contents + recursive dirs + symlinks).
# Laws: A1-A21 (see register). Standalone-safe (cron OK); systemd user unit optional.
set -u

PROG=$(basename "$0")

refuse() { echo "refused: $*" >&2; exit 1; }
die()    { echo "error: $*" >&2; exit 1; }

usage() {
  cat <<EOF
usage: $PROG [--dry-run] [--verify]
env:   HERMES_CONTEXT_SRC (default /opt/data/workspace/hermes-context/)
       HERMES_CONTEXT_DST (default /workspace/hermes-context/)
EOF
}

DRY_RUN=0
VERIFY_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --verify)  VERIFY_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $arg" ;;
  esac
done

# --- A17: env override is the mandated contract mechanism -------------------
SRC_RAW=${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}
DST_RAW=${HERMES_CONTEXT_DST:-/workspace/hermes-context/}

# --- helpers ----------------------------------------------------------------
# strip trailing slashes (keep a bare "/")
strip_slashes() {
  local p=$1
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p=${p%/}; done
  printf '%s' "$p"
}

# component-boundary-aware containment: 1 within/eq 2
path_within() {
  local a=$1 b=$2
  [ "$a" = "$b" ] && return 0
  case "$a" in "$b"/*) return 0 ;; esac
  return 1
}

# canonicalize WITHOUT writing anything (realpath -m resolves symlinks in
# existing components; -m tolerates a not-yet-existing tail). A20-safe.
canon() {
  local p
  p=$(strip_slashes "$1")
  [ -z "$p" ] && return 1
  realpath -m -- "$p" 2>/dev/null
}

# --- A18: degenerate paths (component tests on raw values) ------------------
for raw in "$SRC_RAW" "$DST_RAW"; do
  s=$(strip_slashes "$raw")
  if [ -z "$s" ] || [ "$s" = "." ] || [ "$s" = "/" ]; then
    refuse "A18: degenerate path ('$raw' resolves to empty/'.'/'/')"
  fi
done

SRC=$(canon "$SRC_RAW") || refuse "A18: cannot canonicalize SRC '$SRC_RAW'"
DST=$(canon "$DST_RAW") || refuse "A18: cannot canonicalize DST '$DST_RAW'"
[ "$SRC" = "/" ] && refuse "A18: SRC is root"
[ "$DST" = "/" ] && refuse "A18: DST is root"

# --- A12: realpath identity / ancestor / descendant / DST-inside-SRC --------
[ "$SRC" = "$DST" ] && refuse "A12: realpath(SRC) == realpath(DST) ($SRC)"
path_within "$DST" "$SRC" && refuse "A12: DST '$DST' is inside or equals SRC '$SRC' (realpath-resolved)"
path_within "$SRC" "$DST" && refuse "A12: SRC '$SRC' is inside or equals DST '$DST' (realpath-resolved)"

# --- owned concrete paths (A14/A15): log dir, stage base, entrypoint dir ----
LOGDIR=${HERMES_CONTEXT_LOG_DIR:-$HOME/.cache/hermes-context}
LOGDIR=$(strip_slashes "$LOGDIR")
[ -z "$LOGDIR" ] || [ "$LOGDIR" = "/" ] || [ "$LOGDIR" = "." ] \
  && refuse "A18: degenerate log dir"
LOGDIR_C=$(canon "$LOGDIR") || refuse "A14: cannot canonicalize log dir"
LOGFILE="$LOGDIR_C/sync.log"

ENTRY_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || ENTRY_DIR=""
[ -n "$ENTRY_DIR" ] || ENTRY_DIR=$(pwd)
ENTRY_DIR=$(canon "$ENTRY_DIR") || refuse "A14: cannot canonicalize entrypoint dir"

# stage base is computed as a PURE STRING here (A20): no mktemp/mkdir/write yet.
STAGE_BASE="$LOGDIR_C"

for owned in "$LOGDIR_C" "$STAGE_BASE" "$ENTRY_DIR"; do
  path_within "$owned" "$DST" && refuse "A14/A15: owned path '$owned' is inside DST '$DST' (A8: log/entrypoint/stage never inside mirrored tree)"
  path_within "$DST" "$owned" && refuse "A14/A15: owned path '$owned' contains DST '$DST'"
  path_within "$owned" "$SRC" && refuse "A14/A15: owned path '$owned' is inside SRC '$SRC'"
  path_within "$SRC" "$owned" && refuse "A14/A15: owned path '$owned' contains SRC '$SRC'"
done

# --- A6/A16: dry-run — plan to stdout ONLY, zero side effects ---------------
if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry-run plan (no writes performed):"
  echo "  SRC: $SRC"
  echo "  DST: $DST"
  echo "  strategy: $(command -v rsync >/dev/null 2>&1 && echo 'rsync -a --delete (primary)' || echo 'tar-pipe + prunelist reconcile (fallback)')"
  echo "  order: stage -> content-verify (A9/A13) -> replace DST (A11)"
  echo "  stale entries in DST: deleted at all depths (A5/A7)"
  echo "  log: $LOGFILE (NOT written during dry-run)"
  exit 0
fi

# --- A13: --verify compares DST to SRC directly; fails if DST absent --------
if [ "$VERIFY_ONLY" -eq 1 ]; then
  [ -e "$DST" ] || { echo "verify FAIL: DST '$DST' does not exist" >&2; exit 1; }
  if diff -r --no-dereference -q -- "$SRC" "$DST" >/dev/null 2>&1; then
    echo "verify OK: DST mirrors SRC"
    exit 0
  fi
  echo "verify FAIL: DST does not mirror SRC" >&2
  exit 1
fi

# ============================ REAL RUN (writes allowed) =====================
mkdir -p -- "$LOGDIR_C" || die "cannot create log dir $LOGDIR_C"
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOGFILE"; }

log "START src=$SRC dst=$DST strategy=$(command -v rsync >/dev/null 2>&1 && echo rsync || echo tar-fallback)"

# A20: stage base validated above; only NOW create the concrete stage (A15).
STAGE=$(mktemp -d "$STAGE_BASE/.hc-stage.XXXXXX") || die "cannot create staging dir under $STAGE_BASE"

cleanup() { [ -n "${STAGE:-}" ] && [ -d "$STAGE" ] && rm -rf -- "$STAGE"; return 0; }
trap cleanup EXIT

# --- stage copy: contents of SRC into stage (no nesting) --------------------
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete -- "$SRC/" "$STAGE/" || { log "FAIL rsync staging"; die "staging rsync failed"; }
else
  # fallback: tar pipe, then prunelist reconcile (A7/A20)
  (cd "$SRC" && tar -cf - .) | (cd "$STAGE" && tar -xf -) || { log "FAIL tar staging"; die "staging tar-pipe failed"; }
  SRC_LIST=$(mktemp "$STAGE_BASE/.hc-list.XXXXXX") || die "mktemp failed"
  STG_LIST=$(mktemp "$STAGE_BASE/.hc-list.XXXXXX") || die "mktemp failed"
  ( cd "$SRC"  && find . ) | sort > "$SRC_LIST"
  ( cd "$STAGE" && find . ) | sort > "$STG_LIST"
  PRUNE=$(mktemp "$STAGE/.prunelist.XXXXXX") || die "mktemp failed"
  comm -13 "$SRC_LIST" "$STG_LIST" | sed 's#^\./##' | grep -v '^$' > "$PRUNE" || true
  # delete stale entries deepest-first, all depths (A7)
  sort -r "$PRUNE" | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    rm -rf -- "$STAGE/$rel"
  done
  rm -f -- "$PRUNE" "$SRC_LIST" "$STG_LIST"
fi

# --- A9/A13: content-verify stage vs SRC BEFORE touching DST ----------------
if ! diff -r --no-dereference -q -- "$SRC" "$STAGE" >/dev/null 2>&1; then
  log "FAIL staging verification mismatch (A9)"
  echo "verification FAIL: staged copy does not match SRC (A9); DST untouched" >&2
  exit 1
fi
log "staging verified against SRC (A9/A13)"

# --- A11/A18: only now touch DST --------------------------------------------
# If raw DST was a symlink that passed guards (resolves outside SRC), replace
# the symlink itself with the real tree (A18).
if [ -L "$DST_RAW" ] || [ -L "$DST" ]; then
  rm -f -- "$DST_RAW" 2>/dev/null
fi
rm -rf -- "$DST"

if ! mv -- "$STAGE" "$DST" 2>/dev/null; then
  # cross-filesystem: move the VERIFIED copy via rsync/cp, then drop stage
  mkdir -p -- "$DST"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete -- "$STAGE/" "$DST/" || { log "FAIL cross-fs move"; die "cross-filesystem move failed"; }
  else
    cp -a -- "$STAGE/." "$DST/" || { log "FAIL cross-fs move"; die "cross-filesystem copy failed"; }
  fi
  rm -rf -- "$STAGE"
fi
STAGE=""

log "DONE dst=$DST mirrors src=$SRC"
echo "synced: $SRC -> $DST (verified mirror, stale entries deleted)"
exit 0

