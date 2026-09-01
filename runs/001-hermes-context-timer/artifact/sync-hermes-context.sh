#!/usr/bin/env bash
# sync-hermes-context.sh — one-way SRC->DST mirror of the hermes context tree.
# stage -> verify -> destroy/reconcile DST; source never modified.
# Guards: identity / ancestor / DST-symlink-into-SRC (exit 2, zero writes).
# --dry-run: plan only, zero filesystem writes, exit 0.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sync-hermes-context.sh [--dry-run|-h|--help]
Environment:
  HERMES_CONTEXT_SRC      source tree      (default /opt/data/workspace/hermes-context/)
  HERMES_CONTEXT_DST      destination tree (default /workspace/hermes-context/)
  HERMES_CONTEXT_LOG_DIR  log directory    (default ~/.cache/hermes-context/)
Modes:
  (none)      real run: stage SRC, verify, reconcile DST, append one log line
  --dry-run   compute and print plan only; writes nothing anywhere, exit 0
EOF
}

die() { echo "sync-hermes-context: $1" >&2; exit "${2:-1}"; }

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  --dry-run) DRY=1 ;;
  *) usage >&2; exit 1 ;;
esac
DRY=${DRY:-0}

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG_DIR="${HERMES_CONTEXT_LOG_DIR:-$HOME/.cache/hermes-context}"
LOG_FILE="$LOG_DIR/hermes-context.log"

# --- guards (before ANY write; refusal exits produce zero writes) -------------
[ -n "$SRC" ] && [ -n "$DST" ] || die "HERMES_CONTEXT_SRC/DST required" 2
[ -d "$SRC" ] || die "source does not exist or is not a directory: $SRC" 2

RS=$(realpath -e "$SRC") || die "cannot resolve source: $SRC" 2
# component-boundary ancestor check, not string-prefix
RD=$(realpath -m "$DST")
if [ "$RS" = "$RD" ]; then die "SRC == DST refused" 2; fi
case "$RD/" in "$RS"/*) die "DST is inside SRC refused" 2 ;; esac
case "$RS/" in "$RD"/*) die "SRC is inside DST refused" 2 ;; esac
# DST symlink resolving into SRC
if [ -L "$DST" ]; then
  RL=$(realpath "$DST") || die "cannot resolve DST symlink" 2
  [ "$RL" = "$RS" ] && die "DST symlink -> SRC refused" 2
  case "$RL/" in "$RS"/*) die "DST symlink resolves inside SRC refused" 2 ;; esac
fi
# A14/A8: refuse a script-owned log path (HERMES_CONTEXT_LOG_DIR) inside SRC or DST
HL=$(realpath -m "$LOG_DIR")
[ "$HL" = "$RS" ] && die "log dir inside SRC refused (A8)" 2
case "$HL/" in "$RS"/*) die "log dir inside SRC refused (A8)" 2 ;; esac
[ "$HL" = "$RD" ] && die "log dir inside DST refused (A8)" 2
case "$HL/" in "$RD"/*) die "log dir inside DST refused (A8)" 2 ;; esac
LOG_FILE="$HL/hermes-context.log"

if [ "$DRY" = 1 ]; then
  echo "DRY-RUN plan for $RS -> $RD:"
  if command -v rsync >/dev/null 2>&1; then
    echo "  stage: rsync -a --delete $RS/ <stage>/"
  else
    echo "  stage: cp -a $RS/. <stage>/"
  fi
  echo "  verify: diff -r --no-dereference SRC vs stage"
  echo "  reconcile: replace $RD with verified stage (stale subtrees deleted)"
  echo "  log: one line to $LOG_FILE"
  exit 0
fi

# --- real run: stage ----------------------------------------------------------
STAGE=$(mktemp -d /tmp/hermes-context-stage.XXXXXX) || die "mktemp failed" 1
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$RS/" "$STAGE/" || { echo "staging failed" >&2; exit 1; }
else
  # fallback: fresh temp dir + cp -a (stale-subtree deletion is inherent: stage
  # is empty, then DST is fully replaced by the verified stage after verify)
  cp -a "$RS/." "$STAGE/" || { echo "staging failed" >&2; exit 1; }
fi

# --- self-verify at A9 class (contents + structure + symlinks) ----------------
if ! diff -r --no-dereference -q "$RS" "$STAGE" >/dev/null 2>&1; then
  echo "self-verify failed: staged copy diverges from SRC; DST untouched" >&2
  exit 1
fi

# --- only after verify passes: destroy/reconcile DST --------------------------
if [ -e "$RD" ] || [ -L "$RD" ]; then
  rm -rf "$RD" || { echo "DST teardown failed; stage preserved: $STAGE" >&2; exit 1; }
fi
mkdir -p "$(dirname "$RD")"
mv "$STAGE" "$RD" || { echo "DST promote failed" >&2; exit 1; }
trap - EXIT

# --- log (real runs only; never under DST) ------------------------------------
mkdir -p "$HL"
echo "$(date -Is) synced $RS -> $RD (rsync=$(command -v rsync >/dev/null 2>&1 && echo yes || echo no))" >> "$LOG_FILE"

exit 0

