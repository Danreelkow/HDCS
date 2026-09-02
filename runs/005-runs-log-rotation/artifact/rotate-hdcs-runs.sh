#!/usr/bin/env bash
# rotate-hdcs-runs.sh — rotate stale files out of RUNS_DIR into ARCHIVE_DIR.
# Pure bash + coreutils. --apply is the sole writer (A1); default mode is dry-run.
# Staleness: explicit stat epoch math — age >= AGE_DAYS (boundary rotates, A5).
# A5_mirror: every moved file preserves its recursive relative path, i.e.
#   RUNS_DIR/<rel>  ->  ARCHIVE_DIR/<rel>   (collision suffix appended to the
#   basename only, inside the mirrored directory — never flattened).
# Usage: rotate-hdcs-runs.sh [--apply]
# Env overrides: HDCS_RUNS_DIR, HDCS_ARCHIVE_DIR (set-but-empty refused, A4).

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
        case "$line" in
            [A-Z_]*=*) : ;;
            *) return 1 ;;
        esac
        key="${line%%=*}"
        val="${line#*=}"
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

# ---- A4 path law: refusals precede ANY write --------------------------------
for p in "$RUNS_DIR" "$ARCHIVE_DIR"; do
    case "$p" in
        ''|'.'|'/') die "A4: degenerate path '$p' refused" ;;
    esac
done
case "$AGE_DAYS" in
    ''|*[!0-9]*) die "A4: AGE_DAYS must be a nonnegative integer" ;;
esac
case "$KEEP" in
    ''|*[!0-9]*) die "A4: KEEP must be a nonnegative integer" ;;
esac

RUNS_R="$(realpath -m -- "$RUNS_DIR")"  || die "A4: cannot resolve RUNS_DIR '$RUNS_DIR'"
ARCH_R="$(realpath -m -- "$ARCHIVE_DIR")" || die "A4: cannot resolve ARCHIVE_DIR '$ARCHIVE_DIR'"

if [ "$RUNS_R" = "$ARCH_R" ]; then
    die "A4: RUNS_DIR and ARCHIVE_DIR resolve to the same path ($RUNS_R); refusing"
fi
case "$ARCH_R/" in "$RUNS_R"/*) die "A4: ARCHIVE_DIR ($ARCH_R) is inside RUNS_DIR ($RUNS_R); refusing" ;; esac
case "$RUNS_R/" in "$ARCH_R"/*) die "A4: RUNS_DIR ($RUNS_R) is inside ARCHIVE_DIR ($ARCH_R); refusing" ;; esac

# ---- stale plan via explicit epoch math (A5) --------------------------------
# age = now_epoch - mtime_epoch; stale iff age >= AGE_DAYS * 86400.
# find is used ONLY to enumerate candidate paths (no time predicate at all);
# the staleness decision is applied per file from stat epochs, so a file whose
# exact age equals AGE_DAYS is included (boundary per A5).
THRESHOLD=$((AGE_DAYS * 86400))
NOW_EPOCH="$(date +%s)" || die "cannot read clock"
declare -a STALE=()
while IFS= read -r -d '' f; do
    [ -n "$f" ] || continue
    mtime="$(stat -c %Y -- "$f")" || die "cannot stat $f"
    if [ "$((NOW_EPOCH - mtime))" -ge "$THRESHOLD" ]; then
        STALE+=("$f")
    fi
done < <(find "$RUNS_R" -type f -name "$PATTERN" -print0 2>/dev/null | sort -z)

# ---- A5_mirror helper: mirrored destination for a source path ---------------
rel_of() {
    local src="$1"
    if [ "$src" = "$RUNS_R" ]; then
        printf '%s' "."
    else
        printf '%s' "${src#"$RUNS_R"/}"
    fi
}

plan_dest() {
    local src="$1" rel dir base dest n
    rel="$(rel_of "$src")"
    dir="$ARCH_R/$(dirname -- "$rel")"
    base="$(basename -- "$rel")"
    dest="$dir/$base"
    n=1
    while [ -e "$dest" ]; do
        dest="$dir/$base.$n"
        n=$((n + 1))
    done
    printf '%s' "$dest"
}

# ---- dry-run (default): print plan, create nothing (A1) --------------------
if [ "${1-}" != "--apply" ]; then
    if [ "${#STALE[@]}" -eq 0 ]; then
        echo "dry-run: nothing to rotate"
        exit 0
    fi
    for src in "${STALE[@]}"; do
        echo "$src -> $(plan_dest "$src")"
    done
    echo "dry-run: ${#STALE[@]} file(s) would be rotated (no changes made)"
    exit 0
fi

# ---- --apply: sole writer (A1) ---------------------------------------------
mkdir -p -- "$ARCH_R" || die "cannot create ARCHIVE_DIR $ARCH_R"

moved=0
for src in "${STALE[@]}"; do
    rel="$(rel_of "$src")"
    dir="$ARCH_R/$(dirname -- "$rel")"
    base="$(basename -- "$rel")"
    mkdir -p -- "$dir" || die "cannot create mirrored archive dir $dir"
    dest="$dir/$base"
    n=1
    while [ -e "$dest" ]; do
        dest="$dir/$base.$n"
        n=$((n + 1))
    done
    # lossless check (A5): snapshot bytes, move, cmp-verify
    tmp="$(mktemp)" || die "mktemp failed"
    cp -- "$src" "$tmp" || { rm -f -- "$tmp"; die "snapshot failed for $src"; }
    if mv -- "$src" "$dest" && cmp -s -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        echo "rotated: $src -> $dest"
        moved=$((moved + 1))
    else
        rm -f -- "$tmp"
        die "rotation of $src failed (bytes not verified); source left in place"
    fi
done

# ---- KEEP pruning: oldest archived entries beyond KEEP are removed ---------
while IFS= read -r old; do
    [ -n "$old" ] || continue
    rm -f -- "$old"
    echo "pruned (KEEP=$KEEP): $old"
done < <(find "$ARCH_R" -type f -printf '%T@ %p\n' 2>/dev/null \
         | sort -rn | awk -v k="$KEEP" 'NR > k { $1=""; sub(/^ /,""); print }')

if [ "$moved" -eq 0 ]; then
    echo "apply: zero-action (no files at or beyond AGE_DAYS=$AGE_DAYS)"
fi
exit 0

