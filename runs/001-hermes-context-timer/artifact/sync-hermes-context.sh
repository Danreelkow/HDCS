#!/usr/bin/env bash
# sync-hermes-context.sh — one-way host->workspace mirror of the hermes context.
# Install location: ~/.local/bin/sync-hermes-context.sh (matches hermes-context.service
# ExecStart=%h/.local/bin/sync-hermes-context.sh and the README install section).
# Modes: default = real sync; --dry-run = plan only, zero writes; --verify = A9-class
# compare only (exit 0 iff exact mirror).
set -euo pipefail

MODE=sync
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE=dry ;;
    --verify)  MODE=verify ;;
    *) echo "usage: $0 [--dry-run|--verify]" >&2; exit 2 ;;
  esac
done

# --- A23: unset -> mandated production paths; set-but-empty -> refuse ----------
DEFAULT_SRC="/opt/data/workspace/hermes-context"
DEFAULT_DST="/workspace/hermes-context"
SRC="${HERMES_CONTEXT_SRC-$DEFAULT_SRC}"
DST="${HERMES_CONTEXT_DST-$DEFAULT_DST}"
if [ -z "$SRC" ]; then echo "A23: HERMES_CONTEXT_SRC is set but empty" >&2; exit 1; fi
if [ -z "$DST" ]; then echo "A23: HERMES_CONTEXT_DST is set but empty" >&2; exit 1; fi

# --- A18: degenerate values (raw, before canonicalization) --------------------
case "$SRC" in "/"|"."|"") echo "A18: degenerate HERMES_CONTEXT_SRC='$SRC'" >&2; exit 1 ;; esac
case "$DST" in "/"|"."|"") echo "A18: degenerate HERMES_CONTEXT_DST='$DST'" >&2; exit 1 ;; esac
# canonicalize trailing slashes once; all later mutations use canonical paths
while [ "$SRC" != "/" ] && [ "${SRC%/}" != "$SRC" ]; do SRC="${SRC%/}"; done
while [ "$DST" != "/" ] && [ "${DST%/}" != "$DST" ]; do DST="${DST%/}"; done
case "$SRC" in ""|".") echo "A18: degenerate HERMES_CONTEXT_SRC" >&2; exit 1 ;; esac
case "$DST" in ""|".") echo "A18: degenerate HERMES_CONTEXT_DST" >&2; exit 1 ;; esac

R_SRC=$(realpath -m -- "$SRC")
R_DST=$(realpath -m -- "$DST")
[ "$R_SRC" != "/" ] || { echo "A18: degenerate SRC resolves to /" >&2; exit 1; }
[ "$R_DST" != "/" ] || { echo "A18: degenerate DST resolves to /" >&2; exit 1; }

LOG_PARENT="${HOME}/.cache/hermes-context"
LOG_FILE="$LOG_PARENT/sync.log"
ENTRYPOINT_DIR="${HOME}/.local/bin"

# bidirectional containment on component boundaries (never string prefixes)
contains_bi() { # true if a==b, a inside b, or b inside a
  local a=$1 b=$2
  [ "$a" = "$b" ] || [ "${a#"$b"/}" != "$a" ] || [ "${b#"$a"/}" != "$b" ]
}
is_inside() { # true if child==parent or strictly inside parent
  local child=$1 parent=$2
  [ "$child" = "$parent" ] || [ "${child#"$parent"/}" != "$child" ]
}

# --- A12: identity / ancestor / descendant (realpath-based) -------------------
if [ "$R_SRC" = "$R_DST" ]; then
  echo "A12: SRC and DST resolve to the same path ($R_DST)" >&2; exit 1
fi
if is_inside "$R_DST" "$R_SRC" || is_inside "$R_SRC" "$R_DST"; then
  echo "A12: SRC and DST are in an ancestor/descendant relation" >&2; exit 1
fi

# --- A22: DST itself is a symlink -> refuse, never replace --------------------
if [ -L "$DST" ]; then
  echo "A22: DST is a symlink ($DST -> $(readlink -- "$DST")); refusing to replace it" >&2
  exit 1
fi

# --- A22/A12: symlinked ANCESTOR of DST -> refuse, never follow ---------------
# Walk every real path component of DST (component tests, never string prefixes).
# An ancestor that is a symlink REFUSES: if it resolves into SRC the path law
# is A12 (identity containment via realpath), otherwise A22 — a symlinked DST
# path is never followed or replaced, so no writes can land through the link.
comp="$R_DST"
while [ "$comp" != "/" ]; do
  if [ -L "$comp" ]; then
    RP=$(realpath -- "$comp")
    if [ "$RP" = "$R_SRC" ] || is_inside "$RP" "$R_SRC"; then
      echo "A12: DST component $comp is a symlink resolving into SRC ($RP)" >&2
      exit 1
    fi
    echo "A22: DST component $comp is a symlink (-> $RP); refusing to follow or replace it" >&2
    exit 1
  fi
  comp=$(dirname -- "$comp")
done

# --- A14/A15: DST vs owned concrete paths (log parent, entrypoint dir) --------
for OWNED in "$LOG_PARENT" "$ENTRYPOINT_DIR"; do
  R_OWNED=$(realpath -m -- "$OWNED")
  if contains_bi "$R_DST" "$R_OWNED"; then
    echo "A14: DST ($R_DST) overlaps owned path ($R_OWNED)" >&2; exit 1
  fi
done

# walk_root: when the traversal root is itself a symlink, find(1) with -P does
# not descend through a command-line symlink; "$root/." is the same directory
# resolved, so every traversal below uses walk_root + strip_root and stays
# lossless for a symlinked source (A12 permits source symlinks).
walk_root() { # $1 = root path -> prints a find(1)-traversable form
  if [ -L "$1" ]; then printf '%s/.' "$1"; else printf '%s' "$1"; fi
}
strip_root() { # $1 = root, $2 = find-printed path -> prints path relative to root
  local r=$1 p=$2
  if [ "${p#"$r/./"}" != "$p" ]; then
    printf '%s' "${p#"$r/./"}"
  else
    printf '%s' "${p#"$r"/}"
  fi
}

# lstat-based entry equality: type AND, for symlinks, the exact readlink TARGET.
# LSTAT-based, never -d/-f on the link itself: a DST symlink-to-directory is a
# SYMLINK first ([ -L ] checked before [ -d ]), so same_type returns false for
# (SRC dir, DST symlink-to-dir) and for (SRC symlink, DST real dir) — the
# fallback reconcile then removes and replaces such entries instead of
# following the link and writing outside DST.
same_type() { # $1 src path, $2 dst path — returns 0 iff entries are A9-equal
  local s=$1 d=$2
  if [ -L "$s" ]; then
    [ -L "$d" ] || return 1
    [ "$(readlink -- "$s")" = "$(readlink -- "$d")" ] || return 1
    return 0
  fi
  [ -L "$d" ] && return 1
  if [ -d "$s" ]; then [ -d "$d" ] && return 0 || return 1; fi
  if [ -f "$s" ]; then [ -f "$d" ] && return 0 || return 1; fi
  return 1
}

# A9-class compare: contents + structure + symlinks (NOT metadata/times).
# Never dereferences symlinks: a regular file holding the target bytes of a SRC
# symlink still fails. Empty rsync itemize diff AND full lstat walk must pass.
verify_a9() { # $1 = source, $2 = destination; return 1 on any mismatch
  local s=$1 d=$2 rel sp dp out wr
  if command -v rsync >/dev/null 2>&1; then
    out=$(rsync -rcn --delete --itemize-changes "$s/" "$d/" 2>/dev/null || true)
    if [ -n "$out" ]; then
      echo "A9: rsync content diff detected:" >&2
      printf '%s\n' "$out" >&2
      return 1
    fi
  fi
  wr=$(walk_root "$s")
  while IFS= read -r -d '' p; do
    rel=$(strip_root "$s" "$p")
    dp="$d/$rel"
    if [ -L "$p" ]; then
      [ -L "$dp" ] || { echo "A9: type mismatch (symlink vs other): $rel" >&2; return 1; }
      [ "$(readlink -- "$p")" = "$(readlink -- "$dp")" ] || \
        { echo "A9: symlink target mismatch: $rel" >&2; return 1; }
    elif [ -d "$p" ]; then
      if [ ! -d "$dp" ] || [ -L "$dp" ]; then
        echo "A9: type mismatch (dir vs other): $rel" >&2; return 1
      fi
    elif [ -f "$p" ]; then
      if [ -L "$dp" ] || [ ! -f "$dp" ]; then
        echo "A9: type mismatch (file vs other): $rel" >&2; return 1
      fi
      cmp -s -- "$p" "$dp" || { echo "A9: content mismatch: $rel" >&2; return 1; }
    fi
  done < <(find "$wr" -mindepth 1 -print0)
  while IFS= read -r -d '' p; do
    rel=${p#"$d"/}
    { [ -e "$s/$rel" ] || [ -L "$s/$rel" ]; } || \
      { echo "A9: extra entry in destination: $rel" >&2; return 1; }
  done < <(find "$d" -mindepth 1 -print0)
  return 0
}

# --- dry-run branch: zero writes of any kind, including logs ------------------
if [ "$MODE" = dry ]; then
  if { [ -e "$DST" ] || [ -L "$DST" ]; } && [ -d "$DST" ]; then
    if command -v rsync >/dev/null 2>&1; then
      # --checksum in the plan too: a same-size/same-mtime byte change must be
      # counted as work, matching what the real run will actually do
      out=$(rsync -anc --delete --itemize-changes "$SRC/" "$DST/" 2>/dev/null || true)
      DEL=$(printf '%s\n' "$out" | grep -c '^\*deleting' || true)
      SYNC=$(printf '%s\n' "$out" | grep -Ev '^(\.|\*deleting|$)' | grep -c . || true)
    else
      # read-only find-diff plan: entries whose type or symlink TARGET differs,
      # plus differing file bytes, count as syncs; stale DST entries as deletes
      SYNC=0; DEL=0
      while IFS= read -r -d '' p; do
        rel=$(strip_root "$SRC" "$p")
        dp="$DST/$rel"
        if ! same_type "$p" "$dp"; then SYNC=$((SYNC + 1))
        elif [ -f "$p" ] && [ ! -L "$p" ] && ! cmp -s -- "$p" "$dp"; then
          SYNC=$((SYNC + 1))
        fi
      done < <(find "$(walk_root "$SRC")" -mindepth 1 -print0)
      while IFS= read -r -d '' p; do
        rel=${p#"$DST"/}
        { [ -e "$SRC/$rel" ] || [ -L "$SRC/$rel" ]; } || DEL=$((DEL + 1))
      done < <(find "$DST" -mindepth 1 -print0)
    fi
  else
    # DST absent: whole tree would be created
    SYNC=$(find "$(walk_root "$SRC")" -mindepth 1 \( -type f -o -type d -o -type l \) -print | wc -l)
    DEL=0
  fi
  echo "dry-run: sync=$SYNC delete=$DEL"
  exit 0
fi

# --- verify branch: fail when DST absent; OK only on exact mirror -------------
if [ "$MODE" = verify ]; then
  if [ ! -d "$DST" ] || [ -L "$DST" ]; then
    echo "verify: FAIL — DST does not exist as a real directory ($DST)" >&2; exit 1
  fi
  if verify_a9 "$SRC" "$DST"; then
    echo "verify: OK — DST is an exact A9-class mirror of SRC"
    exit 0
  fi
  echo "verify: FAIL — DST is not an exact mirror of SRC" >&2
  exit 1
fi

# --- real run: A20 staging — validate parent string BEFORE mktemp -------------
PARENT="${TMPDIR-/tmp}"
if [ -z "$PARENT" ]; then
  echo "A14: TMPDIR set but empty; no usable stage parent" >&2; exit 1
fi
R_PARENT=$(realpath -m -- "$PARENT")
# stage parent must not be INSIDE DST/SRC/owned (reverse is normal: DST under
# /tmp is fine — /tmp is NOT inside DST, so this must sync, not refuse)
if is_inside "$R_PARENT" "$R_DST"; then
  echo "A14: stage parent ($R_PARENT) is inside DST ($R_DST)" >&2; exit 1
fi
if is_inside "$R_PARENT" "$R_SRC"; then
  echo "A14: stage parent ($R_PARENT) is inside SRC ($R_SRC)" >&2; exit 1
fi
for OWNED in "$LOG_PARENT" "$ENTRYPOINT_DIR"; do
  R_OWNED=$(realpath -m -- "$OWNED")
  if is_inside "$R_PARENT" "$R_OWNED"; then
    echo "A14: stage parent ($R_PARENT) is inside owned path ($R_OWNED)" >&2; exit 1
  fi
done
STAGE=$(mktemp -d "$R_PARENT/hermes-context-stage.XXXXXX")
# re-validate the INSTANTIATED stage path (A20/A14/A15): BIDIRECTIONAL
# component-overlap — refuse if the stage is inside DST/SRC/owned OR if
# DST/SRC is inside the stage (a stage containing DST would be destroyed by
# stage cleanup, so overlap in either direction refuses)
R_STAGE=$(realpath -- "$STAGE")
if [ -L "$STAGE" ]; then
  echo "A14: instantiated stage path is a symlink ($R_STAGE)" >&2
  rm -rf -- "$STAGE"; exit 1
fi
if contains_bi "$R_STAGE" "$R_DST"; then
  echo "A14: instantiated stage ($R_STAGE) overlaps DST ($R_DST)" >&2
  rm -rf -- "$STAGE"; exit 1
fi
if contains_bi "$R_STAGE" "$R_SRC"; then
  echo "A14: instantiated stage ($R_STAGE) overlaps SRC ($R_SRC)" >&2
  rm -rf -- "$STAGE"; exit 1
fi
for OWNED in "$LOG_PARENT" "$ENTRYPOINT_DIR"; do
  R_OWNED=$(realpath -m -- "$OWNED")
  if contains_bi "$R_STAGE" "$R_OWNED"; then
    echo "A14: instantiated stage ($R_STAGE) overlaps owned path ($R_OWNED)" >&2
    rm -rf -- "$STAGE"; exit 1
  fi
done

cleanup_stage() { rm -rf -- "$STAGE"; }

fallback_copy() { # $1 = source root, $2 = dest root (A9 mirror without rsync)
  local s=$1 d=$2 rel sp dp wr
  # the destination root always exists after a fallback run — even when the
  # source is empty, the mirror is an (empty) directory, never an absent path
  mkdir -p -- "$d"
  # remove dest entries absent from SRC
  while IFS= read -r -d '' p; do
    rel=${p#"$d"/}
    { [ -e "$s/$rel" ] || [ -L "$s/$rel" ]; } || rm -rf -- "$p"
  done < <(find "$d" -mindepth 1 -print0)
  # copy missing/differing entries; same_type is lstat-based and includes the
  # symlink-TARGET comparison, so a DST symlink-to-dir over a SRC dir (or a DST
  # symlink whose target differs from the SRC symlink) is REMOVED and replaced
  # by the exact source entry — never followed, never written through
  wr=$(walk_root "$s")
  while IFS= read -r -d '' p; do
    rel=$(strip_root "$s" "$p"); sp="$s/$rel"; dp="$d/$rel"
    if [ ! -e "$dp" ] && [ ! -L "$dp" ]; then
      mkdir -p -- "$d/$(dirname "$rel")" 2>/dev/null || true
      cp -a -- "$sp" "$dp"
    elif ! same_type "$sp" "$dp"; then
      rm -rf -- "$dp"; cp -a -- "$sp" "$dp"
    elif [ -f "$sp" ] && [ ! -L "$sp" ] && ! cmp -s -- "$sp" "$dp"; then
      cp -a -- "$sp" "$dp"
    fi
  done < <(find "$wr" -mindepth 1 -print0)
}

# remove DST entries whose type or symlink target differs from SRC
# (file<->dir, symlink<->file, dir<->symlink-to-dir, or symlink->differing-target)
# — done only AFTER the stage has been built and verified (A11)
pre_reconcile_types() {
  local rel
  while IFS= read -r -d '' p; do
    rel=$(strip_root "$SRC" "$p")
    if { [ -e "$DST/$rel" ] || [ -L "$DST/$rel" ]; } && ! same_type "$p" "$DST/$rel"; then
      rm -rf -- "$DST/$rel"
    fi
  done < <(find "$(walk_root "$SRC")" -mindepth 1 -print0)
}

if command -v rsync >/dev/null 2>&1; then
  RSYNC=yes
  # --checksum (with -a): a file whose bytes changed while size and mtime stayed
  # identical is still copied — rsync's default quick-check would skip it, the
  # stage would converge, and the final verify would fail instead of repair
  if ! rsync -ac --delete "$SRC/" "$STAGE/" ; then
    fallback_copy "$SRC" "$STAGE"
    RSYNC=no
  fi
else
  RSYNC=no
  rm -rf -- "$STAGE"/* "$STAGE"/.[!.]* "$STAGE"/..?* 2>/dev/null || true
  mkdir -p "$STAGE"
  fallback_copy "$SRC" "$STAGE"
fi

# --- A13: A9-class compare SRC vs stage; DST still untouched ------------------
if ! verify_a9 "$SRC" "$STAGE"; then
  echo "A13: stage verification failed; DST left untouched" >&2
  cleanup_stage; exit 1
fi

# --- touch DST ----------------------------------------------------------------
pre_reconcile_types
if [ "$RSYNC" = yes ]; then
  # --checksum here as well: the same quick-check skip on an existing DST file
  # (changed bytes, same size/mtime) would leave DST un-repaired after the
  # stage was verified, and verify_a9 would then exit nonzero instead of
  # converging. With --checksum the apply itself repairs, keeping A5's
  # converged end state as a normal-operation outcome, not a verify failure.
  if ! rsync -ac --delete "$STAGE/" "$DST/" ; then
    fallback_copy "$STAGE" "$DST"
  fi
else
  fallback_copy "$STAGE" "$DST"
fi

if ! verify_a9 "$SRC" "$DST"; then
  echo "A9: final DST verification failed" >&2
  cleanup_stage; exit 1
fi

# --- one-line log, real runs only (A8: parent outside DST) --------------------
mkdir -p -- "$LOG_PARENT"
printf '%s mode=sync rsync=%s src=%s dst=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RSYNC" "$SRC" "$DST" >> "$LOG_FILE"

cleanup_stage
exit 0

