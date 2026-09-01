#!/usr/bin/env bash
# MUST_KEEP SRC default: /opt/data/workspace/hermes-context/
set -euo pipefail

SRC="${SRC:-/opt/data/workspace/hermes-context/}"
DST="${DST:-/workspace/hermes-context/}"
LOG="${LOG:-$HOME/.cache/hermes-context/sync.log}"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *)
      echo "usage: $0 [--dry-run]" >&2
      exit 2
      ;;
  esac
done

[[ -d "$SRC" ]] || { echo "SRC not a directory: $SRC" >&2; exit 1; }
[[ -d "$DST" ]] || { echo "DST not a directory: $DST" >&2; exit 1; }

# Normalize: strip trailing slash for path math; SRC/ is a dir, never a file.
SRC_DIR="${SRC%/}"
DST_DIR="${DST%/}"

if (( DRY_RUN )); then
  # A6: dry-run enumerates actions to stdout only; zero writes anywhere.
  if command -v rsync >/dev/null 2>&1; then
    echo "[dry-run] would run: rsync -a --delete \"$SRC_DIR\"/ \"$DST_DIR\"/"
    rsync -a --delete -n "$SRC_DIR"/ "$DST_DIR"/ | sed 's/^/[dry-run] rsync: /'
  else
    echo "[dry-run] rsync unavailable; would run cp-fallback reconcile:"
    # enumerate copies
    while IFS= read -r -d '' rel; do
      if [[ ! -e "$DST_DIR/$rel" ]] || ! cmp -s "$SRC_DIR/$rel" "$DST_DIR/$rel"; then
        echo "[dry-run] copy: $rel"
      fi
    done < <(find "$SRC_DIR" -type f -printf '%P\0')
    # enumerate deletions (stale at any depth)
    while IFS= read -r -d '' rel; do
      [[ -e "$SRC_DIR/$rel" ]] || echo "[dry-run] delete: $rel"
    done < <(find "$DST_DIR" -mindepth 1 -printf '%P\0')
  fi
  exit 0
fi

# Real run: ensure log location exists (never under DST — A8).
mkdir -p "$(dirname "$LOG")"
TMP_LOG="$(mktemp)"
trap 'rm -f "$TMP_LOG"' EXIT

COPIED=0
DELETED=0

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SRC_DIR"/ "$DST_DIR"/
else
  # cp-fallback: reconcile recursively, converge byte-identical at all depths.
  # 1. ensure directories exist
  while IFS= read -r -d '' rel; do
    mkdir -p "$DST_DIR/$rel"
  done < <(find "$SRC_DIR" -type d -printf '%P\0')

  # 2. copy missing/changed files (regular files and symlinks)
  while IFS= read -r -d '' rel; do
    sf="$SRC_DIR/$rel"
    df="$DST_DIR/$rel"
    if [[ ! -e "$df" ]] || [[ -L "$sf" && ! -L "$df" ]] || ! cmp -s "$sf" "$df"; then
      rm -rf "$df"
      cp -a "$sf" "$df"
      COPIED=$((COPIED + 1))
    fi
  done < <(find "$SRC_DIR" \( -type f -o -type l \) -printf '%P\0')

  # 3. delete stale entries in DST not present in SRC (all depths, dirs last)
  while IFS= read -r -d '' rel; do
    if [[ ! -e "$SRC_DIR/$rel" && ! -L "$SRC_DIR/$rel" ]]; then
      rm -rf "$DST_DIR/$rel"
      DELETED=$((DELETED + 1))
    fi
  done < <(find "$DST_DIR" -mindepth 1 -depth -printf '%P\0')
fi

# I9: exactly one summary line per real run.
printf '%s sync ok src=%s dst=%s copied=%d deleted=%d\n' \
  "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$SRC_DIR" "$DST_DIR" "$COPIED" "$DELETED" \
  >> "$LOG"
rm -f "$TMP_LOG"
trap - EXIT

