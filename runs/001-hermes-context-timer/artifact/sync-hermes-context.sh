#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror of HERMES_CONTEXT_SRC -> HERMES_CONTEXT_DST
# Stage -> content-verify -> touch DST (A11/A13/A20). Refusals cite A-numbers (A19).
set -u

die() { echo "REFUSE: $*" >&2; exit 1; }
info() { echo "sync-hermes-context: $*"; }

MODE="sync"
[ "${1-}" = "--dry-run" ] && MODE="dry-run"
[ "${1-}" = "--verify" ] && MODE="verify"

# ---- env parameterization (A23): unset -> production default; set-but-empty -> REFUSE A23 ----
if [ -z "${HERMES_CONTEXT_SRC+x}" ]; then
  raw_src="/opt/data/workspace/hermes-context/"
else
  raw_src="${HERMES_CONTEXT_SRC}"
fi
if [ -z "${HERMES_CONTEXT_DST+x}" ]; then
  raw_dst="/workspace/hermes-context/"
else
  raw_dst="${HERMES_CONTEXT_DST}"
fi
# Canonical log identifier is HERMES_CONTEXT_LOG (full log FILE path).
if [ -z "${HERMES_CONTEXT_LOG+x}" ]; then
  raw_log="$HOME/.cache/hermes-context/sync.log"
else
  raw_log="${HERMES_CONTEXT_LOG}"
fi

canon() { # strip trailing slashes (but never bare "/")
  local p=$1
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p=${p%/}; done
  printf '%s' "$p"
}

SRC=$(canon "$raw_src")
DST=$(canon "$raw_dst")
LOG_FILE=$(canon "$raw_log")

[ -z "$SRC" ] && die "A23: HERMES_CONTEXT_SRC set but empty — refusing, no default fallback"
[ -z "$DST" ] && die "A23: HERMES_CONTEXT_DST set but empty — refusing, no default fallback"
[ -z "$LOG_FILE" ] && die "A23: HERMES_CONTEXT_LOG set but empty — refusing, no default fallback"

# ---- A18 degenerate paths: '/', '', '.' (component test, not slash-suffix) ----
[ "$SRC" = "/" ] || [ "$SRC" = "." ] && die "A18: degenerate HERMES_CONTEXT_SRC='$raw_src'"
[ "$DST" = "/" ] || [ "$DST" = "." ] && die "A18: degenerate HERMES_CONTEXT_DST='$raw_dst'"

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd -P) || SCRIPT_DIR=""

# ---- A22: DST path-level symlink -> REFUSE, never replace (operator removes manually) ----
if [ -L "$DST" ]; then
  die "A22: HERMES_CONTEXT_DST='$DST' is a symlink — sync never replaces a user-placed symlink; remove it manually and rerun"
fi

# ---- A12: realpath identity guards (component-boundary, never string prefixes) ----
contains() { # $2 == $1 or $2 inside $1
  [ "$2" = "$1" ] || [ "${2#"$1"/}" != "$2" ]
}
related() {
  contains "$1" "$2" || contains "$2" "$1"
}

rsrc=$(realpath -- "$SRC") || die "A12: cannot resolve realpath of SRC='$SRC'"
rdst=$(realpath -m -- "$DST")

if [ "$rdst" = "$rsrc" ]; then
  die "A12: realpath(DST) == realpath(SRC) ('$rsrc') — refusing"
fi
if contains "$rsrc" "$rdst"; then
  die "A12: DST '$DST' resolves inside SRC '$rsrc' — refusing"
fi
if contains "$rdst" "$rsrc"; then
  die "A12: SRC '$SRC' resolves inside DST '$DST' — refusing"
fi

# ---- A14/A15: DST vs OWNED concrete paths (log file's PARENT dir, entrypoint dir) ----
LOG_PARENT=$(dirname -- "$LOG_FILE")
rlogp=$(realpath -m -- "$LOG_PARENT")
if related "$rdst" "$rlogp"; then
  die "A14: DST '$DST' collides with owned log parent '$rlogp' — refusing"
fi
if [ -n "$SCRIPT_DIR" ]; then
  rent=$(realpath -- "$SCRIPT_DIR") || rent=""
  if [ -n "$rent" ] && related "$rdst" "$rent"; then
    die "A14: DST '$DST' collides with owned entrypoint dir '$rent' — refusing"
  fi
fi

# ---- MIRROR_CLASS verifier: contents, recursive structure, symlinks (lstat-based, never dereferences) ----
cmp_tree() { # $1=srcdir $2=dstdir ; 0 = exact mirror on MIRROR_CLASS
  local s=$1 d=$2 name sp dp rc=0
  while IFS= read -r -d '' name; do
    name=${name#./}
    sp="$s/$name"; dp="$d/$name"
    if [ -L "$sp" ]; then
      if [ ! -L "$dp" ]; then echo "MISMATCH: '$name' is a symlink in SRC but not in DST" >&2; rc=1; continue; fi
      if [ "$(readlink -- "$sp")" != "$(readlink -- "$dp")" ]; then echo "MISMATCH: symlink target differs: '$name'" >&2; rc=1; fi
    elif [ -d "$sp" ]; then
      if [ ! -d "$dp" ] || [ -L "$dp" ]; then echo "MISMATCH: '$name' is a dir in SRC but not in DST" >&2; rc=1; continue; fi
      cmp_tree "$sp" "$dp" || rc=1
    elif [ -f "$sp" ]; then
      if [ ! -f "$dp" ] || [ -L "$dp" ]; then echo "MISMATCH: '$name' is a file in SRC but not in DST" >&2; rc=1; continue; fi
      cmp -s -- "$sp" "$dp" || { echo "MISMATCH: content differs: '$name'" >&2; rc=1; }
    else
      echo "KNOWN_LIMITATION: exotic file type skipped: '$name'" >&2
    fi
  done < <(cd -- "$s" && find . -mindepth 1 -maxdepth 1 -print0)
  # reverse walk: stale entries in DST
  while IFS= read -r -d '' name; do
    name=${name#./}
    if [ ! -e "$s/$name" ] && [ ! -L "$s/$name" ]; then echo "MISMATCH: stale in DST: '$name'" >&2; rc=1; fi
  done < <(cd -- "$d" && find . -mindepth 1 -maxdepth 1 -print0)
  return $rc
}

# ---- dry-run: ALL guards done above; print plan only, ZERO writes (A6, A16) ----
if [ "$MODE" = "dry-run" ]; then
  if [ -e "$DST" ]; then
    info "dry-run plan: mirror '$SRC/' -> '$DST/' (stale entries deleted)"
    if cmp_tree "$SRC" "$DST"; then
      info "dry-run: DST already an exact mirror on MIRROR_CLASS — no changes would be made"
    else
      info "dry-run: differences listed above would be reconciled (no writes performed)"
    fi
  else
    info "dry-run plan: DST '$DST' absent — a real run would mkdir -p and mirror '$SRC/' into it (nothing written now)"
  fi
  exit 0
fi

# ---- verify mode: no writes; FAILS when DST absent; lstat-based (A9, ledger 12) ----
if [ "$MODE" = "verify" ]; then
  if [ ! -e "$DST" ]; then
    echo "VERIFY FAIL: DST '$DST' does not exist" >&2
    exit 1
  fi
  if cmp_tree "$SRC" "$DST"; then
    info "verify OK: '$DST' is an exact mirror of '$SRC' on MIRROR_CLASS"
    exit 0
  fi
  echo "VERIFY FAIL: '$DST' is not an exact mirror of '$SRC' on MIRROR_CLASS" >&2
  exit 1
fi

# ---- real run: stage (A20). Every parent candidate is validated AS A STRING and then
#      RESOLVED and guard-checked (vs SRC/DST/owned) BEFORE mktemp -d creates anything
#      under it; only then is the stage instantiated and re-validated (A15). ----
stage_parent=$(canon "${TMPDIR:-/tmp}")
owned_fallback="$HOME/.cache/hermes-context"   # script-owned fallback parent (A20)
stage=""
for cand in "$stage_parent" "$owned_fallback"; do
  # string-level validation of the parent candidate BEFORE any creation under it
  case "$cand" in
    ""|"/"|"."|*//*) continue ;;
  esac
  # pre-instantiation guard: resolve the candidate (no writes) and check against SRC/DST/owned
  rcand=$(realpath -m -- "$cand") || continue
  if related "$rcand" "$rsrc" || related "$rcand" "$rdst" || related "$rcand" "$rlogp"; then
    continue   # candidate is an owned/guarded path — never create a stage under it
  fi
  # only the OWNED fallback may be created; TMPDIR/system tmp is validated as-is
  if [ "$cand" = "$owned_fallback" ] && [ ! -d "$cand" ]; then
    mkdir -p -- "$cand" 2>/dev/null || continue
  fi
  [ -d "$cand" ] && [ -w "$cand" ] || continue
  # parent validated and guard-checked; NOW atomically instantiate the stage under it
  stage=$(mktemp -d "$cand/hctx-stage.XXXXXX" 2>/dev/null) || continue
  break
done
[ -n "$stage" ] || die "A20: no usable stage parent among '$stage_parent', '$owned_fallback'"

# re-validate the INSTANTIATED stage path (closes validate-string-then-mkdir TOCTOU, A15)
rstage=$(realpath -- "$stage") || { rm -rf -- "$stage"; die "A15: cannot resolve instantiated stage path"; }
if related "$rstage" "$rsrc" || related "$rstage" "$rdst" || related "$rstage" "$rlogp"; then
  rm -rf -- "$stage"
  die "A15: instantiated stage '$rstage' collides with SRC/DST/owned path — refusing"
fi

cleanup_stage() { rm -rf -- "$stage"; }
trap cleanup_stage EXIT

# ---- fill stage with SRC CONTENTS (no nesting): rsync primary, cp -a fallback (A4/A5) ----
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SRC/" "$stage/" || { die "A5: rsync stage fill failed"; }
else
  cp -a "$SRC/." "$stage/" || { die "A5: cp -a stage fill failed"; }
  # fallback stale deletion: explicit recursive removal of stage entries absent from SRC (A7)
  (cd "$stage" && find . -mindepth 1 -maxdepth 1 -print0) | while IFS= read -r -d '' e; do
    e=${e#./}
    if [ ! -e "$SRC/$e" ] && [ ! -L "$SRC/$e" ]; then rm -rf -- "$stage/$e"; fi
  done
fi

# ---- A13 gate: stage is VERIFIED only after content comparison on MIRROR_CLASS ----
if ! cmp_tree "$SRC" "$stage"; then
  echo "ERROR: stage failed MIRROR_CLASS verification against SRC — DST untouched (A11/A13)" >&2
  exit 1
fi

# ---- promote VERIFIED stage into DST (exact mirror, stale deleted) ----
mkdir -p -- "$DST" || die "A5: cannot create DST '$DST'"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$stage/" "$DST/" || die "A5: rsync promotion into DST failed"
else
  # fallback: clear DST children (any type, every depth via recursion) then copy verified stage (A7)
  find "$DST" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  cp -a "$stage/." "$DST/" || die "A5: cp -a promotion into DST failed"
fi

trap - EXIT
rm -rf -- "$stage"

# ---- log one line OUTSIDE DST (guaranteed by A14 guard above, A8) ----
mkdir -p -- "$LOG_PARENT" 2>/dev/null
printf '%s sync src=%s dst=%s ok\n' "$(date -Is 2>/dev/null || date)" "$SRC" "$DST" >>"$LOG_FILE" 2>/dev/null

info "sync complete: '$SRC/' -> '$DST/' (exact mirror, idempotent on rerun)"
exit 0

