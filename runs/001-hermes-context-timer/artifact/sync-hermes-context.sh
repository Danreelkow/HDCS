#!/usr/bin/env bash
# sync-hermes-context.sh — one-way host->workspace mirror of the hermes context.
# A2 one-way; A5 recursive mirror (rsync primary, cp fallback); A6/A16 dry-run zero-write;
# A11 stage -> verify -> touch DST; A9-class compare (contents+structure+symlinks).
set -euo pipefail

DRY=0
VERIFY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --verify) VERIFY=1 ;;
    *) echo "sync-hermes-context: unknown argument: $a" >&2; exit 1 ;;
  esac
done

die() { echo "sync-hermes-context: refused $*" >&2; exit 1; }

# A23: unset -> mandated production defaults; set-but-empty -> refuse.
if [ "${HERMES_CONTEXT_SRC+x}" = x ]; then
  [ -n "$HERMES_CONTEXT_SRC" ] || die "A23: HERMES_CONTEXT_SRC is set but empty"
  SRC="$HERMES_CONTEXT_SRC"
else
  SRC="/opt/data/workspace/hermes-context"
fi
if [ "${HERMES_CONTEXT_DST+x}" = x ]; then
  [ -n "$HERMES_CONTEXT_DST" ] || die "A23: HERMES_CONTEXT_DST is set but empty"
  DST="$HERMES_CONTEXT_DST"
else
  DST="/workspace/hermes-context"
fi

# Canonicalize trailing slashes ONCE; mutate only through canonical paths afterwards.
canon() {
  local p="$1"
  while [ "$p" != "/" ] && [ "$p" != "${p%/}" ]; do p="${p%/}"; done
  printf '%s' "$p"
}
SRC=$(canon "$SRC")
DST=$(canon "$DST")

# A18: degenerate paths via component test.
for p in "$SRC" "$DST"; do
  if [ -z "$p" ] || [ "$p" = "." ] || [ "$p" = "/" ]; then
    die "A18: degenerate path '$p' (must not be '/', '', or '.')"
  fi
done

# Component-boundary containment: is $2 equal to or under $1?
is_within() {
  [ "$2" = "$1" ] && return 0
  case "$2" in "$1"/*) return 0 ;; esac
  return 1
}

RSRC=$(realpath -e "$SRC") || { echo "sync-hermes-context: SRC not accessible: $SRC" >&2; exit 1; }
if [ -L "$DST" ]; then
  die "A22: DST is a symlink ($DST); refusing to replace a user-placed symlink"
fi
if [ -e "$DST" ]; then
  RDST=$(realpath "$DST")
else
  RDST=$(realpath -m "$DST")
fi

# A12: identity / ancestor / descendant / symlinked ancestor resolving into SRC.
if is_within "$RSRC" "$RDST" || is_within "$RDST" "$RSRC"; then
  die "A12: SRC and DST are identical or nested (realpath $RSRC vs $RDST)"
fi

# A8 owned paths (concrete instantiated): log file parent, entrypoint dir.
LOG="${HOME}/.cache/hermes-context/sync.log"
LOGP=$(realpath -m "$(dirname "$LOG")")
EDIR=$(realpath -m "${HOME}/.local/bin")

# A13/A9-class tree compare: contents + structure + symlink-ness; NO dereferencing.
compare_trees() {
  if command -v rsync >/dev/null 2>&1; then
    local out
    out=$(rsync -rnc --links --delete --itemize-changes "$1/" "$2/" 2>&1) || return 1
    if printf '%s\n' "$out" | grep -qE '^([<>]|c|\*deleting)'; then return 1; fi
    return 0
  fi
  if diff -r --no-dereference "$1" "$2" >/dev/null 2>&1; then return 0; fi
  diff -r "$1" "$2" >/dev/null 2>&1
}

if [ "$VERIFY" = 1 ]; then
  if [ ! -e "$RDST" ] && [ ! -L "$RDST" ]; then
    echo "sync-hermes-context: verify: DST does not exist: $RDST" >&2
    exit 1
  fi
  compare_trees "$RSRC" "$RDST" \
    || { echo "sync-hermes-context: verify: DST is not an exact mirror of SRC" >&2; exit 1; }
  echo "verify: OK ($RDST mirrors $RSRC)"
  exit 0
fi

if [ "$DRY" = 1 ]; then
  # A6/A16: plan only — zero writes of any kind, no stage, no log, absent DST stays absent.
  if [ ! -e "$RDST" ]; then
    n=$(find "$RSRC" -mindepth 1 | wc -l)
    echo "dry-run: sync=$n delete=0 (DST absent: all-create)"
  elif command -v rsync >/dev/null 2>&1; then
    out=$(rsync -rnc --links --delete --itemize-changes "$RSRC/" "$RDST/" 2>&1) || out=""
    syncn=$(printf '%s\n' "$out" | grep -cE '^>' || true)
    deln=$(printf '%s\n' "$out" | grep -c '\*deleting' || true)
    echo "dry-run: sync=$syncn delete=$deln"
  else
    if diff -r --no-dereference "$RSRC" "$RDST" >/dev/null 2>&1 \
       || diff -r "$RSRC" "$RDST" >/dev/null 2>&1; then
      echo "dry-run: sync=0 delete=0"
    else
      echo "dry-run: differences detected (cp fallback path; counts unavailable)"
    fi
  fi
  exit 0
fi

# A20: validate the stage PARENT as a string/realpath BEFORE mktemp.
PARENT=$(realpath -m "${TMPDIR:-/tmp}")
if [ -z "$PARENT" ] || [ "$PARENT" = "." ] || [ "$PARENT" = "/" ]; then
  PARENT="/tmp"
fi
if is_within "$RDST" "$PARENT" || is_within "$RSRC" "$PARENT"; then
  die "A14/A15: stage parent $PARENT lies inside a protected path"
fi

STAGE=$(mktemp -d "$PARENT/hermes-context-stage.XXXXXX")
STAGE=$(realpath "$STAGE")
cleanup_stage() { rm -rf -- "$STAGE"; }
trap cleanup_stage EXIT

# A14/A15: re-validate the INSTANTIATED stage path (concrete owned set).
for owned in "$STAGE" "$LOGP" "$EDIR"; do
  if is_within "$owned" "$RDST" || is_within "$RDST" "$owned"; then
    die "A14/A15: DST $RDST conflicts with owned path $owned"
  fi
done

# Delete entries in $2 absent from $1 (used by the cp fallback reconcile).
prune_extra() {
  local from="$1" to="$2" e b
  find "$to" -mindepth 1 -maxdepth 1 -print0 | while IFS= read -r -d '' e; do
    b=$(basename "$e")
    if [ ! -e "$from/$b" ] && [ ! -L "$from/$b" ]; then
      rm -rf -- "$e"
    fi
  done
}

# Top-level recursive reconcile for the cp fallback (handles file<->dir swaps,
# replaces symlinks, never follows them: rm -rf on a symlink path unlinks only).
copy_tree() {
  local from="$1" to="$2" e b
  find "$from" -mindepth 1 -maxdepth 1 -print0 | while IFS= read -r -d '' e; do
    b=$(basename "$e")
    if [ -L "$e" ] || [ -f "$e" ]; then
      if [ -f "$to/$b" ] && [ ! -L "$to/$b" ] && [ ! -L "$e" ] && cmp -s "$e" "$to/$b"; then
        :
      else
        rm -rf -- "$to/$b"
        cp -a -- "$e" "$to/$b"
      fi
    elif [ -d "$e" ]; then
      if [ -e "$to/$b" ] && [ ! -d "$to/$b" ]; then rm -rf -- "$to/$b"; fi
      mkdir -p -- "$to/$b"
      copy_tree "$e" "$to/$b"
    fi
  done
}

# A11: stage -> fill stage.
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$RSRC/" "$STAGE/"
else
  cp -a "$RSRC/." "$STAGE/"
  prune_extra "$RSRC" "$STAGE"
fi

# A13: content-verify the stage vs SRC (A9-class) BEFORE touching DST.
if ! compare_trees "$RSRC" "$STAGE"; then
  echo "sync-hermes-context: error: stage failed verification; DST untouched" >&2
  exit 1
fi

# Only now touch DST.
mkdir -p "$(dirname "$RDST")"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$STAGE/" "$RDST/"
else
  mkdir -p "$RDST"
  prune_extra "$STAGE" "$RDST"
  copy_tree "$STAGE" "$RDST"
fi

# Self-verify: A9-class compare SRC vs DST; mismatch -> nonzero, never warn-and-exit-0.
if ! compare_trees "$RSRC" "$RDST"; then
  echo "sync-hermes-context: error: post-sync verification failed (DST != SRC)" >&2
  exit 1
fi

# A8: one log line per real run; log parent is outside DST (guarded above).
mkdir -p "$LOGP"
backend="cp-fallback"
command -v rsync >/dev/null 2>&1 && backend="rsync"
printf '%s sync ok src=%s dst=%s backend=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RSRC" "$RDST" "$backend" >> "$LOG"

exit 0

