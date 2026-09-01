#!/usr/bin/env bash
# sync-hermes-context.sh — one-way host->workspace mirror (hcdl register run 001)
# SRC -> DST, rsync --delete primary, cp -a fallback with recursive delete-reconciliation.
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
  esac
done

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context}"
LOG_DIR="${HERMES_CONTEXT_LOG_DIR:-$HOME/.cache}"
LOG_FILE="$LOG_DIR/hermes-context-sync.log"

die() { echo "sync-hermes-context: $1" >&2; exit "${2:-1}"; }

# ---- guards (before ANY write) ----
[ -n "$SRC" ] || die "HERMES_CONTEXT_SRC empty" 1
[ -e "$SRC" ] || die "SRC missing: $SRC (no writes performed)" 1
SRC_REAL="$(realpath -e "$SRC")" || die "cannot resolve SRC: $SRC" 1
DST_REAL="$(realpath -m "$DST")"

if [ "$SRC_REAL" = "$DST_REAL" ]; then
  die "refusing: SRC and DST resolve to the same path ($SRC_REAL)" 1
fi
case "$DST_REAL/" in
  "$SRC_REAL"/*) die "refusing: DST is inside SRC ($DST_REAL under $SRC_REAL)" 1 ;;
esac
case "$SRC_REAL/" in
  "$DST_REAL"/*) die "refusing: DST is an ancestor of SRC ($DST_REAL contains $SRC_REAL)" 1 ;;
esac
# DST resolving through a symlink into SRC: check each ancestor component of DST
_p="$DST"
while [ "$_p" != "/" ]; do
  if [ -L "$_p" ]; then
    _t="$(readlink -f "$_p" 2>/dev/null || true)"
    if [ -n "$_t" ] && [ "$_t" != "/" ]; then
      case "$_t/" in
        "$SRC_REAL"|"$SRC_REAL"/*) die "refusing: DST resolves through symlink into SRC ($_p -> $_t)" 1 ;;
      esac
    fi
  fi
  _p="$(dirname "$_p")"
done
# log dir must not live inside DST (A8)
LOG_DIR_REAL="$(realpath -m "$LOG_DIR")"
case "$LOG_DIR_REAL/" in
  "$DST_REAL"|"$DST_REAL"/*) die "refusing: log dir inside DST ($LOG_DIR_REAL under $DST_REAL)" 1 ;;
esac

log() {
  mkdir -p "$LOG_DIR"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE"
}

# ---- snapshot helper (contents incl. symlinks + structure), written to stdout only ----
snapshot() {
  local root="$1"
  if [ ! -e "$root" ]; then echo "__ABSENT__"; return 0; fi
  ( cd "$root" && find . -mindepth 1 -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' p; do
      if [ -L "$p" ]; then
        printf 'link %s -> %s\n' "$p" "$(readlink "$p")"
      elif [ -d "$p" ]; then
        printf 'dir  %s\n' "$p"
      else
        printf 'file %s %s\n' "$p" "$(cksum < "$p" | awk '{print $1":"$2}')"
      fi
    done )
}

# ---- dry-run (A6: zero writes of ANY kind, gated by DST byte-identity) ----
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN: no files, dirs, symlinks, or logs will be written."
  echo "SRC=$SRC -> DST=$DST"
  before="$(snapshot "$DST")"
  if command -v rsync >/dev/null 2>&1; then
    rsync -rlptgoD --dry-run --delete "$SRC"/ "$DST"/ || die "rsync dry-run failed" 1
  else
    echo "rsync absent; planned copy/delete list (find-based diff):"
    if [ ! -e "$DST" ]; then
      echo "  (DST absent) would create $DST and copy entire tree:"
      ( cd "$SRC" && find . -mindepth 1 -print ) | sed 's/^/  copy /'
    else
      src_list="$( ( cd "$SRC" && find . -mindepth 1 -print | LC_ALL=C sort ) )"
      dst_list="$( ( cd "$DST" && find . -mindepth 1 -print | LC_ALL=C sort ) )"
      comm -23 <(printf '%s\n' "$src_list") <(printf '%s\n' "$dst_list") | sed 's/^/  copy /'
      comm -13 <(printf '%s\n' "$src_list") <(printf '%s\n' "$dst_list") | sed 's/^/  delete /'
      # changed contents among common files
      ( cd "$SRC" && find . -type f -print0 ) | while IFS= read -r -d '' f; do
        if [ -f "$DST/$f" ] && ! cmp -s "$SRC/$f" "$DST/$f"; then
          echo "  update $f"
        fi
      done
    fi
  fi
  # A6 gate: DST must be byte-identical after the dry run (contents incl.
  # symlinks + structure), not merely "no probe.txt".
  after="$(snapshot "$DST")"
  if [ "$before" != "$after" ]; then
    echo "DRY-RUN GATE FAIL: DST changed during dry-run (A6 violation):" >&2
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
    exit 1
  fi
  echo "DRY-RUN complete: exit 0, zero writes (A6 gate passed: DST byte-identical)."
  exit 0
fi

# ---- live sync ----
sync_rsync() {
  rsync -rlptgoD --delete "$SRC"/ "$DST"/ || die "rsync sync failed" 1
}

sync_cp_fallback() {
  # A11: never rm -rf DST before a verified copy of the source exists elsewhere.
  [ -d "$DST" ] || mkdir -p "$DST"
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/hermes-sync.XXXXXX")" || die "mktemp failed" 1
  ( cd "$SRC" && cp -a . "$tmp"/ ) || { rm -rf "$tmp"; die "cp -a of SRC to staging failed" 1; }
  [ -n "$(ls -A "$tmp" 2>/dev/null || true)" ] || [ -z "$(find "$SRC" -mindepth 1 -print -quit 2>/dev/null)" ] \
    || { rm -rf "$tmp"; die "staged copy unexpectedly empty; refusing to touch DST" 1; }
  # verified source copy now exists at $tmp — safe to reconcile DST
  # delete-reconciliation at EVERY depth (A7), deepest-first; also remove
  # type mismatches (dir vs file/symlink, differing symlink targets) that
  # cp -a cannot replace by overwriting — convergence equals rsync --delete.
  ( cd "$DST" && find . -mindepth 1 -depth -print0 ) | while IFS= read -r -d '' p; do
    if [ ! -e "$SRC/$p" ] && [ ! -L "$SRC/$p" ]; then
      rm -rf -- "$p"
    elif [ -d "$p" ] && { [ ! -d "$SRC/$p" ] || [ -L "$SRC/$p" ]; }; then
      rm -rf -- "$p"                       # DST dir, SRC non-dir (or symlinked dir)
    elif [ -d "$SRC/$p" ] && [ ! -L "$SRC/$p" ] && { [ ! -d "$p" ] || [ -L "$p" ]; }; then
      rm -rf -- "$p"                       # SRC dir, DST non-dir
    elif [ -L "$p" ] && [ -L "$SRC/$p" ] && [ "$(readlink "$p")" != "$(readlink "$SRC/$p")" ]; then
      rm -f -- "$p"                        # differing symlink target: replace cleanly
    elif [ -L "$p" ] && [ ! -L "$SRC/$p" ] && [ ! -d "$SRC/$p" ]; then
      rm -f -- "$p"                        # DST symlink, SRC regular file
    elif [ ! -L "$p" ] && [ -f "$p" ] && [ -L "$SRC/$p" ]; then
      rm -f -- "$p"                        # DST regular file, SRC symlink
    fi
  done
  # copy remaining/changed content from the verified staging copy
  ( cd "$tmp" && cp -a . "$DST"/ ) || { rm -rf "$tmp"; die "cp -a into DST failed" 1; }
  rm -rf "$tmp"
  # remove empty dirs left behind, deepest-first, repeat until stable
  local pass=0
  while [ "$pass" -lt 16 ]; do
    ( cd "$DST" && find . -mindepth 1 -depth -type d -empty -print0 ) | while IFS= read -r -d '' d; do
      rmdir -- "$d" 2>/dev/null || true
    done
    local emptied
    emptied="$(cd "$DST" && find . -mindepth 1 -type d -empty | wc -l)"
    [ "$emptied" -eq 0 ] && break
    pass=$((pass+1))
  done
}

# ---- self-verify (A9 class only: contents, structure, symlinks) ----
self_verify() {
  local status=0
  # byte-identical contents and structure via diff -r (no timestamps/metadata)
  local vdiff
  vdiff="$(mktemp "${TMPDIR:-/tmp}/hdcs-verify-diff.XXXXXX")"
  if ! diff -r --no-dereference "$SRC" "$DST" >"$vdiff" 2>&1; then
    echo "SELF-VERIFY FAIL: content/structure mismatch:" >&2
    cat "$vdiff" >&2
    status=1
  fi
  rm -f "$vdiff"
  # symlink targets and existence (diff -r does not compare link targets)
  local sl1 sl2
  sl1="$( ( cd "$SRC" && find . -type l -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' p; do printf '%s -> %s\n' "$p" "$(readlink "$p")"; done ) )"
  sl2="$( ( cd "$DST" && find . -type l -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' p; do printf '%s -> %s\n' "$p" "$(readlink "$p")"; done ) )"
  if [ "$sl1" != "$sl2" ]; then
    echo "SELF-VERIFY FAIL: symlink set/target mismatch:" >&2
    diff <(printf '%s\n' "$sl1") <(printf '%s\n' "$sl2") >&2 || true
    status=1
  fi
  [ "$status" -eq 0 ] || die "self-verify failed; DST does not mirror SRC in A9 class" 1
  echo "self-verify OK"
}

mkdir -p "$DST"
if command -v rsync >/dev/null 2>&1; then
  sync_rsync
  log "rsync --delete sync: $SRC -> $DST"
else
  sync_cp_fallback
  log "cp fallback sync (recursive delete-reconciliation): $SRC -> $DST"
fi
self_verify
exit 0

