#!/usr/bin/env bash
# rotate-hdcs-runs.sh — hdcs runs rotation.
# Default (no args): DRY-RUN — prints planned moves/prunes, performs ZERO writes (A1).
# --apply: sole writing mode. Toolchain: bash + coreutils only (A2). No root, no logrotate.
# Stale law (A5/A6): stale <=> floor((now - mtime)/86400) >= AGE_DAYS — explicit epoch
# arithmetic, never bare -mtime +N.
# Env overrides: HDCS_RUNS_DIR, HDCS_ARCHIVE_DIR (unset -> conf defaults; set-but-empty -> refuse, A4).
# PATTERN/AGE_DAYS/KEEP overrides honored everywhere: HDCS_PATTERN, HDCS_AGE_DAYS, HDCS_KEEP.
# KEEP=0 prunes the ENTIRE archive (A5: KEEP is a hard bound, never skipped).
# Prune uses only POSIX-portable find/stat (no -printf).
set -u

APPLY=0
if [ "${1:-}" = "--apply" ]; then
  APPLY=1
elif [ $# -gt 0 ]; then
  echo "usage: rotate-hdcs-runs.sh [--apply]" >&2
  exit 2
fi

die() { echo "REFUSE (A4): $1" >&2; exit 1; }

# --- conf defaults (operator-fixed, exactly 5 keys, no comments) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/hdcs-runs-rotation.conf"
CONF_RUNS=""; CONF_ARCH=""; CONF_AGE=""; CONF_PAT=""; CONF_KEEP=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    RUNS_DIR=*) CONF_RUNS="${line#RUNS_DIR=}";;
    ARCHIVE_DIR=*) CONF_ARCH="${line#ARCHIVE_DIR=}";;
    AGE_DAYS=*) CONF_AGE="${line#AGE_DAYS=}";;
    PATTERN=*) CONF_PAT="${line#PATTERN=}";;
    KEEP=*) CONF_KEEP="${line#KEEP=}";;
  esac
done < "$CONF"

# --- resolve effective dirs: env override allowed; unset -> default; set-but-empty -> refuse (A4) ---
RUNS_SRC="${HDCS_RUNS_DIR-$CONF_RUNS}"
ARCH_SRC="${HDCS_ARCHIVE_DIR-$CONF_ARCH}"
[ -z "$RUNS_SRC" ] && die "HDCS_RUNS_DIR is set-but-empty"
[ -z "$ARCH_SRC" ] && die "HDCS_ARCHIVE_DIR is set-but-empty"

# --- path law (A4): degenerate '', '.', '/' — checked on the original string AND after canonicalization ---
case "$RUNS_SRC" in ''|.|/) die "degenerate RUNS_DIR '$RUNS_SRC'";; esac
case "$ARCH_SRC" in ''|.|/) die "degenerate ARCHIVE_DIR '$ARCH_SRC'";; esac

RUNS="$(realpath -m -- "$RUNS_SRC")" || die "RUNS_DIR not resolvable"
ARCH="$(realpath -m -- "$ARCH_SRC")" || die "ARCHIVE_DIR not resolvable"
[ "$RUNS" = "/" ] && die "RUNS_DIR canonicalizes to '/'"
[ "$ARCH" = "/" ] && die "ARCHIVE_DIR canonicalizes to '/'"
[ "$RUNS" = "$ARCH" ] && die "RUNS_DIR and ARCHIVE_DIR are identical"

# containment (either direction), component-safe via realpath'd canonical paths
case "$RUNS" in "$ARCH"|"$ARCH"/*) die "RUNS_DIR '$RUNS' is inside ARCHIVE_DIR '$ARCH'";; esac
case "$ARCH" in "$RUNS"|"$RUNS"/*) die "ARCHIVE_DIR '$ARCH' is inside RUNS_DIR '$RUNS'";; esac

AGE_DAYS="${HDCS_AGE_DAYS-$CONF_AGE}"
PATTERN="${HDCS_PATTERN-$CONF_PAT}"
KEEP="${HDCS_KEEP-$CONF_KEEP}"
case "$AGE_DAYS" in ''|*[!0-9]*) die "AGE_DAYS not a non-negative integer";; esac
case "$KEEP" in ''|*[!0-9]*) die "KEEP not a non-negative integer";; esac

NOW="$(date +%s)"
MOVES=()
while IFS= read -r -d '' f; do
  mt="$(stat -c %Y -- "$f")"
  age=$(( (NOW - mt) / 86400 ))
  if [ "$age" -ge "$AGE_DAYS" ]; then
    MOVES+=("$f")
  fi
done < <(find "$RUNS" -type f -name "$PATTERN" -print0 2>/dev/null | sort -z)

# portable prune-list builder: emits "<mtime> <seq> <path>" lines sorted newest-first,
# trimmed to KEEP entries; paths printed from field 3 on (spaces tolerated).
# KEEP=0 -> every archived file is a prune candidate (A5: the bound always applies).
prune_select() { # $1 = archive dir, $2 = KEEP; prints paths to prune (newline-delimited)
  local p mt i=0 keep="$2"
  local -a payload=()
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    mt="$(stat -c %Y -- "$p" 2>/dev/null)" || { echo "WARN: cannot stat archive file: $p" >&2; i=$((i+1)); continue; }
    payload+=("$mt $i $p")
    i=$((i+1))
  done < <(find "$1" -type f | sort)
  local n="${#payload[@]}"
  [ "$n" -gt "$keep" ] || return 0
  if [ "$keep" -eq 0 ]; then
    printf '%s\n' "${payload[@]}" | sort -k1,1nr -k2,2n | cut -d' ' -f3-
  else
    printf '%s\n' "${payload[@]}" | sort -k1,1nr -k2,2n | tail -n +"$((keep+1))" | cut -d' ' -f3-
  fi
}

if [ "$APPLY" -eq 0 ]; then
  # ---------------- DRY-RUN: zero writes (A1) ----------------
  if [ "${#MOVES[@]}" -eq 0 ]; then
    echo "dry-run: no stale files (stale <=> floor(age_days) >= $AGE_DAYS)"
  else
    for f in "${MOVES[@]}"; do
      rel="${f#"$RUNS"/}"
      echo "move: $rel -> ARCHIVE_DIR/$rel"
    done
  fi
  if [ -d "$ARCH" ]; then
    prune_select "$ARCH" "$KEEP" | while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      echo "prune: ${rel#"$ARCH"/} (oldest beyond KEEP=$KEEP)"
    done
  fi
  exit 0
fi

# ---------------- APPLY: sole writing mode ----------------
mkdir -p -- "$ARCH" || { echo "REFUSE (A4): cannot create ARCHIVE_DIR" >&2; exit 1; }

for f in "${MOVES[@]}"; do
  rel="${f#"$RUNS"/}"
  dest="$ARCH/$rel"
  parent="$(dirname -- "$dest")"
  mkdir -p -- "$parent" || { echo "WARN: cannot stage $rel, skipped" >&2; continue; }
  if [ -e "$dest" ]; then
    i=1
    while [ -e "$dest.$i" ]; do i=$((i+1)); done
    dest="$dest.$i"
  fi
  if cp -p -- "$f" "$dest" && cmp -s -- "$f" "$dest"; then
    rm -f -- "$f" && echo "rotated: $rel -> ${dest#"$ARCH"/}"
  else
    echo "WARN: lossless check failed for $rel; source kept, archive copy at ${dest#"$ARCH"/}" >&2
  fi
done

# prune ARCHIVE_DIR to KEEP newest (ARCHIVE_DIR only — RUNS_DIR is never pruned);
# KEEP=0 prunes everything (A5)
if [ -d "$ARCH" ]; then
  prune_select "$ARCH" "$KEEP" | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    rm -f -- "$rel" && echo "pruned: ${rel#"$ARCH"/}"
  done
fi

exit 0

