#!/bin/sh
# sync-hermes-context.sh — one-way exact mirror of SRC into DST (contents).
# Standalone-capable (no systemd required). POSIX sh, no root.
# Invariants: A2 one-way, A4 contents/fallback, A5 mirror+delete,
#             A6 dry-run zero writes, A7 recursive stale deletion,
#             A8 LOG/entrypoints outside mirrored tree, A9 self-verify.
set -eu

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG="${HERMES_CONTEXT_LOG:-$HOME/.cache/hermes-context/sync.log}"

DRY_RUN=0
FORCE_MODE="${HERMES_CONTEXT_FORCE_MODE:-auto}"   # auto|rsync|fallback

usage() {
    echo "usage: sync-hermes-context.sh [--dry-run]" >&2
    echo "  env: HERMES_CONTEXT_SRC, HERMES_CONTEXT_DST, HERMES_CONTEXT_LOG, HERMES_CONTEXT_FORCE_MODE" >&2
}

[ $# -le 1 ] || { usage; exit 2; }
[ $# -eq 0 ] || {
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
}

# --- sanity checks, ALL before any destructive operation ---
SRC="${SRC%/}"
DST="${DST%/}"

if [ ! -d "$SRC" ]; then
    echo "FATAL: SRC does not exist or is not a directory: $SRC" >&2
    exit 3
fi

case "$DST/" in
    "$SRC"/*) echo "FATAL: DST inside SRC (would nest): $DST" >&2; exit 4 ;;
esac
case "$SRC/" in
    "$DST"/*) echo "FATAL: SRC inside DST (refusing writeback target): $SRC" >&2; exit 4 ;;
esac

# A8: LOG must be outside DST — checked BEFORE any sync/delete can touch it.
case "$LOG/" in
    "$DST"/*)
        echo "FATAL: LOG ($LOG) inside DST ($DST); refusing (A8)" >&2
        exit 5
        ;;
esac

MODE=fallback
if [ "$FORCE_MODE" = rsync ] || { [ "$FORCE_MODE" = auto ] && command -v rsync >/dev/null 2>&1; }; then
    MODE=rsync
fi

# --- sync (status captured so a failure still yields exactly one LOG line) ---
sync_status=0
if [ "$MODE" = rsync ]; then
    # -a: no -H/-A/-X (metadata/hardlinks/xattrs excluded per A9);
    # trailing slash semantics = contents of SRC into DST (A4);
    # --delete: exact mirror, stale removed (A5/A7).
    if [ "$DRY_RUN" -eq 1 ]; then
        rsync -a --delete --dry-run "$SRC/" "$DST/" || sync_status=$?
    else
        rsync -a --delete "$SRC/" "$DST/" || sync_status=$?
    fi
else
    # Fallback: reconcile recursively — remove stale subtrees at every depth
    # first, then copy. Identical mirror semantics to rsync --delete (A5/A7).
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY-RUN (fallback): would reconcile '$DST' to '$SRC' (stale removed)"
    else
        mkdir -p "$DST"
        ( cd "$DST" && rm -rf ./* ./.[!.]* ./..?* 2>/dev/null || true )
        if command -v tar >/dev/null 2>&1; then
            tar -C "$SRC" -cf - . | tar -C "$DST" -xf - || sync_status=$?
        else
            cp -a "$SRC"/. "$DST"/ || sync_status=$?
        fi
    fi
fi

# --- self-verify (A9): {file contents, dir structure, symlink targets} ---
verify() {
    status=0
    ( cd "$SRC" && find . -mindepth 1 \( -type d -o -type f -o -type l \) -print ) | sort > "$tmp_src_list"
    ( cd "$DST" && find . -mindepth 1 \( -type d -o -type f -o -type l \) -print ) | sort > "$tmp_dst_list"
    if ! cmp -s "$tmp_src_list" "$tmp_dst_list"; then
        echo "VERIFY MISMATCH: directory/file/symlink structure differs (SRC vs DST):" >&2
        diff "$tmp_src_list" "$tmp_dst_list" >&2 || true
        status=1
    else
        while IFS= read -r p; do
            s_type=$( [ -L "$SRC/$p" ] && echo link || { [ -d "$SRC/$p" ] && echo dir || echo file; } )
            d_type=$( [ -L "$DST/$p" ] && echo link || { [ -d "$DST/$p" ] && echo dir || echo file; } )
            if [ "$s_type" != "$d_type" ]; then
                echo "VERIFY MISMATCH: type differs for '$p': SRC=$s_type DST=$d_type" >&2
                status=1
                continue
            fi
            case "$s_type" in
                link)
                    s_t=$(readlink "$SRC/$p")
                    d_t=$(readlink "$DST/$p")
                    if [ "$s_t" != "$d_t" ]; then
                        echo "VERIFY MISMATCH: symlink target for '$p': SRC='$s_t' DST='$d_t'" >&2
                        status=1
                    fi
                    ;;
                file)
                    if ! cmp -s "$SRC/$p" "$DST/$p"; then
                        echo "VERIFY MISMATCH: file contents differ: '$p'" >&2
                        diff "$SRC/$p" "$DST/$p" >&2 || true
                        status=1
                    fi
                    ;;
            esac
        done < "$tmp_src_list"
    fi
    return $status
}

verify_status=0
tmp_dir=""
if [ "$DRY_RUN" -eq 0 ]; then
    tmp_dir=$(mktemp -d)
    tmp_src_list="$tmp_dir/src.list"
    tmp_dst_list="$tmp_dir/dst.list"
    if verify; then
        verify_status=0
    else
        verify_status=1
    fi
    rm -rf "$tmp_dir"
fi

# --- logging (A6: skip ALL writes in dry-run) ---
# Exactly one line per non-dry-run run, including sync/verify failures.
if [ "$DRY_RUN" -eq 0 ]; then
    log_dir=$(dirname "$LOG")
    mkdir -p "$log_dir"
    if [ "$sync_status" -ne 0 ]; then
        result="SYNC_FAIL"
    elif [ "$verify_status" -ne 0 ]; then
        result="VERIFY_FAIL"
    else
        result="OK"
    fi
    echo "$(date '+%Y-%m-%dT%H:%M:%S%z') mode=$MODE dry_run=0 result=$result" >> "$LOG"
fi

if [ "$sync_status" -ne 0 ]; then
    echo "FATAL: sync step failed (status $sync_status)" >&2
    exit 7
fi

if [ "$verify_status" -ne 0 ]; then
    echo "FATAL: self-verify failed; DST != mirror of SRC" >&2
    exit 6
fi

exit 0

