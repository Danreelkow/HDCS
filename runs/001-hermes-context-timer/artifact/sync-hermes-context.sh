#!/usr/bin/env bash
# sync-hermes-context.sh — mirror SRC contents into DST (A1-A15).
# Standalone-capable; no systemd dependency.
set -euo pipefail

DEFAULT_SRC=/opt/data/workspace/hermes-context/
DEFAULT_DST=/workspace/hermes-context/
LOG_DIR="$HOME/.cache/hermes-context"
LOG_FILE="$LOG_DIR/sync.log"
ENTRYPOINT_DIR="$HOME/.local/bin"

usage() {
  cat <<'EOF'
Usage: sync-hermes-context.sh [--dry-run] [--src=PATH] [--dst=PATH]
Environment: HERMES_CONTEXT_SRC (source, required default /opt/data/workspace/hermes-context/),
             HERMES_CONTEXT_DST (destination, required default /workspace/hermes-context/).
Mirrors contents of SRC into DST (stale entries deleted at every depth).
--dry-run: prints planned actions only; performs ZERO writes (no stage, no log, no DST change).
EOF
}

DRY_RUN=0
SRC="${HERMES_CONTEXT_SRC:-$DEFAULT_SRC}"
DST="${HERMES_CONTEXT_DST:-$DEFAULT_DST}"

for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    --src=*) SRC="${arg#--src=}" ;;
    --dst=*) DST="${arg#--dst=}" ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

log() {
  # caller must ensure not dry-run
  mkdir -p "$LOG_DIR"
  printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG_FILE"
}

die() { echo "FAIL: $*" >&2; exit 1; }

# entry exists including dangling symlinks (A9: symlinks are content, not metadata)
path_exists() { [ -e "$1" ] || [ -L "$1" ]; }

# ---------- A12/A14 guards (before ANY destructive op) ----------
resolve() { realpath -e "$1" 2>/dev/null || realpath -m "$1"; }

SRC_R=$(resolve "$SRC")
DST_R=$(resolve "$DST")
LOG_PARENT_R=$(resolve "$(dirname "$LOG_FILE")")
ENTRYPOINT_R=$(resolve "$ENTRYPOINT_DIR")

# boundary-aware containment: is path $2 inside dir $1 by component split?
contains() { # contains DIR PATH -> 0 if PATH == DIR or under DIR
  local d="$1" p="$2"
  [ "$d" = "$p" ] && return 0
  case "$p/" in "$d"/*) return 0 ;; esac
  return 1
}

[ -e "$SRC_R" ] || die "source $SRC_R does not exist"

# A12: identity / ancestor-descendant / symlink-into-SRC
[ "$SRC_R" = "$DST_R" ] && die "refusing: SRC and DST are the same path (A12)"
if contains "$SRC_R" "$DST_R" || contains "$DST_R" "$SRC_R"; then
  die "refusing: SRC and DST in ancestor/descendant relation (A12)"
fi
if [ -L "$DST" ] && [ -e "$DST" ]; then
  DT=$(realpath "$DST")
  contains "$SRC_R" "$DT" && die "refusing: DST is a symlink into SRC (A12)"
fi

# A14: DST must not boundary-contain any owned concrete path
for owned in "$LOG_PARENT_R" "$ENTRYPOINT_R"; do
  if contains "$DST_R" "$owned"; then
    die "refusing: DST boundary-contains owned path $owned (A14)"
  fi
done

# ---------- A6 dry-run: zero writes, exit before any write path ----------
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN (no writes performed):"
  echo "  would sync contents of: $SRC_R"
  echo "  into:                   $DST_R"
  echo "  would delete stale files/subtrees in DST at every depth"
  echo "  would log to:           $LOG_FILE"
  exit 0
fi

# ---------- A13 staging ----------
# A14: refuse BEFORE creating anything if the staging base (TMPDIR included)
# resolves inside SRC or DST — clean nonzero exit, zero writes.
STAGE_BASE_R=$(resolve "${TMPDIR:-/tmp}")
if contains "$SRC_R" "$STAGE_BASE_R" || contains "$DST_R" "$STAGE_BASE_R"; then
  die "refusing: staging base $STAGE_BASE_R resolves inside SRC or DST (A14)"
fi

STAGE=$(mktemp -d "$STAGE_BASE_R/hermes-sync.XXXXXX")
STAGE_R=$(realpath "$STAGE")
# defensive re-check (race/aliasing); stage is our own concrete path here
if contains "$SRC_R" "$STAGE_R" || contains "$DST_R" "$STAGE_R"; then
  rm -rf "$STAGE"
  die "refusing: stage resolves inside SRC or DST (A14)"
fi
cleanup() { [ -n "${STAGE:-}" ] && [ -d "$STAGE" ] && rm -rf "$STAGE"; }
trap cleanup EXIT

copy_tree() { # copy_tree FROM TO  (sync contents of FROM into TO, delete stale)
  local from="$1" to="$2"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$from"/ "$to"/
  else
    # cp -a + recursive reconcile: delete stale entries at every depth
    reconcile() {
      local src="$1" dst="$2" name s d
      mkdir -p "$dst"
      for s in "$src"/* "$src"/.[!.]* "$src"/..?*; do
        path_exists "$s" || continue
        name="${s##*/}"; d="$dst/$name"
        if [ -d "$s" ] && [ ! -L "$s" ]; then
          if path_exists "$d" && { [ ! -d "$d" ] || [ -L "$d" ]; }; then rm -rf "$d"; fi
          reconcile "$s" "$d"
        else
          if [ -d "$d" ] && [ ! -L "$d" ]; then rm -rf "$d"; fi
          cp -a "$s" "$d"
        fi
      done
      # delete stale entries in dst not present in src (incl. dangling symlinks)
      for d in "$dst"/* "$dst"/.[!.]* "$dst"/..?*; do
        path_exists "$d" || continue
        name="${d##*/}"
        path_exists "$src/$name" || rm -rf "$d"
      done
    }
    reconcile "$from" "$to"
  fi
}

copy_tree "$SRC_R" "$STAGE_R"

# ---------- A9 content-compare: stage vs SRC ----------
# compares contents + recursive structure + symlinks (levels 1-3); ignores metadata
compare_trees() { # compare_trees A B -> 0 if equivalent per A9 class
  local a="$1" b="$2"
  compare_one() {
    local sa="$1" sb="$2" item sub
    # symlink vs non-symlink: compare link text (works for dangling links too)
    if [ -L "$sa" ] || [ -L "$sb" ]; then
      [ -L "$sa" ] && [ -L "$sb" ] || return 1
      [ "$(readlink "$sa")" = "$(readlink "$sb")" ] || return 1
      return 0
    fi
    if [ -d "$sa" ]; then
      [ -d "$sb" ] || return 1
      for item in "$sa"/* "$sa"/.[!.]* "$sa"/..?*; do
        path_exists "$item" || continue
        sub="${item##*/}"
        path_exists "$sb/$sub" || return 1
        compare_one "$item" "$sb/$sub" || return 1
      done
      for item in "$sb"/* "$sb"/.[!.]* "$sb"/..?*; do
        path_exists "$item" || continue
        sub="${item##*/}"
        path_exists "$sa/$sub" || return 1
      done
      return 0
    fi
    [ -f "$sb" ] || return 1
    cmp -s "$sa" "$sb"
  }
  compare_one "$a" "$b"
}

if ! compare_trees "$SRC_R" "$STAGE_R"; then
  log "VERIFY FAIL: staged copy does not match SRC (A9); DST untouched"
  die "staged copy failed A9 verification against SRC; DST untouched"
fi
log "stage verified against SRC (A9)"

# ---------- A11: only now touch DST ----------
copy_tree "$STAGE_R" "$DST_R"

# ---------- self-verify post-sync ----------
if ! compare_trees "$SRC_R" "$DST_R"; then
  log "SELF-VERIFY FAIL: DST does not match SRC after sync (A9)"
  die "post-sync self-verify failed: DST does not match SRC (A9)"
fi
log "sync complete: $SRC_R -> $DST_R (verified)"
exit 0

