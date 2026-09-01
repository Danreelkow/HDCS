#!/usr/bin/env bash
# sync-hermes-context.sh — one-way host->workspace context mirror (A2/A9)
# rsync primary; cp/tar fallback converges to identical end state (A5/A7)
# A13: ALL destructive paths (primary and fallback) copy into a staging tree,
#      content-verify the staging against SRC, and only then mutate DST.
# dry-run: zero writes, never creates DST (A6/A16)
# refusals: closed list only (A12, A14/A15, A18) — cite A-numbers, zero writes (A19/A20)
# A8: log/env-override target is refused if it resolves inside DST
set -euo pipefail

# --- env parameterization (A17): gate names first, brief names as fallback ---
SRC_RAW=${HERMES_CONTEXT_SRC:-${SRC_DIR:-/opt/data/workspace/hermes-context/}}
DST_RAW=${HERMES_CONTEXT_DST:-${DST_DIR:-/workspace/hermes-context}}
LOG_RAW=${HERMES_CTX_LOG:-${LOG_DIR:-$HOME/.cache/hermes-context}}

MODE="${1:-}"

# --- canonicalize via realpath (S4 finding: lexical prefixes are spoofable by
#     symlinks; realpath resolves symlinked ancestors) ---
# resolve_path: realpath of the deepest existing ancestor, plus the not-yet-
# existing lexical tail — so guards hold for DST/LOG paths that do not exist yet.
resolve_path() {
  local p=$1 cur tail=""
  if [ -e "$p" ] || [ -L "$p" ]; then
    realpath -- "$p"
    return 0
  fi
  cur=$p
  while [ ! -e "$cur" ]; do
    tail="/$(basename -- "$cur")$tail"
    cur=$(dirname -- "$cur")
    [ "$cur" = "/" ] && break
  done
  printf '%s%s' "$(realpath -- "$cur")" "$tail"
}

strip_trailing() { # lexical cleanup before resolution
  local p=$1
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p=${p%/}; done
  printf '%s' "$p"
}

SRC=$(resolve_path "$(strip_trailing "$SRC_RAW")")
DST=$(resolve_path "$(strip_trailing "$DST_RAW")")
LOG_DIR=$(resolve_path "$(strip_trailing "$LOG_RAW")")

# --- guards: refusal paths write nothing (A19/A20) ---
if [ "$(id -u)" -eq 0 ]; then
  echo "REFUSED (A12): refusing to run as root; use a systemd user unit or standalone exec as a normal user (A3)" >&2
  exit 2
fi
if [ ! -d "$SRC" ]; then
  echo "REFUSED (A14/A15): source '$SRC' does not exist or is not a directory; nothing was written" >&2
  exit 2
fi
# A18: realpath-based — catches DST==SRC, lexical nesting, AND a DST symlink or
# symlinked ancestor that resolves into SRC
if [ "$DST" = "$SRC" ] || [ "${DST#"$SRC"/}" != "$DST" ]; then
  echo "REFUSED (A18): destination '$DST' is equal to or nested inside source '$SRC' (realpath-resolved); nothing was written" >&2
  exit 2
fi
# A8: log directory must never resolve inside (or onto) DST
if [ "$LOG_DIR" = "$DST" ] || [ "${LOG_DIR#"$DST"/}" != "$LOG_DIR" ]; then
  echo "REFUSED (A8): log directory '$LOG_DIR' resolves inside destination '$DST'; nothing was written" >&2
  exit 2
fi

# --- helpers ---
type_of() {
  if [ -L "$1" ]; then printf 'l'
  elif [ -d "$1" ]; then printf 'd'
  elif [ -e "$1" ]; then printf 'f'
  else printf 'x'; fi
}

# NUL-delimited sorted "type relpath" listing of a tree (symlinks as links,
# not followed) — lossless for filenames containing newlines (S4 finding)
tree_list() { # $1=tree root, $2=output file (NUL-delimited)
  (cd "$1" 2>/dev/null && find . -mindepth 1 \
     \( -type d -printf 'd %p\0' -o -type f -printf 'f %p\0' -o -type l -printf 'l %p\0' \) \
     | sort -z > "$2")
}

# recursive compare: structure + contents + symlink targets (A9/A13)
tree_cmp() {
  local a=$1 b=$2 ta tb t p rc=0
  ta=$(mktemp); tb=$(mktemp)
  tree_list "$a" "$ta"
  tree_list "$b" "$tb"
  if ! cmp -s "$ta" "$tb"; then
    rc=1
  else
    while IFS= read -r -d '' line; do
      t=${line%% *}; p=${line#* }
      case "$t" in
        f) if ! cmp -s -- "$a$p" "$b$p"; then rc=1; break; fi ;;
        l) if [ "$(readlink -- "$a$p")" != "$(readlink -- "$b$p")" ]; then rc=1; break; fi ;;
      esac
    done < "$ta"
  fi
  rm -f -- "$ta" "$tb"
  return "$rc"
}

# emit newline-joined mismatched/changed paths (verify + dry-run share logic);
# comparisons are NUL-safe internally
list_mismatches() { # $1=src $2=dst
  local a=$1 b=$2 ta tb t p
  ta=$(mktemp); tb=$(mktemp)
  tree_list "$a" "$ta"; tree_list "$b" "$tb"
  comm -z -23 "$ta" "$tb" | while IFS= read -r -d '' line; do
    [ -n "$line" ] && printf '%s\n' "${line#* }"
  done
  comm -z -13 "$ta" "$tb" | while IFS= read -r -d '' line; do
    [ -n "$line" ] && printf '%s\n' "${line#* }"
  done
  comm -z -12 "$ta" "$tb" | while IFS= read -r -d '' line; do
    [ -n "$line" ] || continue
    t=${line%% *}; p=${line#* }
    case "$t" in
      f) cmp -s -- "$a$p" "$b$p" || printf '%s\n' "$p" ;;
      l) [ "$(readlink -- "$a$p")" = "$(readlink -- "$b$p")" ] || printf '%s\n' "$p" ;;
    esac
  done
  rm -f -- "$ta" "$tb"
}

# --- dry-run (A6/A16): read-only diff report, never creates DST ---
dry_run() {
  local a=$SRC b=$DST ta tb t p
  ta=$(mktemp); tb=$(mktemp)
  tree_list "$a" "$ta"; tree_list "$b" "$tb"
  comm -z -23 "$ta" "$tb" | while IFS= read -r -d '' line; do
    [ -n "$line" ] && printf 'would-create: %s\n' "${line#* }"
  done
  comm -z -13 "$ta" "$tb" | while IFS= read -r -d '' line; do
    [ -n "$line" ] && printf 'would-delete: %s\n' "${line#* }"
  done
  comm -z -12 "$ta" "$tb" | while IFS= read -r -d '' line; do
    [ -n "$line" ] || continue
    t=${line%% *}; p=${line#* }
    case "$t" in
      f) cmp -s -- "$a$p" "$b$p" || printf 'would-update: %s\n' "$p" ;;
      l) [ "$(readlink -- "$a$p")" = "$(readlink -- "$b$p")" ] || printf 'would-update: %s\n' "$p" ;;
    esac
  done
  rm -f -- "$ta" "$tb"
  echo "dry-run complete: no writes performed (A6/A16)"
  exit 0
}

# --- verify subcommand: recursive SRC vs DST comparison, nonzero on mismatch ---
verify_cmd() {
  local bad
  if [ ! -d "$DST" ]; then
    echo "VERIFY FAIL: DST '$DST' does not exist — not a mirror of SRC (A9)" >&2
    exit 1
  fi
  bad=$(list_mismatches "$SRC" "$DST")
  if [ -n "$bad" ]; then
    echo "VERIFY FAIL: DST does not mirror SRC (A9). Mismatched paths:" >&2
    printf '%s\n' "$bad" >&2
    exit 1
  fi
  echo "verify OK: DST mirrors SRC (contents+structure+symlinks)"
  exit 0
}

# --- staging (A13, applies to BOTH primary and fallback paths): copy SRC into
#     a staging tree, content-verify staging against SRC, BEFORE touching DST ---
build_verified_stage() {
  local STAGE
  mkdir -p "$LOG_DIR"
  STAGE=$(mktemp -d "$LOG_DIR/.stage.XXXXXX")
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$SRC/" "$STAGE/"
  elif command -v tar >/dev/null 2>&1; then
    (cd "$SRC" && tar -cf - .) | (cd "$STAGE" && tar -xf -)
  else
    cp -a "$SRC/." "$STAGE/"
  fi
  # A13: content-compare staging against SRC before any DST destruction
  if ! tree_cmp "$SRC" "$STAGE"; then
    rm -rf -- "$STAGE"
    echo "ERROR (A13): staging verification failed; DST untouched" >&2
    exit 3
  fi
  printf '%s' "$STAGE"
}

# --- apply verified staging to DST (reconcile, rsync-style --delete semantics) ---
apply_stage() {
  local STAGE=$1 rel sp dp
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$STAGE/" "$DST/"
    return 0
  fi
  # fallback (A5/A7): delete stale / type-mismatched DST entries first
  while IFS= read -r -d '' rel; do
    [ -z "$rel" ] && continue
    sp="$SRC/$rel"; dp="$DST/$rel"
    if [ -L "$dp" ] || [ -e "$dp" ]; then
      if [ ! -e "$sp" ] || [ "$(type_of "$sp")" != "$(type_of "$dp")" ]; then
        rm -rf -- "$dp"
      fi
    fi
  done < <(cd "$DST" && find . -mindepth 1 -print0 | sed -z 's|^\./||' | sort -z)
  # move staged contents into DST (cp -a over a DST symlink replaces the link,
  # never follows it — S4/run-018 finding)
  cp -a "$STAGE/." "$DST/"
}

# --- real-run sync ---
sync_real() {
  local STAGE mode
  STAGE=$(build_verified_stage)   # A13: verified before DST exists or is mutated
  mkdir -p "$DST"
  mode=fallback
  command -v rsync >/dev/null 2>&1 && mode=rsync
  apply_stage "$STAGE"
  rm -rf -- "$STAGE"
  # post-sync self-check (A9)
  if ! tree_cmp "$SRC" "$DST"; then
    echo "ERROR: post-sync verification failed (A9)" >&2
    exit 3
  fi
  # real-run logging only; LOG_DIR guard above guarantees it is outside DST (A8/A17)
  mkdir -p "$LOG_DIR"
  printf '%s sync OK src=%s dst=%s mode=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$SRC" "$DST" "$mode" \
    >> "$LOG_DIR/sync.log"
}

case "$MODE" in
  --dry-run) dry_run ;;
  --verify|verify) verify_cmd ;;
  "") sync_real ;;
  *) echo "usage: $0 [--dry-run|--verify]" >&2; exit 2 ;;
esac

