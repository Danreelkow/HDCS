#!/usr/bin/env bash
# sync-hermes-context.sh — mirror HERMES_CONTEXT_SRC -> HERMES_CONTEXT_DST
# stage -> verify -> touch-DST (A11/A13/A20); refusals cite A-numbers (A19).
set -u

DRY_RUN=0
VERIFY_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --verify)  VERIFY_ONLY=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# --- env (A17); explicit empty check BEFORE defaults (8b: never swallow "") ---
SRC="${HERMES_CONTEXT_SRC-default}"
DST="${HERMES_CONTEXT_DST-default}"
LOG_DIR="${HERMES_CONTEXT_LOG_DIR-default}"
[ -z "$SRC" ] && { echo "REFUSED A18: HERMES_CONTEXT_SRC is explicitly empty" >&2; exit 3; }
[ -z "$DST" ] && { echo "REFUSED A18: HERMES_CONTEXT_DST is explicitly empty" >&2; exit 3; }
[ -z "$LOG_DIR" ] && LOG_DIR="$HOME/.cache/hermes-context"

# canonicalize once (trailing-slash rule 7): all mutations via canonical paths
SRC="${SRC%/}"
DST="${DST%/}"
LOG_DIR="${LOG_DIR%/}"

die() { echo "REFUSED $1: $2" >&2; exit 3; }

# --- A18: degenerate paths (component test, not slash-suffix) ---
for v in "$SRC" "$DST"; do
  case "$v" in
    ""|"/"|".") die "A18" "degenerate path '$v' (must not be '/', empty, or '.')" ;;
  esac
done

# --- owned paths (A14/A15): log dir + entrypoint (script) dir, component-boundary aware ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
contains() { # contains $1 (ancestor-candidate) $2 (descendant-candidate), component test
  [ "$1" = "$2" ] && return 0
  case "$2/" in "$1"/*) return 0 ;; esac
  return 1
}

# --- A12: realpath identity / ancestor / descendant / through-symlink-into-SRC ---
RS="$(realpath -m "$SRC")" || die "A12" "cannot resolve SRC"
RD="$(realpath -m "$DST")" || die "A12" "cannot resolve DST"
[ "$RS" = "$RD" ] && die "A12" "realpath(SRC) == realpath(DST)"
if contains "$RS" "$RD"; then die "A12" "DST is inside SRC (descendant)"; fi
if contains "$RD" "$RS"; then die "A12" "SRC is inside DST (DST is an ancestor of SRC)"; fi

# --- A22: DST itself is a symlink (path level) -> refuse, never replace ---
if [ -L "$DST" ]; then
  die "A22" "DST path is a symlink; operator must remove it manually (sync never destroys a user-placed symlink)"
fi

# --- A14/A15: DST vs owned paths (stage parent, LOG_DIR, entrypoint dir) ---
STAGE_PARENT="${TMPDIR:-/tmp}"
STAGE_PARENT="${STAGE_PARENT%/}"
RS_PARENT="$(realpath -m "$STAGE_PARENT")"
if contains "$RD" "$RS_PARENT" || contains "$RS_PARENT" "$RD"; then
  die "A14/A15" "DST collides with script-owned stage area"
fi
RLD="$(realpath -m "$LOG_DIR")"
if [ "$RD" = "$RLD" ] || contains "$RLD" "$RD" || contains "$RD" "$RLD"; then
  die "A14/A15" "DST is equal to, inside, or contains the log dir (owned path)"
fi
RSD="$(realpath -m "$SCRIPT_DIR")"
if [ "$RD" = "$RSD" ] || contains "$RSD" "$RD" || contains "$RD" "$RSD"; then
  die "A14/A15" "DST collides with the entrypoint directory (owned path)"
fi

[ -d "$SRC" ] || { echo "FATAL: SRC '$SRC' is not a directory" >&2; exit 4; }

# --- A9 verification: lstat-based, never dereferences symlinks ---
verify_tree() { # verify_tree <src> <dst> -> 0 only on exact MIRROR_CLASS match
  diff -r --no-dereference "$1" "$2" >/dev/null 2>&1
}

# --- --verify mode: no writes; FAILS when DST absent (never deref) ---
if [ "$VERIFY_ONLY" -eq 1 ]; then
  if [ ! -d "$DST" ] && [ ! -L "$DST" ]; then
    echo "VERIFY FAIL: DST '$DST' does not exist" >&2
    exit 1
  fi
  if verify_tree "$SRC" "$DST"; then
    echo "VERIFY OK: '$DST' mirrors '$SRC' on MIRROR_CLASS"
    exit 0
  fi
  echo "VERIFY FAIL: '$DST' does not mirror '$SRC' (A9)" >&2
  exit 1
fi

# --- A20/A22: stage path as pure string -> validate -> THEN create -> re-validate ---
if ! STAGE="$(mktemp -d "$STAGE_PARENT/hermes-stage.XXXXXX" 2>/dev/null)"; then
  echo "WARN: TMPDIR-based mktemp failed; using script-owned fallback stage" >&2
  STAGE="$(mktemp -d "$SCRIPT_DIR/.hermes-stage.XXXXXX")" || { echo "FATAL: no stage possible" >&2; exit 4; }
fi
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT
# re-validate the INSTANTIATED stage path (A15/A22)
RST="$(realpath "$STAGE")"
if contains "$RD" "$RST" || contains "$RST" "$RD"; then
  die "A14/A15" "instantiated stage path collides with DST"
fi
if [ -L "$STAGE" ]; then die "A22" "stage path is a symlink"; fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "PLAN (dry-run, zero writes — A6/A16):"
  echo "  SRC: $SRC (realpath $RS)"
  echo "  DST: $DST (realpath $RD)"
  if [ -d "$DST" ]; then
    echo "  would mirror SRC contents into existing DST; stale entries removed (A5/A7)"
    if verify_tree "$SRC" "$DST"; then
      echo "  current state already mirrors SRC (no changes would be made)"
    else
      echo "  changes required:"
      diff -r --no-dereference "$SRC" "$DST" 2>&1 | head -50 || true
    fi
  else
    echo "  DST does not exist; would mkdir -p and mirror (real run only — dry-run must not create it, A16)"
  fi
  echo "  no log, no stage dir, no DST writes performed (A6)"
  exit 0
fi

# --- sync SRC CONTENTS into stage (no nesting) — rsync primary, cp -a fallback (A4/A7) ---
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SRC"/ "$STAGE"/ || { echo "FATAL: rsync failed" >&2; exit 4; }
else
  # fallback: fresh full copy semantics; stale subtrees at every depth are
  # eliminated because the stage is rebuilt from scratch and promoted whole
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp -a "$SRC"/. "$STAGE"/ || { echo "FATAL: cp -a fallback failed" >&2; exit 4; }
fi

# --- A13: content-compare stage vs SRC on MIRROR_CLASS before touching DST ---
if ! verify_tree "$SRC" "$STAGE"; then
  echo "FATAL: stage verification failed (A9/A13) — DST untouched" >&2
  exit 1
fi

# --- only after VERIFIED stage: promote (A11) ---
if [ -e "$DST" ] || [ -L "$DST" ]; then
  rm -rf "$DST" || { echo "FATAL: could not remove old DST" >&2; exit 4; }
fi
mkdir -p "$(dirname "$DST")"
mv "$STAGE" "$DST" || { echo "FATAL: stage promotion failed" >&2; exit 4; }
trap - EXIT

# --- log one line, OUTSIDE DST (A8) ---
mkdir -p "$LOG_DIR" 2>/dev/null || true
printf '%s synced %s -> %s\n' "$(date -Is)" "$SRC" "$DST" >> "$LOG_DIR/hermes-context.log" 2>/dev/null || true

echo "sync complete: $SRC -> $DST"
exit 0
