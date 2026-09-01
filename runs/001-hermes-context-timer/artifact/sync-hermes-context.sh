#!/usr/bin/env bash
# sync-hermes-context.sh — mirror SRC -> DST per hcdl laws A1–A21.
# Standalone (cron-safe); systemctl --user timer optional (A3).
# Order of operations (A13/A20): guards -> stage -> content-verify -> touch DST.
set -u

MODE="sync"
case "${1:-}" in
  --dry-run) MODE="dry" ;;
  --verify)  MODE="verify" ;;
  "")        : ;;
  *) echo "usage: $0 [--dry-run|--verify]" >&2; exit 2 ;;
esac

# Refusals cite the governing A-number (A19). Zero writes before guards pass.
fail() { echo "refused: $1: $2" >&2; exit 1; }

# ---- 1a. resolve parameters (A17: env override is the mandated mechanism) ----
SRC_RAW="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST_RAW="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"

# ---- 1b. guards BEFORE any write ----

# A18: degenerate paths — component tests, not slash-suffix strings.
check_degenerate() {
  local p="$1" reduced c
  [ -z "$p" ] && return 0
  reduced=$(printf '%s' "$p" | sed -e 's:^/*::' -e 's:/*$::')
  [ -z "$reduced" ] && return 0   # "" or "/"
  IFS='/' read -ra comps <<< "$reduced"
  for c in "${comps[@]}"; do
    [ -z "$c" ] && return 0
    [ "$c" = "." ]  && return 0
    [ "$c" = ".." ] && return 0
  done
  return 1
}
check_degenerate "$SRC_RAW" && fail "A18" "degenerate SRC path: '$SRC_RAW'"
check_degenerate "$DST_RAW" && fail "A18" "degenerate DST path: '$DST_RAW'"

# realpath resolves symlinks: all guards below operate on the RESOLVED paths
# (A12). A DST symlink is allowed iff its resolved target passes every guard;
# it is then replaced by the real tree during the sync (A18).
CANON_SRC=$(realpath -m -- "$SRC_RAW") || fail "A18" "cannot resolve SRC: '$SRC_RAW'"
CANON_DST=$(realpath -m -- "$DST_RAW") || fail "A18" "cannot resolve DST: '$DST_RAW'"
[ "$CANON_SRC" = "/" ] && fail "A18" "SRC resolves to /"
[ "$CANON_DST" = "/" ] && fail "A18" "DST resolves to /"

# A12: realpath identity / ancestor / descendant / DST-inside-SRC (symlink-resolved).
inside_of() { [ "$1" = "$2" ] || [[ "$1" == "$2"/* ]]; }
[ "$CANON_SRC" = "$CANON_DST" ] && fail "A12" "realpath(SRC) == realpath(DST): $CANON_SRC"
inside_of "$CANON_DST" "$CANON_SRC" && fail "A12" "DST resolves inside SRC: $CANON_DST"
inside_of "$CANON_SRC" "$CANON_DST" && fail "A12" "DST contains SRC (sync would destroy source): $CANON_DST"

# A14/A15: owned paths = concrete instantiated paths, boundary-aware compare.
CANON_LOG=$(realpath -m -- "${HOME}/.cache/hermes-context")   # log FILE's resolved parent
inside_of "$CANON_LOG" "$CANON_DST" && fail "A14" "log dir inside DST (A8): $CANON_LOG"
inside_of "$CANON_LOG" "$CANON_SRC" && fail "A14" "log dir inside SRC: $CANON_LOG"
inside_of "$CANON_DST" "$CANON_LOG" && fail "A14" "DST contains log dir (sync would delete it)"
inside_of "$CANON_SRC" "$CANON_LOG" && fail "A14" "SRC contains log dir"
# Stage namespace is a pure string (A20: no mktemp/mkdir/write yet); lives under log root,
# so the log-root validation above covers it; validate the prefix explicitly too.
STAGE_TPL="$CANON_LOG/.hc-stage.XXXXXX"
STAGE_PREFIX="$CANON_LOG/.hc-stage"
inside_of "$STAGE_PREFIX" "$CANON_DST" && fail "A14" "stage namespace inside DST: $STAGE_PREFIX"
inside_of "$STAGE_PREFIX" "$CANON_SRC" && fail "A14" "stage namespace inside SRC: $STAGE_PREFIX"
# Entrypoint dir (A8: sync must never delete its own entrypoints).
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || SCRIPT_DIR=""
if [ -n "$SCRIPT_DIR" ]; then
  CANON_EP=$(realpath -m -- "$SCRIPT_DIR")
  inside_of "$CANON_EP" "$CANON_DST" && fail "A14" "entrypoint dir inside DST (A8): $CANON_EP"
  inside_of "$CANON_EP" "$CANON_SRC" && fail "A14" "entrypoint dir inside SRC: $CANON_EP"
  inside_of "$CANON_DST" "$CANON_EP" && fail "A14" "DST contains entrypoint dir (A8)"
  inside_of "$CANON_SRC" "$CANON_EP" && fail "A14" "SRC contains entrypoint dir"
fi

# A9-class verification: recursive content diff + explicit symlink-target compare.
verify_mirror() {
  local a="$1" b="$2"
  diff -r --no-dereference -- "$a" "$b" >/dev/null 2>&1 || return 1
  diff <(cd "$a" && find . -type l -printf '%p\t%l\n' | LC_ALL=C sort) \
       <(cd "$b" && find . -type l -printf '%p\t%l\n' | LC_ALL=C sort) >/dev/null 2>&1 || return 1
  return 0
}

# ---- 1c. dry-run: plan to stdout ONLY (A6/A16: zero side effects) ----
if [ "$MODE" = "dry" ]; then
  echo "dry-run plan (no writes will occur):"
  echo "  SRC:           $CANON_SRC"
  echo "  DST:           $CANON_DST"
  echo "  log:           $CANON_LOG/sync.log (outside DST, A8)"
  echo "  stage:         $STAGE_TPL (script-owned, outside DST/SRC, A14/A20)"
  if command -v rsync >/dev/null 2>&1; then
    echo "  method:        rsync -a --delete (primary)"
  else
    echo "  method:        tar-pipe + recursive prune (fallback, A4/A7)"
  fi
  echo "  convergence:   DST end state == SRC (contents, recursive dirs, symlinks); stale deleted at all depth (A5/A7)"
  echo "  order:         stage -> content-verify -> replace DST (A11/A13)"
  exit 0
fi

# ---- --verify: read-only A9-class check; fails when DST is absent ----
if [ "$MODE" = "verify" ]; then
  if [ ! -e "$CANON_DST" ]; then
    echo "verify-failed: DST does not exist: $CANON_DST" >&2
    exit 1
  fi
  if verify_mirror "$CANON_SRC" "$CANON_DST"; then
    echo "verify: OK (MIRROR-class match: contents, recursive dirs, symlinks)"
    exit 0
  else
    echo "verify-failed: DST differs from SRC (A9 mismatch)" >&2
    exit 1
  fi
fi

# ---- 1d. real run: writes allowed from here on ----
mkdir -p -- "$CANON_LOG" || { echo "sync: cannot create log dir $CANON_LOG" >&2; exit 1; }
LOGFILE="$CANON_LOG/sync.log"
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOGFILE"; }

mkdir -p -- "$(dirname -- "$CANON_DST")" || { echo "sync: cannot create DST parent" >&2; exit 1; }
mkdir -p -- "$CANON_DST" || { echo "sync: cannot create DST $CANON_DST" >&2; exit 1; }  # A16: real run only

STAGE=$(mktemp -d -- "$STAGE_TPL") || { echo "sync: cannot create stage" >&2; exit 1; }
trap 'rm -rf -- "$STAGE"' EXIT

# ---- 1e. stage copy (contents of SRC into stage, no nesting) ----
if command -v rsync >/dev/null 2>&1; then
  METHOD="rsync"
  rsync -a --delete -- "$CANON_SRC/" "$STAGE/" \
    || { log "FAIL staging (rsync) SRC=$CANON_SRC"; echo "sync: staging failed" >&2; exit 1; }
else
  METHOD="tar-fallback"
  tar -C "$CANON_SRC" -cf - . | tar -C "$STAGE" -xf - \
    || { log "FAIL staging (tar-pipe) SRC=$CANON_SRC"; echo "sync: staging failed" >&2; exit 1; }
  # A7: recursive reconciliation — delete stale entries at all depths.
  # A20: prunelist via mktemp in the reserved '.prunelist' namespace under stage.
  PRUNE=$(mktemp -- "$STAGE/.prunelist.XXXXXX") || { echo "sync: cannot create prunelist" >&2; exit 1; }
  comm -13 \
    <(cd "$CANON_SRC" && find . -mindepth 1 | sed 's:^\./::' | LC_ALL=C sort) \
    <(cd "$STAGE"   && find . -mindepth 1 | sed 's:^\./::' | LC_ALL=C sort) > "$PRUNE" \
    || { log "FAIL prune-list build"; echo "sync: prune-list build failed" >&2; exit 1; }
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    rm -rf -- "$STAGE/$rel"
  done < "$PRUNE"
  rm -f -- "$PRUNE"
fi

# ---- 1f. content-verify stage vs SRC (A9/A13) ----
if ! verify_mirror "$CANON_SRC" "$STAGE"; then
  log "FAIL verification mismatch (A9/A13); DST untouched SRC=$CANON_SRC"
  echo "sync: staged copy FAILED verification (A9); DST untouched" >&2
  exit 1
fi

# ---- 1g. VERIFIED_COPY exists -> only now touch DST (A11) ----
# If DST_RAW was a symlink that passed the guards, rm -rf removes the symlink
# itself and the verified tree takes its place (A18: symlink -> real tree).
rm -rf -- "$CANON_DST_RAW_PLACEHOLDER" 2>/dev/null || true
rm -rf -- "$DST_RAW" "$CANON_DST"
if mv -- "$STAGE" "$CANON_DST" 2>/dev/null; then
  :
else
  # cross-filesystem: materialize verified stage into DST, then drop stage
  mkdir -p -- "$CANON_DST" || { log "FAIL recreate DST"; echo "sync: cannot recreate DST" >&2; exit 1; }
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete -- "$STAGE/" "$CANON_DST/" || { log "FAIL cross-fs materialize"; echo "sync: materialize failed" >&2; exit 1; }
  else
    cp -a -- "$STAGE/." "$CANON_DST/" || { log "FAIL cross-fs materialize (cp -a)"; echo "sync: materialize failed" >&2; exit 1; }
  fi
  rm -rf -- "$STAGE"
fi
trap - EXIT

# ---- 1i. log (real runs only; file lives outside DST, A8) ----
log "OK method=$METHOD mirrored $CANON_SRC -> $CANON_DST (verified copy; stale deleted at all depths)"
echo "sync: OK ($METHOD, content-verified, exact recursive mirror)"
exit 0

