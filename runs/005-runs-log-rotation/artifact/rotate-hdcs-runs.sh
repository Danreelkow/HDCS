#!/usr/bin/env bash
# rotate-hdcs-runs.sh — hdcs runs rotation.
# Default (no args): DRY-RUN — prints planned moves/prunes, performs ZERO writes (A1).
# --apply: sole writing mode. Toolchain: bash + coreutils only (A2). No root, no logrotate.
# Stale law (A5): stale <=> floor((now - mtime)/86400) >= AGE_DAYS — explicit epoch
# arithmetic, never bare -mtime +N.
# Env overrides: HDCS_RUNS_DIR, HDCS_ARCHIVE_DIR ONLY (unset -> conf defaults;
# set-but-empty -> refuse, A4). AGE_DAYS/PATTERN/KEEP are operator-fixed conf values
# and are never overridden by the environment.
# KEEP=0 prunes the ENTIRE archive (KEEP is a hard bound, never skipped).
# Prune uses only POSIX-portable find/stat (no -printf).
# Scratch discipline (A1/L_modes): the scratch dir is created via mktemp -d at a
# base that is VERIFIED (component test, not string prefix) to be OUTSIDE RUNS_DIR,
# ARCHIVE_DIR, and any owned path — before AND after instantiation. A TMPDIR pointing
# into either protected tree is rejected; /tmp is used instead. Zero writes ever
# land inside RUNS_DIR/ARCHIVE_DIR, in any mode.
# Traversal discipline: every find writes its listing to a scratch file so its
# EXIT STATUS is captured — a failed/truncated traversal is a hard refusal, never
# a silent skip. prune_select's status is NEVER consumed through a pipeline whose
# last command would mask it: its output goes to a file and its exit status is
# tested explicitly.
# FAILURE DISCIPLINE (apply): every step in the --apply writing path (parent mkdir,
# cp, cmp, rm of source, rm of pruned file) is status-checked; ANY failure sets
# APPLY_FAIL and the script exits NONZERO after finishing — --apply never reports
# success while a stale file remained unrotated, a copy was not verified, or a
# prune removal failed.
set -u

APPLY=0
if [ "${1:-}" = "--apply" ]; then
  APPLY=1
elif [ $# -gt 0 ]; then
  echo "usage: rotate-hdcs-runs.sh [--apply]" >&2
  exit 2
fi

die() { echo "REFUSE (A4): $1" >&2; exit 1; }

# --- conf parse (L_conf): strictly 5 KEY=VALUE lines; blank lines and lines
# starting with '#' are ignored; ANY other non-empty, non-comment line is a
# parse failure -> nonzero exit, zero writes. Each of the 5 keys must appear
# EXACTLY once (missing key or duplicate key = parse failure). ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/hdcs-runs-rotation.conf"
CONF_RUNS=""; CONF_ARCH=""; CONF_AGE=""; CONF_PAT=""; CONF_KEEP=""
SEEN_RUNS=0; SEEN_ARCH=0; SEEN_AGE=0; SEEN_PAT=0; SEEN_KEEP=0
CONF_LINES=0
if [ ! -r "$CONF" ]; then
  echo "CONF PARSE FAILURE (L_conf): conf unreadable: $CONF" >&2
  exit 1
fi
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    '') continue;;
    \#*) continue;;
    RUNS_DIR=*)
      CONF_LINES=$((CONF_LINES + 1))
      if [ "$SEEN_RUNS" -ne 0 ]; then
        echo "CONF PARSE FAILURE (L_conf): duplicate key RUNS_DIR" >&2; exit 1
      fi
      SEEN_RUNS=1; CONF_RUNS="${line#RUNS_DIR=}";;
    ARCHIVE_DIR=*)
      CONF_LINES=$((CONF_LINES + 1))
      if [ "$SEEN_ARCH" -ne 0 ]; then
        echo "CONF PARSE FAILURE (L_conf): duplicate key ARCHIVE_DIR" >&2; exit 1
      fi
      SEEN_ARCH=1; CONF_ARCH="${line#ARCHIVE_DIR=}";;
    AGE_DAYS=*)
      CONF_LINES=$((CONF_LINES + 1))
      if [ "$SEEN_AGE" -ne 0 ]; then
        echo "CONF PARSE FAILURE (L_conf): duplicate key AGE_DAYS" >&2; exit 1
      fi
      SEEN_AGE=1; CONF_AGE="${line#AGE_DAYS=}";;
    PATTERN=*)
      CONF_LINES=$((CONF_LINES + 1))
      if [ "$SEEN_PAT" -ne 0 ]; then
        echo "CONF PARSE FAILURE (L_conf): duplicate key PATTERN" >&2; exit 1
      fi
      SEEN_PAT=1; CONF_PAT="${line#PATTERN=}";;
    KEEP=*)
      CONF_LINES=$((CONF_LINES + 1))
      if [ "$SEEN_KEEP" -ne 0 ]; then
        echo "CONF PARSE FAILURE (L_conf): duplicate key KEEP" >&2; exit 1
      fi
      SEEN_KEEP=1; CONF_KEEP="${line#KEEP=}";;
    *)
      echo "CONF PARSE FAILURE (L_conf): malformed non-empty non-comment line: $line" >&2
      exit 1;;
  esac
done < "$CONF"
if [ "$CONF_LINES" -ne 5 ]; then
  echo "CONF PARSE FAILURE (L_conf): expected exactly 5 KEY=VALUE lines, found $CONF_LINES" >&2
  exit 1
fi
for k in RUNS_DIR ARCHIVE_DIR AGE_DAYS PATTERN KEEP; do
  case "$k" in
    RUNS_DIR) [ "$SEEN_RUNS" -eq 1 ] || { echo "CONF PARSE FAILURE (L_conf): missing key $k" >&2; exit 1; };;
    ARCHIVE_DIR) [ "$SEEN_ARCH" -eq 1 ] || { echo "CONF PARSE FAILURE (L_conf): missing key $k" >&2; exit 1; };;
    AGE_DAYS) [ "$SEEN_AGE" -eq 1 ] || { echo "CONF PARSE FAILURE (L_conf): missing key $k" >&2; exit 1; };;
    PATTERN) [ "$SEEN_PAT" -eq 1 ] || { echo "CONF PARSE FAILURE (L_conf): missing key $k" >&2; exit 1; };;
    KEEP) [ "$SEEN_KEEP" -eq 1 ] || { echo "CONF PARSE FAILURE (L_conf): missing key $k" >&2; exit 1; };;
  esac
done

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
# degenerate AFTER canonicalization too: './', 'foo/..', trailing-slash cwd forms
# all canonicalize to the current directory (or '/') and must be refused (A4).
# realpath -m NEVER returns the literal string '.' — it returns the absolute cwd —
# so the post-canonicalization test compares against the canonicalized CURRENT
# DIRECTORY (obtained the same way), not against the literal '.' string.
CWD="$(realpath -m -- '.')" || die "cannot canonicalize current directory"
[ "$RUNS" = "$CWD" ] && die "RUNS_DIR '$RUNS_SRC' canonicalizes to the current directory (degenerate)"
[ "$ARCH" = "$CWD" ] && die "ARCHIVE_DIR '$ARCH_SRC' canonicalizes to the current directory (degenerate)"
[ "$RUNS" = "/" ] && die "RUNS_DIR canonicalizes to '/'"
[ "$ARCH" = "/" ] && die "ARCHIVE_DIR canonicalizes to '/'"
[ "$RUNS" = "$ARCH" ] && die "RUNS_DIR and ARCHIVE_DIR are identical"

# containment (either direction), component-safe via realpath'd canonical paths
case "$RUNS" in "$ARCH"|"$ARCH"/*) die "RUNS_DIR '$RUNS' is inside ARCHIVE_DIR '$ARCH'";; esac
case "$ARCH" in "$RUNS"|"$RUNS"/*) die "ARCHIVE_DIR '$ARCH' is inside RUNS_DIR '$RUNS'";; esac

AGE_DAYS="$CONF_AGE"
PATTERN="$CONF_PAT"
KEEP="$CONF_KEEP"
case "$AGE_DAYS" in ''|*[!0-9]*) die "AGE_DAYS not a non-negative integer";; esac
case "$KEEP" in ''|*[!0-9]*) die "KEEP not a non-negative integer";; esac

# --- component-inside test: $1 inside $2 (path COMPONENTS, never string prefix) ---
comp_inside() {
  local a="${1%/}" b="${2%/}"
  [ "${a#"$b"/}" != "$a" ] || [ "$a" = "$b" ]
}

# --- scratch dir for find listings (A1/L_modes): NEVER inside RUNS_DIR/ARCHIVE_DIR.
# The BASE is checked first, then the INSTANTIATED mktemp result is re-checked
# (a base outside the trees does not guarantee the instantiated path is, and the
# check must hold on the concrete created path). Candidate order: TMPDIR, then /tmp. ---
mk_scratch() {
  local base cand
  for base in "${TMPDIR-}" /tmp; do
    [ -n "$base" ] || continue
    cand="$(realpath -m -- "$base" 2>/dev/null)" || continue
    comp_inside "$cand" "$RUNS" && continue
    comp_inside "$cand" "$ARCH" && continue
    cand="$(mktemp -d "${cand%/}/hdcs-rotate.XXXXXX" 2>/dev/null)" || continue
    # re-validate the INSTANTIATED stage path against both protected trees
    if comp_inside "$cand" "$RUNS" || comp_inside "$cand" "$ARCH"; then
      rm -rf -- "$cand"
      continue
    fi
    printf '%s' "$cand"
    return 0
  done
  return 1
}
SCRATCH=""
if ! SCRATCH="$(mk_scratch)"; then
  die "cannot create scratch dir outside RUNS_DIR/ARCHIVE_DIR"
fi
trap 'rm -rf -- "$SCRATCH"' EXIT

NOW="$(date +%s)"
MOVES=()
# find status is captured: a failed traversal refuses rather than silently
# skipping stale files (a skipped stale file would violate the rotation law).
FIND_ERR="$SCRATCH/find-runs-err"
: > "$FIND_ERR"
if ! find "$RUNS" -type f -name "$PATTERN" -print0 2>"$FIND_ERR" > "$SCRATCH/stale-list"; then
  echo "REFUSE (A4): RUNS_DIR traversal failed" >&2
  cat "$FIND_ERR" >&2
  exit 1
fi
if [ -s "$FIND_ERR" ]; then
  echo "REFUSE (A4): RUNS_DIR traversal reported errors" >&2
  cat "$FIND_ERR" >&2
  exit 1
fi
while IFS= read -r -d '' f; do
  if ! mt="$(stat -c %Y -- "$f" 2>/dev/null)"; then
    echo "REFUSE (A4): cannot stat RUNS file: ${f#"$RUNS"/}" >&2
    exit 1
  fi
  age=$(( (NOW - mt) / 86400 ))
  if [ "$age" -ge "$AGE_DAYS" ]; then
    MOVES+=("$f")
  fi
done < "$SCRATCH/stale-list"

# portable prune-list builder: emits "<mtime> <seq> <path>" lines sorted newest-first,
# trimmed to KEEP entries; paths printed from field 3 on (spaces tolerated).
# KEEP=0 -> every archived file is a prune candidate (the bound always applies).
# find status captured: a failed archive traversal refuses (never silently prunes
# from a partial listing). The function's EXIT STATUS reflects traversal success —
# callers MUST test it directly (never through a pipeline whose last stage would
# mask it).
prune_select() { # $1 = archive dir, $2 = KEEP; prints paths to prune (newline-delimited);
                 # returns nonzero on traversal failure (a refusal was already printed)
  local p mt i=0 keep="$2" lerr="$SCRATCH/prune-find-err"
  local -a payload=()
  : > "$lerr"
  if ! find "$1" -type f -print0 2>"$lerr" > "$SCRATCH/prune-list"; then
    echo "REFUSE (A4): ARCHIVE_DIR traversal failed" >&2
    cat "$lerr" >&2
    return 1
  fi
  if [ -s "$lerr" ]; then
    echo "REFUSE (A4): ARCHIVE_DIR traversal reported errors" >&2
    cat "$lerr" >&2
    return 1
  fi
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    if ! mt="$(stat -c %Y -- "$p" 2>/dev/null)"; then
      echo "REFUSE (A4): cannot stat archive file: $p — pruning from a partial listing would violate losslessness" >&2
      return 1
    fi
    payload+=("$mt $i $p")
    i=$((i+1))
  done < "$SCRATCH/prune-list"
  local n="${#payload[@]}"
  [ "$n" -gt "$keep" ] || return 0
  if [ "$keep" -eq 0 ]; then
    printf '%s\n' "${payload[@]}" | sort -k1,1nr -k2,2n | cut -d' ' -f3-
  else
    printf '%s\n' "${payload[@]}" | sort -k1,1nr -k2,2n | tail -n +"$((keep+1))" | cut -d' ' -f3-
  fi
  return 0
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
  # prune_select status is tested EXPLICITLY — output is captured to a scratch file
  # and iterated from there, so a traversal failure can never be masked by the
  # pipeline's last command (a hidden failure would exit 0 and misreport the plan).
  if [ -d "$ARCH" ]; then
    if ! prune_select "$ARCH" "$KEEP" > "$SCRATCH/prune-out"; then
      echo "REFUSE (A4): dry-run prune plan aborted — ARCHIVE_DIR traversal failed" >&2
      exit 1
    fi
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      echo "prune: ${rel#"$ARCH"/} (oldest beyond KEEP=$KEEP)"
    done < "$SCRATCH/prune-out"
  fi
  exit 0
fi

# ---------------- APPLY: sole writing mode ----------------
# APPLY_FAIL accumulates every failure in the writing path; the run exits NONZERO
# if any step failed — success is only reported when the rotation truly completed.
APPLY_FAIL=0

mkdir -p -- "$ARCH" || { echo "REFUSE (A4): cannot create ARCHIVE_DIR" >&2; exit 1; }

for f in "${MOVES[@]}"; do
  rel="${f#"$RUNS"/}"
  dest="$ARCH/$rel"
  parent="$(dirname -- "$dest")"
  if ! mkdir -p -- "$parent"; then
    echo "FAIL: cannot create archive parent for $rel" >&2
    APPLY_FAIL=1
    continue
  fi
  if [ -e "$dest" ]; then
    i=1
    while [ -e "$dest.$i" ]; do i=$((i+1)); done
    dest="$dest.$i"
  fi
  if ! cp -p -- "$f" "$dest"; then
    echo "FAIL: copy failed for $rel; source kept" >&2
    APPLY_FAIL=1
    continue
  fi
  if ! cmp -s -- "$f" "$dest"; then
    echo "FAIL: lossless check failed for $rel; source kept, archive copy at ${dest#"$ARCH"/}" >&2
    APPLY_FAIL=1
    continue
  fi
  if ! rm -f -- "$f"; then
    echo "FAIL: source removal failed for $rel (archive copy present at ${dest#"$ARCH"/})" >&2
    APPLY_FAIL=1
    continue
  fi
  echo "rotated: $rel -> ${dest#"$ARCH"/}"
done

# prune ARCHIVE_DIR to KEEP newest (ARCHIVE_DIR only — RUNS_DIR is never pruned);
# KEEP=0 prunes everything. prune_select's exit status is tested explicitly on its
# redirected output — a traversal failure aborts the prune (refusing to prune from
# a partial listing is the lossless choice); it can never be masked by a pipeline.
if [ -d "$ARCH" ]; then
  if ! prune_select "$ARCH" "$KEEP" > "$SCRATCH/prune-out"; then
    echo "REFUSE (A4): prune aborted — archive traversal failed" >&2
    exit 1
  fi
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if ! rm -f -- "$rel"; then
      echo "FAIL: prune removal failed: ${rel#"$ARCH"/}" >&2
      APPLY_FAIL=1
      continue
    fi
    echo "pruned: ${rel#"$ARCH"/}"
  done < "$SCRATCH/prune-out"
fi

if [ "$APPLY_FAIL" -ne 0 ]; then
  echo "apply completed WITH FAILURES (see above) — exiting nonzero" >&2
  exit 1
fi

exit 0
