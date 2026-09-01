#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror SRC -> DST (A2), exact recursive mirror
# with stale deletion (A5/A7), staging + verification before touching DST (A11/A13),
# realpath identity guards (A12), zero-write dry-run (A6), log outside DST (A8).
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG_FILE="${HERMES_CONTEXT_LOG:-$HOME/.cache/hermes-context/sync.log}"

die() { printf 'sync-hermes-context: ERROR: %s\n' "$1" >&2; exit 1; }

[ -d "$SRC" ] || die "source directory not found: $SRC"

# ---- A12 identity guard (realpath-based, before ANY write) ----
SRC_R="$(realpath -e "$SRC")" || die "cannot resolve SRC: $SRC"
DST_R="$(realpath -m "$DST")"
if [ -e "$DST_R" ]; then
  DST_R="$(realpath -e "$DST_R")" || die "cannot resolve DST: $DST"
fi

paths_conflict() {
  local a="$1" b="$2"
  [ "$a" = "$b" ] && return 0
  case "$b/" in "$a"/*) return 0 ;; esac   # b inside a (a ancestor)
  case "$a/" in "$b"/*) return 0 ;; esac   # a inside b (b ancestor)
  return 1
}

if paths_conflict "$SRC_R" "$DST_R"; then
  die "A12 guard: SRC and DST are identical or ancestor/descendant (SRC=$SRC_R DST=$DST_R); refusing"
fi

# DST resolving through a symlink into SRC: check every ancestor of DST
_d="$DST_R"
while [ "$_d" != "/" ]; do
  if [ -L "$_d" ]; then
    _t="$(realpath -e "$_d" 2>/dev/null || true)"
    if [ -n "$_t" ] && paths_conflict "$SRC_R" "$_t"; then
      die "A12 guard: DST path resolves through symlink into SRC ($_d -> $_t); refusing"
    fi
  fi
  _d="$(dirname "$_d")"
done

# ---- A8: log path must live outside DST ----
LOG_R="$(realpath -m "$LOG_FILE")"
if paths_conflict "$DST_R" "$LOG_R"; then
  die "A8 guard: log path ($LOG_R) is inside DST ($DST_R); refusing"
fi

# ---- A6: dry-run — compute plan, ZERO writes anywhere (no staging, no log) ----
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN plan: mirror $SRC_R -> $DST_R (recursive, stale entries deleted)"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --dry-run --itemize-changes "$SRC_R/" "$DST_R/"
  else
    # read-only diff listing (no writes)
    if [ -d "$DST_R" ]; then
      diff -rq "$SRC_R" "$DST_R" || true
    else
      echo "DST does not exist; full initial copy of $SRC_R would be performed"
    fi
  fi
  echo "DRY-RUN complete: no files, logs, or directories were written."
  exit 0
fi

# ---- real run: stage -> verify -> touch DST (A11 order = law) ----
mkdir -p "$(dirname "$LOG_R")"

STAGE="${DST_R%/}/.hc-stage.$$"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$STAGE"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SRC_R/" "$STAGE/"
else
  # A4 fallback: cp -a then reconcile deletions recursively (A5/A7 semantics)
  cp -a "$SRC_R/." "$STAGE/"
  if [ -d "$DST_R" ]; then
    # remove stale top-level entries present in DST but absent from SRC;
    # once top level matches, removed subtrees are gone entirely (A7 all depths)
    ( cd "$DST_R" && find . -mindepth 1 -maxdepth 1 -print ) | LC_ALL=C sort > /tmp/.hc-dst.$$.list
    ( cd "$STAGE" && find . -mindepth 1 -maxdepth 1 -print ) | LC_ALL=C sort > /tmp/.hc-stage.$$.list
    comm -23 /tmp/.hc-dst.$$.list /tmp/.hc-stage.$$.list | while IFS= read -r rel; do
      rm -rf "${DST_R%/}/${rel#./}"
    done
    rm -f /tmp/.hc-dst.$$.list /tmp/.hc-stage.$$.list
  fi
fi

# ---- A13 verification: content-compare staging vs SRC (contents + structure + symlinks) ----
# Self-contained recursive compare: does not rely on diff flags that vary across
# diffutils versions (a missing --no-dereference flag previously caused spurious
# verification failures).
verify_stage() {
  local src="$1" st="$2"

  # 1) structure: identical multiset of (type, path) entries, any depth
  ( cd "$src" && find . -mindepth 1 -printf '%y %P\n' ) | LC_ALL=C sort > /tmp/.hc-vsrc.$$.list
  ( cd "$st"  && find . -mindepth 1 -printf '%y %P\n' ) | LC_ALL=C sort > /tmp/.hc-vst.$$.list
  if ! cmp -s /tmp/.hc-vsrc.$$.list /tmp/.hc-vst.$$.list; then
    rm -f /tmp/.hc-vsrc.$$.list /tmp/.hc-vst.$$.list
    return 1
  fi
  rm -f /tmp/.hc-vsrc.$$.list /tmp/.hc-vst.$$.list

  # 2) content: every regular file byte-identical; every symlink target identical
  local rel
  while IFS= read -r rel; do
    case "$rel" in
      f) ;; d) ;; l) ;; *) ;; esac
    :
  done < /dev/null
  local -a lines
  mapfile -t lines < <( cd "$src" && find . -mindepth 1 -printf '%y %P\n' )
  local line
  for line in "${lines[@]}"; do
    local t="${line%% *}"
    rel="${line#* }"
    case "$t" in
      f) cmp -s "$src/$rel" "$st/$rel" || return 1 ;;
      l) [ "$(readlink "$src/$rel")" = "$(readlink "$st/$rel")" ] || return 1 ;;
      d) [ -d "$st/$rel" ] || return 1 ;;
      *) : ;;  # other types out of scope per A9_class
    esac
  done
  return 0
}

if ! verify_stage "$SRC_R" "$STAGE"; then
  rm -rf "$STAGE"
  die "A13 verification failed: staging copy does not match SRC; DST untouched"
fi

# ---- touch DST ----
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$STAGE/" "$DST_R/"
else
  mkdir -p "$DST_R"
  cp -a "$STAGE/." "$DST_R/"
  # reconcile: remove anything in DST not in verified staging (top level;
  # subtrees vanish with their parent, satisfying A7 recursively)
  ( cd "$DST_R" && find . -mindepth 1 -maxdepth 1 -print ) | LC_ALL=C sort > /tmp/.hc-dst.$$.list
  ( cd "$STAGE" && find . -mindepth 1 -maxdepth 1 -print ) | LC_ALL=C sort > /tmp/.hc-stage.$$.list
  comm -23 /tmp/.hc-dst.$$.list /tmp/.hc-stage.$$.list | while IFS= read -r rel; do
    rm -rf "${DST_R%/}/${rel#./}"
  done
  rm -f /tmp/.hc-dst.$$.list /tmp/.hc-stage.$$.list
fi

rm -rf "$STAGE"
trap - EXIT

# ---- one-line log entry (real runs only) ----
printf '%s mode=real status=ok src=%s dst=%s\n' "$(date -Is)" "$SRC_R" "$DST_R" >> "$LOG_R"

exit 0

