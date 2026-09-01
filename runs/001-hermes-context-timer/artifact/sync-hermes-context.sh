#!/usr/bin/env bash
# sync-hermes-context.sh — host->workspace one-way mirror of HERMES context.
# Standalone (no systemd dependency). Laws: A1–A22 of hcdl register.
set -u

# ---- 1a. flags + env resolution (A17) ---------------------------------------
DRYRUN=0
VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRYRUN=1 ;;
    --verify)  VERIFY=1 ;;
    *) echo "refused: A18: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"

# canonicalize trailing slashes ONCE; all mutation via canonical paths (ledger 7)
SRC="${SRC%/}"
DST="${DST%/}"

refuse() { echo "refused: $1: $2" >&2; exit 1; }

# ---- 1b. guards BEFORE any write (zero writes on refusal) -------------------
# A18 degenerate paths: component tests, never slash-suffix strings
case "$SRC" in
  ""|"/"|"."|"/.") refuse "A18" "degenerate SRC path: '$SRC'" ;;
esac
case "$DST" in
  ""|"/"|"."|"/.") refuse "A18" "degenerate DST path: '$DST'" ;;
esac

RSRC="$(realpath -m -- "$SRC")" || refuse "A18" "SRC unresolvable"
RDST="$(realpath -m -- "$DST")" || refuse "A18" "DST unresolvable"
case "$RSRC" in
  ""|"/"|"."|"/.") refuse "A18" "degenerate SRC realpath: '$RSRC'" ;;
esac
case "$RDST" in
  ""|"/"|"."|"/.") refuse "A18" "degenerate DST realpath: '$RDST'" ;;
esac

# A22: DST itself is a symlink at the path level -> REFUSE, never replace.
# The operator removes the symlink manually; sync never destroys a user-placed
# symlink. (A12 still covers the into-SRC case first for its specific citation.)
if [ -L "$DST" ]; then
  LTGT="$(realpath -- "$DST")" || refuse "A22" "DST symlink unresolvable"
  if [ "$LTGT" = "$RSRC" ] || case "$LTGT/" in "$RSRC"/*) true;; *) false;; esac; then
    refuse "A12" "DST symlink resolves into SRC"
  fi
  refuse "A22" "DST is a symlink (target outside SRC: $LTGT) — remove it manually; sync never replaces a user-placed symlink"
fi

# A12: identity / ancestor / descendant, either direction (realpath, component-safe)
[ "$RSRC" = "$RDST" ] && refuse "A12" "realpath(SRC) == realpath(DST)"
case "$RDST/" in "$RSRC"/*) refuse "A12" "DST inside SRC";; esac
case "$RSRC/" in "$RDST"/*) refuse "A12" "SRC inside DST (DST is ancestor of SRC)";; esac

# ---- owned concrete paths (A14/A15): computed pure, validated before creation
# Every owned path is REALPATH-RESOLVED before comparison (A15: concrete
# instantiated paths, symlink targets resolved), never raw-string compared.
LOGDIR="${XDG_CACHE_HOME:-$HOME/.cache}/hermes-context"

# resolve the log dir (and any log env var) THROUGH existing symlinks, purely:
# realpath -m performs no filesystem writes, so the zero-write guard holds.
LOGDIR_R="$(realpath -m -- "$LOGDIR")" || refuse "A14" "log dir unresolvable: $LOGDIR"
LOGFILE="$LOGDIR/sync.log"           # log ALWAYS outside DST (A8)
LOGFILE_R="$LOGDIR_R/sync.log"
if [ -L "$LOGFILE" ] || [ -e "$LOGFILE" ]; then
  LOGFILE_R="$(realpath -m -- "$LOGFILE")" || refuse "A14" "log file unresolvable: $LOGFILE"
fi
ENTRYDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)" || ENTRYDIR=""

# ledger 8: any log-related env var resolved (through symlinks) into the
# mirror tree -> refuse, write nothing
LOGENV_CANDIDATES=()
[ -n "${HERMES_CTX_LOG:-}" ] && LOGENV_CANDIDATES+=("$(realpath -m -- "$(dirname -- "$HERMES_CTX_LOG")")")
[ -n "${LOG_DIR:-}" ] && LOGENV_CANDIDATES+=("$(realpath -m -- "$LOG_DIR")")

# A14/A15 scope: owned paths are gated against DST relationships ONLY.
# Component-boundary-aware both directions; no SRC restriction is invented
# (A15 forbids over-broad refusal; the closed law list has no SRC/owned rule).
owned_check() {
  local owned="$1"
  [ -n "$owned" ] || return 0
  case "$owned/" in "$RDST"/*) refuse "A14" "owned path inside mirror tree: $owned";; esac
  case "$RDST/" in "$owned"/*) refuse "A15" "DST inside owned path: $owned";; esac
  [ "$owned" = "$RDST" ] && refuse "A14" "owned path collides with DST: $owned"
  return 0
}
for owned in "$LOGDIR_R" "$LOGFILE_R" "$ENTRYDIR" "${LOGENV_CANDIDATES[@]}"; do
  owned_check "$owned"
done

# A20: stage path is a PURE STRING plan here — no mktemp/mkdir yet.
# The instantiated stage is created (real run only) via mktemp -d under the
# validated parent, then RE-VALIDATED (A15/A22) before any copy.
STAGEPARENT="$LOGDIR"
STAGE_PLAN="$STAGEPARENT/stage"

# ---- --verify mode (ledger 12): FAIL nonzero when DST absent; OK only on exact mirror
if [ "$VERIFY" = "1" ]; then
  if [ -L "$DST" ] || [ ! -e "$DST" ]; then
    echo "FAIL: verify: DST absent (or still a symlink): $DST" >&2
    exit 1
  fi
  if diff -r --no-dereference -- "$SRC" "$DST" >/dev/null 2>&1; then
    echo "OK: DST is an exact MIRROR of SRC"
    exit 0
  fi
  echo "FAIL: verify: DST does not exactly mirror SRC" >&2
  exit 1
fi

# ---- 1c. dry-run: stdout plan ONLY; zero writes incl. logs (A6/A16) ---------
if [ "$DRYRUN" = "1" ]; then
  echo "dry-run plan (no writes performed):"
  echo "  SRC=$SRC"
  echo "  DST=$DST"
  echo "  would: mkdir -p $LOGDIR"
  echo "  would: mktemp -d stage under $STAGEPARENT, re-validate instantiated path"
  if command -v rsync >/dev/null 2>&1; then
    echo "  primary: rsync -a --delete '$SRC/' -> stage/"
  else
    echo "  fallback: cp -a SRC/. -> stage (then verified; stale reconcile at install)"
  fi
  echo "  would: content-verify stage vs SRC (MIRROR class: contents+dirs+symlinks)"
  echo "  would: install verified stage as DST (exact mirror, stale deleted)"
  echo "  would: append result to $LOGFILE"
  exit 0
fi

# ---- 1d. real run: only now may we create anything (A16) --------------------
mkdir -p -- "$LOGDIR" || { echo "FAIL: cannot create log dir $LOGDIR" >&2; exit 1; }

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOGFILE"; }

# A20/A22: mktemp -d under the VALIDATED parent; re-validate the INSTANTIATED
# path before use. TMPDIR/parent failure -> script-owned fallback stage dir.
STAGE="$(mktemp -d "$STAGEPARENT/stage.XXXXXX" 2>/dev/null)" || {
  STAGE="$STAGEPARENT/fallback-stage.$$"
  mkdir -p -- "$STAGE" || { echo "FAIL: cannot create fallback stage" >&2; exit 1; }
}
STAGE_R="$(realpath -- "$STAGE")" || { echo "FAIL: stage unresolvable" >&2; exit 1; }
owned_check "$STAGE_R"

cleanup_fail() { rm -rf -- "$STAGE" 2>/dev/null; log "FAIL: $1"; echo "FAIL: $1" >&2; exit 1; }

# ---- 1e. copy SRC contents into stage (no nesting, A4) ----------------------
if command -v rsync >/dev/null 2>&1; then
  # plain -a: symlinks copied as symlinks (MIRROR class)
  rsync -a --delete "$SRC/" "$STAGE/" || cleanup_fail "rsync staging failed"
else
  # A4-mandated fallback: cp -a semantics. The stage is freshly created, so
  # cp -a of SRC/. produces the exact recursive tree; stale-subtree deletion
  # (A5/A7) is achieved at install time by replacing DST with this tree.
  cp -a -- "$SRC/." "$STAGE/" || cleanup_fail "cp -a staging failed"
fi

# ---- 1f. content-verify stage vs SRC (A9/A13, MIRROR class) -----------------
# diff -r --no-dereference covers files, recursive dirs, and symlinks (link targets)
if diff -r --no-dereference -- "$SRC" "$STAGE" >/dev/null 2>&1; then
  :
else
  cleanup_fail "staged copy failed MIRROR verification against SRC"
fi
# VERIFIED copy now exists outside DST (A11 satisfied)

# ---- 1g. install the verified real tree as DST (A11) ------------------------
# DST is guaranteed NOT a symlink here (A22 refused earlier), so this only
# ever replaces a real directory/tree or creates DST fresh. Replacing DST
# with the verified tree deletes stale entries at every depth (A5/A7).
if [ -e "$DST" ]; then
  rm -rf -- "$DST"
fi
if ! mv -- "$STAGE" "$DST" 2>/dev/null; then
  # cross-filesystem: converge then clean stage (DST freshly removed -> exact mirror)
  mkdir -p -- "$DST"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$STAGE/" "$DST/" || cleanup_fail "cross-fs install into DST failed"
  else
    cp -a -- "$STAGE/." "$DST/" || cleanup_fail "cross-fs install into DST failed"
  fi
  rm -rf -- "$STAGE"
fi

# final assertion: DST is now the real tree, exact mirror
[ -L "$DST" ] && refuse "A22" "DST still a symlink after sync (internal error)"
diff -r --no-dereference -- "$SRC" "$DST" >/dev/null 2>&1 \
  || cleanup_fail "post-install mirror verification failed"

log "OK: mirror verified"
exit 0

