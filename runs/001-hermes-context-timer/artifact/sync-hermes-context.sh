#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror SRC -> DST (contents, dir structure, symlinks).
# Standalone (no systemd required to run); designed for a user timer.
# Usage: sync-hermes-context.sh [--dry-run] [--src S] [--dst D]
# Env:   HERMES_CONTEXT_SRC / HERMES_CONTEXT_DST (optional default overrides)
set -u

usage() {
  cat >&2 <<EOF
usage: $0 [--dry-run] [--src S] [--dst D]
  --dry-run   plan only; performs no writes — zero, incl. logs and stage
  --src S     override source (default: \$HERMES_CONTEXT_SRC, then /opt/data/workspace/hermes-context/)
  --dst D     override destination (default: \$HERMES_CONTEXT_DST, then /workspace/hermes-context/)
EOF
}

MODE=apply
SRCOPT=""; DSTOPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE=dry-run ;;
    --src) [ $# -ge 2 ] || { usage; exit 2; }; SRCOPT=$2; shift ;;
    --dst) [ $# -ge 2 ] || { usage; exit 2; }; DSTOPT=$2; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
  shift
done

# A14: HERMES_CTX_LOG is not a supported knob; refuse outright (never honor overrides).
if [ -n "${HERMES_CTX_LOG:-}" ]; then
  echo "refusing: HERMES_CTX_LOG is not a supported knob (log location is fixed, A8/A14)" >&2
  exit 3
fi

SRC=$(realpath -m "${SRCOPT:-${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}}")
DST=$(realpath -m "${DSTOPT:-${HERMES_CONTEXT_DST:-/workspace/hermes-context/}}")
LOG="${HOME}/.cache/hermes-context-sync.log"
ENTRY="${HOME}/.local/bin/sync-hermes-context"
SELF=$(realpath -m "$0")
# A14 note: only the script-OWNED staging parent is a guarded path — the raw
# TMPDIR base itself is not script-owned (e.g. --dst /tmp is legitimate; only
# the staging prefix beneath it belongs to us).
STAGEPARENT=$(realpath -m "${TMPDIR:-/tmp}")/hermes-context-sync-stage

# under PREFIX X: X == PREFIX or X beneath PREFIX
under() { case "$2" in "$1"|"$1"/*) return 0 ;; *) return 1 ;; esac; }

refuse() { echo "refusing: $1" >&2; exit 3; }

# ---- guards: clean nonzero, zero writes, before any filesystem action ----
# A11: identical paths
[ "$SRC" = "$DST" ] && refuse "SRC == DST (A11): $SRC"
# A12: ancestor/descendant/symlink-into either direction (realpath-normalized)
under "$SRC" "$DST" && refuse "DST is ancestor/descendant of or symlink-into SRC (A12): $SRC -> $DST"
under "$DST" "$SRC" && refuse "SRC is ancestor/descendant of or symlink-into DST (A12): $DST -> $SRC"
# A14: DST must not contain or sit inside any script-owned path
for P in "$LOG" "$ENTRY" "$SELF" "$STAGEPARENT"; do
  under "$DST" "$P" && refuse "owned path inside DST (A14): $P"
  under "$P" "$DST" && refuse "DST inside owned path (A14): $DST"
done

# source must exist and be a directory
[ -d "$SRC" ] || { echo "error: source is not a directory: $SRC" >&2; exit 1; }

verify_class() { # A9: contents + dir structure + symlinks only
  diff -r --no-dereference "$1" "$2" >/dev/null 2>&1
}

BACKEND=rsync
if [ "${HCTX_BACKEND:-}" = "tar" ] || ! command -v rsync >/dev/null 2>&1; then
  BACKEND=tar
fi

# ---- dry-run: zero writes anywhere (no stage, no tmp, no log) ----
if [ "$MODE" = "dry-run" ]; then
  echo "dry-run plan ($BACKEND backend): mirror contents of $SRC/ -> $DST/ recursively, stale entries deleted"
  if [ "$BACKEND" = "rsync" ]; then
    rsync -rlnc --delete --itemize-changes "$SRC/" "$DST/" 2>&1
    rc=$?
  else
    if [ -d "$DST" ]; then
      diff -r --no-dereference "$SRC" "$DST"
      rc=$?
    else
      echo "DST absent; would create it and populate with:"
      find "$SRC" -mindepth 1 | sed "s|^$SRC|DST|"
      rc=0
    fi
  fi
  echo "dry-run complete: no writes performed (A6)"
  exit "$rc"
fi

# ---- real run: stage -> verify -> apply -> re-verify (A13) ----
COPIED=0
DELETED=0

run_sync() {
  # stage
  STAGE=$(mktemp -d "${STAGEPARENT}.XXXXXXXXXX") || return 1
  # populate stage (never touches SRC)
  if [ "$BACKEND" = "rsync" ]; then
    rsync -rl --delete "$SRC/" "$STAGE/" || { rm -rf "$STAGE"; return 1; }
  else
    tar -C "$SRC" -cf - . | tar -C "$STAGE" -xf - || { rm -rf "$STAGE"; return 1; }
  fi
  # verify stage vs source (A9 class) before any destruction
  if ! verify_class "$SRC" "$STAGE"; then
    echo "FAIL: stage verification mismatch vs source (A9)" >&2
    diff -r --no-dereference "$SRC" "$STAGE" >&2 || true
    rm -rf "$STAGE"
    return 1
  fi
  # verified copy exists in stage; only now may DST be touched (A11/A13)
  if [ "$BACKEND" = "rsync" ]; then
    OUT=$(rsync -rli --delete --itemize-changes "$STAGE/" "$DST/" 2>&1) || { echo "$OUT" >&2; rm -rf "$STAGE"; return 1; }
    COPIED=$(printf '%s\n' "$OUT" | grep -c '^>f' || true)
    DELETED=$(printf '%s\n' "$OUT" | grep -c '^\*deleting' || true)
  else
    # count deletions relative to stage before clearing
    DELETED=$(comm -23 \
      <(cd "$DST" 2>/dev/null && find . -mindepth 1 | sort) \
      <(cd "$STAGE" && find . -mindepth 1 | sort) | wc -l)
    COPIED=$(cd "$STAGE" && find . -mindepth 1 | wc -l)
    [ -d "$DST" ] || mkdir -p "$DST" || { rm -rf "$STAGE"; return 1; }
    find "$DST" -mindepth 1 -delete || { rm -rf "$STAGE"; return 1; }
    tar -C "$STAGE" -cf - . | tar -C "$DST" -xf - || { rm -rf "$STAGE"; return 1; }
  fi
  # re-verify DST vs source; mismatch -> nonzero, never warn-and-0
  if ! verify_class "$SRC" "$DST"; then
    echo "FAIL: post-apply verification mismatch DST vs source (A9)" >&2
    diff -r --no-dereference "$SRC" "$DST" >&2 || true
    rm -rf "$STAGE"
    return 1
  fi
  rm -rf "$STAGE"
  return 0
}

if run_sync; then
  STATUS=OK
else
  STATUS=FAIL
fi

# exactly one log line per non-dry-run
mkdir -p "$(dirname "$LOG")"
printf '%s|%s|%s|%s|%s|%s\n' "$(date +%s)" "$MODE" "$BACKEND" "$COPIED" "$DELETED" "$STATUS" >> "$LOG"

[ "$STATUS" = OK ] || exit 1
echo "sync OK: backend=$BACKEND copied=$COPIED deleted=$DELETED"
exit 0

