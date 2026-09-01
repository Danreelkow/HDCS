#!/bin/sh
set -eu

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
DRY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [ "$DRY" = 0 ]; then
  mkdir -p "$DST"
fi

if command -v rsync >/dev/null 2>&1; then
  TOOL=rsync
  rsync -a --delete ${DRY:+--dry-run} "$SRC"/ "$DST"/
  COUNT=$(find "$SRC" -mindepth 1 -maxdepth 1 | wc -l)
else
  TOOL=cp-fallback
  if [ "$DRY" = 1 ]; then
    echo "[dry-run] would copy $SRC/ -> $DST/ (cp -a fallback)"
    COUNT=$(find "$SRC" -mindepth 1 -maxdepth 1 | wc -l)
  else
    COUNT=0
    find "$SRC" -mindepth 1 -maxdepth 1 | while read -r f; do
      rm -rf "$DST/$(basename "$f")"
      cp -a "$f" "$DST"/
    done
    COUNT=$(find "$SRC" -mindepth 1 -maxdepth 1 | wc -l)
  fi
fi

echo "sync-hermes-context: src=$SRC dst=$DST mode=$([ "$DRY" = 1 ] && echo dry-run || echo run) tool=$TOOL files=$COUNT"

