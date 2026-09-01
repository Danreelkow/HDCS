#!/usr/bin/env bash
# sync-hermes-context.sh — one-way contents-sync SRC -> DST (A2).
# Order: stage -> verify (content-compare) -> touch DST (A13).
# Mirror class: contents, structure, symlinks only (A9). --dry-run writes nothing (A6).
set -euo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

# s0 defaults, env-overridable (1.1)
SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG="${HERMES_CTX_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/sync-hermes-context.log}"
PROTECTED="${HERMES_CTX_PROTECTED:-/ /etc /usr /bin /sbin /var /boot /dev /proc /sys}"

err() { echo "sync-hermes-context: $*" >&2; exit 1; }

# boundary-aware containment: compare path components, not bare string prefix (A15)
under() {
  local p="${1%/}" d="${2%/}"
  [ "$p" = "$d" ] && return 0
  case "$d/" in "$p"/*) return 0 ;; esac
  return 1
}

# --- guards (run before any destructive op) ---
[ -d "$SRC" ] || err "SRC is not a directory: $SRC"
[ "$SRC" != "$DST" ] || err "SRC equals DST — abort (A11)"
RSRC=$(realpath -e "$SRC") || err "cannot resolve SRC: $SRC"

# --- plan phase: --dry-run computes plan, writes nothing, no log file (A6) ---
# Missing DST is a valid dry-run input: plan is a full population; zero writes.
if [ "$DRY" -eq 1 ]; then
  if [ ! -d "$DST" ]; then
    N=$(find "$RSRC" | wc -l)
    echo "DRY-RUN: DST missing — full population of $N entries planned; SRC=$RSRC -> DST=$DST; zero writes (incl. logs)"
    exit 0
  fi
  RDST=$(realpath -e "$DST") || err "cannot resolve DST: $DST"
  [ "$RSRC" != "$RDST" ] || err "realpath(SRC) == realpath(DST) — abort (A12)"
  for P in $PROTECTED; do
    RP=$(realpath -e "$P" 2>/dev/null) || continue
    under "$RP" "$RDST" && err "DST $RDST is at or under protected path $P — abort (A14)"
  done
  if command -v rsync >/dev/null 2>&1; then
    PLAN=$(rsync -ain --delete "$RSRC"/ "$RDST"/) || err "rsync plan failed"
  else
    PLAN=$(diff -r "$RSRC"/. "$RDST"/. 2>&1 || true)
  fi
  N=$(printf '%s\n' "$PLAN" | grep -c . || true); N=${N:-0}
  echo "DRY-RUN: $N change line(s) planned; SRC=$RSRC -> DST=$RDST; zero writes (incl. logs)"
  exit 0
fi

# --- real run: full guards ---
[ -d "$DST" ] || err "DST is not a directory: $DST"
RSRC=$(realpath -e "$SRC") || err "cannot resolve SRC: $SRC"
RDST=$(realpath -e "$DST") || err "cannot resolve DST: $DST"
[ "$RSRC" != "$RDST" ] || err "realpath(SRC) == realpath(DST) — abort (A12)"
# A14/A15 protected-path guard over owned concrete paths
for P in $PROTECTED; do
  RP=$(realpath -e "$P" 2>/dev/null) || continue
  under "$RP" "$RDST" && err "DST $RDST is at or under protected path $P — abort (A14)"
done
# A8: log path must never live inside the mirrored tree
under "$RDST" "$LOG" && err "log path $LOG is inside DST — refusing (A8)"

# --- stage phase ---
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/sync-hermes-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
if command -v rsync >/dev/null 2>&1; then
  # path A: rsync; symlinks copied as symlinks (--copy-links off by default)
  rsync -a --delete "$RSRC"/ "$STAGE"/
else
  # path B: tar pipe; deletions propagate because DST contents are replaced wholesale later
  (cd "$RSRC" && tar cf - .) | (cd "$STAGE" && tar xf -)
fi

# --- verify phase: content-compare SRC vs STAGE; mismatch -> nonzero, DST untouched (A9) ---
set +e
VOUT=$(diff -r --no-dereference "$RSRC"/. "$STAGE"/. 2>&1)
VRC=$?
if [ "$VRC" -ge 2 ]; then
  # older diffutils without --no-dereference
  VOUT=$(diff -r "$RSRC"/. "$STAGE"/. 2>&1)
  VRC=$?
fi
set -e
[ "$VRC" -eq 0 ] || err "verify failed (stage discarded, DST untouched): $VOUT"

# --- touch DST phase: destructive op only after verified copy (A13) ---
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$STAGE"/ "$RDST"/
else
  rm -rf "$RDST"/* "$RDST"/.[!.]* "$RDST"/..?* 2>/dev/null || true
  cp -a "$STAGE"/. "$RDST"/
fi

# --- log one-line summary, outside DST only ---
N=$(find "$STAGE" | wc -l)
mkdir -p "$(dirname "$LOG")"
printf '%s sync ok SRC=%s DST=%s entries=%s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$RSRC" "$RDST" "$N" >> "$LOG"
exit 0

