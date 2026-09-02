#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONF=$SCRIPT_DIR/hdcs-runs-rotation.conf
[ -r "$CONF" ] || { echo "A4: configuration is unreadable" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONF"

if [ "${HDCS_RUNS_DIR-default}" = "" ] || [ "${HDCS_ARCHIVE_DIR-default}" = "" ]; then
  echo "A4: set-but-empty directory override" >&2
  exit 1
fi
RUNS_DIR=${HDCS_RUNS_DIR-"$RUNS_DIR"}
ARCHIVE_DIR=${HDCS_ARCHIVE_DIR-"$ARCHIVE_DIR"}

bad_path() {
  local p=$1
  [ -n "$p" ] && [ "$p" != "." ] && [ "$p" != "/" ]
}
inside() {
  local child=$1 parent=$2
  [ "$child" = "$parent" ] || case "$child/" in "$parent/"*) return 0;; esac
  return 1
}
if ! bad_path "$RUNS_DIR" || ! bad_path "$ARCHIVE_DIR"; then
  echo "A4: empty, dot, or root path is forbidden" >&2
  exit 1
fi
RUNS_DIR=$(realpath -m -- "$RUNS_DIR") || {
  echo "A4: invalid runs path" >&2
  exit 1
}
ARCHIVE_DIR=$(realpath -m -- "$ARCHIVE_DIR") || {
  echo "A4: invalid archive path" >&2
  exit 1
}
if inside "$RUNS_DIR" "$ARCHIVE_DIR" || inside "$ARCHIVE_DIR" "$RUNS_DIR"; then
  echo "A4: runs and archive paths overlap" >&2
  exit 1
fi

STALE_FOUND=0
INTACT=1
now=$(date +%s)
while IFS= read -r -d '' file; do
  mtime=$(stat -c '%Y' -- "$file") || INTACT=0
  age=$(( (now - mtime) / 86400 ))
  [ "$age" -ge "$AGE_DAYS" ] && STALE_FOUND=1
done < <(find "$RUNS_DIR" -type f -name "$PATTERN" -print0 2>/dev/null)

manifest=$ARCHIVE_DIR/.hdcs-rotation.cksum
declare -A listed_paths=()
listed=0

if [ ! -f "$manifest" ]; then
  INTACT=0
else
  while IFS='|' read -r expected_sum expected_bytes rel; do
    [ -n "$rel" ] || continue
    if [ "${listed_paths[$rel]+present}" = "present" ]; then
      INTACT=0
    fi
    listed_paths["$rel"]=1
    listed=$((listed + 1))
    file=$ARCHIVE_DIR/$rel
    if [ ! -f "$file" ]; then
      INTACT=0
      continue
    fi
    read -r actual_sum actual_bytes _ < <(cksum -- "$file") || INTACT=0
    [ "$actual_sum" = "$expected_sum" ] || INTACT=0
    [ "$actual_bytes" = "$expected_bytes" ] || INTACT=0
  done < "$manifest"

  [ "$listed" -gt 0 ] || INTACT=0

  actual=0
  while IFS= read -r -d '' file; do
    rel=${file#"$ARCHIVE_DIR"/}
    actual=$((actual + 1))
    [ "${listed_paths[$rel]+present}" = "present" ] || INTACT=0
  done < <(find "$ARCHIVE_DIR" -type f ! -name '.hdcs-rotation.cksum' -print0 2>/dev/null)

  [ "$actual" -eq "$listed" ] || INTACT=0
fi

if [ "$STALE_FOUND" -ne 0 ] || [ "$INTACT" -ne 1 ]; then
  exit 1
fi
exit 0
