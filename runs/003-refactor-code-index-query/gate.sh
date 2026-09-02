#!/usr/bin/env bash
# gate.sh — 003: scope, syntax, baseline integrity, behavior-identical CLI. exit 0 = GATE PASS.
set -u
cd "$(dirname "$0")" || exit 1
fail() { echo "GATE FAIL: $1"; exit 1; }
[ -f artifact/query-code-index.mjs ] || fail "artifact/query-code-index.mjs missing"
[ "$(ls artifact | wc -l)" -eq 1 ] || fail "scope: artifact must be exactly one file (A1)"
node --check artifact/query-code-index.mjs || fail "ESM syntax error"
grep -nE "^import .* from '[^'.]" artifact/query-code-index.mjs | grep -v "from 'node:" && fail "non-builtin import (A5)"
[ -f source/query-code-index.mjs ] || fail "source/ baseline missing"
[ "$(md5sum source/query-code-index.mjs | cut -d' ' -f1)" = "$(md5sum /workspace/kb/tools/query-code-index.mjs | cut -d' ' -f1)" ] || fail "baseline drifted from live tool (A1)"
# tmp layout replica: import.meta.url resolves inside the fixture; zero workspace mutation (A9)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/code-index" "$T/tools"
cp /workspace/kb/code-index/index.json "$T/code-index/index.json"
cp artifact/query-code-index.mjs "$T/tools/"
cp source/query-code-index.mjs "$T/tools/query-code-index-baseline.mjs"
node "$T/tools/query-code-index.mjs" >/dev/null 2>&1; [ $? -eq 2 ] || fail "no-args exit changed (A2: usage=2)"
node "$T/tools/query-code-index-baseline.mjs" >/dev/null 2>&1; [ $? -eq 2 ] || fail "baseline replica broken (gate bug)"
node "$T/tools/query-code-index.mjs" zzqqxx-nosuch >/dev/null 2>&1; [ $? -eq 1 ] || fail "miss exit changed (A2: 1)"
H1=$(node "$T/tools/query-code-index.mjs" service --limit 3 2>/dev/null); [ $? -eq 0 ] || fail "hit exit changed (A2: 0)"
echo "$H1" | grep -qE '\S+:\d+' || fail "stdout row format changed (A6: file:line column)"
H0=$(node "$T/tools/query-code-index-baseline.mjs" service --limit 3 2>/dev/null)
diff <(echo "$H1") <(echo "$H0") >/dev/null || fail "stdout diverges from baseline for the same query (A6): $(diff <(echo "$H1") <(echo "$H0") | head -4 | tr '\n' ' | ')"
L0=$(wc -l < "$T/code-index/usage.log" 2>/dev/null || echo 0)
node "$T/tools/query-code-index.mjs" gateprobe >/dev/null 2>&1 || true
L1=$(wc -l < "$T/code-index/usage.log" 2>/dev/null || echo 0)
[ "$L1" -gt "$L0" ] || fail "telemetry append missing (A4)"
echo "GATE PASS"
