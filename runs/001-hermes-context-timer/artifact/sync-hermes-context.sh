#!/usr/bin/env bash
# sync-hermes-context.sh — mirror HERMES_CONTEXT_SRC -> HERMES_CONTEXT_DST
# Primary: rsync -a --delete. Fallback: tar-pipe copy + find-based recursive
# deletion of stale entries at every depth. Never writes inside SRC.
# Dry-run performs zero writes, including logs.

set -u

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG="${HERMES_CONTEXT_LOG:-${HOME}/.cache/hermes-context-sync.log}"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# Normalize trailing slashes
SRC="${SRC%/}/"
DST="${DST%/}/"

if [ "$DRY_RUN" -eq 1 ]; then
  # Dry-run: compute-and-compare only, no writes anywhere (no logs, no DST changes)
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --dry-run --itemize-changes "${SRC}" "${DST}"
    status=$?
  else
    # Fallback dry-run: compute-and-compare only (report what would change)
    status=0
    if [ ! -d "$DST" ]; then
      echo "dry-run: would create DST $DST"
    else
      # files that differ or are missing in DST
      (cd "$SRC" && find . -type f) | while IFS= read -r f; do
        if [ ! -f "${DST}${f#./}" ] || ! cmp -s "${SRC}${f#./}" "${DST}${f#./}"; then
          echo "dry-run: would copy ${f#./}"
        fi
      done
      # stale entries in DST absent from SRC (every depth)
      (cd "$DST" && find . -mindepth 1) | sort -r | while IFS= read -r p; do
        rel="${p#./}"
        if [ ! -e "${SRC}${rel}" ]; then
          echo "dry-run: would delete ${rel}"
        fi
      done
    fi
  fi
  exit 0
fi

# ---- real run ----
status=0
mode="rsync"

if command -v rsync >/dev/null 2>&1; then
  mkdir -p "$DST"
  rsync -a --delete "${SRC}/" "${DST}/" || status=$?
else
  mode="fallback"
  mkdir -p "$DST"
  # Copy src contents into dst (no nesting)
  if command -v tar >/dev/null 2>&1; then
    tar -C "$SRC" -cf - . | tar -C "$DST" -xf - || status=$?
  else
    cp -a "${SRC}." "$DST"/ || status=$?
  fi
  # Remove stale entries in DST absent from SRC, at every depth.
  # Process deepest-first so directories are removed after their contents.
  (cd "$DST" && find . -mindepth 1 -depth) | while IFS= read -r p; do
    rel="${p#./}"
    if [ ! -e "${SRC}${rel}" ]; then
      rm -rf -- "${DST}${rel}"
    fi
  done
fi

# One summary line per real run only
mkdir -p "$(dirname "$LOG")"
printf '%s mode=%s status=%s src=%s dst=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$mode" "$status" "$SRC" "$DST" >> "$LOG"

exit "$status"
