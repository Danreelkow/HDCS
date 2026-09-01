#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror of HERMES_CONTEXT_SRC -> HERMES_CONTEXT_DST
# Stage -> content-verify -> touch DST (A11/A13/A20). Refusals cite A-numbers (A19).
set -u

die() { echo "REFUSE: $*" >&2; exit 1; }
info() { echo "sync-hermes-context: $*"; }

MODE="sync"
[ "${1-}" = "--dry-run" ] && MODE="dry-run"
[ "${1-}" = "--verify" ] && MODE="verify"

# ---- env parameterization: mandated defaults on UNSET (A1/A17); explicitly EMPTY
# values REFUSE and never fall back (ledger 8b: ${VAR-default}, then empty check) ----
raw_src="${HERMES_CONTEXT_SRC-/opt/data/workspace/hermes-context/}"
raw_dst="${HERMES_CONTEXT_DST-/workspace/hermes-context/}"
raw_log="${HERMES_CONTEXT_LOG_DIR-${LOG_DIR-$HOME/.cache/hermes-context/sync.log}}"

canon() { # strip trailing slashes (but never bare "/")
  local p=$1
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p=${p%/}; done
  printf '%s' "$p"
}

SRC=$(canon "$raw_src")
DST=$(canon "$raw_dst")
LOG_FILE=$(canon "$raw_log")

[ -z "$SRC" ] && die "A18: HERMES_CONTEXT_SRC explicitly empty — refusing, no default fallback"
[ -z "$DST" ] && die "A18: HERMES_CONTEXT_DST explicitly empty — refusing, no default fallback"
[ -z "$LOG_FILE" ] && die "A18: log path explicitly empty — refusing, no default fallback"

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
  while IFS= read -r -d '' name
