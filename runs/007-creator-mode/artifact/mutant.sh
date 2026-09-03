#!/usr/bin/env bash
# mutant: minimal repro executed with no scope guard (law A1)
# repro: git status --porcelain executed with cwd outside /workspace/hdcs
set -u
scope_root=""
case "$scope_root" in
  /workspace/hdcs|/workspace/hdcs/*) exit 0 ;;
esac
exit 1

