#!/usr/bin/env bash
# verify-rotation.sh — read-only verifier for the rotation state (A6).
# Exit 0 iff: conf parses; no stale-matching file under RUNS_DIR;
# archived listing is consistent (valid rotation names, no duplicate
# basename+suffix). Exit >=1 otherwise; exit 2 on malformed conf.
# Never writes (A1 applies to rotate-hdcs-runs.sh only; this script is read-only).

set -u

die() { echo "ERROR: $*" >&2; exit "${2:-1}"; }

CONF_PATH="$(cd "$(dirname "$0")" && pwd)/hdcs-runs-rotation.conf"

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
parse_conf "$CONF_PATH" || die "malformed config $CONF_PATH" 2

if [ -n "${HDCS_RUNS_DIR+x}" ]; then
    [ -n "$HDCS_RUNS_DIR" ] || die "A4: HDCS_RUNS_DIR is set but empty; refusing" 1
    RUNS_DIR="$HDCS_RUNS_DIR"
else
    RUNS_DIR="${CONF[RUNS_DIR]}"
fi
if [ -n "${HDCS_ARCHIVE_DIR+x}" ]; then
    [ -n "$HDCS_ARCHIVE_DIR" ] || die "A4: HDCS_ARCHIVE_DIR is set but empty; refusing" 1
    ARCHIVE_DIR="$HDCS_ARCHIVE_DIR"
else
    ARCHIVE_DIR="${CONF[ARCHIVE_DIR]}"
fi
AGE_DAYS="${CONF[AGE_DAYS]}"
PATTERN="${CONF[PATTERN]}"

for p in "$RUNS_DIR" "$ARCHIVE_DIR"; do
    case "$p" in
        ''|'.'|'/') die "A4: degenerate path '$p' refused" 1 ;;
    esac
done

RUNS_R="$(realpath -m -- "$RUNS_DIR")"  || die "A4: cannot resolve RUNS_DIR '$RUNS_DIR'" 1
ARCH_R="$(realpath -m -- "$ARCHIVE_DIR")" || die "A4: cannot resolve ARCHIVE_DIR '$ARCHIVE_DIR'" 1

if [ "$RUNS_R" = "$ARCH_R" ]; then
    die "A4: RUNS_DIR and ARCHIVE_DIR resolve to the same path ($RUNS_R); refusing" 1
fi
case "$ARCH_R/" in "$RUNS_R"/*) die "A4: ARCHIVE_DIR inside RUNS_DIR; refusing" 1 ;; esac
case "$RUNS_R/" in "$ARCH_R"/*) die "A4: RUNS_DIR inside ARCHIVE_DIR; refusing" 1 ;; esac

# (b) no stale-matching file pending rotation.
# A5_move_once: age >= AGE_DAYS must be matched EXACTLY (GNU find's rounded
# -mtime +N skips files inside the N-day bucket), so select files whose mtime
# is at or before (now - AGE_DAYS days).
stale="$(find "$RUNS_R" -type f -name "$PATTERN" ! -newermt "$AGE_DAYS days ago" 2>/dev/null)"
if [ -n "$stale" ]; then
    echo "PENDING ROTATION:" >&2
    echo "$stale" >&2
    die "stale file(s) under RUNS_DIR not yet rotated" 1
fi

# (c) archived listing consistent: <name>.<suffix>, no duplicate basename+suffix
if [ -d "$ARCH_R" ]; then
    declare -A SEEN=()
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        base="$(basename -- "$f")"
        case "$base" in
            *.*) name="${base%.*}"; sfx="${base##*.}" ;;
            *) die "archive entry '$f' lacks rotation suffix" 1 ;;
        esac
        case "$sfx" in
            ''|*[!0-9]*) die "archive entry '$f' has invalid rotation suffix" 1 ;;
        esac
        [ -n "$name" ] || die "archive entry '$f' has empty basename" 1
        if [ -n "${SEEN[$base]+x}" ]; then
            die "duplicate archived basename+suffix: $base" 1
        fi
        SEEN["$base"]=1
    done < <(find "$ARCH_R" -type f | sort)
fi

echo "verify: OK"
exit 0

