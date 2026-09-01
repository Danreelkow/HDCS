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
grep -q "HERMES_CONTEXT_SRC" sync-hermes-context.sh || fail "source not parameterized"
grep -q "HERMES_CONTEXT_DST" sync-hermes-context.sh || fail "destination not parameterized"
grep -qi "rsync" sync-hermes-context.sh || fail "not rsync-based"
# end-to-end proof in tmp fixtures: dry-run writes nothing, real run syncs, second run idempotent
SRC=/tmp/hdcs-gate-src; DST=/tmp/hdcs-gate-dst
rm -rf "$SRC" "$DST"; mkdir -p "$SRC"
printf 'freshness probe %s\n' "$(date +%s)" > "$SRC/probe.txt"
DRYOUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh --dry-run 2>&1) || fail "dry-run exited nonzero: $DRYOUT"
[ -e "$DST/probe.txt" ] && fail "dry-run wrote files"
RUNOUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh 2>&1) || fail "real run exited nonzero: $RUNOUT"
cmp -s "$SRC/probe.txt" "$DST/probe.txt" || fail "synced content mismatch"
RUN2OUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh 2>&1) || fail "second run (idempotency) exited nonzero: $RUN2OUT"
echo "GATE PASS"
