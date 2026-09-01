#!/usr/bin/env bash
# sync-hermes-context.sh — mirror /opt/data/workspace/hermes-context/ -> /workspace/hermes-context/
# Laws: A1-A21 (see register). Stage -> content-verify -> touch DST (A13). Guards cite A-numbers (A19).
set -u

MODE_SYNC=0; MODE_DRY=0; MODE_VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE_DRY=1 ;;
    --verify)  MODE_VERIFY=1 ;;
    *) echo "unknown argument: $arg (supported: --dry-run, --verify)" >&2; exit 2 ;;
  esac
done

refuse() { echo "refused: $*" >&2; exit 1; }
die()   { echo "error: $*" >&2; exit 1; }

# --- 1a. resolve SRC/DST from env or defaults (A17) ---
SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"

# strip trailing slashes (canonical lexical form; all mutations go through these)
norm() {
  local p="$1"
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  printf '%s' "$p"
}
# boundary-aware containment (component split via slash delimiter, never string prefix) (A15)
contains() { # $1=ancestor $2=descendant -> 0 if $2 == $1 or inside $1
  [ "$2" = "$1" ] && return 0
  case "$2/" in "$1"/*) return 0 ;; *) return 1 ;; esac
}

SRC_N=$(norm "$SRC"); DST_N=$(norm "$DST")

# --- 1b. guards BEFORE any write, zero side effects ---
# A18: degenerate paths (component tests, not slash-suffix strings)
for v in "$SRC_N" "$DST_N"; do
  [ -z "$v" ] && refuse "A18: degenerate path (empty)"
  [ "$v" = "/" ] && refuse "A18: degenerate path (root '/')"
  [ "$v" = "." ] && refuse "A18: degenerate path ('.')"
done

SRC_R=$(realpath -m -- "$SRC_N") || refuse "A12: cannot resolve SRC path"
DST_R=$(realpath -m -- "$DST_N") || refuse "A12: cannot resolve DST path"
[ "$SRC_R" = "/" ] && refuse "A18: SRC resolves to root '/'"
[ "$DST_R" = "/" ] && refuse "A18: DST resolves to root '/'"

# A12: identity / ancestor / descendant / DST-inside-SRC (realpath-based, symlink-resolved)
[ "$SRC_R" = "$DST_R" ] && refuse "A12: realpath(SRC) == realpath(DST)"
contains "$SRC_R" "$DST_R" && refuse "A12: DST resolves inside SRC (realpath)"
contains "$DST_R" "$SRC_R" && refuse "A12: SRC resolves inside DST (realpath)"

# --- A14/A15: owned concrete paths (log FILE parent, stage parent, entrypoint dir) ---
OWN_BASE="${HOME:-/tmp}/.cache/hermes-context"
LOG_DIR="$OWN_BASE"
LOG_FILE="$LOG_DIR/sync.log"
STAGE_PARENT="$LOG_DIR/stage"

LOG_R=$(realpath -m -- "$LOG_DIR")       || refuse "A14: cannot resolve log dir"
STAGEP_R=$(realpath -m -- "$STAGE_PARENT") || refuse "A14: cannot resolve stage parent"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || refuse "A14: cannot resolve entrypoint dir"
ENTRY_R=$(realpath -m -- "$SCRIPT_DIR")  || refuse "A14: cannot resolve entrypoint dir"

for owned in "$LOG_R" "$STAGEP_R" "$ENTRY_R"; do
  [ "$owned" = "$SRC_R" ] && refuse "A14: owned path ($owned) == SRC"
  [ "$owned" = "$DST_R" ] && refuse "A14: owned path ($owned) == DST"
  contains "$SRC_R" "$owned" && refuse "A14: owned path ($owned) inside SRC"
  contains "$DST_R" "$owned" && refuse "A14: owned path ($owned) inside DST"
  contains "$owned" "$DST_R" && refuse "A14: DST resolves inside owned path ($owned)"
  contains "$owned" "$SRC_R" && refuse "A14: SRC resolves inside owned path ($owned)"
done
# A20/A14: stage (under STAGEP_R) must never be inside DST or SRC
contains "$DST_R" "$STAGEP_R" && refuse "A14: stage parent inside DST"
contains "$SRC_R" "$STAGEP_R" && refuse "A14: stage parent inside SRC"

# --- 1f (helper). content-verify dstdir vs srcdir (A9/A13): files, dirs, symlinks (targets), recursive ---
verify_copy() { # $1=srcdir $2=dstdir
  s="$1"; d="$2"
  while IFS= read -r p; do
    rel="${p#./}"; sd="$s/$rel"; dd="$d/$rel"
    if [ -L "$sd" ]; then
      [ -L "$dd" ] || return 1
      [ "$(readlink -- "$sd")" = "$(readlink -- "$dd")" ] || return 1
    elif [ -d "$sd" ]; then
      { [ -d "$dd" ] && [ ! -L "$dd" ]; } || return 1
    elif [ -f "$sd" ]; then
      { [ -f "$dd" ] && [ ! -L "$dd" ]; } || return 1
      cmp -s -- "$sd" "$dd" || return 1
    else
      [ -e "$dd" ] || [ -L "$dd" ] || return 1
    fi
  done < <( cd "$s" && find . -mindepth 1 )
  while IFS= read -r p; do
    rel="${p#./}"
    { [ -e "$s/$rel" ] || [ -L "$s/$rel" ]; } || return 1
  done < <( cd "$d" && find . -mindepth 1 )
  return 0
}

# --- 1c. dry-run: plan to stdout ONLY, zero writes (A6/A16) ---
if [ "$MODE_DRY" -eq 1 ]; then
  echo "dry-run plan (no writes performed):"
  echo "  SRC: $SRC_R"
  echo "  DST: $DST_R (would be created if absent; stale entries deleted recursively)"
  if command -v rsync >/dev/null 2>&1; then
    echo "  strategy: rsync -a --delete (primary) into verified staging, then replace DST"
  else
    echo "  strategy: tar-pipe fallback + recursive stale reconciliation (A7), then replace DST"
  fi
  echo "  staging: $STAGEP_R/.hc-stage.XXXXXX (content-verified vs SRC before DST is touched, A13)"
  echo "  log: $LOG_FILE (outside DST, A8)"
  exit 0
fi

# --- verify mode: read-only; FAIL when DST absent or mismatched ---
if [ "$MODE_VERIFY" -eq 1 ]; then
  if [ ! -e "$DST_N" ] && [ ! -L "$DST_N" ]; then
    echo "verify FAIL: DST absent: $DST_N" >&2
    exit 1
  fi
  if verify_copy "$SRC_R" "$DST_N"; then
    echo "verify OK: DST matches SRC (contents, recursive dirs, symlinks)"
    exit 0
  else
    echo "verify FAIL: DST does not match SRC (A9)" >&2
    exit 1
  fi
fi

# --- 1d. real run: writes allowed from here on ---
mkdir -p "$LOG_DIR"    || die "cannot create log dir $LOG_DIR"
mkdir -p "$STAGE_PARENT" || die "cannot create stage parent $STAGE_PARENT"
# A20: stage created only AFTER guards passed; script-owned mktemp name, reserved namespace
stage=$(mktemp -d "$STAGE_PARENT/.hc-stage.XXXXXX") || die "cannot create staging dir"
cleanup() { [ -n "${stage:-}" ] && rm -rf -- "$stage" 2>/dev/null; }
trap cleanup EXIT

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }

# A16: only real runs may create DST
mkdir -p "$DST_N" || die "cannot create DST $DST_N"

# --- 1e. build MIRROR-class copy of SRC contents in stage (no nesting) ---
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --copy-links=no -- "$SRC_R/" "$stage/" || { log "FAIL: rsync staging failed"; die "rsync staging failed"; }
else
  # fallback: tar-pipe (A4), then recursive stale reconciliation (A7) via prunelist (A20)
  tar -C "$SRC_R" -cf - . | tar -C "$stage" -xf - || { log "FAIL: tar staging failed"; die "tar staging failed"; }
  pl=$(mktemp "$stage/.prunelist.XXXXXX") || { log "FAIL: prunelist mktemp failed"; die "prunelist mktemp failed"; }
  ( cd "$stage" && find . -mindepth 1 ) | while IFS= read -r p; do
    rel="${p#./}"
    if [ ! -e "$SRC_R/$rel" ] && [ ! -L "$SRC_R/$rel" ]; then
      printf '%s\n' "$rel" >> "$pl"
    fi
  done
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    rm -rf -- "${stage:?}/$rel"
  done < "$pl"
  rm -f -- "$pl"
fi

# --- 1f. content-verify stage vs SRC (A9/A13) ---
if ! verify_copy "$SRC_R" "$stage"; then
  log "FAIL: staging verification mismatch vs SRC (A9) — DST untouched"
  echo "verification FAIL: staged copy does not match SRC; DST untouched" >&2
  exit 1
fi

# --- 1g. verified copy exists elsewhere (A11): now replace DST ---
if [ -L "$DST_N" ]; then
  rm -f -- "$DST_N"   # A18: DST was symlink passing guards -> replace with real tree
else
  rm -rf -- "$DST_N"
fi
if mv -- "$stage" "$DST_N" 2>/dev/null; then
  stage=""
else
  # cross-filesystem fallback
  cp -a "$stage/." "$DST_N/" || { log "FAIL: DST replacement failed"; die "DST replacement failed"; }
fi
log "OK: synced $SRC_R -> $DST_N (verified staged copy; stale entries deleted recursively)"
echo "sync OK: $SRC_R -> $DST_N"
exit 0

