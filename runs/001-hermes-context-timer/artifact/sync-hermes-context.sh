#!/usr/bin/env bash
# sync-hermes-context.sh — mirror SRC -> DST (recursive, verified, idempotent)
# A5 mirror | A6 purity dry-run | A7 recursive fallback convergence | A8 LOG∉DST
# A9 verify | A10 normal-defects-only | A11/A12 guards | A13 idempotent | A14 1-line log
#
# Fully parameterized: SRC and DST are REQUIRED from the environment.
# LOG and ART_DIR have env-overridable defaults. No hardcoded-only paths.
set -u

# --- 1a. Config via env -------------------------------------------------------
: "${SRC:?sync-hermes-context: SRC must be set in the environment}"
: "${DST:?sync-hermes-context: DST must be set in the environment}"
LOG="${LOG:-$HOME/.cache/hermes-context-sync.log}"
ART_DIR="${ART_DIR:-$HOME/.cache/hermes-context-sync-artifacts}"

EXIT_OK=0
EXIT_VERIFY=1
EXIT_GUARD=2

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# Zero-write failure path: never touch LOG on guard/dry-run.
die() { echo "sync-hermes-context: error: $*" >&2; exit "$2"; }

# --- 1b. realpath guard (A12/A11) — pre-ANY-op, incl. LOG --------------------
SRC_REAL="$(realpath -e -- "$SRC" 2>/dev/null)" || die "SRC not readable: $SRC" $EXIT_GUARD
DST_REAL="$(realpath -e -- "$DST" 2>/dev/null || true)"
if [ -z "$DST_REAL" ]; then
    # DST may not exist yet; canonicalize its nearest existing ancestor.
    DST_PARENT="$(dirname -- "$DST")"
    DST_BASE="$(basename -- "$DST")"
    DST_PARENT_REAL="$(realpath -e -- "$DST_PARENT" 2>/dev/null)" \
        || die "DST parent not found: $DST_PARENT" $EXIT_GUARD
    DST_REAL="$DST_PARENT_REAL/$DST_BASE"
fi

[ "$SRC_REAL" = "$DST_REAL" ] && die "SRC==DST (A11): $SRC_REAL" $EXIT_GUARD
# ancestor/descendant check (string-prefix with boundary)
case "$DST_REAL/" in
    "$SRC_REAL"/*) die "DST inside SRC (A11): $DST_REAL" $EXIT_GUARD ;;
esac
case "$SRC_REAL/" in
    "$DST_REAL"/*) die "SRC inside DST (A11): $SRC_REAL" $EXIT_GUARD ;;
esac
# DST symlink resolving into SRC (redundant with realpath check but explicit)
if [ -L "$DST" ]; then
    DST_LINK="$(realpath -- "$DST" 2>/dev/null || true)"
    case "$DST_LINK/" in
        "$SRC_REAL"/*) die "DST symlink resolves into SRC (A11)" $EXIT_GUARD ;;
    esac
fi

# A8: force LOG outside DST (before ANY write, incl. LOG itself)
LOG_REAL="$(realpath -m -- "$LOG" 2>/dev/null || printf '%s' "$LOG")"
case "$LOG_REAL/" in
    "$DST_REAL"/*) LOG="$HOME/.cache/hermes-context-sync.log" ;;
esac
[ -n "$LOG" ] || LOG="$HOME/.cache/hermes-context-sync.log"

# --- 1e. Self-verify (A9): contents, structure, symlinks ---------------------
# Emits NUL-delimited records: "D <path>", "F <path>", "L <path> -> <target>"
fingerprint() { # $1 = root
    local root="$1" p
    if [ ! -d "$root" ]; then return 1; fi
    ( cd "$root" && find . -mindepth 1 -print0 ) |
    while IFS= read -r -d '' p; do
        if [ -L "$root/$p" ]; then
            printf 'L %s -> %s\0' "$p" "$(readlink -- "$root/$p")"
        elif [ -d "$root/$p" ]; then
            printf 'D %s\0' "$p"
        else
            printf 'F %s\0' "$p"
        fi
    done
}

verify() { # $1 = SRC root, $2 = DST root
    local sroot="$1" droot="$2" tmpL tmpR p
    [ -d "$sroot" ] || return 1
    tmpL="$(mktemp)" || return 1
    tmpR="$(mktemp)" || { rm -f "$tmpL"; return 1; }
    fingerprint "$sroot" | sort -z > "$tmpL"
    fingerprint "$droot" | sort -z > "$tmpR" || : > "$tmpR"
    cmp -s "$tmpL" "$tmpR"
    local rc_struct=$?
    rm -f "$tmpL" "$tmpR"
    [ "$rc_struct" -eq 0 ] || return 1
    # contents: byte-compare every regular file (NUL-delimited traversal)
    local fail=0
    while IFS= read -r -d '' p; do
        if ! cmp -s -- "$sroot/$p" "$droot/$p"; then
            fail=1
            break
        fi
    done < <( cd "$sroot" && find . -mindepth 1 -type f -print0 )
    return "$fail"
}

# --- Fallback copy (A4/A7): NUL-delimited find, any depth, staged first ------
fallback_copy() { # $1 = staging dir
    local stage="$1"
    if command -v cpio >/dev/null 2>&1; then
        ( cd "$SRC_REAL" && find . -mindepth 1 -print0 |
          cpio -0 -pdm --quiet "$stage" 2>/dev/null ) && return 0
    fi
    if command -v tar >/dev/null 2>&1; then
        ( cd "$SRC_REAL" && find . -mindepth 1 -print0 |
          tar --null -T - -cf - 2>/dev/null |
          tar -xf - -C "$stage" 2>/dev/null ) && return 0
    fi
    # last resort: cp -a with NUL-safe per-entry copy
    mkdir -p "$stage" || return 1
    while IFS= read -r -d '' p; do
        cp -a -- "$SRC_REAL/$p" "$stage/$p" 2>/dev/null || return 1
    done < <( cd "$SRC_REAL" && find . -mindepth 1 -print0 )
    return 0
}

# --- 1c/1d. Sync --------------------------------------------------------------
RSYNC_BIN="$(command -v rsync 2>/dev/null || true)"

if [ "$DRY_RUN" -eq 1 ]; then
    # A6: zero writes of any kind, including LOG. Plan/diff computation only.
    if [ -n "$RSYNC_BIN" ]; then
        "$RSYNC_BIN" -aN --delete --dry-run -- "$SRC_REAL/" "$DST_REAL/" >/dev/null 2>&1
        # plan-only: a differing tree is the expected plan signal, not a defect
        exit $EXIT_OK
    fi
    # fallback plan: NUL-delimited diff of trees; no writes, no action
    verify "$SRC_REAL" "$DST_REAL" >/dev/null 2>&1 || true
    exit $EXIT_OK
fi

# --- Real run -----------------------------------------------------------------
mkdir -p -- "$DST_REAL" || die "cannot create DST: $DST_REAL" $EXIT_GUARD

if [ -n "$RSYNC_BIN" ]; then
    "$RSYNC_BIN" -a --delete -- "$SRC_REAL/" "$DST_REAL/" \
        || die "rsync failed" $EXIT_VERIFY
else
    # A7 fallback: stage a verified copy elsewhere, then swap into place.
    # Never rm -rf DST before a verified copy exists elsewhere (A11).
    DST_PARENT_DIR="$(dirname -- "$DST_REAL")"
    STAGE="$(mktemp -d "${DST_PARENT_DIR}/.hermes-sync-stage.XXXXXX")" \
        || die "cannot create staging dir" $EXIT_VERIFY
    fallback_copy "$STAGE" \
        || { rm -rf -- "$STAGE"; die "fallback copy failed" $EXIT_VERIFY; }
    verify "$SRC_REAL" "$STAGE" \
        || { rm -rf -- "$STAGE"; die "staged copy failed verification (A9)" $EXIT_VERIFY; }
    # verified copy now exists (STAGE); swap is safe
    OLD="$(mktemp -d "${DST_PARENT_DIR}/.hermes-sync-old.XXXXXX")" \
        || { rm -rf -- "$STAGE"; die "cannot stage old DST" $EXIT_VERIFY; }
    rmdir -- "$OLD" || { rm -rf -- "$STAGE"; die "swap prep failed" $EXIT_VERIFY; }
    mv -- "$DST_REAL" "$OLD" \
        || { rm -rf -- "$STAGE"; die "swap failed" $EXIT_VERIFY; }
    mv -- "$STAGE" "$DST_REAL" \
        || { mv -- "$OLD" "$DST_REAL" 2>/dev/null; rm -rf -- "$STAGE"; die "swap-in failed" $EXIT_VERIFY; }
    rm -rf -- "$OLD"
fi

# --- Verify (A9) ---------------------------------------------------------------
verify "$SRC_REAL" "$DST_REAL" \
    || die "post-sync verification failed (A9)" $EXIT_VERIFY

# --- Log (A14): 1 line, real-run only ------------------------------------------
mkdir -p -- "$(dirname -- "$LOG")" 2>/dev/null || true
printf '%s sync-hermes-context ok %s -> %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SRC_REAL" "$DST_REAL" >> "$LOG" 2>/dev/null || true

exit $EXIT_OK

