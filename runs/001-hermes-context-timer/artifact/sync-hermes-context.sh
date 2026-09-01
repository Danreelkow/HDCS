#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror of the hermes context into the workspace.
# Standalone-runnable (no systemd, no rsync required). Never writes to SRC.
# BusyBox-compatible: uses no find -printf, only POSIX-safe constructs.
set -euo pipefail

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG="${HERMES_CONTEXT_LOG:-}"
DRY_RUN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --log)
      shift
      [ "$#" -gt 0 ] || { echo "error: --log requires a FILE argument" >&2; exit 2; }
      LOG="$1"
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if [ ! -d "$SRC" ]; then
  echo "error: SRC directory does not exist: $SRC" >&2
  exit 1
fi

# List top-level entry names of a directory, one per line, sorted (read-only).
list_entries() {
  # $1 = directory
  for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ -e "$entry" ] || continue
    printf '%s\n' "${entry##*/}"
  done | sort
}

if [ "$DRY_RUN" -eq 1 ]; then
  # Dry run: zero writes to any fs target (DST, log), stdout only.
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --dry-run "$SRC"/ "$DST"/
  else
    echo "planned copy:"
    list_entries "$SRC" | while IFS= read -r entry; do
      if [ -e "$DST/$entry" ]; then
        echo "  update: $entry"
      else
        echo "  copy:   $entry"
      fi
    done
    echo "planned deletions:"
    if [ -d "$DST" ]; then
      list_entries "$DST" | while IFS= read -r entry; do
        if [ ! -e "$SRC/$entry" ]; then
          echo "  delete: $entry"
        fi
      done
    fi
  fi
  exit 0
fi

# Real run
mkdir -p "$DST"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SRC"/ "$DST"/
else
  mkdir -p "$DST"
  cp -a "$SRC"/. "$DST"/
  # Reconciliation pass: delete entries in DST not present in SRC (mirror --delete)
  list_entries "$DST" | while IFS= read -r entry; do
    if [ ! -e "$SRC/$entry" ]; then
      rm -rf -- "$DST/$entry"
    fi
  done
fi

if [ -n "$LOG" ]; then
  printf '%s mode=%s src=%s dst=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
    "$(command -v rsync >/dev/null 2>&1 && echo rsync || echo cp-fallback)" \
    "$SRC" "$DST" >> "$LOG"
fi

exit 0

