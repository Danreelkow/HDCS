#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror SRC -> DST (user-level)
# Class: contents + structure + symlinks, recursive. No metadata/timestamps/hardlinks.
# Writes only to DST and ~/.cache/hermes-context/. Never writes to SRC.
# Portable: no GNU-only find -printf (BusyBox-safe); uses ls -A (see L1 in README).
set -u

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG_DIR="${HOME}/.cache/hermes-context"
LOG_FILE="${LOG_DIR}/sync.log"

DRYRUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRYRUN=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# --- normalize (ensure trailing slash semantics: contents of SRC -> DST) ---
SRC="${SRC%/}/"
DST="${DST%/}/"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# --- guards (1b) — run before any write, incl. log dir creation ---
[ "$SRC" = "$DST" ] && fail "SRC == DST ('$SRC') — refusing to mirror onto itself"
[ -d "$SRC" ] || fail "SRC does not exist or is not a directory: $SRC"

# A8/L2: reject DST placed under the log dir (adversarial config)
case "$DST" in
  "$LOG_DIR"|"$LOG_DIR"/*) fail "DST under log dir ($LOG_DIR) — adversarial config, aborting" ;;
esac

# --- dry-run paths (A6: zero writes anywhere, incl. log dir) ---
if [ "$DRYRUN" -eq 1 ]; then
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --dry-run "$SRC" "$DST" || fail "rsync dry-run failed"
    echo "dry-run: no changes written"
  else
    diff -r "$SRC" "$DST" >/dev/null 2>&1 \
      && echo "dry-run: DST already mirrors SRC" \
      || echo "dry-run: differences exist; would reconcile (no writes performed)"
  fi
  exit 0
fi

# --- real runs only from here on: log dir may now be created ---
mkdir -p "$LOG_DIR" || fail "cannot create log dir $LOG_DIR"

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE"
}

# --- rsync path (1c) ---
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SRC" "$DST" || fail "rsync failed"
  log "rsync sync $SRC -> $DST"
else
  # --- cp fallback (1d) ---
  STAGE="${LOG_DIR}/stage.$$"
  trap 'rm -rf "$STAGE"' EXIT
  mkdir -p "$STAGE" || fail "cannot create staging dir $STAGE"

  # copy contents of SRC (incl. dotfiles) into staging
  cp -a "$SRC"/. "$STAGE"/ || fail "staging copy failed"

  # source survival check: verified copy exists before touching DST (A11).
  # An empty source is legitimate: mirror of empty SRC is empty DST (A5/A9).
  [ -d "$STAGE" ] || fail "verified copy missing after staging"

  # reconcile DST recursively: delete stale files/subtrees at any depth
  # (only after verified copy exists — A11). Portable listing via ls -A (L1).
  mkdir -p "$DST"
  while IFS= read -r name; do
    [ -e "$STAGE/$name" ] || [ -L "$STAGE/$name" ] || rm -rf -- "${DST}${name}"
  done < <(cd "$DST" && ls -A)

  # copy new/changed items: remove existing DST entry first so cp -a replaces
  # it outright (never nests a directory beneath an existing one — A4/A5)
  while IFS= read -r name; do
    rm -rf -- "${DST}${name}"
    cp -a -- "$STAGE/$name" "$DST/$name" || fail "copy failed for $name"
  done < <(cd "$STAGE" && ls -A)

  rm -rf "$STAGE"
  trap - EXIT
  log "cp-fallback sync $SRC -> $DST"
fi

# --- self-verify (1e): contents + structure + symlinks, recursive ---
# diff -r compares contents and structure recursively, ignoring
# metadata/timestamps/hardlinks. Symlinks are compared separately below.
VERIFY_OUT="$(mktemp "${LOG_DIR}/.verify.XXXXXX")" || fail "cannot create verify temp file"
VERIFY_STATUS=0
if ! diff -r "$SRC" "$DST" > "$VERIFY_OUT" 2>&1; then
  VERIFY_STATUS=1
fi
# symlink class check: same set of symlinks with same targets, at any depth
SYMLINK_OUT="$(mktemp "${LOG_DIR}/.verify.XXXXXX")" || fail "cannot create verify temp file"
( cd "$SRC" && find . -type l ) | sort > "$SYMLINK_OUT"
SRC_LINKS="$SYMLINK_OUT"
SYMLINK_OUT="$(mktemp "${LOG_DIR}/.verify.XXXXXX")" || fail "cannot create verify temp file"
( cd "$DST" && find . -type l ) | sort > "$SYMLINK_OUT"
if ! cmp -s "$SRC_LINKS" "$SYMLINK_OUT"; then
  VERIFY_STATUS=1
  { echo "symlink sets differ (SRC vs DST):"; diff "$SRC_LINKS" "$SYMLINK_OUT"; } >> "$VERIFY_OUT"
fi
rm -f "$SRC_LINKS" "$SYMLINK_OUT"

if [ "$VERIFY_STATUS" -ne 0 ]; then
  echo "FAIL: post-sync verification mismatch (SRC vs DST):" >&2
  cat "$VERIFY_OUT" >&2
  rm -f "$VERIFY_OUT"
  exit 1
fi
rm -f "$VERIFY_OUT"

log "verify OK $SRC -> $DST"
echo "sync OK: $SRC -> $DST"
exit 0

