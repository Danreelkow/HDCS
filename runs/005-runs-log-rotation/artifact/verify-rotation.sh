#!/usr/bin/env bash
# verify-rotation.sh — read-only verifier for the rotation state (A6).
# Exit 0 iff: conf parses; no stale (age >= AGE_DAYS, explicit stat epoch math,
# A5) PATTERN-matching file under RUNS_DIR; ARCHIVE_DIR exists and its file
# listing is intact. Never writes into the artifact dir or the watched tree:
# any scratch file lives in the system temp dir (mktemp outside the tree) and
# is removed on exit. Every check feeds a flag accumulator (A7); a failed scan
# (find error, unreadable stat) is a verify FAILURE, never a silent pass.

set -u

die() { echo "ERROR: $*" >&2; exit "${2:-1}"; }

CONF_PATH="$(cd "$(dirname "$0")" && pwd)/hdcs-runs-rotation.conf"

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

# Scratch files live OUTSIDE the artifact dir and the watched tree (system
# temp via mktemp), and are always cleaned up — verify stays read-only.
OUTTMP="$(mktemp)" || die "cannot create scratch file outside the tree" 1
ERRTMP="$(mktemp)" || { rm -f -- "$OUTTMP"; die "cannot create scratch file outside the tree" 1; }
cleanup() { rm -f -- "$OUTTMP" "$ERRTMP"; }
trap cleanup EXIT

# (b) no stale-matching file pending rotation — explicit epoch math (A5).
# One find invocation writes candidates to a scratch file and its stderr to a
# separate scratch file; find's OWN exit status is captured directly (no
# pipeline, so no head/awk status masking — A7). The threshold is applied per
# file via stat, so files whose exact age equals AGE_DAYS are flagged.
THRESHOLD=$((AGE_DAYS * 86400))
NOW_EPOCH="$(date +%s)" || die "cannot read clock" 1
STALE_FOUND=0
SCAN_FAILED=0
if ! find "$RUNS_R" -type f -name "$PATTERN" -print0 >"$OUTTMP" 2>"$ERRTMP"; then
    echo "SCAN FAILURE: find over $RUNS_R failed" >&2
    SCAN_FAILED=1
fi
if [ -s "$ERRTMP" ]; then
    echo "SCAN FAILURE: find over $RUNS_R reported errors:" >&2
    cat "$ERRTMP" >&2
    SCAN_FAILED=1
fi
while IFS= read -r -d '' f; do
    [ -n "$f" ] || continue
    if ! mtime="$(stat -c %Y -- "$f" 2>/dev/null)"; then
        echo "SCAN FAILURE: cannot stat $f" >&2
        SCAN_FAILED=1
        continue
    fi
    if [ "$((NOW_EPOCH - mtime))" -ge "$THRESHOLD" ]; then
        echo "PENDING ROTATION: $f" >&2
        STALE_FOUND=1
    fi
done <"$OUTTMP"
[ "$SCAN_FAILED" -eq 0 ] || die "stale scan incomplete; refusing to report OK (A6)" 1
[ "$STALE_FOUND" -eq 0 ] || die "stale file(s) under RUNS_DIR not yet rotated" 1

# (c) archive intact: ARCHIVE_DIR exists and its recursive file listing succeeds
if [ ! -d "$ARCH_R" ]; then
    die "archive directory $ARCH_R missing" 1
fi
if ! find "$ARCH_R" -type f -print >/dev/null 2>&1; then
    die "archive listing corrupt" 1
fi

echo "verify: OK"
exit 0

