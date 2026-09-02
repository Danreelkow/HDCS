#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror SRC -> DST (A2: host -> workspace, never writeback).
# Installed at: ~/.local/bin/sync-hermes-context.sh
# Mirror class A9: contents + recursive structure + symlinks (NOT metadata/timestamps/hardlinks).
# Refusals cite only: A12 | A14/A15 | A18 | A22 | A23 (A19 closed law).
# Modes: (default) real sync | --dry-run (zero writes) | --verify (A9-class compare, exit != 0 on mismatch)
set -euo pipefail

die() { printf 'refusal (%s): %s\n' "$1" "$2" >&2; exit 1; }
fail() { printf 'error: %s\n' "$1" >&2; exit 1; }

canonicalize() { # strip trailing slashes, once, at the boundary
  local v=$1
  while [ "$v" != "${v%/}" ]; do v=${v%/}; done
  printf '%s' "$v"
}

inside() { # inside CHILD ANCESTOR — component-boundary test on canonical paths, never a string prefix
  [ "$1" = "$2" ] && return 0
  case "$1" in
    "$2"/*) return 0 ;;
  esac
  return 1
}

# --- argument parsing -------------------------------------------------------
DRYRUN=0
VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRYRUN=1 ;;
    --verify)  VERIFY=1 ;;
    *) fail "unknown argument: $arg (supported: --dry-run, --verify)" ;;
  esac
done

# --- A23: env resolution (unset -> mandated production default; set-but-empty -> refuse) ---
SRC_RAW="${HERMES_CONTEXT_SRC-/opt/data/workspace/hermes-context}"
DST_RAW="${HERMES_CONTEXT_DST-/workspace/hermes-context}"
[ -n "$SRC_RAW" ] || die A23 "HERMES_CONTEXT_SRC is set but empty (unset uses the production default)"
[ -n "$DST_RAW" ] || die A23 "HERMES_CONTEXT_DST is set but empty (unset uses the production default)"

SRC=$(canonicalize "$SRC_RAW")
DST=$(canonicalize "$DST_RAW")

# --- A18: degenerate paths, component test ---
for pair in "HERMES_CONTEXT_SRC:$SRC" "HERMES_CONTEXT_DST:$DST"; do
  name=${pair%%:*}; val=${pair#*:}
  [ -n "$val" ] || die A18 "degenerate path: $name='' (empty)"
  [ "$val" != "/" ] || die A18 "degenerate path: $name='/'"
  [ "$val" != "." ] || die A18 "degenerate path: $name='.'"
done

[ -d "$SRC" ] || fail "source directory does not exist: $SRC"

realSRC=$(realpath -m -- "$SRC")
realDST=$(realpath -m -- "$DST")

# --- A12: identity / ancestor / descendant ---
if [ "$realSRC" = "$realDST" ]; then
  die A12 "SRC and DST resolve to the same path: $realDST"
fi
if inside "$realDST" "$realSRC"; then
  die A12 "DST is inside SRC (descendant): $realDST"
fi
if inside "$realSRC" "$realDST"; then
  die A12 "SRC is inside DST (ancestor): $realDST"
fi

# --- A22 / A12: DST itself a symlink — refuse, never replace ---
if [ -L "$DST" ]; then
  res=$(realpath -- "$DST")
  if inside "$res" "$realSRC"; then
    die A12 "DST symlink resolves into SRC: $DST -> $res"
  fi
  die A22 "DST resolves to a user-placed symlink outside SRC: $DST -> $res (refusing, path left untouched)"
fi

# --- A8/A14/A15: owned concrete paths (log file's PARENT dir, entrypoint dir) ---
LOGF="${HERMES_CTX_LOG-${HOME}/.cache/hermes-context/sync.log}"
if [ -z "$LOGF" ]; then
  LOGF="${HOME}/.cache/hermes-context/sync.log"
fi
LOGPARENT=$(realpath -m -- "$(dirname -- "$LOGF")")
ENTRYDIR=$(dirname -- "$(realpath -- "$0")")

owned_guard() { # refuse iff realpath(DST)==owned ∨ owned ⊂ DST ∨ DST ⊂ owned
  local o=$1
  if inside "$realDST" "$o" || inside "$o" "$realDST"; then
    die A14 "DST $realDST overlaps an owned path $o (log parent / entrypoint dir must live outside DST)"
  fi
}
owned_guard "$LOGPARENT"
owned_guard "$ENTRYDIR"

# --- A9-class recursive compare (lstat-based: types, symlink targets, bytes; never dereferences) ---
A9MSG=""
cmpwalk() { # cmpwalk SRCDIR DSTDIR — returns 1 on first mismatch
  local s d name
  for s in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ -e "$s" ] || [ -L "$s" ] || continue
    name=${s##*/}
    d="$2/$name"
    if [ -L "$s" ]; then
      if [ ! -L "$d" ]; then A9MSG="type mismatch at $name: SRC symlink vs DST $( [ -e "$d" ] || printf missing )"; return 1; fi
      [ "$(readlink -- "$s")" = "$(readlink -- "$d")" ] || { A9MSG="symlink target mismatch at $name"; return 1; }
    elif [ -d "$s" ]; then
      if [ ! -d "$d" ] || [ -L "$d" ]; then A9MSG="type mismatch at $name: SRC dir vs DST $( [ -e "$d" ] || printf missing )"; return 1; fi
      cmpwalk "$s" "$d" || return 1
    else
      if [ ! -f "$d" ] || [ -L "$d" ]; then A9MSG="type mismatch at $name: SRC file vs DST $( [ -L "$d" ] && printf symlink || printf missing )"; return 1; fi
      cmp -s -- "$s" "$d" || { A9MSG="content mismatch at $name"; return 1; }
    fi
  done
  for d in "$2"/* "$2"/.[!.]* "$2"/..?*; do
    [ -e "$d" ] || [ -L "$d" ] || continue
    name=${d##*/}
    if [ ! -e "$1/$name" ] && [ ! -L "$1/$name" ]; then A9MSG="stale entry in DST: $name"; return 1; fi
  done
  return 0
}
a9_cmp() {
  A9MSG=""
  cmpwalk "$1" "$2"
}

# --- read-only diff counter (dry-run fallback when rsync is unavailable) ---
SYNC=0; DEL=0
diffcount() { # diffcount SRCDIR DSTDIR
  local s d name
  for s in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ -e "$s" ] || [ -L "$s" ] || continue
    name=${s##*/}; d="$2/$name"
    if [ -L "$s" ]; then
      if [ ! -L "$d" ] || [ "$(readlink -- "$s")" != "$(readlink -- "$d" 2>/dev/null)" ]; then SYNC=$((SYNC+1)); fi
    elif [ -d "$s" ]; then
      if [ ! -d "$d" ] || [ -L "$d" ]; then SYNC=$((SYNC+1)); else diffcount "$s" "$d"; fi
    else
      if [ ! -f "$d" ] || [ -L "$d" ] || ! cmp -s -- "$s" "$d"; then SYNC=$((SYNC+1)); fi
    fi
  done
  for d in "$2"/* "$2"/.[!.]* "$2"/..?*; do
    [ -e "$d" ] || [ -L "$d" ] || continue
    name=${d##*/}
    if [ ! -e "$1/$name" ] && [ ! -L "$1/$name" ]; then DEL=$((DEL+1)); fi
  done
}

# --- dry-run: zero writes of any kind, absent DST stays absent ---
if [ "$DRYRUN" -eq 1 ]; then
  SYNC=0; DEL=0
  PLAN=""
  if command -v rsync >/dev/null 2>&1; then
    PLAN=$(rsync -an --delete --itemize-changes -- "$SRC/" "$DST/" 2>&1) || true
    SYNC=$(printf '%s\n' "$PLAN" | grep -c '^>f' || true)
    DEL=$(printf '%s\n' "$PLAN" | grep -c '^\*deleting' || true)
    printf '%s\n' "$PLAN"
  else
    if [ -d "$DST" ]; then
      diffcount "$SRC" "$DST"
    else
      diffcount "$SRC" "$(mktemp -u -d)" 2>/dev/null || { SYNC=0; DEL=0; }
      # DST absent: every SRC entry would be created — count recursively, read-only
      SYNC=0; DEL=0
      count_all() {
        local s
        for s in "$1"/* "$1"/.[!.]* "$1"/..?*; do
          [ -e "$s" ] || [ -L "$s" ] || continue
          SYNC=$((SYNC+1))
          if [ -d "$s" ] && [ ! -L "$s" ]; then count_all "$s"; fi
        done
      }
      count_all "$SRC"
    fi
  fi
  printf 'dry-run: sync=%s delete=%s\n' "$SYNC" "$DEL"
  exit 0
fi

# --- verify: FAILS when DST absent; OK only on exact A9-class mirror ---
if [ "$VERIFY" -eq 1 ]; then
  [ -d "$DST" ] || fail "verify: DST does not exist: $DST (verify must fail when destination is absent)"
  if a9_cmp "$SRC" "$DST"; then
    printf 'verify OK: %s == %s\n' "$SRC" "$DST"
    exit 0
  fi
  printf 'verify FAILED: %s\n' "${A9MSG:-unknown mismatch}" >&2
  exit 1
fi

# --- real run: stage parent validated BEFORE mktemp (A20/A11) ---
RSTAGE=""
cleanup() { [ -n "$RSTAGE" ] && rm -rf -- "$RSTAGE"; return 0; }
trap cleanup EXIT

TP=$(canonicalize "${TMPDIR-/tmp}")
[ -n "$TP" ] || die A18 "degenerate stage parent: TMPDIR=''"
[ "$TP" != "/" ] || die A18 "degenerate stage parent: TMPDIR='/'"
[ "$TP" != "." ] || die A18 "degenerate stage parent: TMPDIR='.'"
realTP=$(realpath -m -- "$TP")
if inside "$realTP" "$realDST"; then
  die A14 "stage parent $realTP is inside DST — nothing may descend into a protected path before verification"
fi
if inside "$realTP" "$realSRC"; then
  die A14 "stage parent $realTP is inside SRC — nothing may descend into a protected path before verification"
fi
if inside "$realTP" "$LOGPARENT" || inside "$LOGPARENT" "$realTP"; then
  die A14 "stage parent $realTP overlaps owned log-parent path $LOGPARENT"
fi
if inside "$realTP" "$ENTRYDIR" || inside "$ENTRYDIR" "$realTP"; then
  die A14 "stage parent $realTP overlaps owned entrypoint path $ENTRYDIR"
fi

STAGE=$(mktemp -d -- "${TP}/hctx-stage.XXXXXXXX")
RSTAGE=$STAGE
realSTAGE=$(realpath -- "$STAGE")
if inside "$realSTAGE" "$realDST" || inside "$realDST" "$realSTAGE"; then
  die A14 "instantiated stage $realSTAGE overlaps DST"
fi
if inside "$realSTAGE" "$LOGPARENT" || inside "$realSTAGE" "$ENTRYDIR"; then
  die A14 "instantiated stage $realSTAGE is inside an owned path"
fi

# --- populate stage (A11: nothing touches DST before this stage is verified) ---
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete -- "$SRC/" "$STAGE/"
  RSYNC_MODE=rsync
else
  cp -a -- "$SRC/." "$STAGE/"
  RSYNC_MODE=cp
fi

# --- A13: A9-class content verification of stage vs SRC — only then touch DST ---
if ! a9_cmp "$SRC" "$STAGE"; then
  fail "staged copy failed A9-class verification: ${A9MSG} — DST untouched"
fi

# --- touch DST ---
if [ -e "$DST" ] && [ ! -d "$DST" ] && [ ! -L "$DST" ]; then
  rm -f -- "$DST"   # stage is verified; type change file->dir is safe here
fi
if [ "$RSYNC_MODE" = rsync ]; then
  rsync -a --delete -- "$STAGE/" "$DST/"
else
  fallback_sync() { # fallback_sync SRCDIR DSTDIR — converge symlink targets, types, bytes, delete stale
    local s d name tgt
    if [ -e "$2" ] && [ ! -d "$2" ] && [ ! -L "$2" ]; then rm -f -- "$2"; fi
    mkdir -p -- "$2"
    for d in "$2"/* "$2"/.[!.]* "$2"/..?*; do
      [ -e "$d" ] || [ -L "$d" ] || continue
      name=${d##*/}
      if [ ! -e "$1/$name" ] && [ ! -L "$1/$name" ]; then rm -rf -- "$d"; fi
    done
    for s in "$1"/* "$1"/.[!.]* "$1"/..?*; do
      [ -e "$s" ] || [ -L "$s" ] || continue
      name=${s##*/}; d="$2/$name"
      if [ -L "$s" ]; then
        tgt=$(readlink -- "$s")
        if [ ! -L "$d" ] || [ "$(readlink -- "$d" 2>/dev/null)" != "$tgt" ]; then
          rm -rf -- "$d"; ln -s -- "$tgt" "$d"
        fi
      elif [ -d "$s" ]; then
        if [ ! -d "$d" ] || [ -L "$d" ]; then rm -rf -- "$d"; mkdir -p -- "$d"; fi
        fallback_sync "$s" "$d"
      else
        if [ ! -f "$d" ] || [ -L "$d" ] || ! cmp -s -- "$s" "$d"; then
          rm -rf -- "$d"; cp -- "$s" "$d"
        fi
      fi
    done
  }
  fallback_sync "$STAGE" "$DST"
fi

# --- final self-verify: SRC vs DST, A9-class; mismatch -> exit nonzero, never warn-and-exit-0 ---
if ! a9_cmp "$SRC" "$DST"; then
  fail "post-sync verification failed: ${A9MSG}"
fi

# --- one-line UTC log (real runs only; parent dir outside DST by A14 guard) ---
mkdir -p -- "$(dirname -- "$LOGF")"
printf '%s sync ok src=%s dst=%s mode=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SRC" "$DST" "$RSYNC_MODE" >> "$LOGF"

printf 'synced: %s -> %s (%s)\n' "$SRC" "$DST" "$RSYNC_MODE"
exit 0

