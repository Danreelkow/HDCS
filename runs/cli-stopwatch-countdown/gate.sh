#!/usr/bin/env bash
set -euo pipefail
root=/workspace/tools2
export PATH="/workspace/.tools/venv/bin:$PATH"
[[ -x "$root/stopwatch.py" && -x "$root/countdown.py" ]]
[[ ! -e /workspace/tools2/../tools/STOPWATCH_DO_NOT_TOUCH ]] || true
${PYTHON_BIN:-/workspace/.tools/venv/bin/python3} - "$root" <<'PY'
import subprocess, sys
root=sys.argv[1]

def run(name, data, timeout=5):
    return subprocess.run([f'{root}/{name}'], input=data, text=True, capture_output=True, timeout=timeout)

sw=run('stopwatch.py', 'lap\nquit\n')
assert sw.returncode == 0, sw.stderr
assert 'LAP' in sw.stdout, sw.stdout
cd=subprocess.run([f'{root}/countdown.py', '0:01'], text=True, capture_output=True, timeout=5, env={**__import__('os').environ, 'COUNTDOWN_TICK_SECS':'0'})
assert cd.returncode == 0, cd.stderr
assert 'Time is up!' in cd.stdout, cd.stdout
bad=subprocess.run([f'{root}/countdown.py','bad'], text=True, capture_output=True)
assert bad.returncode != 0
print('smoke: PASS')
PY
