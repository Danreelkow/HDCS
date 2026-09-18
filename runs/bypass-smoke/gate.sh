#!/usr/bin/env bash
set -euo pipefail
f=/workspace/hdcs/runs/bypass-smoke/hello.mjs
test -f "$f"
test "$(grep -Ec '^(import|export|require)\b' "$f")" -eq 0
actual=$(node "$f")
test "$actual" = 'bypass smoke ok'
printf '%s\n' 'PASS: file, dependency, and stdout contract verified'
