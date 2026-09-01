#!/usr/bin/env bash
# sync-hermes-context.sh — one-way mirror host -> workspace (user-scoped, standalone-capable)
# rsync path (RS) or tar-pipe + reconcile fallback (FB); --dry-run writes nothing anywhere.
set -euo pipefail

# Defaults (canonical paths, overridable via environment)
SRC=${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}
DST=${HERMES_CONTEXT_DST:-/workspace/hermes-context/}
DEFAULT_LOG=${XDG_STATE_HOME:-$HOME/.local/state}/sync-hermes-context.log
LOG=${HERMES_CONTEXT_LOG:-$DEFAULT_LOG}

SRC=${SRC%/}
DST=${DST%/}

# Invariant [A2]: never write to SRC. If LOG resolves inside SRC, fall back to
# the default log location (outside SRC and DST).
case "$LOG" in
  "$SRC"|"$SRC"/*) LOG=$DEFAULT_LOG ;;
esac

# Log path relative to DST if it lives inside DST (must be excluded from mirror)
log_rel() {
  case "$LOG" in
    "$DST"|"$DST"/*) printf '%s' "${LOG#"$DST"/}" ;;
    *) return 1 ;;
  esac
}

# Lists of relative file paths (newline-delimited)
src_files() { (cd "$SRC" && find . -type f | sed 's#^\./##'); }
dst_files() { (cd "$DST" && find . -type f | sed 's#^\./##'); }

dry_run() {
  local adds=() updates=() deletes=() f
  while IFS= read -r f; do
    if [ ! -e "$DST/$f" ]; then
      adds+=("$f")
    elif ! cmp -s "$SRC/$f" "$DST/$f"; then
      updates+=("$f")
    fi
  done < <(src_files)

  local skip=""
  skip=$(log_rel) || skip=""

  while IFS= read -r f; do
    [ -n "$skip" ] && [ "$f" = "$skip" ] && continue
    if [ ! -e "$SRC/$f" ]; then
      deletes+=("$f")
    fi
  done < <(dst_files)

  echo "DRY-RUN mirror plan: SRC=$SRC -> DST=$DST"
  echo "mode: $(command -v rsync >/dev/null 2>&1 && echo RS || echo FB)"
  echo "adds: ${#adds[@]}"
  for f in "${adds[@]}"; do echo "  + $f"; done
  echo "updates: ${#updates[@]}"
  for f in "${updates[@]}"; do echo "  ~ $f"; done
  echo "deletes: ${#deletes[@]}"
  for f in "${deletes[@]}"; do echo "  - $f"; done
  echo "(dry-run performed zero writes; log untouched)"
}

# Pre-pass: remove DST paths whose type differs from SRC (file vs directory),
# so the tar extract and reconcile can always converge to SRC's shape.
fb_fix_type_mismatches() {
  local skip="" p rel
  skip=$(log_rel) || skip=""
  while IFS= read -r p; do
    rel=${p#"$DST"/}
    [ -n "$skip" ] && [ "$rel" = "$skip" ] && continue
    if [ -e "$SRC/$rel" ]; then
      if { [ -d "$DST/$rel" ] && [ ! -d "$SRC/$rel" ]; } ||
         { [ ! -d "$DST/$rel" ] && [ -d "$SRC/$rel" ]; }; then
        rm -rf "$p"
      fi
    fi
  done < <(find "$DST" -mindepth 1 -depth)
}

# Bottom-up: remove every DST path absent in SRC (files, then emptied dirs)
fb_reconcile() {
  local skip="" p rel
  skip=$(log_rel) || skip=""
  while IFS= read -r p; do
    rel=${p#"$DST"/}
    [ -n "$skip" ] && [ "$rel" = "$skip" ] && continue
    if [ ! -e "$SRC/$rel" ]; then
      rm -rf "$p"
      DELETED=$((DELETED + 1))
    fi
  done < <(find "$DST" -mindepth 1 -depth)
}

do_real() {
  mkdir -p "$DST"
  COPIED=0
  DELETED=0
  if command -v rsync >/dev/null 2>&1; then
    MODE=RS
    local out
    local -a args=(rsync -a --delete)
    local skip
    skip=$(log_rel) || skip=""
    [ -n "$skip" ] && args+=(--exclude="$skip")
    out=$("${args[@]}" --out-format='%i|%n' "$SRC/" "$DST/")
    COPIED=$(printf '%s\n' "$out" | grep -c '^>f' || true)
    DELETED=$(printf '%s\n' "$out" | grep -c '^\*deleting' || true)
  else
    MODE=FB
    fb_fix_type_mismatches
    (cd "$SRC" && tar -cf - .) | tar -xf - -C "$DST"
    fb_reconcile
    COPIED=$(find "$SRC" -type f | wc -l)
  fi
}

case "${1:-}" in
  --dry-run)
    dry_run
    exit 0
    ;;
  "")
    MODE=unknown
    COPIED=0
    DELETED=0
    rc=0
    do_real || rc=$?
    status=OK
    [ "$rc" -eq 0 ] || status=FAIL
    line=$(printf '%s mode=%s copied=%s deleted=%s status=%s' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$MODE" "$COPIED" "$DELETED" "$status")
    mkdir -p "$(dirname "$LOG")"
    if log_rel >/dev/null 2>&1; then
      # LOG lives inside DST: keep only the current run's line so no stale log
      # content remains in DST (exact-mirror invariant [A5]).
      printf '%s\n' "$line" > "$LOG"
    else
      printf '%s\n' "$line" >> "$LOG"
    fi
    exit "$rc"
    ;;
  *)
    echo "usage: $0 [--dry-run]" >&2
    exit 2
    ;;
esac

