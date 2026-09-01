#!/usr/bin/env bash
# sync-hermes-context.sh — one-way exact mirror of SRC into DST.
# A2: writes only to DST. A4: rsync -> fallback. A5/A7/A9: recursive exact
# mirror of {contents, dir structure, symlinks}. A6: --dry-run writes nothing.
# Fallback never copies through a pre-existing DST symlink; verification
# never follows DST symlinks (type-conflict detection, A5/A9).
set -u
set -o pipefail

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
DRYRUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRYRUN=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

LOG_DIR="$HOME/.cache/hermes-context"
LOG_FILE="$LOG_DIR/sync.log"
COPIED=0
DELETED=0
MODE=rsync

log_summary() {
  # A6/A8: log append is a write — only on real runs, path outside DST.
  [ "$DRYRUN" -eq 1 ] && return 0
  mkdir -p "$LOG_DIR"
  printf '%s mode=%s copied=%d deleted=%d exit=%d\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$COPIED" "$2" "$3" >> "$LOG_FILE"
}

die() {
  echo "sync-hermes-context: $*" >&2
  log_summary "$MODE" 0 1
  exit 1
}

[ -d "$SRC" ] || { MODE=n/a; die "source '$SRC' is not a directory"; }

# A8: never delete our own entrypoint; nothing inside DST may be an entrypoint.
ENTRYPOINT="$(readlink -f "$0" 2>/dev/null || true)"
DST_REAL="$(readlink -f "$DST" 2>/dev/null || true)"
if [ -n "$ENTRYPOINT" ] && [ -n "$DST_REAL" ] && [ "${ENTRYPOINT#"$DST_REAL"/}" != "$ENTRYPOINT" ]; then
  die "entrypoint inside DST violates A8"
fi

dst_exists() { [ -e "$1" ] || [ -L "$1" ]; }

MODE=rsync
if command -v rsync >/dev/null 2>&1; then
  # contents-level sync: trailing slashes on both sides, no nesting (A4/Q4)
  if [ "$DRYRUN" -eq 1 ]; then
    if [ -d "$DST" ]; then
      rsync -a --delete --dry-run "$SRC"/ "$DST"/ || die "rsync dry-run failed"
    fi
    # DST absent under dry-run: nothing to compare, zero writes, exit 0 (A6)
  else
    mkdir -p "$DST"
    rsync -a --delete "$SRC"/ "$DST"/ || die "rsync failed"
  fi
else
  # A4 fallback: recursive reconciliation at every depth, symlinks as-is.
  # No bulk `cp -a "$SRC"/. "$DST"/`: a stale DST symlink-to-directory at a
  # source dir path could be copied through (A2/A5 violation). Instead each
  # SRC entry is reconciled individually: conflicting DST entries (wrong
  # type, wrong symlink target, differing content) are removed BEFORE copy.
  MODE=fallback
  if [ "$DRYRUN" -ne 1 ]; then
    mkdir -p "$DST"
    # 1) delete stale DST entries absent from SRC, deepest first
    while IFS= read -r rel; do
      if ! dst_exists "$SRC/$rel"; then
        rm -rf -- "$DST/$rel"
      fi
    done < <(cd "$DST" && find . -mindepth 1 -depth -print)
    # 2) reconcile every SRC entry (parents before children)
    while IFS= read -r rel; do
      if dst_exists "$DST/$rel"; then
        if [ -L "$SRC/$rel" ]; then
          # symlink: must be a symlink with identical target
          if ! { [ -L "$DST/$rel" ] && [ "$(readlink "$SRC/$rel")" = "$(readlink "$DST/$rel")" ]; }; then
            rm -rf -- "$DST/$rel"
          fi
        elif [ -d "$SRC/$rel" ]; then
          # dir: DST must be a real dir (not a symlink — never copy through)
          if [ -L "$DST/$rel" ] || [ ! -d "$DST/$rel" ]; then
            rm -rf -- "$DST/$rel"
          fi
        else
          # regular file: DST must be a real file with identical contents
          if [ -L "$DST/$rel" ] || [ ! -f "$DST/$rel" ] || ! cmp -s -- "$SRC/$rel" "$DST/$rel"; then
            rm -rf -- "$DST/$rel"
          fi
        fi
      fi
      if ! dst_exists "$DST/$rel"; then
        # parent dirs already exist (pre-order walk); cp -a never follows a
        # DST symlink here because the destination path does not exist
        cp -a -- "$SRC/$rel" "$DST/$rel" || die "cp failed: $rel"
      fi
    done < <(cd "$SRC" && find . -mindepth 1 -print)
  fi
fi

if [ "$DRYRUN" -ne 1 ]; then
  # count what a real run produced (post-state vs SRC)
  TMP1="$(mktemp)"; TMP2="$(mktemp)"
  ( cd "$SRC" && find . ) | sort > "$TMP1"
  ( cd "$DST" && find . ) | sort > "$TMP2"
  COPIED=$(comm -23 "$TMP1" "$TMP2" | wc -l)
  DELETED=$(comm -13 "$TMP1" "$TMP2" | wc -l)
  rm -f "$TMP1" "$TMP2"
fi

# self_verify: recursive mirror_class check {contents, dir structure, symlinks}.
# Read-only; never follows DST symlinks — a source file/dir behind a DST
# symlink is always a mismatch. Mismatch -> exit != 0 (never warn+0).
# Skipped under dry-run (A6: exit 0, nothing written).
VERIFY_STATUS=0
verify() {
  local rel
  if [ ! -d "$DST" ]; then
    return 1
  fi
  while IFS= read -r rel; do
    if [ -L "$SRC/$rel" ]; then
      if [ ! -L "$DST/$rel" ] || [ "$(readlink "$SRC/$rel")" != "$(readlink "$DST/$rel")" ]; then
        echo "symlink mismatch: $rel" >&2; VERIFY_STATUS=1
      fi
    elif [ -d "$SRC/$rel" ]; then
      if [ -L "$DST/$rel" ] || [ ! -d "$DST/$rel" ]; then
        echo "dir mismatch: $rel" >&2; VERIFY_STATUS=1
      fi
    else
      if [ -L "$DST/$rel" ] || [ ! -f "$DST/$rel" ] || ! cmp -s -- "$SRC/$rel" "$DST/$rel"; then
        echo "content mismatch: $rel" >&2; VERIFY_STATUS=1
      fi
    fi
  done < <(cd "$SRC" && find . -mindepth 1)
  while IFS= read -r rel; do
    if ! dst_exists "$SRC/$rel"; then
      echo "stale in DST: $rel" >&2; VERIFY_STATUS=1
    fi
  done < <(cd "$DST" && find . -mindepth 1)
  return "$VERIFY_STATUS"
}

if [ "$DRYRUN" -eq 1 ]; then
  # A6: dry run writes nothing; read-only report of would-be divergence.
  if [ -d "$DST" ]; then
    DIVERGENCE="$( ( cd "$SRC" && find . -mindepth 1 ); ( cd "$DST" && find . -mindepth 1 ) | sed 's#^#DST-ONLY #' )"
    : # informational only; no writes, exit 0
  fi
  exit 0
fi

if ! verify; then
  die "mirror_class verification failed"
fi

log_summary "$MODE" 0 0
exit 0

