#!/usr/bin/env bash
# verify-rotation.sh — ZERO-WRITE checker (A1/A6).
# exit 0 <=> conf parses (exactly 5 KEY=VALUE lines, verbatim values) AND no stale
# PATTERN file under RUNS_DIR (accumulator pattern; tested AFTER the loop) AND the
# archive is intact: a listing (mtime, cksum, size, path) is recorded in scratch
# BEFORE the recheck pass; a second independent pass re-cksums/re-stats each entry
# against it, and the "newest KEEP present" condition is established by:
#   (a) the archived count must not exceed KEEP, and
#   (b) rotation-suffix families must be mtime-ordered — for every archived
#       base.N, a sibling base.(N-1) (or base) must exist with mtime >= its own,
#       i.e. the un-numbered/newest copy of each family is present.
# Fresh PATTERN files never fail. Only env overrides honored: HDCS_RUNS_DIR /
# HDCS_ARCHIVE_DIR (set-but-empty refused, A4); AGE_DAYS/PATTERN/KEEP come solely
# from the shipped conf.
# Scratch: mktemp -d strictly OUTSIDE the artifact dir / RUNS_DIR / ARCHIVE_DIR
# (component-overlap tested; TMPDIR falling inside any tree is rejected and /tmp is
# used instead). Nothing is written into any tree; stderr goes to the caller's stderr.
# No root, no logrotate.
set -u

FLAGS=0
note_fail() { echo "VERIFY FAIL: $1" >&2; FLAGS=$((FLAGS + 1)); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/hdcs-runs-rotation.conf"

# --- conf parse: KEY=VALUE lines counted, blanks/# comments ignored; accumulator ---
if [ ! -r "$CONF" ]; then
  note_fail "conf unreadable: $CONF"
  nkeys=0
else
  nkeys=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue;;
      [A-Z_]*=*) nkeys=$((nkeys + 1));;
      *) note_fail "conf stray line (not KEY=VALUE): $line";;
    esac
  done < "$CONF"
  if [ "$nkeys" -ne 5 ]; then
    note_fail "conf must contain exactly 5 KEY=VALUE lines (found $nkeys)"
  fi
  if ! grep -q '^RUNS_DIR=/workspace/hdcs/runs$' "$CONF"; then note_fail "conf RUNS_DIR value not verbatim"; fi
  if ! grep -q '^ARCHIVE_DIR=/workspace/.hdcs-rotate/archive$' "$CONF"; then note_fail "conf ARCHIVE_DIR value not verbatim"; fi
  if ! grep -q '^AGE_DAYS=14$' "$CONF"; then note_fail "conf AGE_DAYS value not verbatim"; fi
  if ! grep -q '^PATTERN=\*\.txt$' "$CONF"; then note_fail "conf PATTERN value not verbatim"; fi
  if ! grep -q '^KEEP=50$' "$CONF"; then note_fail "conf KEEP value not verbatim"; fi
fi

CONF_RUNS=""; CONF_ARCH=""; CONF_AGE=""; CONF_PAT=""; CONF_KEEP=""
if [ -r "$CONF" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      RUNS_DIR=*) CONF_RUNS="${line#RUNS_DIR=}";;
      ARCHIVE_DIR=*) CONF_ARCH="${line#ARCHIVE_DIR=}";;
      AGE_DAYS=*) CONF_AGE="${line#AGE_DAYS=}";;
      PATTERN=*) CONF_PAT="${line#PATTERN=}";;
      KEEP=*) CONF_KEEP="${line#KEEP=}";;
    esac
  done < "$CONF"
fi

RUNS_SRC="${HDCS_RUNS_DIR-$CONF_RUNS}"
ARCH_SRC="${HDCS_ARCHIVE_DIR-$CONF_ARCH}"
AGE_DAYS="$CONF_AGE"
PATTERN="$CONF_PAT"
KEEP="$CONF_KEEP"
case "$AGE_DAYS" in ''|*[!0-9]*) note_fail "conf AGE_DAYS not a non-negative integer: '$AGE_DAYS'";; esac
case "$KEEP" in ''|*[!0-9]*) note_fail "conf KEEP not a non-negative integer: '$KEEP'";; esac
[ -z "$RUNS_SRC" ] && note_fail "REFUSE (A4): HDCS_RUNS_DIR is set-but-empty"
[ -z "$ARCH_SRC" ] && note_fail "REFUSE (A4): HDCS_ARCHIVE_DIR is set-but-empty"

# --- path law (A4): degenerate/identity/containment, before and after canonicalization ---
law_ok=1
case "$RUNS_SRC" in ''|.|/) note_fail "REFUSE (A4): degenerate RUNS_DIR '$RUNS_SRC'"; law_ok=0;; esac
case "$ARCH_SRC" in ''|.|/) note_fail "REFUSE (A4): degenerate ARCHIVE_DIR '$ARCH_SRC'"; law_ok=0;; esac
RUNS=""; ARCH=""
if [ "$law_ok" -eq 1 ]; then
  if ! RUNS="$(realpath -m -- "$RUNS_SRC" 2>/dev/null)"; then
    note_fail "REFUSE (A4): RUNS_DIR unresolvable"; law_ok=0
  fi
  if ! ARCH="$(realpath -m -- "$ARCH_SRC" 2>/dev/null)"; then
    note_fail "REFUSE (A4): ARCHIVE_DIR unresolvable"; law_ok=0
  fi
fi
if [ "$law_ok" -eq 1 ]; then
  if [ "$RUNS" = "/" ]; then note_fail "REFUSE (A4): RUNS_DIR canonicalizes to '/'"; law_ok=0; fi
  if [ "$ARCH" = "/" ]; then note_fail "REFUSE (A4): ARCHIVE_DIR canonicalizes to '/'"; law_ok=0; fi
  if [ "$RUNS" = "$ARCH" ]; then note_fail "REFUSE (A4): RUNS_DIR == ARCHIVE_DIR (identity)"; law_ok=0; fi
  case "$RUNS" in "$ARCH"|"$ARCH"/*) note_fail "REFUSE (A4): RUNS_DIR '$RUNS' inside ARCHIVE_DIR '$ARCH'"; law_ok=0;; esac
  case "$ARCH" in "$RUNS"|"$RUNS"/*) note_fail "REFUSE (A4): ARCHIVE_DIR '$ARCH' inside RUNS_DIR '$RUNS'"; law_ok=0;; esac
fi

# component-overlap: is $1 inside $2 (path-component test, never string prefix)?
comp_inside() {
  local a="${1%/}" b="${2%/}"
  [ "${a#"$b"/}" != "$a" ] || [ "$a" = "$b" ]
}

# --- scratch dir strictly outside artifact/RUNS/ARCHIVE trees (A6) ---
mk_scratch() {
  local cand base
  for base in "${TMPDIR-}" /tmp; do
    [ -n "$base" ] || continue
    cand="$(realpath -m -- "$base")" || continue
    comp_inside "$cand" "$SCRIPT_DIR" && continue
    [ -n "$RUNS" ] && comp_inside "$cand" "$RUNS" && continue
    [ -n "$ARCH" ] && comp_inside "$cand" "$ARCH" && continue
    mktemp -d "${cand%/}/hdcs-verify.XXXXXX" 2>/dev/null && return 0
  done
  return 1
}
SCRATCH=""
if ! SCRATCH="$(mk_scratch)"; then
  echo "VERIFY FAIL: cannot create scratch dir outside all protected trees (A6)" >&2
  exit 1
fi
LISTING="$SCRATCH/listing"
FAMLIST="$SCRATCH/families"
cleanup() { rm -rf -- "$SCRATCH"; }
trap cleanup EXIT

stale_scan_rc=0
ARCH_OK=1
if [ "$law_ok" -eq 1 ]; then
  # --- check 2: stale scan — accumulator set INSIDE the loop, tested AFTER ---
  if [ -d "$RUNS" ]; then
    NOW="$(date +%s)"
    STALE_FOUND=0
    while IFS= read -r -d '' f; do
      if ! mt="$(stat -c %Y -- "$f" 2>/dev/null)"; then
        note_fail "cannot stat RUNS file: ${f#"$RUNS"/}"
        stale_scan_rc=1
        continue
      fi
      age=$(( (NOW - mt) / 86400 ))
      if [ "$age" -ge "$AGE_DAYS" ]; then
        STALE_FOUND=1
        note_fail "stale file pending rotation: ${f#"$RUNS"/} (age_days=$age >= $AGE_DAYS)"
      fi
    done < <(find "$RUNS" -type f -name "$PATTERN" -print0 2>/dev/null)
    if [ "$STALE_FOUND" -ne 0 ]; then stale_scan_rc=1; fi
  else
    note_fail "RUNS_DIR '$RUNS' is not a directory"
    stale_scan_rc=1
  fi

  # --- check 3: archive intact — record a listing (mtime, cksum, size, path) FIRST,
  #     then a second pass re-cksums and re-stats each file against the recorded
  #     values; the two passes are distinct reads, so mid-run mutation is detected
  #     (not tautological) ---
  if [ -d "$ARCH" ]; then
    : > "$LISTING"
    : > "$FAMLIST"
    n_arch=0
    while IFS= read -r -d '' f; do
      base="$(basename -- "$f")"
      case "$base" in
        $PATTERN|$PATTERN.[0-9]*) ;;
        *) note_fail "archive orphan (does not match PATTERN '$PATTERN' + rotation suffix): ${f#"$ARCH"/}"; ARCH_OK=0;;
      esac
      if c="$(cksum -- "$f" 2>/dev/null)" && s="$(stat -c %s -- "$f" 2>/dev/null)" && mt="$(stat -c %Y -- "$f" 2>/dev/null)"; then
        crc="${c%% *}"
        printf '%s %s %s %s\n' "$mt" "$crc" "$s" "${f#"$ARCH"/}" >> "$LISTING"
        # family record: "rel_dir <tab> family <tab> seqnum <tab> mtime"
        rel="${f#"$ARCH"/}"
        rdir="$(dirname -- "$rel")"; [ "$rdir" = "." ] && rdir=""
        case "$base" in
          *.1|*.2|*.3|*.4|*.5|*.6|*.7|*.8|*.9|*.10|*.11|*.12|*.13|*.14|*.15|*.16|*.17|*.18|*.19|*.20) ;;
        esac
        num=""
        case "$base" in
          *.[0-9]) num="${base##*.}"; fam="${base%.*}";;
          *.[0-9][0-9]) num="${base##*.}"; fam="${base%.*}";;
        esac
        if [ -n "$num" ]; then
          case "$fam" in
            $PATTERN) ;;
            *) num=""; fam="$base";; # suffix on a non-PATTERN base: treat as plain family
          esac
        else
          num=0; fam="$base"
        fi
        printf '%s\t%s\t%s\t%s\n' "$rdir" "$fam" "$num" "$mt" >> "$FAMLIST"
        n_arch=$((n_arch + 1))
      else
        note_fail "cannot checksum archived file: ${f#"$ARCH"/}"
        ARCH_OK=0
      fi
    done < <(find "$ARCH" -type f -print0 2>/dev/null | sort -z)
    # recheck pass: independent re-derivation compared per-entry against the recorded listing
    while IFS= read -r -d '' f; do
      rel="${f#"$ARCH"/}"
      rec="$(grep -F " $rel" "$LISTING" | grep -F "$rel" | head -1)"
      if [ -z "$rec" ]; then
        note_fail "archive changed between passes (entry vanished/new): $rel"
        ARCH_OK=0
        continue
      fi
      rec_mt="$(printf '%s' "$rec" | awk '{print $1}')"
      rec_crc="$(printf '%s' "$rec" | awk '{print $2}')"
      rec_size="$(printf '%s' "$rec" | awk '{print $3}')"
      c="$(cksum -- "$f" 2>/dev/null)" || { note_fail "cksum recheck failed: $rel"; ARCH_OK=0; continue; }
      crc="${c%% *}"
      s="$(stat -c %s -- "$f" 2>/dev/null)" || s=""
      mt="$(stat -c %Y -- "$f" 2>/dev/null)" || mt=""
      if [ "$crc" != "$rec_crc" ] || [ "$s" != "$rec_size" ] || [ "$mt" != "$rec_mt" ]; then
        note_fail "archive file does not match recorded listing (bytes/size/mtime changed): $rel"
        ARCH_OK=0
      fi
    done < <(find "$ARCH" -type f -print0 2>/dev/null | sort -z)
    # newest-KEEP present: (a) count bound, (b) rotation-suffix families mtime-ordered
    case "$KEEP" in
      ''|*[!0-9]*) : ;; # already flagged above
      *) if [ "$n_arch" -gt "$KEEP" ]; then
           note_fail "archive exceeds KEEP=$KEEP ($n_arch archived files) — prune bound violated"
           ARCH_OK=0
         fi;;
    esac
    # (b): for every base.N, the un-numbered base (or base.(N-1)) must exist with
    # mtime >= base.N's — i.e. each family's newest copy is present, so the newest
    # generation of every archived stream survives the KEEP prune.
    while IFS="$(printf '\t')" read -r rdir fam num mt; do
      [ -n "$rdir" ] || { [ -n "$fam" ] || continue; }
      [ "$num" != "0" ] || continue
      prev=$((num - 1))
      if [ "$prev" -eq 0 ]; then prevname="$fam"; else prevname="$fam.$prev"; fi
      if [ -n "$rdir" ]; then prevrel="$rdir/$prevname"; else prevrel="$prevname"; fi
      prevmt="$(awk -F'\t' -v d="$rdir" -v f="$fam" -v n="$prev" '$1==d && $2==f && $3==n {print $4; exit}' "$FAMLIST")"
      if [ -z "$prevmt" ]; then
        note_fail "archive family incomplete (newest KEEP copy missing): $prevrel (only base.$num present)"
        ARCH_OK=0
      elif [ "$prevmt" -lt "$mt" ]; then
        note_fail "archive family mtime order violated: $prevrel older than its rotation suffix $fam.$num"
        ARCH_OK=0
      fi
    done < "$FAMLIST"
  elif [ -e "$ARCH" ]; then
    note_fail "ARCHIVE_DIR '$ARCH' exists but is not a directory"
    ARCH_OK=0
  fi
  # archive absent + no stale pending => healthy (exit 0), per spec
  if [ ! -e "$ARCH" ] && [ "$stale_scan_rc" -eq 0 ] && [ "$FLAGS" -eq 0 ]; then
    echo "verify: ARCHIVE_DIR absent and no stale pending — OK"
  fi
fi

# --- fresh PATTERN match in RUNS_DIR never fails (informational) ---
if [ "$law_ok" -eq 1 ] && [ -d "$RUNS" ]; then
  NOW="$(date +%s)"
  fresh=0
  while IFS= read -r -d '' f; do
    if mt="$(stat -c %Y -- "$f" 2>/dev/null)"; then
      age=$(( (NOW - mt) / 86400 ))
      if [ "$age" -lt "$AGE_DAYS" ]; then
        fresh=1
      fi
    fi
  done < <(find "$RUNS" -type f -name "$PATTERN" -print0 2>/dev/null)
  if [ "$fresh" -eq 1 ]; then
    echo "verify: fresh PATTERN match present (not a failure)"
  fi
fi

if [ "$FLAGS" -eq 0 ]; then
  echo "verify: OK"
fi
exit "$FLAGS"

