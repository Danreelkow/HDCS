#!/usr/bin/env bash
# rotate-hdcs-runs.sh — rotate stale *.txt files from RUNS_DIR into ARCHIVE_DIR.
# Pure bash + coreutils (A2). Default mode is DRY-RUN (zero writes, A1);
# --apply is the sole writing mode. Path law refusals cite A4.
set -u

CONF="$(dirname "$(realpath "$0")")/hdcs-runs-rotation.conf"
[ -f "$CONF" ] || CONF="hdcs-runs-rotation.conf"

# (a) parse conf via source-safe read: exactly the five KEY=VALUE keys, no extras
declare -A C=()
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|\#*) continue ;; esac
  k="${line%%=*}"; v="${line#*=}"
  [ "$k" != "$line" ] || { echo "conf parse error: $line" >&2; exit 1; }
  case "$k" in
    RUNS_DIR|ARCHIVE_DIR|AGE_DAYS|PATTERN|KEEP) ;;
    *) echo "conf: unknown key '$k' — exactly five keys required" >&2; exit 1 ;;
  esac
  C["$k"]="$v"
done < "$CONF"
for k in RUNS_DIR ARCHIVE_DIR AGE_DAYS PATTERN KEEP; do
  [ -n "${C[$k]:-}" ] || { echo "conf missing key $k" >&2; exit 1; }
done
[ "${#C[@]}" -eq 5 ] || { echo "conf must have exactly 5 keys, found ${#C[@]}" >&2; exit 1; }

RUNS_DIR="${C[RUNS_DIR]}"
ARCHIVE_DIR="${C[ARCHIVE_DIR]}"
AGE_DAYS="${C[AGE_DAYS]}"
PATTERN="${C[PATTERN]}"
KEEP="${C[KEEP]}"

# (b) env override; set-but-empty = refusal citing A4, zero writes
if [ "${HDCS_RUNS_DIR+set}" = "set" ]; then
  [ -n "$HDCS_RUNS_DIR" ] || { echo "A4: HDCS_RUNS_DIR set but empty — refusing" >&2; exit 1; }
  RUNS_DIR="$HDCS_RUNS_DIR"
fi
if [ "${HDCS_ARCHIVE_DIR+set}" = "set" ]; then
  [ -n "$HDCS_ARCHIVE_DIR" ] || { echo "A4: HDCS_ARCHIVE_DIR set but empty — refusing" >&2; exit 1; }
  ARCHIVE_DIR="$HDCS_ARCHIVE_DIR"
fi

# (c) path law: degenerate paths, realpath, equality, containment (A4)
for p in "$RUNS_DIR" "$ARCHIVE_DIR"; do
  case "$p" in ''|'.'|'/') echo "A4: degenerate path '$p' — refusing" >&2; exit 1 ;; esac
done
R="$(realpath -m -- "$RUNS_DIR")"
A="$(realpath -m -- "$ARCHIVE_DIR")"
[ "$R" = "$A" ] && { echo "A4: RUNS_DIR == ARCHIVE_DIR ($R) — refusing" >&2; exit 1; }
case "$R/" in "$A"/*) echo "A4: ARCHIVE_DIR contains RUNS_DIR — refusing" >&2; exit 1 ;; esac
case "$A/" in "$R"/*) echo "A4: RUNS_DIR contains ARCHIVE_DIR — refusing" >&2; exit 1 ;; esac

MODE="DRY-RUN"
[ "${1:-}" = "--apply" ] && MODE="APPLY"

# (d) candidates: files matching PATTERN with mtime >= AGE_DAYS
mapfile -t CANDS < <(find "$R" -type f -name "$PATTERN" -mtime +"$((AGE_DAYS-1))" 2>/dev/null | sort)

if [ "$MODE" = "DRY-RUN" ]; then
  echo "DRY-RUN plan: ${#CANDS[@]} file(s) would be rotated from $R to $A"
  for f in "${CANDS[@]}"; do
    echo "  would rotate: ${f#"$R"/}"
  done
  echo "DRY-RUN: no files moved, nothing created (A1)"
  exit 0
fi

# (e) --apply
[ -d "$R" ] || { echo "RUNS_DIR $R does not exist" >&2; exit 1; }
mkdir -p -- "$A" || { echo "cannot create ARCHIVE_DIR $A" >&2; exit 1; }

MANIFEST="$A/.hdcs-rotation-manifest"

moved=0
for f in "${CANDS[@]}"; do
  rel="${f#"$R"/}"
  dest="$A/$rel"
  dest_dir="$(dirname -- "$dest")"
  mkdir -p -- "$dest_dir" || { echo "cannot create $dest_dir" >&2; exit 1; }
  target="$dest"
  if [ -e "$target" ]; then
    n=1
    while [ -e "$dest.$n" ]; do n=$((n+1)); done
    target="$dest.$n"
  fi
  # lossless: copy, cmp, then remove source (A5)
  cp -p -- "$f" "$target" || { echo "copy failed: $f" >&2; exit 1; }
  if cmp -s -- "$f" "$target"; then
    rm -f -- "$f" || { echo "remove failed: $f" >&2; exit 1; }
    echo "rotated: $rel -> ${target#"$A"/}"
    moved=$((moved+1))
  else
    echo "A5: byte mismatch for $rel — keeping source, removing bad copy" >&2
    rm -f -- "$target"
    exit 1
  fi
done

# refresh archive manifest (cksum listing) so verify can check archive identity
find "$A" -type f ! -name '.hdcs-rotation-manifest' -print0 2>/dev/null \
  | LC_ALL=C sort -z | xargs -0 -r cksum > "$MANIFEST" || { echo "manifest write failed" >&2; exit 1; }

echo "$moved moved"
exit 0

