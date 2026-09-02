#!/usr/bin/env bash
# verify-rotation.sh — ZERO-WRITE checker (A1/A6).
# exit 0 <=> conf parses (exactly 5 keys, verbatim values, NO malformed lines) AND no
# stale file under RUNS_DIR AND archive listing intact (names preserved + rotation
# suffixes, per PATTERN) AND fresh PATTERN match present (which never fails).
# A7: EVERY check — including the exit status of every grep/find scan — is accumulated
# into FLAGS via note_fail; no bare pipeline status, no suppressed scan status. Pipelines
# are avoided entirely: each stage runs separately with its status captured.
# PATTERN override (HDCS_PATTERN / conf PATTERN) governs both the stale scan and the
# archive orphan check (A2: the effective configuration is used, never a hardcoded glob).
# No mktemp, no writes anywhere: stderr goes to the caller's stderr, never into $DIR.
set -u

FLAGS=0
note_fail() { echo "VERIFY FAIL: $1" >&2; FLAGS=$((FLAGS + 1)); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/hdcs-runs-rotation.conf"

# --- check 1: conf parses — every line must be one of exactly the 5 KEY=verbatim lines;
#     any malformed line (garbage, unknown key, wrong value, duplicate) is a parse failure.
#     Line-by-line validation: no pipelines, every status accumulated (A7). ---
CONF_RUNS=""; CONF_ARCH=""; CONF_AGE=""; CONF_PAT=""; CONF_KEEP=""
if [ ! -r "$CONF" ]; then
  note_fail "conf unreadable: $CONF"
else
  nlines=0
  parse_ok=1
  while IFS= read -r line || [ -n "$line" ]; do
    nlines=$((nlines + 1))
    case "$line" in
      RUNS_DIR=/workspace/hdcs/runs)
        if [ -n "$CONF_RUNS" ]; then note_fail "conf: duplicate key RUNS_DIR"; parse_ok=0; fi
        CONF_RUNS=/workspace/hdcs/runs;;
      ARCHIVE_DIR=/workspace/.hdcs-rotate/archive)
        if [ -n "$CONF_ARCH" ]; then note_fail "conf: duplicate key ARCHIVE_DIR"; parse_ok=0; fi
        CONF_ARCH=/workspace/.hdcs-rotate/archive;;
      AGE_DAYS=14)
        if [ -n "$CONF_AGE" ]; then note_fail "conf: duplicate key AGE_DAYS"; parse_ok=0; fi
        CONF_AGE=14;;
      'PATTERN=*.txt')
        if [ -n "$CONF_PAT" ]; then note_fail "conf: duplicate key PATTERN"; parse_ok=0; fi
        CONF_PAT='*.txt';;
      KEEP=50)
        if [ -n "$CONF_KEEP" ]; then note_fail "conf: duplicate key KEEP"; parse_ok=0; fi
        CONF_KEEP=50;;
      *)
        note_fail "conf does not parse: malformed or non-verbatim line $nlines: '$line'"
        parse_ok=0;;
    esac
  done < "$CONF"
  if [ "$nlines" -ne 5 ]; then
    note_fail "conf must contain exactly 5 KEY=VALUE lines (found $nlines)"
    parse_ok=0
  fi
  if [ -z "$CONF_RUNS" ]; then note_fail "conf missing RUNS_DIR"; parse_ok=0; fi
  if [ -z "$CONF_ARCH" ]; then note_fail "conf missing ARCHIVE_DIR"; parse_ok=0; fi
  if [ -z "$CONF_AGE" ]; then note_fail "conf missing AGE_DAYS"; parse_ok=0; fi
  if [ -z "$CONF_PAT" ]; then note_fail "conf missing PATTERN"; parse_ok=0; fi
  if [ -z "$CONF_KEEP" ]; then note_fail "conf missing KEEP"; parse_ok=0; fi
  [ "$parse_ok" -eq 1 ] || note_fail "conf parse failed"
fi

RUNS_SRC="${HDCS_RUNS_DIR-$CONF_RUNS}"
ARCH_SRC="${HDCS_ARCHIVE_DIR-$CONF_ARCH}"
AGE_DAYS="${HDCS_AGE_DAYS-$CONF_AGE}"
PATTERN="${HDCS_PATTERN-$CONF_PAT}"

# path law on effective dirs (same refusal semantics as rotate) — A4 cited at every refusal site
law_ok=1
case "$RUNS_SRC" in ''|.|/) note_fail "REFUSE (A4): degenerate RUNS_DIR '$RUNS_SRC'"; law_ok=0;; esac
case "$ARCH_SRC" in ''|.|/) note_fail "REFUSE (A4): degenerate ARCHIVE_DIR '$ARCH_SRC'"; law_ok=0;; esac
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

stale_scan_rc=0
if [ "$law_ok" -eq 1 ]; then
  # --- check 2: no stale file under RUNS_DIR (explicit boundary, A6); find status ACCUMULATED (A7) ---
  if [ -d "$RUNS" ]; then
    NOW="$(date +%s)"
    stale_scan_rc=0
    while IFS= read -r -d '' f; do
      mt="$(stat -c %Y -- "$f")"
      if [ $? -ne 0 ]; then
        note_fail "cannot stat RUNS file: ${f#"$RUNS"/}"
        stale_scan_rc=1
        continue
      fi
      age=$(( (NOW - mt) / 86400 ))
      if [ "$age" -ge "$AGE_DAYS" ]; then
        note_fail "stale file pending rotation: ${f#"$RUNS"/} (age_days=$age >= $AGE_DAYS)"
      fi
    done < <(find "$RUNS" -type f -name "$PATTERN" -print0)
    # the scan's own exit status is accumulated, never suppressed (A7)
    if ! find "$RUNS" -type f -name "$PATTERN" -print0 >/dev/null; then
      note_fail "directory scan of RUNS_DIR '$RUNS' failed (find status nonzero)"
      stale_scan_rc=1
    fi
  else
    note_fail "RUNS_DIR '$RUNS' is not a directory"
    stale_scan_rc=1
  fi

  # --- check 3: archive listing intact — names preserved (+.N suffixes), no orphans;
  #     orphan test derived from the EFFECTIVE PATTERN, never hardcoded (A2) ---
  if [ -d "$ARCH" ]; then
    if ! find "$ARCH" -type f -print0 >/dev/null; then
      note_fail "directory scan of ARCHIVE_DIR '$ARCH' failed (find status nonzero)"
    else
      while IFS= read -r -d '' f; do
        base="$(basename -- "$f")"
        case "$base" in
          $PATTERN|$PATTERN.[0-9]*) ;;
          *) note_fail "archive orphan (does not match PATTERN '$PATTERN' + rotation suffix): ${f#"$ARCH"/}";;
        esac
      done < <(find "$ARCH" -type f -print0)
    fi
  elif [ -e "$ARCH" ]; then
    note_fail "ARCHIVE_DIR '$ARCH' exists but is not a directory"
  fi
fi

# --- check 4: fresh PATTERN match in RUNS_DIR never fails (informational, via accumulator) ---
fresh=0
if [ "$law_ok" -eq 1 ] && [ "$stale_scan_rc" -eq 0 ] && [ -d "$RUNS" ]; then
  NOW="$(date +%s)"
  if ! find "$RUNS" -type f -name "$PATTERN" -print0 >/dev/null; then
    note_fail "fresh-file scan of RUNS_DIR '$RUNS' failed (find status nonzero)"
  else
    while IFS= read -r -d '' f; do
      mt="$(stat -c %Y -- "$f")" || { note_fail "cannot stat RUNS file: ${f#"$RUNS"/}"; continue; }
      age=$(( (NOW - mt) / 86400 ))
      if [ "$age" -lt "$AGE_DAYS" ]; then
        fresh=1
      fi
    done < <(find "$RUNS" -type f -name "$PATTERN" -print0)
  fi
fi
if [ "$fresh" -eq 1 ]; then
  echo "verify: fresh PATTERN match present (not a failure)"
fi

if [ "$FLAGS" -eq 0 ]; then
  echo "verify: OK"
fi
exit "$FLAGS"

