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

MODE=dry-run
if [ "${1-}" = "--apply" ]; then
  MODE=apply
elif [ "${1-}" != "" ]; then
  echo "usage: $0 [--apply]" >&2
  exit 2
fi

now=$(date +%s)
stale_files=()
while IFS= read -r -d '' file; do
  mtime=$(stat -c '%Y' -- "$file") || exit 1
  age=$(( (now - mtime) / 86400 ))
  if [ "$age" -ge "$AGE_DAYS" ]; then
    stale_files+=("$file")
    rel=${file#"$RUNS_DIR"/}
    printf '%s\n' "$rel"
  fi
done < <(find "$RUNS_DIR" -type f -name "$PATTERN" -print0 2>/dev/null)

[ "$MODE" = dry-run ] && exit 0

if [ "${#stale_files[@]}" -gt 0 ]; then
  mkdir -p -- "$ARCHIVE_DIR" || exit 1
fi

for file in "${stale_files[@]}"; do
  [ -f "$file" ] || continue
  rel=${file#"$RUNS_DIR"/}
  target=$ARCHIVE_DIR/$rel
  mkdir -p -- "$(dirname -- "$target")" || exit 1

  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -f "$target" ] && cmp -s -- "$file" "$target"; then
      rm -f -- "$file" || exit 1
      continue
    fi
    n=1
    while [ -e "$target.$n" ] || [ -L "$target.$n" ]; do
      n=$((n + 1))
    done
    target=$target.$n
    mkdir -p -- "$(dirname -- "$target")" || exit 1
  fi

  cp -- "$file" "$target" || exit 1
  cmp -s -- "$file" "$target" || exit 1
  rm -f -- "$file" || exit 1
done

if [ -d "$ARCHIVE_DIR" ]; then
  mapfile -t archived < <(
    find "$ARCHIVE_DIR" -type f ! -name '.hdcs-rotation.cksum' \
      -printf '%T@ %p\n' 2>/dev/null | sort -nr
  )
  if [ "${#archived[@]}" -gt "$KEEP" ]; then
    for ((i=KEEP; i<${#archived[@]}; i++)); do
      old=${archived[i]#* }
      rm -f -- "$old" || exit 1
    done
  fi

  manifest_tmp=$(mktemp "${TMPDIR:-/tmp}/hdcs-rotation.XXXXXX") || exit 1
  while IFS= read -r -d '' file; do
    rel=${file#"$ARCHIVE_DIR"/}
    read -r sum bytes _ < <(cksum -- "$file") || exit 1
    printf '%s|%s|%s\n' "$sum" "$bytes" "$rel" >> "$manifest_tmp"
  done < <(find "$ARCHIVE_DIR" -type f ! -name '.hdcs-rotation.cksum' -print0)
  mv -- "$manifest_tmp" "$ARCHIVE_DIR/.hdcs-rotation.cksum" || exit 1
fi
