#!/usr/bin/env bash
# sync-hermes-context.sh — one-way host->workspace mirror (A5), hdcs/1
# Refusal authority closed list (A19): A12 identity/root, A14/A15 placement,
# A18 degenerate paths. Refusals cite A-numbers and write nothing.
set -euo pipefail

usage() {
  echo "usage: sync-hermes-context.sh [--dry-run] [--verify]" >&2
  echo "  env: SRC_DIR (default /opt/data/workspace/hermes-context/)" >&2
  echo "       DST_DIR (default /workspace/hermes-context)" >&2
  echo "       LOG_DIR (default \$HOME/.cache/hermes-context)" >&2
}

# --- defaults (A17: env override contract; deployed defaults = production) ---
SRC_DIR="${SRC_DIR:-/opt/data/workspace/hermes-context/}"
DST_DIR="${DST_DIR:-/workspace/hermes-context}"
LOG_DIR="${LOG_DIR:-$HOME/.cache/hermes-context}"

# --- flag parse ---
MODE="real"
case "${1:-}" in
  "") ;;
  --dry-run) MODE="dry" ;;
  --verify) MODE="verify" ;;
  *) usage; exit 2 ;;
esac

# --- A12 root refusal (before any write) ---
if [ "$(id -u)" -eq 0 ]; then
  echo "A12: refusing to run as root (user-scope sync only)" >&2
  exit 2
fi

# --- A18 degenerate path guard (on raw values, before realpath) ---
component_degenerate() {
  [ -z "$1" ] && return 0
  local IFS=/
  set -- $1
  [ "$#" -eq 0 ] && return 0
  [ "$#" -eq 1 ] && [ "$1" = "." ] && return 0
  return 1
}
if component_degenerate "$SRC_DIR" || component_degenerate "$DST_DIR"; then
  echo "A18: refusing degenerate path (empty, /, or .): SRC='$SRC_DIR' DST='$DST_DIR'" >&2
  exit 2
fi

is_ancestor() { # $1 ancestor-or-equal, $2 descendant — component-boundary compare
  [ "$1" = "$2" ] && return 0
  case "$2/" in
    "$1"/*) return 0 ;;
  esac
  return 1
}

# Resolve for comparison only.
SRC="$(realpath -m "$SRC_DIR")"
DST_R="$(realpath -m "$DST_DIR")"

# --- A14/A15: SRC must exist and be a directory ---
if [ ! -d "$SRC" ]; then
  echo "A14/A15: SRC does not exist or is not a directory: $SRC" >&2
  exit 2
fi

# --- A12 identity / nesting guard ---
if [ "$SRC" = "$DST_R" ]; then
  echo "A12: SRC and DST resolve to the same path: $SRC" >&2
  exit 2
fi
if is_ancestor "$SRC" "$DST_R"; then
  echo "A18: DST is inside SRC: SRC=$SRC DST=$DST_R" >&2
  exit 2
fi
if is_ancestor "$DST_R" "$SRC"; then
  echo "A18: SRC is inside DST: SRC=$SRC DST=$DST_R" >&2
  exit 2
fi

# --- A14/A15 placement guards: log dir and entrypoint dir never inside DST ---
LOG_DIR_R="$(realpath -m "$LOG_DIR")"
if [ "$LOG_DIR_R" = "$DST_R" ] || is_ancestor "$DST_R" "$LOG_DIR_R"; then
  echo "A14/A15: LOG_DIR ($LOG_DIR_R) is inside DST ($DST_R); refusing" >&2
  exit 2
fi
ENTRY_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)" || ENTRY_DIR=""
if [ -n "$ENTRY_DIR" ]; then
  if [ "$ENTRY_DIR" = "$DST_R" ] || is_ancestor "$DST_R" "$ENTRY_DIR"; then
    echo "A14/A15: entrypoint directory ($ENTRY_DIR) is inside DST ($DST_R); refusing" >&2
    exit 2
  fi
fi

# --- verify mode (read-only): recursive compare SRC vs DST ---
if [ "$MODE" = "verify" ]; then
  MISMATCH=0
  if [ ! -d "$DST_R" ]; then
    echo "verify: DST does not exist: $DST_R" >&2
    exit 1
  fi
  # stale files present in DST but not SRC
  while IFS= read -r -d '' p; do
    rel="${p#"$DST_R"/}"
    [ ! -e "$SRC/$rel" ] && { echo "stale: $rel"; MISMATCH=1; }
  done < <(find "$DST_R" -mindepth 1 -print0)
  # missing / content / symlink-target mismatches, SRC relative to DST
  while IFS= read -r -d '' p; do
    rel="${p#"$SRC"/}"
    if [ ! -e "$DST_R/$rel" ] && [ ! -L "$DST_R/$rel" ]; then
      echo "missing: $rel"; MISMATCH=1
    elif [ -L "$p" ]; then
      if [ ! -L "$DST_R/$rel" ] || [ "$(readlink "$p")" != "$(readlink "$DST_R/$rel")" ]; then
        echo "symlink-mismatch: $rel"; MISMATCH=1
      fi
    elif [ -f "$p" ]; then
      if [ -L "$DST_R/$rel" ] || ! cmp -s "$p" "$DST_R/$rel"; then
        echo "content-mismatch: $rel"; MISMATCH=1
      fi
    elif [ -d "$p" ] && [ ! -d "$DST_R/$rel" ]; then
      echo "type-mismatch: $rel"; MISMATCH=1
    fi
  done < <(find "$SRC" -mindepth 1 -print0)
  if [ "$MISMATCH" -ne 0 ]; then
    echo "verify: FAILED" >&2
    exit 1
  fi
  echo "verify: OK (DST mirrors SRC recursively: contents, structure, symlinks)"
  exit 0
fi

# --- dry-run mode (A6/A16): plan only, zero writes, never creates DST ---
if [ "$MODE" = "dry" ]; then
  echo "dry-run plan: mirror $SRC -> $DST_R (one-way, exact, stale deleted)"
  if [ ! -e "$DST_R" ] && [ ! -L "$DST_R" ]; then
    echo "would-create: $DST_R (full mirror of SRC; DST not created by this run)"
    while IFS= read -r -d '' p; do
      echo "would-create: ${p#"$SRC"/}"
    done < <(find "$SRC" -mindepth 1 -print0)
    exit 0
  fi
  diff -r --no-dereference "$SRC" "$DST_R" >/dev/null 2>&1 \
    && { echo "dry-run: DST already identical; no changes"; exit 0; }
  while IFS= read -r -d '' p; do
    rel="${p#"$DST_R"/}"
    [ ! -e "$SRC/$rel" ] && echo "would-delete: $rel"
  done < <(find "$DST_R" -mindepth 1 -print0)
  while IFS= read -r -d '' p; do
    rel="${p#"$SRC"/}"
    if [ ! -e "$DST_R/$rel" ] && [ ! -L "$DST_R/$rel" ]; then
      echo "would-create: $rel"
    elif [ -L "$p" ]; then
      [ ! -L "$DST_R/$rel" ] || [ "$(readlink "$p")" != "$(readlink "$DST_R/$rel")" ] \
        && echo "would-update: $rel"
    elif [ -f "$p" ]; then
      { [ -L "$DST_R/$rel" ] || ! cmp -s "$p" "$DST_R/$rel"; } && echo "would-update: $rel"
    elif [ -d "$p" ] && [ ! -d "$DST_R/$rel" ]; then
      echo "would-update: $rel"
    fi
  done < <(find "$SRC" -mindepth 1 -print0)
  exit 0
fi

# --- real run: stage, verify stage (A13), then swap; rsync primary, cp fallback (A5) ---
STAGE="$(mktemp -d "$LOG_DIR_R/sync-stage.XXXXXX")"
case "$STAGE" in
  "$LOG_DIR_R"/sync-stage.*) ;;
  *) echo "A14/A15: stage path invalid: $STAGE" >&2; exit 2 ;;
esac
cleanup() { [ -n "${STAGE:-}" ] && [ -d "$STAGE" ] && rm -rf "$STAGE"; }
trap cleanup EXIT

STAGE_R="$(realpath -m "$STAGE")"
if [ "$STAGE_R" = "$DST_R" ] || is_ancestor "$DST_R" "$STAGE_R"; then
  echo "A14/A15: stage ($STAGE_R) inside DST ($DST_R); refusing" >&2
  exit 2
fi

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SRC"/ "$STAGE"/
else
  cp -a "$SRC"/. "$STAGE"/
fi

# A13: content-compare staging against SRC before any DST destruction
VERIFY_OUT="$(diff -r --no-dereference "$SRC" "$STAGE" 2>&1)"
if [ -n "$VERIFY_OUT" ]; then
  echo "A13: stage verification failed; DST untouched:" >&2
  printf '%s\n' "$VERIFY_OUT" >&2
  exit 3
fi

# Swap: remove existing DST (verified copy exists in stage), move stage in
rm -rf "$DST_R"
mv "$STAGE" "$DST_R"
STAGE=""  # moved; trap must not delete

# --- real-run logging only (A6: none in dry-run) ---
mkdir -p "$LOG_DIR_R"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) sync $SRC -> $DST_R ok" >> "$LOG_DIR_R/sync.log"

echo "sync complete: $SRC -> $DST_R"
exit 0

