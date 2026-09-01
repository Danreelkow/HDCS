```bash
#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror SRC -> DST (host -> workspace)
# Standalone-executable and systemd-user-invokable (A3).
# Guards cite A-numbers per closed law list {A12, A14/A15, A18} (A19); A22 for DST symlinks.
set -u

die() { printf 'REFUSAL/ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf '%s\n' "$*" >&2; }

DRY_RUN=0
VERIFY=0
case "${1-}" in
  --dry-run) DRY_RUN=1 ;;
  --verify)  VERIFY=1 ;;
  "") ;;
  *) die "unknown argument: $1 (supported: --dry-run, --verify)" ;;
esac

# --- env (A17); explicit EMPTY values are refused, never defaulted (ledger 8b) ---
SRC="${HERMES_CONTEXT_SRC-default}"
DST="${HERMES_CONTEXT_DST-default}"
LOGDIR="${HERMES_CONTEXT_LOG_DIR-${LOG_DIR-default}}"
[ "$LOGDIR" = "default" ] && LOGDIR="$HOME/.cache/hermes-context"
[ -z "${HERMES_CONTEXT_SRC-default}" ] && die "A18: HERMES_CONTEXT_SRC is empty — refuse (never fall back to default on empty)"
[ -z "${HERMES_CONTEXT_SRC-default}" ] || [ -z "$SRC" ] && true
if [ -z "$SRC" ]; then die "A18: HERMES_CONTEXT_SRC is empty (A18)"; fi
if [ -z "$DST" ]; then die "A18: HERMES_CONTEXT_DST is empty (A18)"; fi
if [ -z "$LOGDIR" ]; then die "A18: log dir env is empty (A18)"; fi

# --- canonicalize trailing slashes ONCE; mutate only through canonical paths (ledger 7) ---
canon() { # strip all trailing slashes; "/" and "" handled by caller
  local p="$1"
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  printf '%s' "$p"
}
SRC_C=$(canon "$SRC"); DST_C=$(canon "$DST")

# --- A18: degenerate paths via component test, not slash-suffix ---
for p in "$SRC_C" "$DST_C"; do
  if [ -z "$p" ] || [ "$p" = "/" ] || [ "$p" = "." ]; then
    die "A18: degenerate path '$p' ('/', '', '.' are refused)"
  fi
done

# --- A22: DST path-level symlink -> refuse, never replace ---
if [ -L "$DST_C" ]; then
  die "A22: $DST_C is a symlink — sync never replaces a user-placed symlink; operator must remove it manually"
fi

# --- realpath identity (A12), component-boundary aware (A15), pre-destruction ---
rp() { realpath -m -- "$1"; }
RP_SRC=$(rp "$SRC_C")
RP_DST=$(rp "$DST_C")
RP_LOG=$(rp "$(dirname -- "$LOGDIR")")
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd -P) || SCRIPT_DIR=""
STAGE_PARENT="${TMPDIR:-/tmp}"; STAGE_PARENT=$(canon "$STAGE_PARENT")
RP_STAGE_PARENT=$(rp "$STAGE_PARENT")

inside() { # component test: $1 strictly inside $2 (or equal)
  [ "$1" = "$2" ] && return 0
  case "$1" in "$2"/*) return 0 ;; esac
  return 1
}

# A12: SRC==DST, ancestor/descendant, DST resolving through symlink into SRC (realpath -m resolves)
if [ "$RP_SRC" = "$RP_DST" ]; then die "A12: realpath(SRC) == realpath(DST): $RP_SRC"; fi
if inside "$RP_DST" "$RP_SRC"; then die "A12: DST $RP_DST is inside SRC $RP_SRC"; fi
if inside "$RP_SRC" "$RP_DST"; then die "A12: DST $RP_DST is an ancestor of SRC $RP_SRC"; fi

# --- verify mode: FAILS when DST absent; OK only on exact mirror; never dereferences (ledger 12) ---
cmp_mirror() { # $1=reference dir $2=candidate dir ; exit nonzero on MIRROR_CLASS mismatch
  local a="$1" b="$2"
  if command -v rsync >/dev/null 2>&1; then
    local out
    out=$(rsync -rcn --delete --out-format='CHG %i %n' -- "$a/" "$b/" 2>/dev/null)
    [ -z "$out" ]
  else
    diff -r --no-dereference -q -- "$a" "$b" >/dev/null 2>&1
  fi
}

if [ "$VERIFY" = 1 ]; then
  [ -d "$DST_C" ] || die "verify failed: DST $DST_C does not exist (verify must fail on absent destination)"
  if cmp_mirror "$SRC_C" "$DST_C"; then
    echo "verify OK: $DST_C is an exact mirror of $SRC_C (MIRROR_CLASS)"
    exit 0
  else
    die "verify FAILED: $DST_C is not an exact mirror of $SRC_C (MIRROR_CLASS: contents/structure/symlinks)"
  fi
fi

# --- A14/A15: DST must not equal/contain/be inside OWNED concrete paths
#     (log file's PARENT dir, entrypoint dir, stage parent — instantiated stage re-checked later) ---
if inside "$RP_DST" "$RP_LOG" || inside "$RP_LOG" "$RP_DST"; then
  die "A14: DST $RP_DST collides with owned log-parent path $RP_LOG (A14/A15)"
fi
if [ -n "$SCRIPT_DIR" ]; then
  RP_SCRIPT=$(rp "$SCRIPT_DIR")
  if inside "$RP_DST" "$RP_SCRIPT" || inside "$RP_SCRIPT" "$RP_DST"; then
    die "A14: DST $RP_DST collides with owned entrypoint dir $RP_SCRIPT (A14/A15)"
  fi
fi
if inside "$RP_DST" "$RP_STAGE_PARENT" || inside "$RP_STAGE_PARENT" "$RP_DST"; then
  die "A14: DST $RP_DST collides with owned stage parent $RP_STAGE_PARENT (A14/A15)"
fi

# --- A20: stage path computed as pure string, validated, THEN created ---
if [ ! -d "$STAGE_PARENT" ] || [ ! -w "$STAGE_PARENT" ]; then
  STAGE_PARENT="$HOME/.cache/hermes-context-stage"   # script-owned fallback (TMPDIR failure)
  RP_STAGE_PARENT=$(rp "$STAGE_PARENT")
  if inside "$RP_DST" "$RP_STAGE_PARENT" || inside "$RP_STAGE_PARENT" "$RP_DST"; then
    die "A14: fallback stage parent $RP_STAGE_PARENT collides with DST (A14/A15)"
  fi
fi

if [ "$DRY_RUN" = 1 ]; then
  # A6/A16: plan/diff print only — ZERO writes: no log, no stage dir, no DST creation
  echo "DRY-RUN plan: sync $SRC_C -> $DST_C (one-way mirror, stale entries deleted)"
  if [ -d "$DST_C" ]; then
    if cmp_mirror "$SRC_C" "$DST_C"; then
      echo "DRY-RUN: DST already matches SRC on MIRROR_CLASS; no changes would be made"
    else
      echo "DRY-RUN: DST differs from SRC on MIRROR_CLASS; changes would be applied"
      if command -v rsync >/dev/null 2>&1; then
        rsync -rcn --delete --itemize-changes -- "$SRC_C/" "$DST_C/" 2>/dev/null || true
      else
        diff -r --no-dereference -- "$SRC_C" "$DST_C" 2>/dev/null || true
      fi
    fi
  else
    echo "DRY-RUN: DST $DST_C does not exist; it would be created and fully populated (dry run creates nothing)"
  fi
  exit 0
fi

# ---------------- real run ----------------

# A20/A22: validate string parent, then mktemp -d, then RE-validate the instantiated path (A15)
if [ ! -d "$STAGE_PARENT" ] || [ ! -w "$STAGE_PARENT" ]; then
  die "A14: stage parent $STAGE_PARENT not usable (A14/A15)"
fi
STAGE=$(mktemp -d "${STAGE_PARENT%/}/hermes-context-stage.XXXXXX") || die "A14: mktemp -d failed under $STAGE_PARENT"
RP_STAGE=$(rp "$STAGE")
if inside "$RP_STAGE" "$RP_DST" || inside "$RP_DST" "$RP_STAGE"; then
  rm -rf -- "$STAGE"
  die "A14: instantiated stage $RP_STAGE collides with DST $RP_DST (A14/A15)"
fi
trap 'rm -rf -- "$STAGE"' EXIT

# A4/A5/A7: sync SRC CONTENTS into stage (no nesting); rsync primary, cp -a fallback
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete -- "$SRC_C/" "$STAGE/" || { die "sync stage failed"; }
else
  mkdir -p "$STAGE"
  cp -a "$SRC_C/." "$STAGE/" || die "cp -a stage copy failed"
fi

# A9/A13: content-compare stage vs SRC on MIRROR_CLASS exactly; mismatch -> nonzero
if ! cmp_mirror "$SRC_C" "$STAGE"; then
  die "A9: stage failed MIRROR_CLASS verification against SRC; refusing to touch DST"
fi
# VERIFIED stage exists from here on (A11/A13) — DST destruction permitted only now.

# A16: create DST if absent (real run only)
mkdir -p -- "$DST_C" || die "cannot create DST $DST_C"

# Promote verified stage to DST: exact mirror incl. stale deletion
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete -- "$STAGE/" "$DST_C/" || die "promotion to DST failed"
else
  find "$DST_C" -mindepth 1 -delete
  cp -a "$STAGE/." "$DST_C/" || die "cp -a promotion failed"
fi

# A8: one log line, LOG_DIR outside DST
mkdir -p -- "$LOGDIR" 2>/dev/null || true
printf '%s sync ok src=%s dst=%s\n' "$(date -Is)" "$SRC_C" "$DST_C" >> "$LOGDIR/sync.log" 2>/dev/null || true

echo "sync complete: $SRC_C -> $DST_C (verified exact mirror)"
