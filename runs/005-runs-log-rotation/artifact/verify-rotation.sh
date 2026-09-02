#!/usr/bin/env bash
# verify-rotation.sh — A6 verifier: exit 0 <=> conf parses AND no pending
# rotation AND archive consistent. Exotic filenames/races -> KNOWN_LIMITATIONS
# warning, never a FAIL (A7). bash+coreutils only, no root, no logrotate (A2).
set -u

CONF_DIR="$(cd "$(dirname "$0")" && pwd)"
if ! source "$CONF_DIR/hdcs-runs-rotation.conf" 2>/dev/null; then
  echo "FAIL: conf does not parse" >&2; exit 1
fi

RUNS_DIR="${HDCS_RUNS_DIR-$RUNS_DIR}"
ARCHIVE_DIR="${HDCS_ARCHIVE_DIR-$ARCHIVE_DIR}"
PATTERN="${HDCS_PATTERN-$PATTERN}"
AGE_DAYS="${HDCS_AGE_DAYS-$AGE_DAYS}"

status=0

# pending rotation check
if [ -d "$RUNS_DIR" ]; then
  pending="$(find "$RUNS_DIR" -type f -name "$PATTERN" -mtime +"$AGE_DAYS" -print -quit 2>/dev/null || true)"
  if [ -n "$pending" ]; then
    echo "FAIL: pending rotation — stale file present: $pending" >&2
    status=1
  fi
fi

# archive consistency: archived paths must lie outside RUNS_DIR
if [ -e "$ARCHIVE_DIR" ]; then
  if ! [ -d "$ARCHIVE_DIR" ]; then
    echo "FAIL: ARCHIVE_DIR exists but is not a directory" >&2; status=1
  else
    while IFS= read -r -d '' f; do
      rel="$(realpath --relative-to "$ARCHIVE_DIR" "$f")"
      if [ -d "$RUNS_DIR" ] && [ -e "$RUNS_DIR/$rel" ]; then
        echo "FAIL: archived path still pending in RUNS_DIR: $rel" >&2
        status=1
      fi
    done < <(find "$ARCHIVE_DIR" -type f -print0 2>/dev/null)
    if inside_check; then :; fi  # placeholder no-op, containment checked below
  fi
fi

inside() {
  local a b; a="$(realpath -m -- "$1" 2>/dev/null)"; b="$(realpath -m -- "$2" 2>/dev/null)"
  [ "$a" = "$b" ] && return 1
  case "$a/" in "$b"/*) return 0 ;; esac
  return 1
}
if [ -e "$ARCHIVE_DIR" ] && inside "$ARCHIVE_DIR" "$RUNS_DIR"; then
  echo "FAIL: ARCHIVE_DIR inside RUNS_DIR" >&2; status=1
fi

if [ "$status" -eq 0 ]; then
  # A7: exotic filenames / races are reported as limitations, not FAILs
  echo "KNOWN_LIMITATIONS: exotic filenames and concurrent modifications are not verified exhaustively"
  echo "verify OK"
fi
exit "$status"

