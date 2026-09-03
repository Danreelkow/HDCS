#!/usr/bin/env bash
# compliant: minimal repro executed under the scope guard (law A1)
set -eu
scope_root="/workspace/hdcs"
case "$scope_root" in
  /workspace/hdcs|/workspace/hdcs/*) exit 0 ;;
esac
exit 1

