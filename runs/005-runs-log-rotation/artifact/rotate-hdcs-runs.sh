#!/usr/bin/env bash
# rotate-hdcs-runs.sh — rotate stale files out of RUNS_DIR into ARCHIVE_DIR.
# Pure bash + coreutils. --apply is the sole writer (A1); default mode is dry-run.
# Usage: rotate-hdcs-runs.sh [--apply]
# Env overrides: HDCS_RUNS_DIR, HDCS_ARCHIVE_DIR (set-but-empty refused, A4).
# Exit codes: 0 success/zero-action; >=1 any refusal/failure.

set -u

die() { echo "ERROR: $*" >&2; exit 1; }

CONF_PATH="$(cd "$(dirname "$0")" && pwd)/hdcs-runs-rotation.conf"

# ---- conf parsing (exactly the 5-key schema) -------------------------------
declare -A CONF=()
parse_conf() {
    local f="$1" line key val
    [ -r "$f" ] || return 1
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        key="${line%%=*}"
        val="${line#*=}"
        [ "$key" = "$line" ] && return 1
        case "$key" in
            RUNS_DIR|ARCHIVE_DIR|AGE_DAYS|PATTERN|KEEP) CONF["$key"]="$val" ;;
            *) return 1 ;;
        esac
    done < "$f"
    for key in RUNS_DIR ARCHIVE_DIR AGE_DAYS PATTERN KEEP; do
        [ -n "${CONF[$key]+x}" ] || return 1
    done
    return 0
}
parse_conf "$CONF_PATH" || die "malformed config $CONF_PATH (schema: RUNS_DIR, ARCHIVE_DIR, AGE_DAYS, PATTERN, KEEP)"

# ---- resolve env > conf; set-but-empty -> refuse (A4) ----------------------
if [ -n "${HDCS_RUNS_DIR+x}" ]; then
    [ -n "$HDCS_RUNS_DIR" ] || die "A4: HDCS_RUNS_DIR is set but empty; refusing"
    RUNS_DIR="$HDCS_RUNS_DIR"
else
    RUNS_DIR="${CONF[RUNS_DIR]}"
fi
if [ -n "${HDCS_ARCHIVE_DIR+x}" ]; then
    [ -n "$HDCS_ARCHIVE_DIR" ] || die "A4: HDCS_ARCHIVE_DIR is set but empty; refusing"
    ARCHIVE_DIR="$HDCS_ARCHIVE_DIR"
else
    ARCHIVE_DIR="${CONF[ARCHIVE_DIR]}"
fi
AGE_DAYS="${CONF[AGE_DAYS]}"
PATTERN="${CONF[PATTERN]}"
KEEP="${CONF[KEEP]}"

# ---- A4 path law: refuses precede ANY write --------------------------------
for p in "$RUNS_DIR" "$ARCHIVE_DIR"; do
    case "$p" in
        ''|'.'|'/') die "A4: degenerate path '$p' refused" ;;
    esac
done
[ "$AGE_DAYS" -ge 0 ] 2>/dev/null || die "A4: AGE_DAYS must be a nonnegative integer"
case "$KEEP" in
    ''|*[!0-9-]*) die "A4: KEEP must be an integer" ;;
esac

RUNS_R="$(realpath -m -- "$RUNS_DIR")"  || die "A4: cannot resolve RUNS_DIR '$RUNS_DIR'"
ARCH_R="$(realpath -m -- "$ARCHIVE_DIR")" || die "A4: cannot resolve ARCHIVE_DIR '$ARCHIVE_DIR'"

if [ "$RUNS_R" = "$ARCH_R" ]; then
    die "A4: RUNS_DIR and ARCHIVE_DIR resolve to the same path ($RUNS_R); refusing"
fi
case "$ARCH_R/" in "$RUNS_R"/*) die "A4: ARCHIVE_DIR ($ARCH_R) is inside RUNS_DIR ($RUNS_R); refusing" ;; esac
case "$RUNS_R/" in "$ARCH_R"/*) die "A4: RUNS_DIR ($RUNS_R) is inside ARCHIVE_DIR ($ARCH_R); refusing" ;; esac

# ---- plan (read-only; safe in both modes) ----------------------------------
# A5_move_once: select files with age >= AGE_DAYS EXACTLY. GNU find's rounded
# -mtime +N skips files whose age falls inside the N-day bucket, so instead we
# select files whose mtime is at or before (now - AGE_DAYS days).
mapfile -t STALE < <(find "$RUNS_R" -type f -name "$PATTERN" ! -newermt "$AGE_DAYS days ago" | sort)

# ---- dry-run (default): print plan, create nothing (A1) --------------------
if [ "${1-}" != "--apply" ]; then
    if [ "${#STALE[@]}" -eq 0 ]; then
        echo "dry-run: nothing to rotate"
        exit 0
    fi
    for src in "${STALE[@]}"; do
        base="$(basename -- "$src")"
        echo "$src -> $ARCHIVE_DIR/$base.1"
    done
    echo "dry-run: ${#STALE[@]} file(s) would be rotated (no changes made)"
    exit 0
fi

# ---- --apply: sole writer (A1) ---------------------------------------------
mkdir -p -- "$ARCH_R" || die "cannot create ARCHIVE_DIR $ARCH_R"

moved=0
for src in "${STALE[@]}"; do
    base="$(basename -- "$src")"
    dest="$ARCH_R/$base.1"
    n=1
    while [ -e "$dest" ]; do
        n=$((n + 1))
        dest="$ARCH_R/$base.$n"
    done
    # lossless check (A5_bytes): snapshot bytes, move, cmp-verify
    tmp="$(mktemp)" || die "mktemp failed"
    cp -- "$src" "$tmp" || { rm -f -- "$tmp"; die "snapshot failed for $src"; }
    if mv -- "$src" "$dest" && cmp -s -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        echo "rotated: $src -> $dest"
        moved=$((moved + 1))
    else
        rc=$?
        cmp -s -- "$tmp" "$src" && mv -- "$src" "$src" 2>/dev/null
        rm -f -- "$tmp"
        die "rotation of $src failed (bytes not verified); source left in place"
    fi
done

# ---- KEEP pruning: oldest archived entries beyond KEEP are removed ---------
if [ "$KEEP" -ge 0 ]; then
    while IFS= read -r old; do
        [ -n "$old" ] || continue
        rm -f -- "$old"
        echo "pruned (KEEP=$KEEP): $old"
    done < <(find "$ARCH_R" -maxdepth 1 -type f -name "$PATTERN.*" -printf '%T@ %p\n' 2>/dev/null \
             | sort -rn | awk -v k="$KEEP" 'NR > k { $1=""; sub(/^ /,""); print }')
fi

if [ "$moved" -eq 0 ]; then
    echo "apply: zero-action (no files at or beyond AGE_DAYS=$AGE_DAYS)"
fi
exit 0

