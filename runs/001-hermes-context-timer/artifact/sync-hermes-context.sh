#!/usr/bin/env bash
# sync-hermes-context.sh — one-way exact mirror SRC -> DST (A1..A13).
# Order law (A13/A11): stage -> verify (A9 class) -> then touch DST.
# Standalone; no systemd required. User-level only, no root.
set -u

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
elif [ $# -gt 0 ]; then
  echo "usage: sync-hermes-context.sh [--dry-run]" >&2
  exit 2
fi

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"

# --- A12 guard: realpath identity check, pre-flight, before ANY write ---
if ! command -v realpath >/dev/null 2>&1; then
  echo "guard: realpath(1) unavailable; refusing to run" >&2
  exit 2
fi
SRC_R=$(realpath -e "$SRC" 2>/dev/null) || { echo "guard: SRC '$SRC' not resolvable" >&2; exit 2; }
DST_R=$(realpath -m "$DST" 2>/dev/null) || { echo "guard: DST '$DST' not resolvable" >&2; exit 2; }
if [ "$SRC_R" = "$DST_R" ]; then
  echo "guard: SRC and DST resolve to the same path ($SRC_R); refusing no-op/destroy" >&2
  exit 2
fi
case "$DST_R/" in "$SRC_R"/*)
  echo "guard: DST ($DST_R) is inside SRC ($SRC_R); refusing" >&2; exit 2 ;;
esac
case "$SRC_R/" in "$DST_R"/*)
  echo "guard: SRC ($SRC_R) is inside DST ($DST_R); refusing" >&2; exit 2 ;;
esac
# --- end guard ---

# A8: log path fixed under ~/.cache, never under DST, never env-overridable.
LOG_DIR="${HOME}/.cache/hermes-context"
LOG_FILE="${LOG_DIR}/sync.log"

# verify_mirror SRC DST — A9 class: contents + recursive structure + symlink targets.
# Returns nonzero on any mismatch; never warn-and-exit-0.
verify_mirror() {
  _vs="$1"; _vd="$2"
  if ! diff -r "$_vs" "$_vd" >/dev/null 2>&1; then
    echo "verify: content/structure mismatch between $_vs and $_vd" >&2
    diff -r "$_vs" "$_vd" 2>&1 | head -20 >&2
    return 1
  fi
  while IFS= read -r -d '' _p; do
    _rel=${_p#"$_vs"/}
    if [ ! -L "$_vd/$_rel" ]; then
      echo "verify: symlink missing in mirror: $_rel" >&2
      return 1
    fi
    if [ "$(readlink "$_p")" != "$(readlink "$_vd/$_rel")" ]; then
      echo "verify: symlink target mismatch: $_rel" >&2
      return 1
    fi
  done < <(find "$_vs" -type l -print0)
  while IFS= read -r -d '' _p; do
    _rel=${_p#"$_vd"/}
    if [ ! -L "$_vs/$_rel" ] && [ ! -e "$_vs/$_rel" ]; then
      echo "verify: extra entry in mirror: $_rel" >&2
      return 1
    fi
  done < <(find "$_vd" -type l -print0)
  return 0
}

# log_line MODE STATUS — one-line summary per real run; dry-run never logs.
log_line() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOG_FILE" 2>/dev/null || true
}

# --- dry-run path (A6): zero writes, no log file, stdout only ---
if [ "$DRY_RUN" -eq 1 ]; then
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --dry-run -v "$SRC_R/" "$DST_R/"
  else
    echo "dry-run (fallback, rsync absent): planned full reconcile of $DST_R from $SRC_R"
    diff -r "$SRC_R" "$DST_R" 2>&1 || true
  fi
  exit 0
fi

# --- real run: stage -> verify -> reconcile DST (A13/A11 order, both paths) ---
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/hermes-stage.XXXXXX") || {
  echo "mktemp failed" >&2; exit 1; }

# 1) Stage SRC into STAGE (content-copy only; DST untouched so far).
if command -v rsync >/dev/null 2>&1; then
  MODE="rsync"
  if ! rsync -a --delete "$SRC_R/" "$STAGE/"; then
    echo "rsync staging failed; DST untouched" >&2
    rm -rf -- "$STAGE"; exit 1
  fi
else
  MODE="fallback"
  if ! cp -a "$SRC_R/." "$STAGE/" 2>/dev/null; then
    tar -C "$SRC_R" -cf - . | tar -C "$STAGE" -xf - || {
      echo "fallback staging failed; DST untouched" >&2; rm -rf -- "$STAGE"; exit 1; }
  fi
fi

# 2) Verify stage against SRC (A9 class) BEFORE touching DST.
if ! verify_mirror "$SRC_R" "$STAGE"; then
  echo "verify: staged copy failed verification; DST left untouched" >&2
  log_line "$MODE VERIFY-FAIL dst=$DST_R"
  rm -rf -- "$STAGE"
  exit 1
fi
# Verified copy of SRC now exists outside DST (A11 satisfied).

# 3) Reconcile DST from the verified stage: full mirror, stale deleted at all depths.
mkdir -p "$DST_R" || { echo "cannot create DST $DST_R" >&2; rm -rf -- "$STAGE"; exit 1; }
find "$DST_R" -mindepth 1 -depth -exec rm -rf -- {} + 2>/dev/null
if command -v rsync >/dev/null 2>&1; then
  if ! rsync -a "$STAGE/" "$DST_R/"; then
    echo "rsync copy to DST failed" >&2
    log_line "$MODE FAIL dst=$DST_R"
    rm -rf -- "$STAGE"; exit 1
  fi
else
  if ! cp -a "$STAGE/." "$DST_R/"; then
    echo "fallback copy to DST failed" >&2
    log_line "$MODE FAIL dst=$DST_R"
    rm -rf -- "$STAGE"; exit 1
  fi
fi

# 4) Final verify of DST against SRC (A9 class). Nonzero on any mismatch.
if ! verify_mirror "$SRC_R" "$DST_R"; then
  log_line "$MODE VERIFY-FAIL dst=$DST_R"
  rm -rf -- "$STAGE"
  exit 1
fi

rm -rf -- "$STAGE"
log_line "$MODE OK src=$SRC_R dst=$DST_R"
echo "sync ok ($MODE): $SRC_R -> $DST_R"
exit 0

