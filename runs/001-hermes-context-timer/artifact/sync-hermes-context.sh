#!/usr/bin/env bash
# sync-hermes-context.sh — one-way host->workspace mirror (A5), hdcs/1
# Path law (closed set, A19): A12 identity, A14/A15 log+stage+entrypoint placement, A18 degenerate paths.
set -u

usage() {
  echo "usage: sync-hermes-context.sh [--dry-run]" >&2
  echo "  env: HERMES_CONTEXT_SRC (default /opt/data/workspace/hermes-context/)" >&2
  echo "       HERMES_CONTEXT_DST (default /workspace/hermes-context/)" >&2
}

# --- Δ1a defaults (A17: env override is contract) ---
# ${VAR-} (not ${VAR:-}) so an EMPTY override stays empty and is caught by A18
# below, before realpath -m can canonicalize "." or "" into a concrete path.
SRC="${HERMES_CONTEXT_SRC-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST-/workspace/hermes-context/}"

# --- Δ1b A18 degenerate-path guard: component test on RAW values, before any realpath ---
component_degenerate() {
  # empty, "/", or "." (as whole-path component decomposition)
  [ -z "$1" ] && return 0
  local IFS=/
  set -- $1
  if [ "$#" -eq 0 ]; then return 0; fi   # "/" decomposes to nothing
  [ "$#" -eq 1 ] && [ "$1" = "." ] && return 0
  return 1
}
if component_degenerate "$SRC" || component_degenerate "$DST"; then
  echo "A18: refusing degenerate path (empty, /, or .): SRC='$SRC' DST='$DST'" >&2
  exit 2
fi

# --- Δ1d flag parse ---
DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *) usage; exit 2 ;;
esac

is_ancestor() { # $1 possibly-ancestor, $2 descendant — component-boundary compare
  local a="$1" d="$2"
  [ "$a" = "$d" ] && return 0
  case "$d/" in
    "$a"/*) return 0 ;;
  esac
  return 1
}

# Resolve for comparison only; DST is kept as the RAW path so a DST symlink is
# replaced at the symlink path itself (A18: replaced by a real tree, never
# followed and never left in place).
SRC="$(realpath -m "$SRC")"
DST_R="$(realpath -m "$DST")"

# --- Δ1c A12 identity guard (precedes any write) ---
if [ "$SRC" = "$DST_R" ]; then
  echo "A12: SRC and DST resolve to the same path: $SRC" >&2
  exit 2
fi
if is_ancestor "$SRC" "$DST_R"; then
  echo "A12: DST is SRC or inside SRC (ancestor/descendant): SRC=$SRC DST=$DST_R" >&2
  exit 2
fi
if is_ancestor "$DST_R" "$SRC"; then
  echo "A12: SRC is inside DST (ancestor/descendant): SRC=$SRC DST=$DST_R" >&2
  exit 2
fi
# DST symlink resolving into SRC
if [ -L "$DST" ]; then
  DST_T="$(realpath -m "$DST")"
  if [ "$DST_T" = "$SRC" ] || is_ancestor "$SRC" "$DST_T"; then
    echo "A12: DST symlink resolves into SRC: $DST -> $DST_T" >&2
    exit 2
  fi
fi

# --- Δ1j entrypoint-directory placement guard (A14/A15) ---
ENTRY_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || ENTRY_DIR=""
if [ -n "$ENTRY_DIR" ]; then
  ENTRY_DIR="$(realpath -m "$ENTRY_DIR")"
  if [ "$ENTRY_DIR" = "$DST_R" ] || is_ancestor "$DST_R" "$ENTRY_DIR"; then
    echo "A14/A15: entrypoint directory ($ENTRY_DIR) is inside DST ($DST_R); refusing" >&2
    exit 2
  fi
fi

# --- Δ1j log placement (A14/A15) — before stage creation; A6: no log in dry-run ---
LOG_PARENT="${XDG_CACHE_HOME:-$HOME/.cache}/hermes-sync"
LOG_PARENT_R="$(realpath -m "$LOG_PARENT")"
if [ "$LOG_PARENT_R" = "$DST_R" ] || is_ancestor "$DST_R" "$LOG_PARENT_R"; then
  echo "A14/A15: resolved log parent ($LOG_PARENT_R) is inside DST ($DST_R); refusing" >&2
  exit 2
fi

# --- Δ1e A20 stage: pure string calc -> validate -> create ---
STAGE_BASE="${TMPDIR:-/tmp}"
case "$STAGE_BASE" in
  /*) ;;  # must be absolute
  *) echo "A20: TMPDIR not absolute: $STAGE_BASE" >&2; exit 2 ;;
esac
STAGE_TEMPLATE="$STAGE_BASE/hermes-sync.XXXXXX"

cleanup() { [ -n "${STAGE:-}" ] && [ -d "$STAGE" ] && rm -rf "$STAGE"; }
trap cleanup EXIT

if [ "$DRY_RUN" -eq 1 ]; then
  # --- Δ1i dry-run (A6/A16): plan only, zero writes incl. log, DST untouched ---
  if [ ! -d "$SRC" ]; then
    echo "dry-run: SRC does not exist: $SRC" >&2
    exit 3
  fi
  echo "dry-run plan: mirror $SRC -> $DST_R (one-way, exact, stale subtrees deleted)"
  if [ ! -e "$DST" ]; then
    echo "dry-run: DST absent; would be created with full mirror of SRC"
    exit 0
  fi
  diff -r --no-dereference "$SRC" "$DST" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "dry-run: DST already identical; no changes"
  else
    echo "dry-run: changes required; full mirror would reconcile DST to SRC (add/update/delete)"
  fi
  exit 0
fi

if [ ! -d "$SRC" ]; then
  echo "A13: SRC does not exist or is not a directory: $SRC" >&2
  exit 3
fi

STAGE="$(mktemp -d "$STAGE_TEMPLATE")" || { echo "A20: stage creation failed" >&2; exit 2; }
case "$STAGE" in
  "$STAGE_BASE"/hermes-sync.*) ;;
  *) echo "A20: stage path invalid: $STAGE" >&2; exit 2 ;;
esac

# --- Δ1j stage placement guard (A14/A15): concrete stage path vs realpath(DST),
#     component-boundary compare — stage must never be created inside DST ---
STAGE_R="$(realpath -m "$STAGE")"
if [ "$STAGE_R" = "$DST_R" ] || is_ancestor "$DST_R" "$STAGE_R"; then
  echo "A14/A15: stage path ($STAGE_R) is inside DST ($DST_R); refusing" >&2
  exit 2
fi

# --- Δ1f copy into stage (A4 fallback reconciles identically to rsync --delete, A5) ---
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SRC"/ "$STAGE"/ || { echo "copy into stage failed" >&2; exit 3; }
else
  # A4 fallback: cp -a semantics, reconciling to the same A5 end state as rsync --delete
  mkdir -p "$STAGE"
  cp -a "$SRC"/. "$STAGE"/ || { echo "copy into stage failed (cp fallback)" >&2; exit 3; }
fi

# --- Δ1g A13 verify stage vs SRC before any DST mutation (A9 class: contents, dirs, symlinks) ---
VERIFY_OUT="$(diff -r --no-dereference "$SRC" "$STAGE" 2>&1)"
if [ -n "$VERIFY_OUT" ]; then
  echo "A13: stage verification failed; DST untouched:" >&2
  printf '%s\n' "$VERIFY_OUT" >&2
  exit 3
fi
# Verified copy now exists in STAGE (A11 precondition satisfied).

# --- Δ1h mutate DST (only after verification) ---
# Operates on the RAW DST path: if DST is a symlink (not into SRC, per A12/A18
# above), rm below unlinks the symlink itself; the real tree replaces it (A18).
if [ -d "$DST" ] && [ ! -L "$DST" ]; then
  if diff -r --no-dereference "$SRC" "$DST" >/dev/null 2>&1; then
    echo "DST already identical to SRC; no-op"
    exit 0
  fi
  rm -rf "$DST"   # A11: verified copy exists in stage
elif [ -e "$DST" ] || [ -L "$DST" ]; then
  # DST symlink (not into SRC) or non-dir: unlink the symlink / remove, replace with real tree
  rm -rf "$DST"
fi
mv "$STAGE" "$DST" || { echo "A13: mv stage -> DST failed" >&2; exit 3; }
STAGE=""  # moved; trap must not delete it

# --- Δ1j log write (outside DST ∀ env, A8) ---
mkdir -p "$LOG_PARENT_R" 2>/dev/null || true
{
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) sync $SRC -> $DST_R ok"
} >> "$LOG_PARENT_R/hermes-sync.log" 2>/dev/null || true

echo "sync complete: $SRC -> $DST_R"
exit 0

