#!/usr/bin/env bash
set -u
root=/workspace/tempconv2
[[ -f "$root/src/index.js" ]] || { echo 'missing /workspace/tempconv2/src/index.js'; exit 1; }
[[ ! -e /workspace/tempconv/src/index.js ]] || { [[ "$(stat -c %Y /workspace/tempconv/src/index.js 2>/dev/null || true)" = "$(cat /workspace/hdcs/runs/tempconv-cli/baseline-mtime 2>/dev/null || true)" ]] || { echo 'legacy tempconv modified'; exit 1; }; }
node --check "$root/src/index.js" || exit 1
run_ok() { out=$(node "$root/src/index.js" "$@") || { echo "expected success: $*"; exit 1; }; [[ -n "$out" ]] || { echo 'empty output'; exit 1; }; }
run_bad() { err=$(node "$root/src/index.js" "$@" 2>&1 >/dev/null); code=$?; [[ $code -eq 1 && -n "$err" ]] || { echo "expected stderr exit1: $* (code=$code err=$err)"; exit 1; }; }
run_ok 0 C F
run_ok 32 fahrenheit celsius
run_ok 273.15 celsius kelvin
run_ok 0 K Celsius
run_bad 1 C
run_bad nope C F
run_bad 1 Rankine F
run_bad -274 C F
run_bad -460 F C
run_bad -1 K C
printf '%s\n' 'GATE PASS'
