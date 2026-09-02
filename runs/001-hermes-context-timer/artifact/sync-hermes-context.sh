#!/usr/bin/env bash
# sync-hermes-context.sh — one-way host->workspace mirror of the hermes context.
# A2 one-way; A5 recursive mirror (rsync primary, cp fallback); A6 dry-run zero-write;
# A9-class compare (contents+structure+symlinks, lstat-based, never dereferencing);
# A11 stage -> verify -> touch DST; refusals cite only A12|A14/A15|A18|A22|A23.
set -euo pipefail

SELF=${BASH_SOURCE[0]}
STAGE=""
cleanup() { [ -n "$STAGE" ] && rm -rf -- "$STAGE" || true; }
trap cleanup EXIT

fail() { printf '%s\n' "$*" >&2; exit 1; }

USE_DRY=0
USE_VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) USE_DRY=1 ;;
    --verify)  USE_VERIFY=1 ;;
    *) fail "unknown argument: $arg" ;;
  esac
done

# --- A23: env resolution (unset -> production default; set-but-empty -> refuse) ---
if [ "${HERMES_CONTEXT_SRC+set}" = "set" ] && [ -z "$HERMES_CONTEXT_SRC" ]; then
  fail "A23: HERMES_CONTEXT_SRC is set but empty — refusing"
fi
if [ "${HERMES_CONTEXT_DST+set}" = "set" ] && [ -z "$HERMES_CONTEXT_DST" ]; then
  fail "A23: HERMES_CONTEXT_DST is set but empty — refusing"
fi
SRC=${HERMES_CONTEXT_SRC-/opt/data/workspace/hermes-context}
DST=${HERMES_CONTEXT_DST-/workspace/hermes-context}

# --- A18: degenerate paths (component test on raw values) ---
for v in "$SRC" "$DST"; do
  if [ -z "$v" ] || [ "$v" = "/" ] || [ "$v" = "." ]; then
    fail "A18: degenerate path '$v' (must not be '/', '' or '.') — refusing"
  fi
done

# Canonicalize once (trailing slashes, etc.); every mutation goes through RSC/RDC.
RSC=$(realpath -m -- "$SRC")
RDC=$(realpath -m -- "$DST")
for v in "$RSC" "$RDC"; do
  if [ -z "$v" ] || [ "$v" = "/" ] || [ "$v" = "." ]; then
    fail "A18: degenerate path '$v' — refusing"
  fi
done

# --- A12: realpath identity / ancestor / descendant ---
inside() { # inside <candidate-child> <ancestor>: component-boundary containment
  [ "$1" = "$2" ] || case "$1" in "$2"/*) return 0 ;; *) return 1 ;; esac
}
if [ "$RSC" = "$RDC" ]; then
  fail "A12: SRC and DST resolve to the same path ($RDC) — refusing"
fi
if inside "$RDC" "$RSC"; then
  fail "A12: DST ($RDC) lies inside SRC ($RSC) — refusing"
fi
if inside "$RSC" "$RDC"; then
  fail "A12: SRC ($RSC) lies inside DST ($RDC) — refusing"
fi

# --- A22: DST resolving to a symlink -> refuse, never replace ---
if [ -L "$RDC" ] || [ -L "$DST" ]; then
  fail "A22: DST ($DST) is a symlink — sync never replaces a user-placed symlink — refusing"
fi

# --- A14/A15: log file parent and entrypoint dir are owned paths ---
LOG=${HERMES_CTX_LOG-${LOG_DIR-$HOME/.cache/hermes-context/sync.log}}
LOGDIR=$(dirname -- "$LOG")
RLP=$(realpath -m -- "$LOGDIR")
if [ "$RLP" = "$RDC" ] || inside "$RLP" "$RDC" || inside "$RDC" "$RLP"; then
  fail "A14/A15: DST ($RDC) overlaps the owned log parent ($RLP) — refusing"
fi
EPDIR=$(cd -- "$(dirname -- "$SELF")" && pwd)
REP=$(realpath -- "$EPDIR")
if [ "$REP" = "$RDC" ] || inside "$REP" "$RDC" || inside "$RDC" "$REP"; then
  fail "A14/A15: DST ($RDC) overlaps the owned entrypoint dir ($REP) — refusing"
fi

# --- A9-class compare: contents + recursive structure + symlinks (lstat-based) ---
if command -v rsync >/dev/null 2>&1; then
  compare9() { # empty itemized diff (checksummed, --delete, no dereference) == exact mirror
    [ -z "$(rsync -ainc --delete --itemize-changes "$1/" "$2/")" ]
  }
else
  compare9() {
    diff -r --no-dereference "$1" "$2" >/dev/null 2>&1 || return 1
    local lsym dsym
    lsym=$(cd -- "$1" && find . -type l -print | sort | xargs -r -n1 readlink --)
    dsym=$(cd -- "$2" && find . -type l -print | sort | xargs -r -n1 readlink --)
    [ "$lsym" = "$dsym" ]
  }
fi

# --- dry-run branch (A6/A16): zero writes of any kind, no stage, no log, DST untouched ---
if [ "$USE_DRY" -eq 1 ]; then
  SYNCED=0; DELETED=0
  if command -v rsync >/dev/null 2>&1; then
    PLAN=$(rsync -an --delete --itemize-changes "$RSC/" "$RDC/") || fail "dry-run plan failed"
    while IFS= read -r line; do
      case "$line" in
        "" ) ;;
        *deleting*) DELETED=$((DELETED+1)) ;;
        *) SYNCED=$((SYNCED+1)) ;;
      esac
    done <<< "$PLAN"
    [ -n "$PLAN" ] && printf '%s\n' "$PLAN"
  elif [ ! -d "$RDC" ]; then
    SYNCED=$(find "$RSC" -mindepth 1 | wc -l)
  else
    PLAN=$(diff -rq --no-dereference "$RSC" "$RDC" 2>/dev/null || true)
    while IFS= read -r line; do
      case "$line" in
        "Only in $RDC"*) DELETED=$((DELETED+1)) ;;
        "") ;;
        *) SYNCED=$((SYNCED+1)) ;;
      esac
    done <<< "$PLAN"
    [ -n "$PLAN" ] && printf '%s\n' "$PLAN"
  fi
  echo "dry-run: sync=$SYNCED delete=$DELETED"
  exit 0
fi

# --- verify branch: FAILS when DST absent; OK only on exact A9-class mirror ---
if [ "$USE_VERIFY" -eq 1 ]; then
  [ -d "$RDC" ] || fail "verify failed: DST ($RDC) does not exist"
  if compare9 "$RSC" "$RDC"; then
    echo "verify: OK — DST is an exact A9-class mirror of SRC"
    exit 0
  fi
  fail "verify failed: DST ($RDC) does not mirror SRC (A9-class mismatch)"
fi

# --- A20 stage: string-validate parent BEFORE mktemp -> re-validate instantiated path ---
TMPROOT=${TMPDIR-/tmp}
[ -n "$TMPROOT" ] || fail "A20: TMPDIR empty"
RTMP=$(realpath -m -- "${TMPROOT%/}")
for v in "$RTMP"; do
  if [ -z "$v" ] || [ "$v" = "/" ] || [ "$v" = "." ]; then
    fail "A18: degenerate stage parent '$v' — refusing"
  fi
done
# Pre-mktemp guard: refuse only when the stage would land inside DST (parent
# string validation; the generic ancestor itself is never owned — A14/A15 scope
# is the concrete instantiated stage path, re-validated below).
if [ "$RTMP" = "$RDC" ] || inside "$RTMP" "$RDC"; then
  fail "A14/A15: stage parent ($RTMP) lies inside DST ($RDC) — refusing"
fi
STAGE=$(mktemp -d "${RTMP%/}/hermes-context-stage.XXXXXX")
RST=$(realpath -- "$STAGE")
if [ "$RST" = "$RDC" ] || inside "$RST" "$RDC" || inside "$RDC" "$RST"; then
  fail "A14/A15: DST ($RDC) overlaps the owned stage dir ($RST) — refusing"
fi

SYNCED=0; DELETED=0

# Recursive reconcile fallback: make DST tree mirror SRC tree (contents+structure+symlinks).
type_of() {
  if [ -L "$1" ]; then echo link
  elif [ -d "$1" ]; then echo dir
  elif [ -e "$1" ]; then echo file
  else echo absent
  fi
}
reconcile() { # reconcile <src> <dst>
  local s="$1" d="$2" sp dp name stype dtgt
  mkdir -p -- "$d"
  while IFS= read -r dp; do
    name=${dp##*/}
    if [ ! -e "$s/$name" ] && [ ! -L "$s/$name" ]; then
      rm -rf -- "$dp"; DELETED=$((DELETED+1))
    fi
  done < <(find "$d" -mindepth 1 -maxdepth 1)
  while IFS= read -r sp; do
    name=${sp##*/}
    dp="$d/$name"
    stype=$(type_of "$sp")
    if [ "$(type_of "$dp")" != "$stype" ]; then
      rm -rf -- "$dp"
    fi
    case "$stype" in
      dir)
        [ -d "$dp" ] || mkdir -p -- "$dp"
        reconcile "$sp" "$dp"
        ;;
      link)
        dtgt=$(readlink -- "$sp")
        if [ ! -L "$dp" ] || [ "$(readlink -- "$dp")" != "$dtgt" ]; then
          rm -f -- "$dp"; ln -s -- "$dtgt" "$dp"; SYNCED=$((SYNCED+1))
        fi
        ;;
      *)
        if ! cmp -s -- "$sp" "$dp"; then
          cp -a -- "$sp" "$dp"; SYNCED=$((SYNCED+1))
        fi
        ;;
    esac
  done < <(find "$s" -mindepth 1 -maxdepth 1)
}

# --- populate stage (A11: nothing touches DST yet) ---
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$RSC/" "$RST/" || { rm -rf -- "$STAGE"; fail "stage population failed"; }
else
  reconcile "$RSC" "$RST"
fi

# --- A13: A9-class compare SRC vs stage before any destructive op on DST ---
if ! compare9 "$RSC" "$RST"; then
  rm -rf -- "$STAGE"
  fail "A13: stage does not mirror SRC (A9-class mismatch) — DST untouched"
fi

# --- touch DST: mirror stage into DST (rsync primary, reconcile fallback) ---
mkdir -p -- "$RDC"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$RST/" "$RDC/" || reconcile "$RST" "$RDC"
else
  reconcile "$RST" "$RDC"
fi

# --- self-verify: A9-class compare SRC vs DST, mismatch -> exit nonzero ---
if ! compare9 "$RSC" "$RDC"; then
  fail "A9-class verify failed: DST does not mirror SRC after sync"
fi

rm -rf -- "$STAGE"; STAGE=""

# --- A8: one-line UTC log, real runs only; log parent outside DST (guarded above) ---
mkdir -p -- "$LOGDIR"
printf '%s sync=hermes-context src=%s dst=%s method=%s copied=%s deleted=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RSC" "$RDC" \
  "$(command -v rsync >/dev/null 2>&1 && echo rsync || echo cp-fallback)" \
  "$SYNCED" "$DELETED" >> "$LOG"

echo "sync complete: $RSC -> $RDC"
exit 0
