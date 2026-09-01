#!/usr/bin/env bash
# sync-hermes-context.sh — mirror SRC -> DST (stage -> verify -> touch DST)
# A5/A6/A13/A17/A18. Standalone or systemd --user. No root.
set -euo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context}"
SRC="${SRC%/}"; DST="${DST%/}"

fail() { echo "sync-hermes-context: REFUSED: $*" >&2; exit 1; }

# ---- A18 guards: pre-write, both modes ----
[ -n "$SRC" ] || fail "SRC is empty"
[ -n "$DST" ] || fail "DST is empty"
[ "$SRC" != "/" ] && [ "$DST" != "/" ] || fail "degenerate path: /"
[ "$SRC" != "." ] && [ "$DST" != "." ] || fail "degenerate path: ."
[ -d "$SRC" ] || fail "SRC is not a directory: $SRC"
RSRC=$(realpath -e "$SRC") || fail "SRC not realpath-resolvable: $SRC"
PROSD=$(realpath -m "$DST") || fail "DST unresolvable"
[ "$RSRC" = "$PROSD" ] && fail "realpath(SRC) == realpath(DST)"
case "$PROSD/" in "$RSRC"/*) fail "DST is inside SRC";; esac
case "$RSRC/" in "$PROSD"/*) fail "SRC is inside DST";; esac

# A18 component-boundary: the component boundary of DST is the deepest
# EXISTING component of the DST path; it must be owned by the invoking user.
# (A not-yet-existing DST root under an existing user-owned component is in
# bounds; a DST whose nearest existing ancestor is foreign is refused.)
BD="$PROSD"
while [ ! -e "$BD" ]; do BD=$(dirname "$BD"); done
BD=$(realpath -e "$BD")
[ "$(stat -c %u "$BD")" = "$(id -u)" ] || fail "component boundary not owned by invoking user: $BD (DST=$PROSD)"

if [ "$DRY" -eq 1 ]; then
  # A6: dry-run — zero write ops (no mkdir, no touch, no log write)
  echo "PLAN (dry-run): mirror $RSRC -> $PROSD"
  if command -v rsync >/dev/null 2>&1; then
    rsync -rlptgoD --delete --dry-run "$RSRC"/ "$PROSD"/
  else
    (cd "$RSRC" && find . -mindepth 1 -print)
  fi
  exit 0
fi

# ---- real run: log path (outside DST), stage, verify, touch DST ----
LOG="${HERMES_CTX_LOG:-$HOME/.cache/hermes-context/sync.log}"
LOGR=$(realpath -m "$LOG")
case "$LOGR/" in "$PROSD"/*) fail "log override points inside DST: $LOG";; esac
mkdir -p "$(dirname "$LOG")"

STAGE=$(mktemp -d "${PROSD}.stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

# A13 stage 1: build full stage on DST filesystem (fresh dir => deletions reconciled)
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$RSRC"/ "$STAGE"/
else
  cp -a "$RSRC"/. "$STAGE"/
fi

# A13 stage 2: verify content comparison (structure + contents + symlink targets)
diff -r --no-dereference "$RSRC" "$STAGE" || fail "verify failed: stage != SRC; DST untouched"

# A13 stage 3: touch DST only after verify passes
rm -rf "$PROSD"
mv "$STAGE" "$PROSD"
trap - EXIT
printf '%s real sync %s -> %s\n' "$(date -u +%FT%TZ)" "$RSRC" "$PROSD" >> "$LOG"
exit 0

