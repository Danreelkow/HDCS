#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror SRC -> DST (hermes-context)
# Installed at: ~/.local/bin/sync-hermes-context.sh
# (matches hermes-context.service ExecStart=%h/.local/bin/sync-hermes-context.sh)
#
# A2 one-way host->workspace; A5 recursive mirror; A6 dry-run zero-write;
# A11 stage -> verify -> touch DST; A9-class compare = contents + structure +
# symlink targets (never metadata, never dereferencing).
set -euo pipefail

DRYRUN=0
VERIFY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRYRUN=1 ;;
    --verify)  VERIFY=1 ;;
    *) echo "usage: sync-hermes-context.sh [--dry-run|--verify]" >&2; exit 2 ;;
  esac
done
if [ "$DRYRUN" -eq 1 ] && [ "$VERIFY" -eq 1 ]; then
  echo "A23: --dry-run and --verify are mutually exclusive" >&2
  exit 1
fi

die() { echo "$1" >&2; exit 1; }

# within PARENT CHILD -> 0 iff CHILD == PARENT or CHILD is under PARENT (component-wise)
within() {
  [ "$2" = "$1" ] && return 0
  case "$2/" in
    "$1"/*) return 0 ;;
  esac
  return 1
}

# --- A23: unset -> mandated production defaults; set-but-empty -> refuse ---
if [ -z "${HERMES_CONTEXT_SRC+x}" ]; then
  SRC="/opt/data/workspace/hermes-context"
else
  if [ -z "${HERMES_CONTEXT_SRC}" ]; then
    die "A23: HERMES_CONTEXT_SRC is set but empty (refusing to fall back to the production default)"
  fi
  SRC="${HERMES_CONTEXT_SRC}"
fi
if [ -z "${HERMES_CONTEXT_DST+x}" ]; then
  DST="/workspace/hermes-context"
else
  if [ -z "${HERMES_CONTEXT_DST}" ]; then
    die "A23: HERMES_CONTEXT_DST is set but empty (refusing to fall back to the production default)"
  fi
  DST="${HERMES_CONTEXT_DST}"
fi

# canonicalize trailing slashes once; all mutation goes through canonical paths
SRC="${SRC%/}"
DST="${DST%/}"

# --- A18: degenerate paths (component test) ---
for p in "$SRC" "$DST"; do
  if [ -z "$p" ]; then die "A18: degenerate empty path refused"; fi
  if [ "$p" = "/" ]; then die "A18: degenerate path '/' refused"; fi
  if [ "$p" = "." ]; then die "A18: degenerate path '.' refused"; fi
done

LOGROOT="${HOME}/.cache/hermes-context"      # log file parent — owned path (A8 placement)
LOGFILE="${LOGROOT}/sync.log"
ENTRYDIR="${HOME}/.local/bin"                # entrypoint dir — owned path

# --- realpath resolution (A12: identity checks are realpath-based, never lexical) ---
RSRC=$(realpath -m -- "$SRC") || die "A12: cannot resolve SRC"
RDST=$(realpath -m -- "$DST") || die "A12: cannot resolve DST"

# --- A22: DST itself resolving to a symlink -> refuse, never replace ---
if [ -L "$DST" ]; then
  die "A22: DST is a symlink (resolves to ${RDST}); sync never replaces a user-placed symlink"
fi

# --- A12: identity / ancestor / descendant ---
if [ "$RSRC" = "$RDST" ]; then
  die "A12: SRC and DST are the same path"
fi
if within "$RSRC" "$RDST"; then
  die "A12: DST (${RDST}) is inside SRC (${RSRC})"
fi
if within "$RDST" "$RSRC"; then
  die "A12: SRC (${RSRC}) is inside DST (${RDST})"
fi

# --- A14/A15: owned concrete paths: log file parent, entrypoint dir ---
for owned in "$LOGROOT" "$ENTRYDIR"; do
  if [ -e "$owned" ]; then
    OW=$(realpath -m -- "$owned")
    if within "$OW" "$RDST" || within "$RDST" "$OW"; then
      die "A14: DST (${RDST}) collides with owned path ${OW}"
    fi
  fi
done

# --- A9-class compare: lstat-based, no dereferencing anywhere ---
a9_cmp() { # a9_cmp A B -> 0 iff B is an exact A9-class mirror of A
  diff -r --no-dereference -q -- "$1" "$2" >/dev/null 2>&1
}

# --- --verify: fail when DST absent; OK only on exact mirror; zero writes ---
if [ "$VERIFY" -eq 1 ]; then
  if [ ! -d "$DST" ] || [ -L "$DST" ]; then
    die "verify: DST does not exist (or is not a real directory): ${DST}"
  fi
  if a9_cmp "$SRC" "$DST"; then
    echo "verify: OK — DST is an exact A9-class mirror of SRC"
    exit 0
  fi
  die "verify: DST differs from SRC (A9 mismatch)"
fi

# --- dry-run branch: zero writes of any kind, exit 0 (A6/A16) ---
if [ "$DRYRUN" -eq 1 ]; then
  if command -v rsync >/dev/null 2>&1; then
    OUT=$(rsync -an --delete --itemize-changes -- "$SRC/" "$DST/" 2>&1) || true
    DEL=$(printf '%s\n' "$OUT" | grep -c '^\*deleting' || true)
    SYNC=$(printf '%s\n' "$OUT" | grep -cE '^[<>cdhfLDS.]' || true)
    printf '%s\n' "$OUT"
    echo "dry-run: sync=${SYNC} delete=${DEL}"
  else
    if [ -d "$DST" ]; then
      if a9_cmp "$SRC" "$DST"; then
        echo "dry-run: sync=0 delete=0 (DST already mirrors SRC)"
      else
        echo "dry-run: fallback mode (no rsync): DST differs from SRC; a real run would reconcile recursively (copy diffs, delete stale subtrees, converge symlink targets)"
      fi
    else
      echo "dry-run: fallback mode (no rsync): DST absent — a real run would create it with the full SRC tree"
    fi
  fi
  exit 0
fi

# --- fallback reconcile (no rsync): converges types, bytes, and symlink targets ---
fallback_reconcile() { # $1 = source side, $2 = destination side
  local s="$1" d="$2" e b t
  mkdir -p -- "$d"
  shopt -s nullglob dotglob
  # delete stale entries absent from source
  for e in "$d"/*; do
    b=$(basename -- "$e")
    if [ ! -e "$s/$b" ] && [ ! -L "$s/$b" ]; then
      rm -rf -- "$e"
    fi
  done
  for e in "$s"/*; do
    b=$(basename -- "$e")
    if [ -L "$e" ]; then
      t=$(readlink -- "$e")
      if [ ! -L "$d/$b" ] || [ "$(readlink -- "$d/$b" 2>/dev/null)" != "$t" ]; then
        rm -rf -- "$d/$b"
        ln -s -- "$t" "$d/$b"
      fi
    elif [ -d "$e" ]; then
      if [ ! -d "$d/$b" ] || [ -L "$d/$b" ]; then
        rm -rf -- "$d/$b"
      fi
      fallback_reconcile "$e" "$d/$b"
    else
      if [ -L "$d/$b" ] || [ ! -f "$d/$b" ] || ! cmp -s -- "$e" "$d/$b"; then
        rm -rf -- "$d/$b"
        cp -p -- "$e" "$d/$b" 2>/dev/null || cp -- "$e" "$d/$b"
      fi
    fi
  done
  shopt -u nullglob dotglob
}

# --- A20: stage parent validated as string BEFORE mktemp; re-validated after ---
SPRAW="${TMPDIR:-/tmp}"
if [ -z "$SPRAW" ] || [ "$SPRAW" = "." ] || [ "$SPRAW" = "/" ]; then
  die "A14: invalid stage parent '${SPRAW}'"
fi
SP=$(realpath -m -- "$SPRAW") || die "A14: cannot resolve stage parent '${SPRAW}'"
if within "$SP" "$RDST" || within "$SP" "$RSRC"; then
  die "A14: stage parent (${SP}) is inside DST or SRC; refusing to stage there"
fi
STAGE=$(mktemp -d "${SP}/hermes-context-stage.XXXXXXXX") || die "A14: cannot create stage dir under ${SP}"
cleanup() {
  if [ -n "${STAGE:-}" ] && [ -d "$STAGE" ]; then
    rm -rf -- "$STAGE"
  fi
}
trap cleanup EXIT
RST=$(realpath -- "$STAGE") || die "A14: cannot re-validate instantiated stage path"
if within "$RST" "$RDST" || within "$RST" "$RSRC"; then
  die "A14: instantiated stage (${RST}) is inside DST or SRC"
fi

# --- stage: copy SRC -> stage (A11: nothing touches DST before verification) ---
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete -- "$SRC/" "$STAGE/"
else
  cp -a -- "$SRC/." "$STAGE/"
  fallback_reconcile "$SRC" "$STAGE"
fi

# --- A13: A9-class compare SRC vs stage; mismatch -> DST untouched ---
if ! a9_cmp "$SRC" "$STAGE"; then
  die "A13: staged copy is not an exact mirror of SRC; DST left untouched"
fi

# --- touch DST ---
mkdir -p -- "$(dirname -- "$DST")"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete -- "$STAGE/" "$DST/"
else
  mkdir -p -- "$DST"
  fallback_reconcile "$STAGE" "$DST"
fi

# --- final A9-class self-verify: mismatch -> exit nonzero, never warn-and-exit-0 ---
if ! a9_cmp "$SRC" "$DST"; then
  die "A9: post-sync compare failed — DST does not mirror SRC"
fi

# --- one-line UTC log summary (real runs only; log parent lives outside DST) ---
mkdir -p -- "$LOGROOT"
printf 'hermes-context sync utc=%s src=%s dst=%s result=ok\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SRC" "$DST" >> "$LOGFILE"

echo "sync: DST is an exact mirror of SRC (${SRC} -> ${DST})"
exit 0

