#!/usr/bin/env bash
# sync-hermes-context.sh — one-way sync of hermes context from host mount to workspace
# Usage: sync-hermes-context.sh [--dry-run]
set -u -o pipefail

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG_FILE="${HERMES_CONTEXT_LOG:-/tmp/hermes-context-sync.log}"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

MODE="sync"
[ "$DRY" -eq 1 ] && MODE="dry-run"

TOOL="unknown"
TRANSFERRED=0
SKIPPED=0

summary() {
    # $1 = ok|error
    local line
    line="mode=${MODE} tool=${TOOL} dir=host->workspace transferred=${TRANSFERRED} skipped=${SKIPPED} status=$1"
    echo "$line"
    echo "$line" >>"$LOG_FILE" 2>/dev/null || true
}

fail() {
    echo "ERROR: $*" >&2
    summary error
    exit 1
}

# Validate source (read-only; never write to SRC)
if [ ! -d "$SRC" ]; then
    fail "source directory not found: $SRC"
fi

# Ensure destination exists (skip in dry-run: zero mutations)
if [ "$DRY" -eq 0 ]; then
    mkdir -p "$DST" || fail "cannot create destination: $DST"
fi

# Files living inside DST that must never be deleted by fallbacks
PROTECTED=(sync-hermes-context.sh hermes-context.service hermes-context.timer README.md)

if command -v rsync >/dev/null 2>&1; then
    TOOL="rsync"
    # Trailing slashes => sync contents, no nesting.
    # Excludes protect the script/units/README that live inside DST itself.
    CMD=(rsync -a --delete
         --exclude='sync-hermes-context.sh'
         --exclude='hermes-context.service'
         --exclude='hermes-context.timer'
         --exclude='README.md'
         --itemize-changes)
    [ "$DRY" -eq 1 ] && CMD+=(--dry-run)
    OUT="$("${CMD[@]}" "${SRC}/" "${DST}/")" || fail "rsync failed"
    # Itemized lines beginning with >f, <f, .f, *deleting etc. indicate changes
    TRANSFERRED=$(printf '%s\n' "$OUT" | grep -cE '^[<>ch.]f|\*deleting' || true)
    TOTAL=$(find "$SRC" -type f | wc -l)
    SKIPPED=$(( TOTAL > TRANSFERRED ? TOTAL - TRANSFERRED : 0 ))
elif command -v cp >/dev/null 2>&1; then
    TOOL="cp"
    # Read-only comparison first (works for both dry-run and counting)
    DIFFOUT="$(diff -rq "$SRC" "$DST" 2>/dev/null || true)"
    TRANSFERRED=$(printf '%s\n' "$DIFFOUT" | grep -c . || true)
    TOTAL=$(find "$SRC" -type f | wc -l)
    SKIPPED=$(( TOTAL > TRANSFERRED ? TOTAL - TRANSFERRED : 0 ))
    if [ "$DRY" -eq 0 ]; then
        # No --delete semantics: idempotent overwrite; never removes script/units/README
        cp -a "${SRC}/." "${DST}/" || fail "cp fallback failed"
    fi
elif command -v tar >/dev/null 2>&1; then
    TOOL="tar"
    DIFFOUT="$(diff -rq "$SRC" "$DST" 2>/dev/null || true)"
    TRANSFERRED=$(printf '%s\n' "$DIFFOUT" | grep -c . || true)
    TOTAL=$(find "$SRC" -type f | wc -l)
    SKIPPED=$(( TOTAL > TRANSFERRED ? TOTAL - TRANSFERRED : 0 ))
    if [ "$DRY" -eq 0 ]; then
        tar -C "$SRC" -cf - . | tar -C "$DST" -xf - || fail "tar pipe fallback failed"
    fi
else
    fail "no sync tool available (rsync, cp, tar)"
fi

summary ok
exit 0

