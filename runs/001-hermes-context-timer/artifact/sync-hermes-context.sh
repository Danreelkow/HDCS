#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror SRC -> DST (host -> workspace).
#
# contract: hcdl register of record
#   A2  one-way host->workspace, never writes back to SRC (log path guarded
#       against landing inside SRC as well)
#   A4  rsync detected -> rsync_path; else cp_path fallback (stage + reconcile)
#   A5/A7  exact mirror incl. stale file/subtree deletion, both paths
#   A6  --dry-run performs ZERO writes of any kind (no files, no log, no mkdir)
#   A8  LOG never inside DST (nor SRC); sync never deletes its own entrypoints
#       (install paths are outside the mirrored tree)
#   A9  mirror class = file contents + dir structure (recursive) + symlinks;
#       verify failure exits nonzero, never warn-exit-0
#   A11/A13 stage -> verify against SRC -> touch DST, for EVERY path including
#       the rsync path; SRC survival > freshness (a verified copy of SRC always
#       exists in staging before DST is modified)
#   A12 realpath identity guards: refuse (clean nonzero, zero writes) on
#       SRC==DST, ancestor/descendant, DST resolving through symlink into SRC
#
# shellcheck notes: deviations are intentional —
#   * vars are canonicalized via realpath into RSRC/RDST before any comparison
#     or destructive step.
#   * find -print0 / sort -z / comm -z require GNU coreutils (Linux target).
#
# env:
#   HERMES_CONTEXT_SRC  source dir   (default /opt/data/workspace/hermes-context/)
#   HERMES_CONTEXT_DST  dest dir     (default /workspace/hermes-context/)
#   HERMES_CONTEXT_LOG  summary log  (default ~/.cache/hermes-context-sync.log)
# usage: sync-hermes-context.sh [--dry-run]

set -u

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOGF="${HERMES_CONTEXT_LOG:-${HOME}/.cache/hermes-context-sync.log}"

DRY=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY=1
elif [ $# -gt 0 ]; then
    echo "usage: $0 [--dry-run]" >&2
    exit 2
fi

# ---------- guards (A12, A8, A2) — must run before ANY write ----------

die() { echo "sync-hermes-context: REFUSED: $*" >&2; exit 3; }

[ -d "$SRC" ] || die "source directory missing: $SRC"

# canonical paths; also catches DST resolving through a symlink into SRC (A12)
RSRC=$(realpath -e "$SRC") || die "cannot resolve source: $SRC"
RDST=$(realpath -m "$DST") || die "cannot resolve destination: $DST"

if [ "$RSRC" = "$RDST" ]; then
    die "source and destination resolve to the same path: $RSRC"
fi
# ancestor/descendant check (append / so /a/b does not match /a/bc)
case "$RDST/" in
    "$RSRC"/*) die "destination is inside source (descendant): $RDST" ;;
esac
case "$RSRC/" in
    "$RDST"/*) die "source is inside destination (ancestor): $RSRC" ;;
esac
if [ -e "$DST" ] && [ -L "$DST" ]; then
    LTGT=$(realpath -m "$DST")
    case "$LTGT/" in
        "$RSRC"/*) die "destination is a symlink resolving into source: $DST -> $LTGT" ;;
    esac
fi

# A8: log file must never land inside the mirrored destination tree
# A2: log file must never land inside the source tree (no writeback to SRC)
if [ -n "${LOGF:-}" ]; then
    RLOG=$(realpath -m "$LOGF")
    case "$RLOG/" in
        "$RDST"/*) die "log path is inside destination tree (A8): $RLOG" ;;
        "$RSRC"/*) die "log path is inside source tree (A2 no-writeback): $RLOG" ;;
    esac
fi

# A11: never start a destructive DST reconcile without a verified copy of SRC;
# that precondition is satisfied by the stage->verify->touch order below, but
# check up front that SRC is actually readable so staging cannot half-succeed.
if [ ! -r "$RSRC" ] || [ ! -x "$RSRC" ]; then
    die "source not readable (A11: SRC survival > freshness): $RSRC"
fi

# ---------- verification helper (A9 class: contents + structure + symlinks) ----------

# listing: relative paths, NUL-separated, sorted (structure check)
listing_of() {
    (cd "$1" && find . -mindepth 1 -print0 | sort -z)
}

# _ref_list/_cand_list are set by the caller (in $WORK) before verify_copy runs
verify_copy() {
    _cand="$1"; _ref="$2"
    listing_of "$_ref" > "$_ref_list"
    listing_of "$_cand" > "$_cand_list"
    if ! cmp -s "$_ref_list" "$_cand_list"; then
        echo "sync-hermes-context: VERIFY FAIL: structure differs" >&2
        diff <(tr '\0' '\n' < "$_ref_list") <(tr '\0' '\n' < "$_cand_list") >&2 || true
        return 1
    fi
    _rc=0
    while IFS= read -r -d '' p; do
        if [ -L "$_ref/$p" ]; then
            if [ ! -L "$_cand/$p" ]; then
                echo "VERIFY FAIL: symlink vs non-symlink: $p" >&2; _rc=1; continue
            fi
            [ "$(readlink "$_ref/$p")" = "$(readlink "$_cand/$p")" ] || {
                echo "VERIFY FAIL: symlink target differs: $p" >&2; _rc=1; continue
            }
        elif [ -f "$_ref/$p" ]; then
            [ -f "$_cand/$p" ] && [ ! -L "$_cand/$p" ] || {
                echo "VERIFY FAIL: file type differs: $p" >&2; _rc=1; continue
            }
            cmp -s "$_ref/$p" "$_cand/$p" || {
                echo "VERIFY FAIL: content differs: $p" >&2; _rc=1; continue
            }
        elif [ -d "$_ref/$p" ]; then
            [ -d "$_cand/$p" ] && [ ! -L "$_cand/$p" ] || {
                echo "VERIFY FAIL: dir type differs: $p" >&2; _rc=1; continue
            }
        else
            # other special entry types are outside the mirror class (A10) —
            # fail loudly rather than silently suppress
            echo "VERIFY FAIL: unsupported entry type (known limitation): $p" >&2
            _rc=1
        fi
    done < "$_ref_list"
    return "$_rc"
}

# ---------- plan / dry-run ----------

have_rsync=0
command -v rsync >/dev/null 2>&1 && have_rsync=1

if [ "$DRY" -eq 1 ]; then
    # A6: report only; no mkdir, no staging, no log write.
    if [ "$have_rsync" -eq 1 ]; then
        echo "dry-run: would mirror (rsync -a --delete): $RSRC/ -> $RDST/"
    else
        echo "dry-run: would mirror (cp_path stage+reconcile): $RSRC/ -> $RDST/"
    fi
    if [ -d "$DST" ] && [ ! -L "$DST" ]; then
        comm -z -13 <(listing_of "$RSRC") <(listing_of "$DST") 2>/dev/null \
            | tr '\0' '\n' | while IFS= read -r p; do
                [ -n "$p" ] && echo "dry-run: would delete stale: $DST/${p#./}"
            done
    fi
    exit 0
fi

# ---------- real run: stage -> verify -> touch DST (A11/A13, both paths) ----------

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hermes-context-sync.XXXXXX") \
    || { echo "sync-hermes-context: cannot create staging dir" >&2; exit 4; }
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
mkdir -p "$STAGE" || exit 4
_ref_list="$WORK/ref.list"
_cand_list="$WORK/cand.list"

# STAGE 1: copy SRC into staging (outside DST) — rsync if present, else cp -a
if [ "$have_rsync" -eq 1 ]; then
    rsync -a "$RSRC/" "$STAGE/" || {
        echo "sync-hermes-context: staging rsync failed; DST untouched" >&2; exit 5; }
    METHOD=rsync
else
    cp -a "$RSRC/." "$STAGE/" || {
        echo "sync-hermes-context: staging copy failed; DST untouched" >&2; exit 5; }
    METHOD=cp
fi

# STAGE 2: verify the staged copy against SRC (A9 class) BEFORE touching DST
verify_copy "$STAGE" "$RSRC" || {
    echo "sync-hermes-context: staged copy failed verification; DST untouched (A13)" >&2
    exit 6
}
# verified copy of SRC now exists at $STAGE — A11 precondition satisfied

# STAGE 3: reconcile verified stage into DST
mkdir -p "$RDST"
if [ "$have_rsync" -eq 1 ]; then
    # rsync_path: exact mirror incl. recursive stale deletion (A5/A7)
    rsync -a --delete "$STAGE/" "$RDST/" || {
        echo "sync-hermes-context: reconcile rsync failed" >&2; exit 5; }
else
    # cp_path: delete stale entries (recursive subtree deletion, A7): anything
    # present in DST but absent from the verified stage
    comm -z -13 <(listing_of "$STAGE") <(listing_of "$RDST") > "$WORK/stale.list" || exit 6
    while IFS= read -r -d '' p; do
        # rm -rf is relative to DST; entrypoints (script/units) live outside
        # the mirrored tree per A8, so nothing here can delete them
        rm -rf -- "$RDST/$p"
    done < "$WORK/stale.list"
    # copy verified stage into DST
    cp -a "$STAGE/." "$RDST/" || {
        echo "sync-hermes-context: reconcile copy failed" >&2; exit 5; }
fi

# STAGE 4: self-verify final DST against SRC (A5/A9: end-state equality)
verify_copy "$RDST" "$RSRC" || {
    echo "sync-hermes-context: post-sync verification FAILED (A9)" >&2
    exit 6
}

# ---------- one-line summary log (real runs only; never in DST or SRC) ----------
LOGDIR=$(dirname "$LOGF")
mkdir -p "$LOGDIR" 2>/dev/null || true
printf '%s method=%s src=%s dst=%s status=ok\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$METHOD" "$RSRC" "$RDST" >> "$LOGF" 2>/dev/null || true

echo "sync-hermes-context: mirror complete (method=$METHOD)"
exit 0

