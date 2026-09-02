#!/usr/bin/env bash
# sync-hermes-context.sh — one-way host→workspace mirror (A2), rsync primary.
# Unset env -> production defaults (A23); set-but-empty -> refuse (A23).
set -euo pipefail

MODE=sync
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE=dry ;;
    --verify)  MODE=verify ;;
    *) echo "usage: $0 [--dry-run|--verify]" >&2; exit 1 ;;
  esac
done

refuse() { echo "refusing: $1" >&2; exit 1; }

# peq A B -> true iff A == B or A is a strict path-prefix component of B
peq() {
  [ "$2" = "$1" ] && return 0
  case "$2/" in "$1"/*) return 0 ;; esac
  return 1
}

# ---- A23: unset -> mandated production default; set-but-empty -> refuse ----
if [ -n "${HERMES_CONTEXT_SRC+x}" ] && [ -z "${HERMES_CONTEXT_SRC}" ]; then
  refuse "A23: HERMES_CONTEXT_SRC is set but empty"
fi
if [ -n "${HERMES_CONTEXT_DST+x}" ] && [ -z "${HERMES_CONTEXT_DST}" ]; then
  refuse "A23: HERMES_CONTEXT_DST is set but empty"
fi
SRC="${HERMES_CONTEXT_SRC-/opt/data/workspace/hermes-context}"
DST="${HERMES_CONTEXT_DST-/workspace/hermes-context}"

# ---- A18: degenerate paths ----
for v in "$SRC" "$DST"; do
  case "$v" in
    ""|"/"|".") refuse "A18: degenerate path '$v' (must not be /, empty, or .)" ;;
  esac
done

# canonicalize trailing slashes once (run-026); all mutations go through canonical forms
SRC="${SRC%%+(/)}"
DST="${DST%%+(/)}"

src_r=$(realpath -m -- "$SRC")
dst_r=$(realpath -m -- "$DST")

# ---- A12: identity / ancestor / descendant via realpath ----
[ "$src_r" = "$dst_r" ] && refuse "A12: realpath(SRC) == realpath(DST) ($dst_r)"
case "$dst_r/" in "$src_r"/*) refuse "A12: DST ($dst_r) is inside SRC ($src_r)" ;; esac
case "$src_r/" in "$dst_r"/*) refuse "A12: SRC ($src_r) is inside DST ($dst_r)" ;; esac

# ---- A22: DST resolving to a symlink -> refuse, never replace ----
if [ -L "$DST" ]; then
  refuse "A22: DST ($DST) is a symlink (resolves to $dst_r); sync never replaces a user-placed symlink"
fi

# ---- A8/A14/A15: owned concrete paths (log parent, entrypoint dir) ----
LOG_FILE="${HOME}/.cache/hermes-context/sync.log"
ENTRY_DIR="${HOME}/.local/bin"
LOG_PARENT=$(dirname -- "$LOG_FILE")
for owned in "$(realpath -m -- "$LOG_PARENT")" "$(realpath -m -- "$ENTRY_DIR")"; do
  peq "$dst_r" "$owned" && refuse "A14/A15: DST equals owned path $owned"
  peq "$owned" "$dst_r" && refuse "A14/A15: DST contains owned path $owned"
done

# ---- A20/A14: validate stage PARENT (string) before mktemp ----
stage_parent="${TMPDIR-/tmp}"
stage_parent="${stage_parent%%+(/)}"
[ -z "$stage_parent" ] && stage_parent="/tmp"
sp_r=$(realpath -m -- "$stage_parent")
peq "$sp_r" "$dst_r" && refuse "A14/A15: stage parent ($sp_r) is inside DST ($dst_r)"

# ---- A9-class recursive compare: contents + structure + symlinks (lstat-based, no deref) ----
a9_compare() {
  local from="$1" to="$2" p s d
  while IFS= read -r -d '' p; do
    s="$from/${p#./}"; d="$to/${p#./}"
    if [ -L "$s" ]; then
      [ -L "$d" ] || return 1
      [ "$(readlink -- "$s")" = "$(readlink -- "$d")" ] || return 1
    elif [ -d "$s" ]; then
      { [ -d "$d" ] && [ ! -L "$d" ]; } || return 1
    elif [ -f "$s" ]; then
      { [ -f "$d" ] && [ ! -L "$d" ]; } || return 1
      cmp -s -- "$s" "$d" || return 1
    else
      return 1
    fi
  done < <(cd -- "$from" && find . -mindepth 1 -print0)
  while IFS= read -r -d '' p; do
    s="$from/${p#./}"
    { [ -e "$s" ] || [ -L "$s" ]; } || return 1
  done < <(cd -- "$to" && find . -mindepth 1 -print0)
  return 0
}

# ---- fallback reconcile (no rsync): delete stale, copy missing/differing, swap types ----
reconcile() {
  local from="$1" to="$2" p s d
  while IFS= read -r -d '' p; do
    s="$from/${p#./}"; d="$to/${p#./}"
    { [ -e "$s" ] || [ -L "$s" ]; } || rm -rf -- "$d"
  done < <(cd -- "$to" && find . -mindepth 1 -print0)
  while IFS= read -r -d '' p; do
    s="$from/${p#./}"; d="$to/${p#./}"
    if [ -L "$s" ]; then
      rm -rf -- "$d"; ln -s -- "$(readlink -- "$s")" "$d"
    elif [ -d "$s" ]; then
      if [ ! -d "$d" ] || [ -L "$d" ]; then rm -rf -- "$d"; mkdir -p -- "$d"; fi
    else
      if [ -L "$d" ] || [ ! -f "$d" ] || ! cmp -s -- "$s" "$d"; then
        rm -rf -- "$d"; cp -- "$s" "$d"
      fi
    fi
  done < <(cd -- "$from" && find . -mindepth 1 -print0)
}

# ---- verify mode: lstat-based, never dereferences; fails when DST absent ----
if [ "$MODE" = verify ]; then
  { [ -e "$DST" ] || [ -d "$DST" ]; } || { echo "verify FAILED: DST ($DST) does not exist" >&2; exit 1; }
  if a9_compare "$src_r" "$dst_r"; then
    echo "verify OK: DST is an exact A9-class mirror of SRC"
    exit 0
  fi
  echo "verify FAILED: DST is not an exact mirror of SRC" >&2
  exit 1
fi

# ---- dry-run branch (A6/A16): zero writes of any kind, no stage, no log ----
if [ "$MODE" = dry ]; then
  if command -v rsync >/dev/null 2>&1; then
    out=$(rsync -an --delete --itemize-changes -- "$SRC/" "$DST/" 2>&1) || out=""
    if [ -n "$out" ]; then
      n=$(printf '%s\n' "$out" | grep -cE '^[<>chLSD]' || true)
      m=$(printf '%s\n' "$out" | grep -c '^\*deleting' || true)
      echo "dry-run: sync=$n delete=$m (no writes performed)"
      [ "${n}${m}" != "00" ] && printf '%s\n' "$out"
      exit 0
    fi
  fi
  # read-only find-diff fallback (or rsync dry-run failed)
  n=0; m=0
  while IFS= read -r -d '' p; do
    s="$SRC/${p#./}"; d="$DST/${p#./}"
    if [ -L "$s" ]; then
      { [ -L "$d" ] && [ "$(readlink -- "$s")" = "$(readlink -- "$d")" ]; } || n=$((n+1))
    elif [ -d "$s" ]; then
      { [ -d "$d" ] && [ ! -L "$d" ]; } || n=$((n+1))
    else
      { [ -f "$d" ] && [ ! -L "$d" ] && cmp -s -- "$s" "$d"; } || n=$((n+1))
    fi
  done < <(cd -- "$SRC" && find . -mindepth 1 -print0)
  if [ -d "$DST" ]; then
    while IFS= read -r -d '' p; do
      s="$SRC/${p#./}"
      { [ -e "$s" ] || [ -L "$s" ]; } || m=$((m+1))
    done < <(cd -- "$DST" && find . -mindepth 1 -print0)
  fi
  echo "dry-run: sync=$n delete=$m (no writes performed)"
  exit 0
fi

# ---- real run: A11 order — stage -> verify -> only then touch DST ----
mkdir -p -- "$DST"
stage=$(mktemp -d "$sp_r/hdcs-stage.XXXXXX")
stage_r=$(realpath -- "$stage")
if peq "$stage_r" "$dst_r" || peq "$dst_r" "$stage_r"; then
  rm -rf -- "$stage"
  refuse "A14/A15: instantiated stage path ($stage_r) conflicts with DST ($dst_r)"
fi

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete -- "$SRC/" "$stage/"
else
  cp -a -- "$SRC/." "$stage/"
  while IFS= read -r -d '' p; do
    s="$SRC/${p#./}"
    { [ -e "$s" ] || [ -L "$s" ]; } || rm -rf -- "$stage/${p#./}"
  done < <(cd -- "$stage" && find . -mindepth 1 -print0)
fi

# A13: A9-class content verification of the stage BEFORE touching DST
if ! a9_compare "$src_r" "$stage_r"; then
  rm -rf -- "$stage"
  echo "stage verification failed; DST untouched" >&2
  exit 1
fi

# touch DST (verified stage only)
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete -- "$stage/" "$DST/"
else
  reconcile "$stage" "$DST"
fi

# self-verify: A9-class compare SRC vs DST; mismatch -> nonzero, never warn-and-exit-0
if ! a9_compare "$src_r" "$dst_r"; then
  rm -rf -- "$stage"
  echo "post-sync verification FAILED: DST is not an exact mirror of SRC" >&2
  exit 1
fi

rm -rf -- "$stage"

# one-line UTC summary, real runs only (log parent outside DST — A8, guarded above)
mkdir -p -- "$(dirname -- "$LOG_FILE")"
printf '%sZ sync ok src=%s dst=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%S)" "$SRC" "$DST" >> "$LOG_FILE"

exit 0

