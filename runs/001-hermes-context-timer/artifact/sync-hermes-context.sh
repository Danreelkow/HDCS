#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror SRC -> DST (hermes-context freshness)
# Standalone-executable and systemd-user-invokable (A3). Refusals cite A-numbers (A19).
set -u
set -o pipefail

MODE="sync"
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry" ;;
    --verify)  MODE="verify" ;;
    *) echo "usage: $0 [--dry-run|--verify]" >&2; exit 2 ;;
  esac
done

die() { echo "REFUSED $1: $2" >&2; exit 1; }
fail() { echo "FAIL: $1" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# canonicalize env values ONCE (strip trailing slashes, never mutate raw again) — ledger #7
canon() {
  local p="$1"
  while [[ "$p" == */ && "$p" != "/" ]]; do p="${p%/}"; done
  printf '%s' "$p"
}

SRC_RAW="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST_RAW="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
SRC="$(canon "$SRC_RAW")"
DST="$(canon "$DST_RAW")"
LOG_DIR="${HERMES_CONTEXT_LOG_DIR:-$HOME/.cache/hermes-context}"

# A18: degenerate paths — component test on canonical form, not slash-suffix
for p in "$SRC" "$DST"; do
  [ -z "$p" ] && die "A18" "degenerate path (empty) is not allowed"
  [ "$p" = "/" ] && die "A18" "degenerate path '/' is not allowed"
  [ "$p" = "." ] && die "A18" "degenerate path '.' is not allowed"
done

# component-boundary-aware containment: true if $2 is $1 or lies inside $1 (A15)
inside() {
  local a b
  a="$(realpath -m -- "$1")" || return 1
  b="$(realpath -m -- "$2")" || return 1
  [ "$b" = "$a" ] || [[ "$b"/ == "$a"/* ]]
}

RSRC="$(realpath -m -- "$SRC")"
RDST="$(realpath -m -- "$DST")"

# A12: identity / ancestor / descendant / DST-resolving-into-SRC (realpath-based, pre-destruction)
[ "$RSRC" = "$RDST" ] && die "A12" "realpath(SRC) == realpath(DST)"
if inside "$SRC" "$DST" || inside "$DST" "$SRC"; then
  die "A12" "SRC and DST are ancestor/descendant of one another (realpath)"
fi

# A22: DST itself is a symlink -> refuse, never replace (operator removes manually).
# (DST symlink resolving INTO SRC was already caught as A12 above.)
[ -L "$DST" ] && die "A22" "DST path is a symlink; sync never replaces a user-placed symlink — remove it manually"

# A14/A15: owned paths (LOG_DIR, optional HERMES_CTX_LOG, script/entrypoint dir)
# DST ==/inside/contains any owned path -> refuse; component-aware, never string-prefix.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd -P)" || SCRIPT_DIR=""
OWNED=("$LOG_DIR" "$SCRIPT_DIR")
[ -n "${HERMES_CTX_LOG:-}" ] && OWNED+=("$HERMES_CTX_LOG")
for o in "${OWNED[@]}"; do
  [ -n "$o" ] || continue
  if inside "$o" "$DST"; then die "A14" "DST is or lies inside owned path '$o'"; fi
  if inside "$DST" "$o"; then die "A14" "DST contains owned path '$o'"; fi
done

LOG_FILE="${HERMES_CTX_LOG:-$LOG_DIR/sync.log}"

# MIRROR_CLASS compare: {file contents, recursive structure, symlinks} — NOT metadata (A9).
# rsync path: -c (checksum content comparison, NOT size/mtime), -r recursive, -L
# symlink dereference for comparison; NO -a (metadata must be excluded from verification).
compare_mirror() { # $1=src $2=dst ; exit 0 iff exact mirror on MIRROR_CLASS
  local s="$1" d="$2"
  if have rsync; then
    local out
    out="$(rsync -rLnc --delete --dry-run -i -- "$s/" "$d/" 2>/dev/null)" || return 1
    [ -z "$out" ]
  else
    local opt=""
    diff -r --no-dereference /dev/null /dev/null >/dev/null 2>&1 && opt="--no-dereference"
    diff -r $opt -- "$s" "$d" >/dev/null 2>&1
  fi
}

if [ "$MODE" = "verify" ]; then
  [ -e "$DST" ] || fail "VERIFY FAIL: DST '$DST' does not exist (verify cannot pass on absent destination)"
  if compare_mirror "$SRC" "$DST"; then
    echo "VERIFY OK: '$DST' is an exact mirror of '$SRC' on MIRROR_CLASS"
    exit 0
  fi
  fail "VERIFY FAIL: '$DST' is not an exact mirror of '$SRC' on MIRROR_CLASS"
fi

if [ "$MODE" = "dry" ]; then
  # A6/A16: dry-run performs ALL guards (done above), prints plan only, ZERO writes:
  # no log file, no stage dir, DST not created if absent.
  echo "DRY-RUN plan: mirror '$SRC' -> '$DST' (rsync --delete semantics; stale entries removed)"
  if have rsync; then
    rsync -a --delete --dry-run -i -- "$SRC/" "$DST/" 2>/dev/null || echo "(rsync preview unavailable)"
  else
    echo "rsync absent: cp -a fallback would copy SRC contents and delete stale subtrees at every depth"
  fi
  echo "DRY-RUN complete: no files, logs, or stage directories were written."
  exit 0
fi

# ---- real run: stage -> verify -> touch DST (A11/A13/A20/A22) ----
# Stage path: validate parent (string), mktemp -d under it, then RE-VALIDATE the
# instantiated path (A15/A22 — closes validate-string-then-mkdir TOCTOU).
STAGE=""
for cand in "$(dirname "$DST")" "${TMPDIR:-/tmp}" "$HOME/.cache"; do
  [ -n "$cand" ] || continue
  [ -d "$cand" ] && [ -w "$cand" ] || continue
  s="$(mktemp -d "${cand%/}/.hermes-stage.XXXXXX" 2>/dev/null)" || continue
  rs="$(realpath -m -- "$s")"
  if inside "$DST" "$rs" || inside "$SRC" "$rs" || inside "$rs" "$DST"; then
    rm -rf -- "$s"; continue
  fi
  STAGE="$s"; break
done
[ -n "$STAGE" ] || fail "no writable stage parent available (TMPDIR and fallbacks failed)"
cleanup() { [ -n "${STAGE:-}" ] && rm -rf -- "$STAGE"; }
trap cleanup EXIT

# sync SRC CONTENTS into stage (no nesting): rsync primary, cp -a fallback (A4)
if have rsync; then
  rsync -a --delete -- "$SRC/" "$STAGE/" || fail "rsync stage population failed"
else
  # stage starts empty, so no stale entries exist yet; the fallback's stale-subtree
  # deletion at every depth is exercised at promote time (A7)
  cp -a -- "$SRC/." "$STAGE/" || fail "cp -a stage population failed"
fi

# A13/A9: content-compare stage vs SRC on MIRROR_CLASS exactly; mismatch -> nonzero
compare_mirror "$SRC" "$STAGE" || fail "stage verification failed: stage is not an exact mirror of SRC (A9/A13)"

# only now, with a VERIFIED stage, touch DST (A11)
mkdir -p -- "$(dirname "$DST")" || fail "cannot create DST parent"
# reconcile a pre-existing regular file at DST into the required directory mirror:
# rsync cannot promote into a file target; the verified stage exists, so removal is safe (A11)
if [ -f "$DST" ] && [ ! -L "$DST" ]; then
  rm -f -- "$DST" || fail "could not replace pre-existing file at DST"
fi
if have rsync; then
  rsync -a --delete -- "$STAGE/" "$DST/" || fail "rsync promote failed"
else
  # fallback promote: remove DST (verified stage exists — A11 satisfied), copy stage.
  # This deletes stale files and stale subtrees at every depth and reconciles
  # file<->dir type changes (A5/A7). Symlinks inside DST are removed, not followed.
  rm -rf -- "$DST" || fail "could not clear DST for fallback promote"
  cp -a -- "$STAGE" "$DST" || fail "cp -a promote failed"
fi

# log one line, OUTSIDE DST (A8); dry-run never reaches here.
# Log failures are NOT suppressed: a normal real run must produce its log line.
mkdir -p -- "$LOG_DIR" || fail "cannot create LOG_DIR '$LOG_DIR' (A8: log lives outside DST)"
printf '%s hermes-context: sync OK src=%s dst=%s mode=%s\n' "$(date -Is 2>/dev/null || date)" "$SRC" "$DST" "$MODE" >>"$LOG_FILE" || fail "could not write log line to '$LOG_FILE'"

echo "sync complete: '$DST' mirrors '$SRC'"
exit 0

