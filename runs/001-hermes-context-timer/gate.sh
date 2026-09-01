#!/usr/bin/env bash
# gate.sh — mechanical acceptance for run 001. exit 0 = GATE PASS.
set -u
cd "$(dirname "$0")/artifact" || { echo "GATE FAIL: no artifact dir"; exit 1; }
fail() { echo "GATE FAIL: $1"; exit 1; }
[ -f sync-hermes-context.sh ] || fail "sync-hermes-context.sh missing"
bash -n sync-hermes-context.sh || fail "sync script syntax error"
[ -f hermes-context.service ] || fail "service unit missing"
[ -f hermes-context.timer ] || fail "timer unit missing"
[ -f README.md ] || fail "README missing"
grep -qi "dry-run" sync-hermes-context.sh || fail "no --dry-run mode"
grep -q "HERMES_CONTEXT_SRC" sync-hermes-context.sh || fail "source not parameterized (contract: read env HERMES_CONTEXT_SRC, required — namespaced, never bare SRC/DST)"
grep -q "HERMES_CONTEXT_DST" sync-hermes-context.sh || fail "destination not parameterized (contract: read env HERMES_CONTEXT_DST, required)"
grep -qi "rsync" sync-hermes-context.sh || fail "not rsync-based"
# timer validity (promoted from run 014 S4 finding: deliverable IS the timer — an unloadable unit must die here, not at S4)
CAL=$(sed -n 's/^OnCalendar=//p' hermes-context.timer | head -1)
[ -n "$CAL" ] || fail "no OnCalendar in timer"
if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze calendar "$CAL" >/dev/null 2>&1 || fail "invalid OnCalendar expression: $CAL (run-014 example of INVALID: '0 */6:00:00'; valid: '*-*-* 00/6:00:00')"
else
  echo "$CAL" | grep -qE '^\*-\*-\* [0-9*/]+:[0-9]{2}:[0-9]{2}$' || fail "OnCalendar not a valid repeating cadence: $CAL (valid: '*-*-* 00/6:00:00')"
fi
# end-to-end proof in tmp fixtures: dry-run writes nothing, real run syncs, second run idempotent
SRC=/tmp/hdcs-gate-src; DST=/tmp/hdcs-gate-dst
rm -rf "$SRC" "$DST"; mkdir -p "$SRC"
printf 'freshness probe %s\n' "$(date +%s)" > "$SRC/probe.txt"
DRYOUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh --dry-run 2>&1) || fail "dry-run exited nonzero: $DRYOUT"
[ -e "$DST/probe.txt" ] && fail "dry-run wrote files"
RUNOUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh 2>&1) || fail "real run exited nonzero: $RUNOUT"
cmp -s "$SRC/probe.txt" "$DST/probe.txt" || fail "synced content mismatch"
RUN2OUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh 2>&1) || fail "second run (idempotency) exited nonzero: $RUN2OUT"
# A8 fixture (promoted from runs 007-014: env-override log guard kept slipping past repairs)
if grep -q "HERMES_CTX_LOG" sync-hermes-context.sh; then
  LOGFAIL=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" HERMES_CTX_LOG="$DST/evil.log" bash sync-hermes-context.sh 2>&1)
  [ $? -eq 0 ] && fail "log-override pointing inside DST was accepted (A8: refuse, nonzero exit)"
  [ -f "$DST/evil.log" ] && fail "log written inside DST despite A8"
fi
echo "GATE PASS"
