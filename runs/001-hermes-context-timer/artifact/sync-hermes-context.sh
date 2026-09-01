#!/usr/bin/env bash
# sync-hermes-context.sh — exact mirror SRC -> DST (A9 class), stage -> verify -> touch (A11).
# One-way host -> workspace (A2). User-level, no root. Standalone-executable.
set -u
set -o pipefail

SRC="/opt/data/workspace/hermes-context/"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG_FILE="${HOME}/.cache/hermes-context/sync.log"

die() { printf 'sync-hermes-context: error: %s\n' "$*" >&2; exit 1; }

DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    *) die "unknown argument: $a (usage: $0 [--dry-run])" ;;
  esac
done

command -v realpath >/dev/null 2>&1 || die "realpath(1) required"
command -v diff >/dev/null 2>&1 || die "diff(1) required"

# ---- 1b. basic guards: SRC exists, readable; no writes yet -------------------
[ -d "$SRC" ] || die "SRC does not exist or is not a directory: $SRC"
[ -r "$SRC" ] || die "SRC is not readable: $SRC"
SRC_R=$(realpath -e "$SRC") || die "cannot resolve SRC: $SRC"
DST_R=$(realpath -m "$DST") || die "cannot resolve DST: $DST"

# ---- 1c. identity / boundary guard (A12) ------------------------------------
# component-split comparison, never a string prefix
under() { # true if $1 is strictly inside $2 (path-component aware)
  local a="${1%/}" b="${2%/}"
  [ "$a" = "$b" ] && return 1
  [ "$b" = "/" ] && return 0
  case "$a/" in "$b"/*) return 0 ;; esac
  return 1
}
related() { under "$1" "$2" || under "$2" "$1"; }

[ "$DST_R" = "/" ] && die "refusing: DST resolves to /"
[ "$SRC_R" = "$DST_R" ] && die "refusing: SRC and DST resolve to the same path (A12)"
related "$SRC_R" "$DST_R" && die "refusing: SRC/DST in ancestor or descendant relation (A12)"
# DST resolving through an intermediate symlink into SRC is covered: realpath -m
# resolved every existing component, so DST_R is inside SRC_R iff reachable.

# ---- A15/A14: owned concrete paths (entrypoint dir, resolved log dir) --------
EP_R=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || EP_R=""
LOGDIR_R=$(realpath -m "${LOG_FILE%/*}") || LOGDIR_R=""
if [ -n "$EP_R" ]; then
  { [ "$DST_R" = "$EP_R" ] || related "$DST_R" "$EP_R"; } && \
    die "refusing: DST conflicts with entrypoint dir $EP_R (A15)"
fi
if [ -n "$LOGDIR_R" ]; then
  # both directions: log dir inside DST (A8) AND DST inside/equal to log dir
  # (post-sync log write would modify the mirrored tree, A14/A15)
  { [ "$DST_R" = "$LOGDIR_R" ] || related "$DST_R" "$LOGDIR_R"; } && \
    die "refusing: log dir $LOGDIR_R conflicts with mirrored tree (A8/A15)"
fi

# ---- 1a. dry-run: plan to stdout, ZERO writes (A6), never creates DST (A16) --
if [ "$DRY" -eq 1 ]; then
  echo "DRY-RUN plan: exact recursive mirror (contents+structure+symlinks, stale deleted) $SRC_R/ -> $DST_R/"
  if command -v rsync >/dev/null 2>&1; then
    if [ -d "$DST_R" ] && [ ! -L "$DST" ]; then
      rsync -a --delete --dry-run --itemize-changes "$SRC_R/" "$DST_R/"
    else
      echo "plan: DST absent -> real run would mkdir -p $DST_R then rsync -a --delete"
      find "$SRC_R" -mindepth 1 | sed "s|^$SRC_R|  would create: |"
    fi
  else
    if [ -d "$DST_R" ] && [ ! -L "$DST" ]; then
      diff -rq --no-dereference "$SRC_R" "$DST_R" 2>&1
      comm -23 <(cd "$DST_R" && find . | sort) <(cd "$SRC_R" && find . | sort) | \
        sed 's|^|  would delete: |'
    else
      echo "plan: DST absent -> real run would mkdir -p $DST_R then tar-pipe/cp -a copy"
      find "$SRC_R" -mindepth 1 | sed "s|^$SRC_R|  would create: |"
    fi
  fi
  exit 0
fi

# ---- 1d. stage dir outside SRC/DST trees -------------------------------------
RSYNC_BIN=""
command -v rsync >/dev/null 2>&1 && RSYNC_BIN=$(command -v rsync)
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/hermes-context-stage.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$STAGE"' EXIT INT TERM
STAGE_R=$(realpath "$STAGE")
related "$STAGE_R" "$DST_R" && die "refusing: stage dir conflicts with DST (A15)"
related "$STAGE_R" "$SRC_R" && die "refusing: stage dir conflicts with SRC (A15)"

# ---- 1e. copy SRC -> stage (A9: contents + structure + symlinks) -------------
if [ -n "$RSYNC_BIN" ]; then
  rsync -a --delete "$SRC_R/" "$STAGE_R/" || die "staging rsync failed"
else
  # fallback: tar-pipe; stage is a fresh empty dir, so semantics equal rsync -a --delete
  tar -C "$SRC_R" -cf - . | tar -C "$STAGE_R" -xf - || die "tar-pipe staging failed"
fi

# ---- 1f. self-verify stage vs SRC (A13: content compare, not emptiness) ------
verify_fail() {
  echo "sync-hermes-context: error: staging verification failed; DST untouched" >&2
  rm -rf "$STAGE"
  trap - EXIT INT TERM
  exit 1
}
diff -r --no-dereference "$SRC_R" "$STAGE_R" >/dev/null 2>&1 || verify_fail
# explicit symlink-target walk (defense in depth)
while IFS= read -r -d '' l; do
  rel="${l#"$STAGE_R/"}"
  [ "$(readlink "$l")" = "$(readlink "$SRC_R/$rel")" ] || verify_fail
done < <(find "$STAGE_R" -type l -print0)
# staging copy is now a verified_copy (A13)

# ---- 1g. touch DST (A16) -----------------------------------------------------
total=$(find "$STAGE_R" \( -type f -o -type l \) | wc -l)
deleted=0
if [ -d "$DST_R" ] && [ ! -L "$DST" ]; then
  deleted=$(comm -23 <(cd "$DST_R" && find . | sort) <(cd "$SRC_R" && find . | sort) | grep -c . || true)
  deleted=${deleted##* }
fi
if [ -n "$RSYNC_BIN" ]; then
  [ -d "$DST" ] || { [ -e "$DST" ] || [ -L "$DST" ]; } && [ ! -d "$DST" ] && rm -f "$DST"
  mkdir -p "$DST" || die "cannot create DST: $DST"
  rsync -a --delete "$STAGE_R/" "$DST/" || die "sync rsync failed"
else
  # fallback: verified stage exists (A11 satisfied), so full reconcile is safe;
  # rm on a symlink argument removes the link, never its target
  rm -rf "$DST"
  mkdir -p "$DST" || die "cannot create DST: $DST"
  cp -a "$STAGE_R/." "$DST/" || die "cp -a sync failed"
fi

# ---- 1h. one-line summary, real runs only (A8: parent outside mirrored tree) -
mkdir -p "${LOG_FILE%/*}" || die "cannot create log dir ${LOG_FILE%/*}"
printf '%s synced=%s deleted=%s src=%s dst=%s\n' "$(date -Is)" "$total" "$deleted" "$SRC_R" "$DST_R" >> "$LOG_FILE" || die "log write failed"
echo "sync-hermes-context: OK synced=$total deleted=$deleted dst=$DST_R"
exit 0

