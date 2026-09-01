#!/usr/bin/env bash
# sync-hermes-context.sh — mirror SRC -> DST (host -> workspace, one-way, A2)
# PIPE law: guards -> stage -> verify_stage -> reconcile -> verify_final -> summary
# Path-law citations: A12 identity, A14/A15 concrete owned paths, A18 degenerate, A8 log placement.
set -euo pipefail

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG="${HERMES_CONTEXT_LOG:-$HOME/.cache/hermes-context/sync.log}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

refuse() { echo "REFUSE [$1] $2" >&2; exit 1; }

rp() { # realpath, tolerant of nonexistent leaf
  if command -v realpath >/dev/null 2>&1; then realpath -m -- "$1"; else readlink -f -- "$1"; fi
}
rpe() { # realpath of existing path
  if command -v realpath >/dev/null 2>&1; then realpath -e -- "$1" 2>/dev/null || readlink -f -- "$1"; else readlink -f -- "$1"; fi
}
inside_or_eq() { # eq-or-inside, boundary-aware component compare (A15)
  case "$2" in "$1"|"$1"/*) return 0 ;; *) return 1 ;; esac
}

# --- guards (before ANY write) — A18 degenerate (component tests, not slash-suffix strings) ---
for p in "$SRC" "$DST"; do
  [ -n "$p" ] || refuse A18 "degenerate path: empty string"
  case "$p" in /|.|//|./) refuse A18 "degenerate path: $p" ;; esac
done

rsrc=$(rpe "$SRC") || refuse A18 "cannot resolve SRC"
rdst=$(rp "$DST")

# --- A12 identity / ancestor / descendant / DST-symlink-into-SRC (realpath, not string equality) ---
inside_or_eq "$rsrc" "$rdst" && refuse A12 "DST equals or lies inside SRC (realpath): $rdst"
inside_or_eq "$rdst" "$rsrc" && refuse A12 "SRC equals or lies inside DST (realpath): $rsrc"

# --- A14/A15: concrete owned paths vs DST (entrypoint dir, resolved log FILE parent).
# NOTE: TMPDIR itself is a generic ancestor, NOT an owned path (A15 calibration: /tmp is
# not concrete). Only the concrete mktemp -d result is checked, post-instantiation.
ENTRY_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
LOGPARENT=$(rp -- "$(dirname -- "$LOG")")
for owned in "$ENTRY_DIR" "$LOGPARENT"; do
  inside_or_eq "$owned" "$rdst" && refuse A14 "owned path is/inside DST: $owned"
  inside_or_eq "$rdst" "$owned" && refuse A15 "DST is/inside owned path: $owned"
done
# A8: log FILE parent must lie outside DST (checked above via concrete LOGPARENT).

if [ "$DRY_RUN" -eq 1 ]; then
  # A6/A16: zero writes — no log file, no stage dir, no mkdir DST; summary to stdout only
  echo "DRY-RUN SUMMARY [A6: zero writes performed]"
  echo "  src: $SRC ($rsrc)"
  echo "  dst: $DST ($rdst)"
  echo "  log: $LOG"
  echo "  plan: stage -> verify_stage -> reconcile (prune stale, all depths) -> verify_final"
  echo "  result: would converge DST to mirror of SRC (recursive, idempotent)"
  exit 0
fi

# --- real run: concrete stage (script-owned; A14/A15 check the CONCRETE path only) ---
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/hermes-context-stage.XXXXXX") || exit 1
trap 'rm -rf -- "$STAGE"' EXIT
cstage=$(rpe "$STAGE")
# A14: the resolved staging must be inside neither DST nor SRC (a TMPDIR under SRC
# would place the stage inside the source tree and contaminate it).
inside_or_eq "$cstage" "$rdst" && refuse A14 "resolved staging is/inside DST: $cstage"
inside_or_eq "$rdst" "$cstage" && refuse A15 "DST is/inside resolved staging: $cstage"
inside_or_eq "$cstage" "$rsrc" && refuse A14 "resolved staging is/inside SRC: $cstage"
inside_or_eq "$rsrc" "$cstage" && refuse A15 "SRC is/inside resolved staging: $cstage"
# Note: the stage is created by mktemp before these checks (a concrete path must exist
# to be resolved); on any refusal the EXIT trap removes it, so DST/SRC are untouched.

HAVE_RSYNC=0
command -v rsync >/dev/null 2>&1 && HAVE_RSYNC=1

# --- stage: copy SRC contents -> stage (contents sync, never nested) ---
if [ "$HAVE_RSYNC" -eq 1 ]; then
  rsync -a --delete "$SRC"/ "$STAGE"/
else
  # A4 fallback: cp -a semantics; prune happens at reconcile
  cp -a "$SRC/." "$STAGE"/
fi

# --- verify_stage (A9/A13): verified copy before DST is touched ---
diff -r --no-dereference "$SRC" "$STAGE" >/dev/null \
  || { echo "FAIL [A9] stage verification mismatch (contents/structure/symlink-targets)" >&2; exit 1; }

# --- reconcile (A11/A13/A18): verified stage exists; only now touch DST ---
# A18: a pre-existing DST symlink is replaced (never followed); but if it resolves
# outside SRC it is refused outright (A12) — replacement is only for in-family links.
if [ -L "$DST" ]; then
  ltarget=$(rp -- "$DST")
  inside_or_eq "$rsrc" "$ltarget" || refuse A18 "DST symlink resolves outside SRC: $ltarget"
  rm -f -- "$DST"
fi
mkdir -p -- "$DST"
if [ "$HAVE_RSYNC" -eq 1 ]; then
  rsync -a --delete "$STAGE"/ "$DST"/
else
  # remove type mismatches (file<->dir, symlink<->file) before copy
  (cd "$STAGE" && find . -mindepth 1 -print0) | while IFS= read -r -d '' p; do
    d="$DST/$p"
    if [ -L "$d" ] || { [ -e "$d" ] && { { [ -d "$STAGE/$p" ] && [ ! -d "$d" ]; } || { [ ! -d "$STAGE/$p" ] && [ -d "$d" ]; }; }; }; then
      rm -rf -- "$d"
    fi
  done
  cp -a "$STAGE/." "$DST"/
  # prune stale subtrees in DST, all depths (A5)
  (cd "$DST" && find . -mindepth 1 -depth -print0) > "$STAGE/.prunelist"
  while IFS= read -r -d '' p; do
    { [ -e "$STAGE/$p" ] || [ -L "$STAGE/$p" ]; } || rm -rf -- "$DST/$p"
  done < "$STAGE/.prunelist"
  rm -f -- "$STAGE/.prunelist"
fi

# --- verify_final (A9): DST end == SRC end per MIRROR class ---
diff -r --no-dereference "$SRC" "$DST" >/dev/null \
  || { echo "FAIL [A9] final verification mismatch: DST != SRC" >&2; exit 1; }

# --- summary + log (A8: log parent verified outside DST in guards) ---
SUMMARY="sync OK: $rsrc -> $rdst (mirror verified, idempotent; rsync=$HAVE_RSYNC)"
echo "$SUMMARY"
mkdir -p -- "$(dirname -- "$LOG")"
printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SUMMARY" >> "$LOG"

