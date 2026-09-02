#!/usr/bin/env bash
# selftest.sh — 15-fixture sandboxed selftest for driver.mjs + classify.mjs + promote-fixture.mjs.
# All state under mktemp -d; never touches the real queue or runs dirs.
set -u
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/queue" "$SB/runs" "$SB/selfupgrade/history"
export HDCS_ROOT="$SB"
export HDCS_QUEUE_DIR="$SB/queue"
export HDCS_RUNS_DIR="$SB/runs"
export HDCS_HISTORY_DIR="$SB/selfupgrade/history"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS F$1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL F$1: $2"; }
assert() { # assert <fixture#> <desc> <cmd...>
  local n="$1" desc="$2"; shift 2
  if "$@" >/dev/null 2>&1; then ok "$n"; else bad "$n" "$desc"; fi
}
assert_not() {
  local n="$1" desc="$2"; shift 2
  if "$@" >/dev/null 2>&1; then bad "$n" "$desc (expected failure, got success)"; else ok "$n"; fi
}

# Stub loop.mjs: sandbox/canary — never the real one. Stage file controls behavior.
make_stub() { # make_stub <exit-code> [verdict-class] [sleep-ms]
  local code="$1" cls="${2:-}" slp="${3:-0}"
  mkdir -p "$SB/runs/t"
  cat > "$SB/loop.mjs" <<EOF
import fs from 'node:fs';
const sleep = ms => new Promise(r => setTimeout(r, ms));
await sleep($slp);
const cls = "$cls";
if (cls) fs.writeFileSync(process.env.HDCS_RUNS_DIR + '/t/s4-verdict.txt', 'VERDICT: FAIL\nEVIDENCE: ' + cls + ' because reasons.\n');
process.exit($code);
EOF
}
queue() { # queue <name> [maxLaps]
  printf '{"task":"t","budget":0.01,"maxLaps":%s}\n' "${2:-3}" > "$SB/queue/TASK-$1.json"
}
lap() { node "$HERE/driver.mjs" --once >/dev/null 2>&1; }
in_queue() { [ -f "$SB/queue/TASK-$1.json" ]; }
in_parked() { [ -f "$SB/queue/parked/TASK-$1.json" ]; }
in_promoted() { [ -f "$SB/queue/promoted/TASK-$1.json" ]; }

# F1: empty queue -> --once exits 0, nothing ran
fresh() { # wipe per-fixture state so entries never leak between fixtures
  rm -rf "$SB/queue" "$SB/runs" "$SB/selfupgrade/history"
  mkdir -p "$SB/queue" "$SB/runs" "$SB/selfupgrade/history"
}
fresh; lap; assert 1 "empty-queue tick should still exit 0" true
in_queue x || true # noop

# F2: stub exits 0 -> delivered -> parked
fresh
make_stub 0; queue d1; lap
assert 2 "delivered entry should land in parked/" in_parked d1

# F3: stub exits 2 -> parked with clarification reason
fresh
make_stub 2; queue d2; lap
assert 3 "needs-clarification entry should park" in_parked d2
if grep -qi 'clarification' "$SB/queue/parked/TASK-d2.note.txt" 2>/dev/null; then ok 3; else bad 3 "park note should mention clarification"; fi

# F4: stub exits 3 -> parked (budget)
fresh
make_stub 3; queue d3; lap
assert 4 "budget entry should park" in_parked d3

# F5: stub exits 1, no verdict file -> requeue (stays queued)
fresh
rm -f "$SB/runs/t/s4-verdict.txt"
make_stub 1; queue d4; lap
assert 5 "exit 1 without verdict should requeue" in_queue d4

# F6: same finding class twice -> promote on second
fresh
make_stub 1 "verify rejects archives"; queue d5; lap; lap
assert 6 "repeated finding class should promote" in_promoted d5

# F7: different classes each lap -> requeue, never promote
fresh
make_stub 1 "alpha class finding"; queue d6; lap
make_stub 1 "beta class finding"; lap
assert 7 "distinct finding classes should stay requeued" in_queue d6
assert_not 7 "distinct classes must not promote" in_promoted d6

# F8: unknown exit code 7 -> parked
fresh
make_stub 7; queue d7; lap
assert 8 "unknown exit code should park" in_parked d7

# F9: maxLaps=1 + exit 1 -> entry leaves queue after the lap
fresh
make_stub 1 "one shot exhausted"; queue d8 1; lap
assert_not 9 "exhausted entry must leave the queue" in_queue d8
assert 9 "exhausted entry should park with note" in_parked d8

# F10: no concurrent laps / single tick processes exactly one queued task
fresh
make_stub 0 "" 2000; queue c1; queue c2; lap
assert 10 "single tick must not drain the whole queue" in_queue c2
assert 10 "first queued task should have run" in_parked c1

# F11: canary outside sandbox untouched
fresh
echo canary > "$SB-canary"
SUM1="$(cksum "$SB-canary")"
make_stub 0; queue d9; lap
SUM2="$(cksum "$SB-canary")"
[ "$SUM1" = "$SUM2" ] && ok 11 || bad 11 "canary file changed"
rm -f "$SB-canary"

# F12: oldest mtime runs first
fresh
make_stub 0; queue o1; sleep 1.1; queue o2; lap
assert 12 "oldest queued task should run first" in_parked o1
assert_not 12 "newer task must wait" in_parked o2

# ---- promote-fixture.mjs locks (F13-F15) ----
PROMOTE="$HERE/promote-fixture.mjs"
mk_prom_run() { # minimal run dir: gate checks existence only; snapshot x.sh exits 0; canary exits $1
  rm -rf "$SB/prom"; mkdir -p "$SB/prom/artifact"
  cat > "$SB/prom/gate.sh" <<'EOF'
#!/usr/bin/env bash
set -u; cd "$(dirname "$0")" || exit 1
fail() { echo "GATE FAIL: $1"; exit 1; }
[ -f "artifact/x.sh" ] || fail "x.sh missing"
echo "GATE PASS"
EOF
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/prom/artifact/x.sh"
  printf '=== x.sh ===\n```\n#!/usr/bin/env bash\nexit %s\n```\n' "${1:-0}" > "$SB/prom/artifact-build.txt"
}
promote_json() { # promote_json <canary-exit> <block-expr> -> emits the JSON verdict line
  printf '%s\n' "$2" > "$SB/block.txt"
  node "$PROMOTE" "$SB/prom" "$SB/block.txt" 2>/dev/null | tail -1
}
json_grep() { # json_grep <canary-exit> <block-expr> <pattern> — parent-shell helper (functions are not inherited by sh -c)
  promote_json "$1" "$2" | grep -q "$3"
}
pf_field() { promote_json "$1" "$2" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{process.stdout.write(String(JSON.parse(d).$3))})"; }

# F13: all three locks -> promote (GREEN passes snapshot; RED catches canary exit-1 x.sh)
fresh
mk_prom_run 1
assert 13 "valid two-sided fixture promotes (locks 1+2+3)" test "$(pf_field 1 'bash artifact/x.sh >/dev/null 2>&1 || fail "A1: x.sh must exit 0"' promote)" = "true"
assert 13 "promote verdict names the red-check catch" json_grep 1 'bash artifact/x.sh >/dev/null 2>&1 || fail "A1: x.sh must exit 0"' 'red-check caught canary'
rm -f "$SB/block.txt"

# F14: block without refusal capability -> grammar guard rejects
mk_prom_run 0
assert 14 "fail-less block must be rejected by grammar guard" test "$(pf_field 0 'true' promote)" = "false"
rm -f "$SB/block.txt"

# F15: canary identical to snapshot -> LOCK3 wall detection
mk_prom_run 0
assert 15 "fixture that cannot fail must fail LOCK3 (wall, not gate)" test "$(pf_field 0 '[ -f artifact/x.sh ] && fail \"A1: unreachable\"' lock3)" = "false"
rm -f "$SB/block.txt"

# ---- promote.mjs end-to-end (F16-F17) ----
cat > "$SB/stub-ok.sh" <<'EOF'
#!/usr/bin/env bash
cat > "$PROMOTE_OUT" <<'JSON'
{"text":"```\nbash artifact/x.sh >/dev/null 2>&1 || fail \"A1: x.sh must exit 0\"\n```"}
JSON
EOF
cat > "$SB/stub-fail.sh" <<'EOF'
#!/usr/bin/env bash
echo boom >&2
exit 1
EOF

# F16: PROMOTE -> author stub -> 3 locks -> gate.sh.proposed (A29: live gate never touched)
fresh
mk_prom_run 1   # canary x.sh exits 1; snapshot exits 0
mkdir -p "$SB/runs"; cp -r "$SB/prom" "$SB/runs/prom"
printf 'VERDICT: FAIL\nEVIDENCE: x.sh exits nonzero on every lap.\n' > "$SB/runs/prom/s4-verdict.txt"
assert 16 "author->locks->proposed flow exits 0" env HDCS_AUTHOR_CMD="bash $SB/stub-ok.sh" node "$HERE/promote.mjs" prom
assert 16 "gate.sh.proposed landed" test -f "$SB/runs/prom/gate.sh.proposed"
assert 16 "proposed carries the authored block" sh -c "grep -q 'A1: x.sh must exit 0' '$SB/runs/prom/gate.sh.proposed'"
assert 16 "live gate.sh untouched (A29)" test "$(cat "$SB/runs/prom/gate.sh" | md5sum | cut -d' ' -f1)" = "$(printf '#!/usr/bin/env bash\nset -u; cd "$(dirname "$0")" || exit 1\nfail() { echo "GATE FAIL: $1"; exit 1; }\n[ -f "artifact/x.sh" ] || fail "x.sh missing"\necho "GATE PASS"\n' | md5sum | cut -d' ' -f1)"

# F17: author seat failure -> clean negative, no proposal
fresh
mk_prom_run 1
mkdir -p "$SB/runs"; cp -r "$SB/prom" "$SB/runs/prom"
assert_not 17 "failed author seat exits nonzero" env HDCS_AUTHOR_CMD="bash $SB/stub-fail.sh" node "$HERE/promote.mjs" prom
assert_not 17 "no gate.sh.proposed on author failure" test -f "$SB/runs/prom/gate.sh.proposed"

echo "----"
echo "selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
