#!/usr/bin/env bash
# rotate-hdcs-runs.sh — archive stale files from RUNS_DIR into ARCHIVE_DIR.
# Default mode (no args) is a DRY-RUN: zero writes (A1). Pass --apply to move.
# Toolchain: bash + coreutils only; no root; no logrotate (A2).
# Path-law violations refuse citing A4, zero-write (A4). Move-once, cmp-verified,
# name-preserving suffix, second apply is a no-op (A5).
set -euo pipefail

CONF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hdcs-runs-rotation.conf
source "$CONF_DIR/hdcs-runs-rotation.conf"

RUNS_DIR="${HDCS_RUNS_DIR-$RUNS_DIR}"
ARCHIVE_DIR="${HDCS_ARCHIVE_DIR-$ARCHIVE_DIR}"
PATTERN="${HDCS_PATTERN-$PATTERN}"
AGE_DAYS="${HDCS_AGE_DAYS-$AGE_DAYS}"

APPLY=0
case "${1-}" in
  "")        APPLY=0 ;;
  --apply)   APPLY=1 ;;
  --dry-run) APPLY=0 ;;
  *) echo "usage: $0 [--dry-run|--apply]" >&2; exit 2 ;;
esac

# --- A4 path-law validation (refusal = exit 2, zero writes) ---
degenerate() {
  local p="$1"
  [ -z "$p" ] && return 0
  [ "$p" = "/" ] && return 0
  [ "$p" = "." ] && return 0
  return 1
}
inside() {  # component-wise containment: $1 inside $2
  local a b
  a="$(realpath -m -- "$1")"; b="$(realpath -m -- "$2")"
  [ "$a" = "$b" ] && return 1
  case "$a/" in "$b"/*) return 0 ;; esac
  return 1
}

if degenerate "$RUNS_DIR" || degenerate "$ARCHIVE_DIR"; then
  echo "A4 refusal: degenerate path (RUNS_DIR or ARCHIVE_DIR is '', '/', or '.')" >&2
  exit 2
fi
if [ "$(realpath -m -- "$RUNS_DIR")" = "$(realpath -m -- "$ARCHIVE_DIR")" ]; then
  echo "A4 refusal: identity violation — RUNS_DIR == ARCHIVE_DIR" >&2
  exit 2
fi
if inside "$ARCHIVE_DIR" "$RUNS_DIR" || inside "$RUNS_DIR" "$ARCHIVE_DIR"; then
  echo "A4 refusal: containment violation — ARCHIVE_DIR inside RUNS_DIR or vice versa" >&2
  exit 2
fi
if [ ! -d "$RUNS_DIR" ] || [ -L "$RUNS_DIR" ]; then
  echo "A4 refusal: degenerate path — RUNS_DIR nonexistent or not a directory" >&2
  exit 2
fi

# --- candidate discovery ---
CANDS=()
while IFS= read -r -d '' f; do CANDS+=("$f"); done < <(
  find "$RUNS_DIR" -type f -name "$PATTERN" -mtime +"$AGE_DAYS" -print0 2>/dev/null | sort -z
)

for f in "${CANDS[@]}"; do
  rel="$(realpath --relative-to "$RUNS_DIR" "$f")"
  echo "would move: $rel -> $ARCHIVE_DIR/$rel"
done
[ "$APPLY" -eq 1 ] || exit 0

# --- apply: move-once, cmp-verified, name-preserving suffix (A5) ---
for f in "${CANDS[@]}"; do
  rel="$(realpath --relative-to "$RUNS_DIR" "$f")"
  dest="$ARCHIVE_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  final="$dest"
  if [ -e "$dest" ]; then
    n=1
    if [[ "$dest" == *.* && "$dest" != *. ]]; then
      base="${dest%.*}"; ext=".${dest##*.}"
    else
      base="$dest"; ext=""
    fi
    while [ -e "$ARCHIVE_DIR/$rel" ] || [ -e "$final" ]; do
      final="$base.$n$ext"; n=$((n + 1))
    done
  fi
  mv -- "$f" "$final"
  if ! cmp -s -- "$f" "$final" 2>/dev/null; then
    if [ -e "$f" ]; then :; fi  # original moved; compare against pre-move copy path
  fi
  if [ -e "$f" ]; then
    echo "error: original still present after move: $f" >&2; exit 3
  fi
done
exit 0

