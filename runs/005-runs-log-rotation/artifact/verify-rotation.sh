#!/usr/bin/env bash
# verify-rotation.sh — exit 0 iff conf parses (exactly 5 keys), no pending
# rotation, and the archive exists with a consistent cksum manifest.
# Nonzero otherwise, with reason line.
set -u

CONF="$(dirname "$(realpath "$0")")/hdcs-runs-rotation.conf"
[ -f "$CONF" ] || CONF="hdcs-runs-rotation.conf"

fail() { echo "VERIFY FAIL: $1" >&2; exit 1; }

# (a) conf parses with exactly 5 keys, no unknown keys
declare -A C=()
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|\#*) continue ;; esac
  k="${line%%=*}"; v="${line#*=}"
  [ "$k" != "$line" ] || fail "conf parse error: $line"
  case "$k" in
    RUNS_DIR|ARCHIVE_DIR|AGE_DAYS|PATTERN|KEEP) ;;
    *) fail "conf: unknown key '$k' — exactly five keys required" ;;
  esac
  C["$k"]="$v"
done < "$CONF"
[ "${#C[@]}" -eq 5 ] || fail "conf must have exactly 5 keys, found ${#C[@]}"
for k in RUNS_DIR ARCHIVE_DIR AGE_DAYS PATTERN KEEP; do
  [ -n "${C[$k]:-}" ] || fail "conf missing key $k"
done

RUNS_DIR="${C[RUNS_DIR]}"
ARCHIVE_DIR="${C[ARCHIVE_DIR]}"
AGE_DAYS="${C[AGE_DAYS]}"
PATTERN="${C[PATTERN]}"
KEEP="${C[KEEP]}"

if [ "${HDCS_RUNS_DIR+set}" = "set" ]; then
  [ -n "$HDCS_RUNS_DIR" ] || fail "A4: HDCS_RUNS_DIR set but empty"
  RUNS_DIR="$HDCS_RUNS_DIR"
fi
if [ "${HDCS_ARCHIVE_DIR+set}" = "set" ]; then
  [ -n "$HDCS_ARCHIVE_DIR" ] || fail "A4: HDCS_ARCHIVE_DIR set but empty"
  ARCHIVE_DIR="$HDCS_ARCHIVE_DIR"
fi

for p in "$RUNS_DIR" "$ARCHIVE_DIR"; do
  case "$p" in ''|'.'|'/') fail "A4: degenerate path '$p'" ;; esac
done
R="$(realpath -m -- "$RUNS_DIR")"
A="$(realpath -m -- "$ARCHIVE_DIR")"
[ "$R" = "$A" ] && fail "A4: RUNS_DIR == ARCHIVE_DIR"
case "$R/" in "$A"/*) fail "A4: ARCHIVE_DIR contains RUNS_DIR" ;; esac
case "$A/" in "$R"/*) fail "A4: RUNS_DIR contains ARCHIVE_DIR" ;; esac

# (b) no PATTERN file with age >= AGE_DAYS under RUNS_DIR
pending=$(find "$R" -type f -name "$PATTERN" -mtime +"$((AGE_DAYS-1))" 2>/dev/null)
[ -z "$pending" ] || fail "pending rotation: $pending"

# (c) archive must exist, hold archived files, and match its cksum manifest (A6)
[ -d "$A" ] || fail "archive directory $A does not exist — nothing has been rotated"
MANIFEST="$A/.hdcs-rotation-manifest"
[ -f "$MANIFEST" ] || fail "archive manifest missing in $A"
count=0
while IFS= read -r f; do
  [ -f "$f" ] || fail "archive entry not a regular file: $f"
  count=$((count+1))
done < <(find "$A" -type f ! -name '.hdcs-rotation-manifest' -print 2>/dev/null)
[ "$count" -gt 0 ] || fail "archive contains no archived files"
[ "$count" -le "$KEEP" ] || fail "archive exceeds KEEP=$KEEP ($count files)"
current=$(find "$A" -type f ! -name '.hdcs-rotation-manifest' -print0 2>/dev/null \
  | LC_ALL=C sort -z | xargs -0 -r cksum)
stored=$(cat "$MANIFEST")
[ "$current" = "$stored" ] || fail "archive listing/cksum inconsistent with manifest"

echo "VERIFY OK"
exit 0

