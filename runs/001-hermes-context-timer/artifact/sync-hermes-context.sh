#!/usr/bin/env bash
# sync-hermes-context.sh — one-way freshness mirror SRC -> DST (hermes-context)
# Standalone-executable and systemd-user-invokable (A3). Refusals cite A-numbers (A19).
# Laws: A4,A5,A6,A7,A8,A9,A11,A12,A13,A14/A15,A16,A18,A20,A22.
set -u

MODE=sync
case "${1-}" in
  --dry-run) MODE=dry ;;
  --verify)  MODE=verify ;;
  "") ;;
  *) echo "usage: $0 [--dry-run|--verify]" >&2; exit 2 ;;
esac

die()  { echo "REFUSED: $1" >&2; exit 1; }
fail() { echo "SYNC FAIL: $1" >&2; exit 1; }

# canonicalize: strip trailing slashes exactly once-cycle; result is the only form used afterwards (ledger #7)
canon() {
  local p=$1
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p=${p%/}; done
  [ -z "$p" ] && p="/"
  printf '%s' "$p"
}
rp() { readlink -f -- "$1"; }

# ---- env (8b: explicit empty check, never swallow into default) ----
SRC_RAW=${HERMES_CONTEXT_SRC-default}
DST_RAW=${HERMES_CONTEXT_DST-default}
LOG_RAW=${HERMES_CONTEXT_LOG_DIR-default}
[ -z "$SRC_RAW" ] && die "A18: HERMES_CONTEXT_SRC explicitly empty — refusing, no default fallback"
[ -z "$DST_RAW" ] && die "A18: HERMES_CONTEXT_DST explicitly empty — refusing, no default fallback"
[ -z "$LOG_RAW" ] && die "A18: HERMES_CONTEXT_LOG_DIR explicitly empty — refusing, no default fallback"
SRC=$(canon "${SRC_RAW:-/opt/data/workspace/hermes-context/}")
DST=$(canon "${DST_RAW:-/workspace/hermes-context/}")
LOG_DIR=$(canon "$LOG_RAW")

SCRIPT_PATH=$(rp "${BASH_SOURCE[0]}") || SCRIPT_PATH="${BASH_SOURCE[0]}"
ENTRY_DIR=$(dirname -- "$SCRIPT_PATH")

# ---- A18 degenerate paths (component test on canonical string, not slash suffix) ----
for P in "$SRC" "$DST"; do
  [ "$P" = "/" ] && die "A18: degenerate path '/' refused"
  [ "$P" = "." ] && die "A18: degenerate path '.' refused"
done

# ---- A22: DST is a path-level symlink -> refuse, never replace (A18: also covers resolving-to-symlink) ----
if [ -L "$DST" ]; then
  die "A22: DST '$DST' is a symlink — sync never replaces a user-placed symlink; remove it manually if intended"
fi

rp_src=$(rp "$SRC") || die "A12: cannot resolve SRC '$SRC'"
rp_dst=$(rp "$DST") || die "A12: cannot resolve DST '$DST'"

# ---- A12 identity guards (realpath + component boundaries, never string prefixes) ----
[ "$rp_src" = "$rp_dst" ] && die "A12: realpath(SRC) == realpath(DST) ('$rp_src')"
case "$rp_dst" in
  "$rp_src")     die "A12: DST is SRC" ;;
  "$rp_src"/*)   die "A12: DST '$DST' resolves inside SRC '$rp_src'" ;;
esac
case "$rp_src" in
  "$rp_dst"/*)   die "A12: SRC resolves inside DST '$rp_dst'" ;;
esac

# ---- A14/A15 owned-path guard (component-boundary-aware, both directions) ----
rp_log=$(rp "$LOG_DIR") || rp_log="$LOG_DIR"
rp_logparent=$(dirname -- "$rp_log")
rp_entry=$(rp "$ENTRY_DIR") || rp_entry="$ENTRY_DIR"
owned_guard() { # $1 = owned realpath, $2 = label
  local O=$1 L=$2
  [ "$rp_dst" = "$O" ] && die "A14: DST '$DST' equals owned path ($L)"
  case "$rp_dst" in "$O"/*) die "A14: DST '$DST' is inside owned path ($L)" ;; esac
  case "$O" in "$rp_dst"/*) die "A14: owned path ($L) is inside DST — sync would destroy it (A8)" ;; esac
}
owned_guard "$rp_log"      "LOG_DIR '$LOG_DIR'"
owned_guard "$rp_logparent" "log file parent dir of '$LOG_DIR'"
owned_guard "$rp_entry"    "entrypoint dir '$ENTRY_DIR'"

# ---- verify mode (A9, A13): lstat-class comparison, never dereferences symlinks ----
mirror_diff() { # $1=reference(SRC) $2=candidate; returns 0 iff exact MIRROR_CLASS match
  if command -v rsync >/dev/null 2>&1; then
    local out
    out=$(rsync -a -c -n --delete --out-format='%i|%n' "$1/" "$2/" 2>/dev/null) || return 1
    [ -z "$out" ]
  else
    diff -r --no-dereference "$1" "$2" >/dev/null 2>&1
  fi
}

if [ "$MODE" = verify ]; then
  [ -e "$DST" ] || fail "verify: DST '$DST' does not exist (verify fails on absent destination)"
  if mirror_diff "$SRC" "$DST"; then
    echo "verify OK: DST is an exact MIRROR_CLASS mirror of SRC"
    exit 0
  fi
  fail "verify: DST is not an exact MIRROR_CLASS mirror of SRC"
fi

# ---- dry-run: all guards done, print plan, ZERO writes (A6, A16) ----
if [ "$MODE" = dry ]; then
  echo "DRY-RUN plan (no writes performed):"
  echo "  SRC=$SRC (realpath $rp_src)"
  echo "  DST=$DST (realpath $rp_dst)"
  echo "  LOG_DIR=$LOG_DIR (outside DST, A8)"
  if command -v rsync >/dev/null 2>&1; then
    echo "  engine: rsync -a --delete (exact recursive mirror, stale removed)"
  else
    echo "  engine: cp -a fallback + explicit recursive stale-subtree deletion at every depth (A7)"
  fi
  echo "  pipeline: stage -> MIRROR_CLASS verify -> touch DST (A11, A13)"
  if [ -e "$DST" ]; then
    echo "  DST exists; post-sync delta on MIRROR_CLASS:"
    rsync -a -c -n --delete --out-format='  %i %n' "$SRC/" "$DST/" 2>/dev/null || echo "  (delta unavailable without rsync)"
  else
    echo "  DST absent; real run would mkdir -p and populate (A16: dry-run must not create it)"
  fi
  exit 0
fi

# ---- real sync: stage -> verify -> touch DST (A11, A13, A20) ----
TPARENT=$(canon "${TMPDIR:-/tmp}")
[ "$TPARENT" = "/" ] && TPARENT="/tmp"
STAGE=""
STAGE=$(mktemp -d "${TPARENT%/}/hermes-context-stage.XXXXXX") || STAGE=""
if [ -z "$STAGE" ]; then
  mkdir -p "$HOME/.cache/hermes-context" || fail "A14: no usable stage parent (TMPDIR failed, fallback failed)"
  STAGE=$(mktemp -d "$HOME/.cache/hermes-context/hermes-context-stage.XXXXXX") || fail "stage creation failed"
fi
# re-validate the INSTANTIATED stage path (A20/A22 — closes validate-string-then-mkdir TOCTOU)
rp_stage=$(rp "$STAGE") || { rm -rf "$STAGE"; fail "stage path unresolvable"; }
[ "$rp_stage" = "$rp_dst" ] && { rm -rf "$STAGE"; die "A14: instantiated stage equals DST"; }
case "$rp_stage" in "$rp_dst"/*) rm -rf "$STAGE"; die "A14: instantiated stage inside DST" ;; esac
case "$rp_dst" in "$rp_stage"/*) rm -rf "$STAGE"; die "A14: DST inside instantiated stage" ;; esac
case "$rp_stage" in "$rp_src"/*) rm -rf "$STAGE"; die "A14: instantiated stage inside SRC" ;; esac

cleanup() { [ -n "${STAGE:-}" ] && rm -rf -- "$STAGE"; }
trap cleanup EXIT

# sync SRC CONTENTS into stage (no nesting, A4); rsync primary, cp fallback
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SRC/" "$STAGE/" || { fail "rsync stage population failed"; }
else
  mkdir -p "$STAGE"
  cp -a "$SRC/." "$STAGE/" || fail "cp -a stage population failed"
  # stage starts empty; cp fallback carries nothing stale, so stage == exact SRC tree
fi

# A13 verification: content-compare stage vs SRC on MIRROR_CLASS {contents, structure, symlinks}
mirror_diff "$SRC" "$STAGE" || fail "A13: stage failed MIRROR_CLASS verification against SRC (refusing to touch DST)"

# only now touch DST (A11): DST may be absent -> mkdir -p (A16 real-run allowance)
mkdir -p "$DST" || fail "cannot create DST '$DST'"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$STAGE/" "$DST/" || fail "promotion to DST failed"
else
  # fallback: clear all depth-1 entries (deletes stale subtrees at every depth, A7) then copy verified stage
  find "$DST" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || fail "stale clearing in DST failed"
  cp -a "$STAGE/." "$DST/" || fail "promotion to DST failed"
fi

mkdir -p "$LOG_DIR" || fail "cannot create LOG_DIR '$LOG_DIR'"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) mode=$mode_unused engine=$(command -v rsync >/dev/null 2>&1 && echo rsync || echo cp-fallback) src=$SRC dst=$DST result=mirror-ok" >> "$LOG_DIR/hermes-context.log" 2>/dev/null \
  || echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) sync ok src=$SRC dst=$DST" >> "$LOG_DIR/hermes-context.log" || true

echo "sync complete: $DST mirrors $SRC"
exit 0

