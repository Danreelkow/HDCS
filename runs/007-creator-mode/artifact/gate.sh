#!/usr/bin/env bash
# gate for git-scope-false-positive: exit 0 = compliant, exit 1 = defect
set -u
here="$(cd "$(dirname "$0")" && pwd)" || exit 1
fail() { echo "FAIL: $*" >&2; exit 1; }
run_case() { bash "$1" >/dev/null 2>&1; }
run_case "$here/fixtures/compliant/compliant.sh" || fail "compliant fixture must pass"
run_case "$here/fixtures/mutant/mutant.sh" && fail "mutant fixture must fail"
echo "OK: git-scope-false-positive"
exit 0

