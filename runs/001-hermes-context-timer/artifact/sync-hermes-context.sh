#!/usr/bin/env bash
# sync-hermes-context.sh — one-way host->workspace context mirror (A2/A9)
# rsync primary; cp/tar fallback converges to identical end state (A5/A7)
# A13: BOTH paths stage -> content-verify against SRC -> only then touch DST
# A6/A16: --dry-run performs ZERO writes (no log, no mkdir, no mktemp)
# A19/A20: refusals cite A-numbers, write nothing; guards precede every write
# A8: log/stage/entrypoint concrete paths are boundary-checked vs SRC and DST
# NOTE: uses only portable find/sed/sort (no GNU -printf); filenames containing
#       newlines/control chars are a documented KNOWN_LIMITATION (A21).
set -euo pipefail

# --- env parameterization (A17): contract names, deployed defaults ---
SRC_RAW=${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}
DST_RAW=${HERMES_CONTEXT_DST:-/workspace/hermes-context}
LOG_RAW=${HERMES_CTX_LOG:-$HOME/.cache/hermes-context}

MODE="${1:-}"

die() { printf 'refused: %s\n' "$2" >&2; exit "${1:-2}"; }

# --- lexical cleanup before resolution ---
strip_trailing() {
  local p=$1
  while [ -n "$p" ] && [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p=${p%/}; done
  printf '%s' "$p"
}

# resolve_path: realpath of deepest existing ancestor + not-yet-existing lexical
# tail — so guards hold for DST/LOG paths that do not exist yet. No writes.
resolve_path() {
  local p=$1 cur tail=""
  if [ -e "$p" ] || [ -L "$p" ]; then realpath -- "$p"; return 0; fi
  cur=$p
  while [ ! -e "$cur" ] && [ "$cur" != "/" ]; do
    tail="/$(basename -- "$cur")$tail"
    cur=$(dirname -- "$cur")
  done
  printf '%s%s' "$(realpath -- "$cur")" "$tail"
}

# --- A18: degenerate-path refusal BEFORE resolution (component tests) ---
for _p in "$SRC_RAW" "$DST_RAW"; do
  case "$(strip_trailing "$_p")" in
    ""|"."|".."|"/") die 2 "A18: degenerate path '$_p' (empty, '.', '..', or '/'); nothing was written" ;;
  esac
done
SRC=$(resolve_path "$(strip_trailing "$SRC_RAW")")
DST=$(resolve_path "$(strip_trailing "$DST_RAW")")
LOG_DIR=$(resolve_path "$(strip_trailing "$LOG_RAW")")
[ "$SRC" = "/" ] && die 2 "A18: source resolves to '/'"
[ "$DST" = "/" ] && die 2 "A18: destination resolves to '/'"

# --- guards: everything below writes nothing (A19/A20) ---
[ -d "$SRC" ] || die 2 "A1: source '$SRC' does not exist or is not a directory"

# A12: realpath identity / ancestor / descendant / DST-inside-SRC, both ways
if [ "$DST" = "$SRC" ] || [ "${DST#"$SRC"/}" != "$DST" ] \
   || [ "${SRC#"$DST"/}" != "$SRC" ]; then
  die 2 "A12: SRC '$SRC' and DST '$DST' are equal or ancestor/descendant (realpath-resolved)"
fi

# A14/A15: concrete owned paths (log FILE parent, stage parent, entrypoint dir)
# boundary-checked (component split) vs realpath(DST)/realpath(SRC).
owned_collision() { # $1=owned resolved path  $2=label
  local p=$1 label=$2
  [ "$p" = "$DST" ] || [ "${p#"$DST"/}" != "$p" ] && \
    die 2 "A14/A15: $label '$p' collides with DST '$DST' boundary"
  [ "$p" = "$SRC" ] || [ "${p#"$SRC"/}" != "$p" ] && \
    die 2 "A14/A15: $label '$p' collides with SRC '$SRC' boundary"
}
owned_collision "$LOG_DIR" "log directory"

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd) || SCRIPT_DIR=""
[ -n "$SCRIPT_DIR" ] && owned_collision "$SCRIPT_DIR" "entrypoint directory"
# stage parent == LOG_DIR (validated above); stage name reserved (A20):
#   mktemp -d "$LOG_DIR/.hc-stage.XXXXXX" is created ONLY after all guards pass.
# env-var-pointed stage/log beyond these owned paths: KNOWN_LIMITATIONS (A14).

# --- helpers ---
type_of() {
  if [ -L "$1" ]; then printf 'l'
  elif [ -d "$1" ]; then printf 'd'
  elif [ -e "$1" ]; then printf 'f'
  else printf 'x'; fi
}

# newline-delimited sorted "type relpath" listing (portable: no find -printf).
# Newline-in-filename safety is out of scope (A21 KNOWN_LIMITATIONS).
tree_list() { # $1=tree root -> stdout
  (cd "$1" 2>/dev/null || exit 9
   find . -mindepth 1 -type d | sed 's|^|d |'
   find . -mindepth 1 -type f | sed 's|^|f |'
   find . -mindepth 1 -type l | sed 's|^|l |') | LC_ALL=C sort
}

# structure + content + symlink-target mismatches between two trees (A9/A13)
list_mismatches() { # $1=src $2=dst -> stdout lines "create|delete|update: path"
  local a=$1 b=$2 line t p
  comm -23 <(tree_list "$a") <(tree_list "$b") | sed 's/^[a-z] /create: /'
  comm -13 <(tree_list "$a") <(tree_list "$b") | sed 's/^[a-z] /delete: /'
  comm -12 <(tree_list "$a") <(tree_list "$b") | while IFS= read -r line; do
    t=${line%% *}; p=${line#* }
    case $t in
      f) cmp -s -- "$a/$p" "$b/$p" || printf 'update: %s\n' "$p" ;;
      l) [ "$(readlink -- "$a/$p")" = "$(readlink -- "$b/$p")" ] || printf 'update: %s\n' "$p" ;;
    esac
  done
  return 0
}

tree_cmp() { [ -z "$(list_mismatches "$1" "$2")" ]; }

# --- dry-run (A6/A16): stdout-only plan; no log write, no mkdir, no mktemp ---
dry_run() {
  list_mismatches "$SRC" "$DST" \
    | sed -e 's/^create:/would-create:/' -e 's/^delete:/would-delete:/' \
          -e 's/^update:/would-update:/'
  echo "dry-run complete: no writes performed (A6/A16)"
  exit 0
}

# --- verify subcommand: recursive SRC vs DST compare, nonzero on mismatch ---
verify_cmd() {
  if [ ! -d "$DST" ]; then
    echo "VERIFY FAIL: DST '$DST' does not exist — not a mirror of SRC (A9)" >&2
    exit 1
  fi
  local bad
  bad=$(list_mismatches "$SRC" "$DST")
  if [ -n "$bad" ]; then
    echo "VERIFY FAIL: DST does not mirror SRC (A9). Mismatched paths:" >&2
    printf '%s\n' "$bad" >&2
    exit 1
  fi
  echo "verify OK: DST mirrors SRC (contents+structure+symlinks)"
  exit 0
}

# --- staging (A13, BOTH paths): copy SRC -> stage, verify stage, print path ---
build_verified_stage() {
  local STAGE
  mkdir -p "$LOG_DIR"
  STAGE=$(mktemp -d "$LOG_DIR/.hc-stage.XXXXXX")   # reserved namespace (A20)
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$SRC/" "$STAGE/"            # contents of SRC, no nesting
  elif command -v tar >/dev/null 2>&1; then
    (cd "$SRC" && tar -cf - .) | (cd "$STAGE" && tar -xf -)
  else
    cp -a "$SRC/." "$STAGE/"
  fi
  if ! tree_cmp "$SRC" "$STAGE"; then
    rm -rf -- "$STAGE"
    echo "ERROR (A13/A9): staging verification failed; DST untouched" >&2
    exit 3
  fi
  printf '%s' "$STAGE"
}

# --- apply verified staging to DST (--delete semantics incl. fallback, A5/A7) ---
apply_stage() {
  local STAGE=$1 rel sp dp
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$STAGE/" "$DST/"
    return 0
  fi
  # fallback: delete stale / type-mismatched DST entries at all depths (A7)
  while IFS= read -r rel; do
    rel=${rel#./}
    [ -z "$rel" ] && continue
    sp="$SRC/$rel"; dp="$DST/$rel"
    if [ -L "$dp" ] || [ -e "$dp" ]; then
      if { [ ! -e "$sp" ] && [ ! -L "$sp" ]; } || [ "$(type_of "$sp")" != "$(type_of "$dp")" ]; then
        rm -rf -- "$dp"
      fi
    fi
  done < <(cd "$DST" && find . -mindepth 1)
  cp -a "$STAGE/." "$DST/"
}

# --- real-run sync ---
sync_real() {
  local STAGE mode=fallback
  command -v rsync >/dev/null 2>&1 && mode=rsync
  STAGE=$(build_verified_stage)          # A13: verified BEFORE DST is touched
  if [ -L "$DST" ]; then rm -f -- "$DST"; fi   # A18: replace symlink w/ real tree
  mkdir -p "$DST"                        # A16: real run only
  apply_stage "$STAGE"
  rm -rf -- "$STAGE"
  if ! tree_cmp "$SRC" "$DST"; then      # A9 post-sync self-check
    echo "ERROR: post-sync verification failed (A9)" >&2
    exit 3
  fi
  printf '%s sync OK src=%s dst=%s mode=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
    "$SRC" "$DST" "$mode" >> "$LOG_DIR/sync.log"   # real runs only (A8)
}

case "$MODE" in
  --dry-run) dry_run ;;
  --verify|verify) verify_cmd ;;
  "") sync_real ;;
  *) echo "usage: $0 [--dry-run|--verify]" >&2; exit 2 ;;
esac

