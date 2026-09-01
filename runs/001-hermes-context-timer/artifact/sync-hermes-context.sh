#!/usr/bin/env bash
# sync-hermes-context.sh — one-way exact-mirror sync host -> workspace.
# Source path is /opt/data/workspace/hermes-context/ (override via HERMES_CONTEXT_SRC).
# Destination /workspace/hermes-context/ (override via HERMES_CONTEXT_DST).
# Dry-run mode that performs no writes of any kind (no staging, no DST changes,
# no log file).
set -u

usage() {
    echo "usage: $0 [--dry-run]" >&2
    exit 2
}

DRYRUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRYRUN=1 ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
done

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG_FILE="${HERMES_CTX_LOG:-$HOME/.cache/hermes-context/log}"

die() { echo "sync-hermes-context: ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------- A12 identity guard
# Resolve realpaths; refuse if equal, ancestor/descendant, or DST resolves
# through a symlink component into SRC. Runs before any other action.
# Read-only: performs no writes of any kind.
real_src="$(realpath -e "$SRC" 2>/dev/null)" || die "cannot resolve source path: $SRC"
real_dst="$(realpath -m "$DST" 2>/dev/null)" || die "cannot resolve destination path: $DST"

[ -n "$real_src" ] && [ -n "$real_dst" ] || die "path resolution failed"

if [ "$real_src" = "$real_dst" ]; then
    die "refusing: SRC and DST resolve to the same path ($real_src)"
fi

case "$real_dst/" in
    "$real_src"/*) die "refusing: DST ($real_dst) is inside SRC ($real_src)" ;;
esac
case "$real_src/" in
    "$real_dst"/*) die "refusing: SRC ($real_src) is inside DST ($real_dst)" ;;
esac

# Walk DST path components; if any symlink component resolves into SRC, refuse.
_check="$real_dst"
while [ "$_check" != "/" ]; do
    if [ -L "$_check" ]; then
        _res="$(realpath -m "$_check")"
        case "$_res/" in
            "$real_src"/|"$real_src") die "refusing: DST path component $_check is a symlink resolving into SRC" ;;
        esac
        case "$real_src/" in
            "$_res"/|"/$_res") die "refusing: DST path component $_check symlink creates ancestor/descendant relation with SRC" ;;
        esac
    fi
    _check="$(dirname "$_check")"
done

[ -d "$real_src" ] || die "source is not a directory: $real_src"

# ---------------------------------------------------------------- dry-run: exit before any write
# A6: zero writes of any kind on --dry-run — no staging dir, no DST change,
# no log file. Guards above are purely read-only.
if [ "$DRYRUN" -eq 1 ]; then
    echo "dry-run: guards passed; no writes performed (no staging, DST untouched, no log written)"
    exit 0
fi

# ---------------------------------------------------------------- logging (real runs only)
log_line() {
    # $1 = result, $2 = detail
    mkdir -p "$(dirname "$LOG_FILE")" || return 1
    printf '%s result=%s detail=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$LOG_FILE"
}

# ---------------------------------------------------------------- A9-class recursive compare
# Compares two trees: contents byte-for-byte, symlink targets, directory
# structure. Ignores metadata/timestamps. Returns nonzero on any mismatch.
tree_compare() { # $1 = expected (SRC), $2 = candidate
    local a="$1" b="$2"
    local -a a_files=() a_dirs=() a_links=()
    local rel

    while IFS= read -r -d '' rel; do
        a_dirs+=("$rel")
    done < <(cd "$a" && find . -type d -print0 | sort -z)
    while IFS= read -r -d '' rel; do
        a_files+=("$rel")
    done < <(cd "$a" && find . -type f -print0 | sort -z)
    while IFS= read -r -d '' rel; do
        a_links+=("$rel")
    done < <(cd "$a" && find . -type l -print0 | sort -z)

    local p
    for p in "${a_dirs[@]}"; do
        [ -d "$b/$p" ] || { echo "missing dir: $p" >&2; return 1; }
    done
    for p in "${a_files[@]}"; do
        [ -f "$b/$p" ] || { echo "missing file: $p" >&2; return 1; }
        cmp -s "$a/$p" "$b/$p" || { echo "content mismatch: $p" >&2; return 1; }
    done
    for p in "${a_links[@]}"; do
        [ -L "$b/$p" ] || { echo "missing symlink: $p" >&2; return 1; }
        [ "$(readlink "$a/$p")" = "$(readlink "$b/$p")" ] || { echo "symlink target mismatch: $p" >&2; return 1; }
    done
    # extra entries in candidate -> not an exact mirror
    local extra
    while IFS= read -r -d '' extra; do
        echo "unexpected extra entry: $extra" >&2
        return 1
    done < <(cd "$b" && find . -mindepth 1 \( -type d -o -type f -o -type l \) -print0 | sort -z \
        | while IFS= read -r -d '' e; do
            case " ${a_dirs[*]} ${a_files[*]} ${a_links[*]} " in
                *" $e "*) ;;
                *) printf '%s\0' "$e" ;;
            esac
          done)
    return 0
}

# ---------------------------------------------------------------- staging (A13)
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/hermes-context-stage.XXXXXX")" || die "mktemp failed"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$real_src/" "$STAGE/" || { echo "sync-hermes-context: ERROR: rsync staging failed" >&2; exit 1; }
else
    # cp -a / tar-pipe fallback; recursive reconcile incl. stale-subtree deletion
    # happens naturally because STAGE is a fresh empty dir (A7-equivalent end state).
    ( cd "$real_src" && tar -cf - . ) | ( cd "$STAGE" && tar -xf - ) \
        || { echo "sync-hermes-context: ERROR: tar-pipe staging failed" >&2; exit 1; }
fi

# ---------------------------------------------------------------- verify staged copy (A13/A9)
if ! tree_compare "$real_src" "$STAGE"; then
    echo "sync-hermes-context: ERROR: staged copy failed verification against SRC; DST untouched" >&2
    exit 1
fi

# ---------------------------------------------------------------- apply to DST (verified copy exists)
mkdir -p "$real_dst" || die "cannot create DST: $real_dst"

# Replace DST contents with staged mirror: delete stale recursively, then copy.
# No rm -rf of DST itself; DST survives, only its contents are reconciled.
find "$real_dst" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || die "failed clearing DST contents"
( cd "$STAGE" && tar -cf - . ) | ( cd "$real_dst" && tar -xf - ) || die "failed applying staged copy to DST"

# Final mirror check on DST itself (A5/A9)
if ! tree_compare "$real_src" "$real_dst"; then
    log_line "FAIL" "post-apply mirror mismatch $real_dst"
    echo "sync-hermes-context: ERROR: DST does not mirror SRC after apply" >&2
    exit 1
fi

COUNT="$(cd "$real_src" && find . \( -type f -o -type l \) | wc -l)"
log_line "OK" "mirrored $COUNT entries to $real_dst"
echo "sync-hermes-context: OK: mirrored $COUNT entries to $real_dst"
exit 0

