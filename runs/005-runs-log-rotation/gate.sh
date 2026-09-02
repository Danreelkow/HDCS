#!/usr/bin/env bash
# gate.sh — 005: rotation triad — dry-run zero-write, apply lossless+idempotent, verify honest. exit 0 = GATE PASS.
set -u; cd "$(dirname "$0")" || exit 1
fail() { echo "GATE FAIL: $1"; exit 1; }
for f in hdcs-runs-rotation.conf rotate-hdcs-runs.sh verify-rotation.sh README.md; do
  [ -f "artifact/$f" ] || fail "$f missing"; done
bash -n artifact/rotate-hdcs-runs.sh || fail "rotate syntax error"
bash -n artifact/verify-rotation.sh || fail "verify syntax error"
for k in RUNS_DIR ARCHIVE_DIR AGE_DAYS PATTERN KEEP; do
  grep -qE "^${k}=" artifact/hdcs-runs-rotation.conf || fail "config missing key $k"; done
R=/tmp/hdcs-rot-runs; A=/tmp/hdcs-rot-archive; rm -rf "$R" "$A"; mkdir -p "$R/001-old" "$R/002-new"
printf 'stale log line\n' > "$R/001-old/gate-out.txt"; printf 'fresh\n' > "$R/002-new/gate-out.txt"
touch -d '30 days ago' "$R/001-old/gate-out.txt"
mkdir -p "$R/003-boundary"; printf 'boundary\n' > "$R/003-boundary/gate-out.txt"; touch -d '14 days ago' "$R/003-boundary/gate-out.txt"
DRY=$(HDCS_RUNS_DIR="$R" HDCS_ARCHIVE_DIR="$A" bash artifact/rotate-hdcs-runs.sh 2>&1) || fail "dry-run nonzero: $DRY"
echo "$DRY" | grep -q "001-old/gate-out.txt" || fail "dry-run did not list the stale file"
echo "$DRY" | grep -q "003-boundary/gate-out.txt" || fail "boundary file (age == AGE_DAYS) not listed (A5: stale = floor(age_days) >= AGE_DAYS)"
[ -e "$A" ] && fail "dry-run created archive dir (A1)"
[ -f "$R/001-old/gate-out.txt" ] || fail "dry-run moved files (A1)"
cp "$R/001-old/gate-out.txt" /tmp/hdcs-rot-orig; cp "$R/003-boundary/gate-out.txt" /tmp/hdcs-rot-orig-bnd
HDCS_RUNS_DIR="$R" HDCS_ARCHIVE_DIR="$A" bash artifact/rotate-hdcs-runs.sh --apply 2>&1 || fail "apply nonzero"
[ -f "$R/001-old/gate-out.txt" ] && fail "stale file not rotated"
[ -f "$R/003-boundary/gate-out.txt" ] && fail "boundary file (age == AGE_DAYS) not rotated (A5: >= law)"
ARC=$(find "$A/001-old" -type f -name 'gate-out.txt*' 2>/dev/null | head -1); [ -n "$ARC" ] || fail "nothing archived (001-old)"
[ -f "$A/001-old/gate-out.txt" ] || [ -f "$A/001-old/gate-out.txt.1" ] || fail "archive flattened relative path (A5_mirror: RUNS_DIR/<rel> must archive to ARCHIVE_DIR/<rel>)"
ls "$A"/gate-out.txt* >/dev/null 2>&1 && fail "archive has flat top-level entries (A5_mirror)"
cmp -s "$ARC" /tmp/hdcs-rot-orig || fail "archived bytes differ (A5 lossless)"
BRC=$(find "$A/003-boundary" -type f -name 'gate-out.txt*' 2>/dev/null | head -1); [ -n "$BRC" ] || fail "nothing archived (003-boundary)"
cmp -s "$BRC" /tmp/hdcs-rot-orig-bnd || fail "boundary archived bytes differ (A5 lossless)"
[ -f "$R/002-new/gate-out.txt" ] || fail "fresh file rotated (AGE_DAYS violated)"
M1=$(find "$A" -type f | sort | cksum)
HDCS_RUNS_DIR="$R" HDCS_ARCHIVE_DIR="$A" bash artifact/rotate-hdcs-runs.sh --apply >/dev/null 2>&1 || fail "2nd apply nonzero"
[ "$M1" = "$(find "$A" -type f | sort | cksum)" ] || fail "second apply changed archive (A5 idempotence)"
G=$(HDCS_RUNS_DIR="$R" HDCS_ARCHIVE_DIR="$R/archive" bash artifact/rotate-hdcs-runs.sh --apply 2>&1)
[ $? -eq 0 ] && fail "archive inside RUNS_DIR accepted (A4)"
[ -e "$R/archive" ] && fail "guard wrote before refusing (A4)"
HDCS_RUNS_DIR="$R" HDCS_ARCHIVE_DIR="$A" bash artifact/verify-rotation.sh >/dev/null 2>&1 || fail "verify failed on rotated tree"
R2=/tmp/hdcs-rot-bad; rm -rf "$R2"; mkdir -p "$R2/x"; printf 'old\n' > "$R2/x/gate-out.txt"; touch -d '30 days ago' "$R2/x/gate-out.txt"
HDCS_RUNS_DIR="$R2" HDCS_ARCHIVE_DIR="$A" bash artifact/verify-rotation.sh >/dev/null 2>&1 && fail "verify missed pending rotation"
echo "GATE PASS"
