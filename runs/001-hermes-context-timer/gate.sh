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
  echo "$CAL" | grep -qE '^(\*-\*-\* )?[0-9]{1,2}/[0-9]+:[0-9]{2}:[0-9]{2}$' || fail "OnCalendar not a valid repeating cadence: $CAL (valid: '*-*-* 00/6:00:00' — preferred, self-documenting — or shorthand '00/6:00:00')"
fi
# end-to-end proof in tmp fixtures: dry-run writes nothing, real run syncs, second run idempotent
SRC=/tmp/hdcs-gate-src; DST=/tmp/hdcs-gate-dst
rm -rf "$SRC" "$DST"; mkdir -p "$SRC"
printf 'freshness probe %s\n' "$(date +%s)" > "$SRC/probe.txt"
DRYOUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh --dry-run 2>&1) || fail "dry-run exited nonzero: $DRYOUT"
[ -e "$DST/probe.txt" ] && fail "dry-run wrote files"
[ -e "$DST" ] && fail "dry-run created DST (A16: only real runs may create it)"
RUNOUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh 2>&1) || fail "real run exited nonzero: $RUNOUT"
cmp -s "$SRC/probe.txt" "$DST/probe.txt" || fail "synced content mismatch"
RUN2OUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh 2>&1) || fail "second run (idempotency) exited nonzero: $RUN2OUT"
# type-change convergence fixture (run 015 S4 finding): file<->dir swaps must reconcile to A5/A7 end state
rm -rf "$SRC" "$DST"; mkdir -p "$SRC/sub"; printf 'file-x\n' > "$SRC/x"; printf 'dir-y\n' > "$SRC/sub/y"
mkdir -p "$DST/x"; printf 'old\n' > "$DST/x/inner"; printf 'stale\n' > "$DST/z"
TCOUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh 2>&1) || fail "type-change run exited nonzero: $TCOUT"
[ -f "$DST/x" ] || fail "type-change: DST/x dir->file not reconciled"
cmp -s "$SRC/x" "$DST/x" || fail "type-change: DST/x content mismatch"
[ -f "$DST/sub/y" ] || fail "type-change: sub/y missing"
[ ! -e "$DST/z" ] || fail "type-change: stale DST/z survived"
rm -rf "$SRC" "$DST"; mkdir -p "$SRC/x"; printf 'inner\n' > "$SRC/x/y"; mkdir -p "$DST"; printf 'was-file\n' > "$DST/x"
TC2OUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh 2>&1) || fail "type-change inverse exited nonzero: $TC2OUT"
[ -d "$DST/x" ] && cmp -s "$SRC/x/y" "$DST/x/y" || fail "type-change inverse: DST file x not converted to dir with matching content"
# symlink-swap fixture (run 018 S4 finding): DST symlink must be REPLACED, never followed
rm -rf "$SRC" "$DST" /tmp/hdcs-gate-outside; mkdir -p "$SRC"; printf 'real\n' > "$SRC/x"
mkdir -p "$DST"; printf 'outside-victim\n' > /tmp/hdcs-gate-outside; ln -s /tmp/hdcs-gate-outside "$DST/x"
SSOUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh 2>&1) || fail "symlink-swap run exited nonzero: $SSOUT"
[ -f "$DST/x" ] && [ ! -L "$DST/x" ] || fail "symlink-swap: DST/x still a symlink (must be replaced by the real file)"
cmp -s "$SRC/x" "$DST/x" || fail "symlink-swap: DST/x content mismatch"
grep -q outside-victim /tmp/hdcs-gate-outside || fail "symlink-swap: cp FOLLOWED the symlink and clobbered a file outside DST"
# trailing-slash fixture (run 026 S4 finding): raw $DST mutations must go through canonical paths —
# slashed env values must converge on initial sync (mv "$STAGE" "$DST/" fails when DST does not exist)
rm -rf "$SRC" "$DST"; mkdir -p "$SRC/sub"; printf 't\n' > "$SRC/sub/f"
TSOUT=$(HERMES_CONTEXT_SRC="$SRC/" HERMES_CONTEXT_DST="$DST/" bash sync-hermes-context.sh 2>&1) || fail "trailing-slash run exited nonzero: $TSOUT"
cmp -s "$SRC/sub/f" "$DST/sub/f" || fail "trailing-slash DST: initial sync did not converge (canonicalize DST/SRC once, mutate only through canonical forms)"
# A12/realpath fixture (run 028 S4 findings): symlinked ANCESTOR of DST resolving into SRC must be refused (realpath guards, not lexical prefixes); --verify must FAIL when DST is absent
rm -rf "$SRC" "$DST" "$(dirname "$DST")/shadow"; mkdir -p "$SRC/sub"; printf 'v\n' > "$SRC/sub/f"; mkdir -p "$(dirname "$DST")/shadow"; ln -s "$SRC" "$(dirname "$DST")/shadow/inner"
SAOUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$(dirname "$DST")/shadow/inner/dst" bash sync-hermes-context.sh 2>&1)
[ $? -eq 0 ] && fail "symlinked DST ancestor resolving into SRC was accepted (A12: realpath-based guards required, lexical prefixes are bypassable)"
[ -e "$SRC/sub/f" ] && cmp -s "$SRC/sub/f" <(printf 'v\n') || fail "symlink-ancestor run wrote into SRC"
rm -rf "$SRC"; mkdir -p "$SRC"; printf 'e\n' > "$SRC/f"; rm -rf "$DST"
VEOUT=$(HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" bash sync-hermes-context.sh --verify 2>&1)
[ $? -eq 0 ] && fail "--verify reported OK with DST absent (verify must fail when destination does not exist)"
# docs consistency (run 015 S4 finding): service ExecStart location must be what README documents
ESP=$(sed -n 's/^ExecStart=//p' hermes-context.service | head -1); ESP=${ESP#%h}
[ -n "$ESP" ] || fail "no ExecStart in service unit"
grep -qF "$ESP" README.md || fail "README does not document the service ExecStart location: $ESP (docs must match the unit)"
# A8 fixture (promoted from runs 007-014: env-override log guard kept slipping past repairs)
for LOGVAR in HERMES_CTX_LOG LOG_DIR; do
  if grep -q "$LOGVAR" sync-hermes-context.sh; then
    LOGFAIL=$(env HERMES_CONTEXT_SRC="$SRC" HERMES_CONTEXT_DST="$DST" "$LOGVAR=$DST/evil.log" bash sync-hermes-context.sh 2>&1)
    [ $? -eq 0 ] && fail "$LOGVAR override pointing inside DST was accepted (A14 scope: the log dir is an owned path)"
    [ -f "$DST/evil.log" ] && fail "log written inside DST despite A8 ($LOGVAR)"
  fi
done
echo "GATE PASS"
