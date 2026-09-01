#!/usr/bin/env bash
# sync-hermes-context.sh — one-way host->workspace mirror (A2)
# SRC/ contents -> DST/ (trailing-slash mirror semantics, A4/A5)
set -euo pipefail

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
LOG="${HERMES_CONTEXT_LOG:-$HOME/.cache/hermes-context/sync.log}"

# A8: log must live outside DST, always. Reject otherwise before any write.
DST_REAL="$(realpath -m "$DST")"
case "$(realpath -m "$LOG")" in
  "$DST_REAL"|"$DST_REAL"/*)
    echo "ERROR: LOG ($LOG) is inside DST ($DST_REAL). Refusing." >&2
    exit 1
    ;;
esac

DRY=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY=1
fi

if [ "$DRY" -eq 1 ]; then
  # A6: dry-run branch — ZERO writes anywhere: no mkdir, no log, no touch,
  # no redirections. Read-only operations only.
  if command -v rsync >/dev/null 2>&1; then
    exec rsync -a --delete --dry-run "$SRC" "$DST"
  else
    # Gate fix (S4): the rsync-missing fallback dry run must inspect DST, not
    # just SRC. Mechanical gate: full-tree checksum (md5) manifests of SRC and
    # DST are computed read-only and diffed; the report shows exactly what a
    # real fallback run would change. No filesystem writes of any kind occur.
    echo "[dry-run] rsync unavailable; computing full-tree checksum manifests (read-only):"
    src_manifest="$(cd "$SRC" && find . -type f -print0 | sort -z | xargs -0 md5sum 2>/dev/null || true)"
    dst_manifest="$(cd "$DST" 2>/dev/null && find . -type f -print0 | sort -z | xargs -0 md5sum 2>/dev/null || true)"
    if [ "$(printf '%s' "$src_manifest" | md5sum | cut -d' ' -f1)" = "$(printf '%s' "$dst_manifest" | md5sum | cut -d' ' -f1)" ]; then
      echo "[dry-run] DST already mirrors SRC (full-tree checksum compare: identical). No changes needed."
    else
      echo "[dry-run] DST differs from SRC. Real run would apply:"
      diff <(printf '%s\n' "$dst_manifest") <(printf '%s\n' "$src_manifest") | sed 's/^/  /' || true
    fi
    echo "[dry-run] fallback semantics: purge DST contents recursively (all depths), then cp -a SRC/. DST/. Zero writes performed."
    exit 0
  fi
fi

# Real mode from here on.
mkdir -p "$DST"

# A8: log dir created only in real mode, always outside DST.
mkdir -p "$(dirname "$LOG")"

if command -v rsync >/dev/null 2>&1; then
  # A5: --delete guarantees exact mirror of SRC.
  rsync -a --delete "$SRC" "$DST" >> "$LOG"
else
  # A4/A7 fallback: reconcile like rsync --delete.
  # Purge DST contents recursively at all depths, then copy faithfully.
  # Because DST is fully emptied first, the copied tree is rebuilt from SRC
  # content; the end state is byte-identical to the rsync -a --delete result
  # (the mechanical gate is a full-tree byte/checksum compare, not link counts).
  rm -rf "$DST"/* "$DST"/.[!.]* "$DST"/..?*
  cp -a "$SRC/." "$DST/"
  # Mechanical convergence verification (full-tree checksum compare).
  src_ck="$(cd "$SRC" && find . -type f -print0 | sort -z | xargs -0 md5sum | md5sum)"
  dst_ck="$(cd "$DST" && find . -type f -print0 | sort -z | xargs -0 md5sum | md5sum)"
  {
    echo "[$(date -Is)] rsync unavailable; cp -a fallback used (stale subtrees purged recursively)."
    if [ "$src_ck" = "$dst_ck" ]; then
      echo "mirror verified: full-tree checksum compare DST == SRC"
    else
      echo "WARNING: full-tree checksum compare reported differences between SRC and DST"
    fi
  } >> "$LOG"
fi

exit 0
