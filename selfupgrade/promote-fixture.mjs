// promote-fixture.mjs — mechanical validation of a fixture-promotion candidate (self-upgrade §2.3).
// Usage: node promote-fixture.mjs <runDir> <blockFile> [canaryBuild]
//   <runDir>      run dir holding gate.sh + artifact/ (the gate-passing snapshot build)
//   <blockFile>   file with the proposed fixture block (gate.sh grammar, `fail "..."` lines)
//   <canaryBuild> optional path to build text holding the DEFECT (default: <runDir>/artifact-build.txt
//                 when artifact/ holds the passing build). Sections `=== name ===` fences are extracted.
// Three locks, all mechanical, zero LLM:
//   LOCK1 syntax  — bash -n on the composed gate (current gate.sh + block)
//   LOCK2 GREEN   — composed gate PASSES the restored gate-passing snapshot (artifact/ as-is)
//   LOCK3 RED     — composed gate FAILS the canary (a fixture that cannot fail is a wall, not a gate)
// Output: one JSON line {lock1, lock2, lock3, promote:boolean, reason}. Exit 0 iff promote.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const [runDir, blockFile, canaryArg] = process.argv.slice(2);
const out = v => console.log(JSON.stringify(v));
const sh = (cmd, opts = {}) => spawnSync('bash', ['-c', cmd], { encoding: 'utf8', ...opts });
const extract = s => [...s.matchAll(/=== ([\w.\-/]+) ===\r?\n([\s\S]*?)(?=\n=== [\w.\-/]+ ===|$)/g)].map(m => [m[1], m[2].replace(/^\s*```[\w]*\r?\n/, '').replace(/\n```\s*$/, '\n')]);

if (!runDir || !blockFile || !fs.existsSync(path.join(runDir, 'gate.sh')) || !fs.existsSync(blockFile)) {
  out({ lock1: false, lock2: false, lock3: false, promote: false, reason: 'bad-usage: need runDir with gate.sh + blockFile' });
  process.exit(1);
}
const gateSrc = fs.readFileSync(path.join(runDir, 'gate.sh'), 'utf8');
const block = fs.readFileSync(blockFile, 'utf8');
const lastLine = block.trim().split('\n').filter(l => l.trim() && !l.trim().startsWith('#')).pop() || '';
if (!/\|\|\s*fail\b|^fail\b|&&\s*fail\b/.test(lastLine)) {
  out({ lock1: false, lock2: false, lock3: false, promote: false, reason: 'block grammar: last non-comment line must carry a fail invocation (gate-not-wall: a fixture must be able to fail)' });
  process.exit(1);
}

// compose + LOCK1
const composed = gateSrc.replace(/(\necho "GATE PASS"\s*$)/, '\n' + block + '$1');
const SB = fs.mkdtempSync(path.join(os.tmpdir(), 'hdcs-promote-'));
try {
  const sandbox = path.join(SB, 'run');
  sh(`cp -r "${runDir}" "${sandbox}" && rm -rf "${sandbox}/state.json"`);
  fs.writeFileSync(path.join(sandbox, 'gate.sh'), composed);
  const l1 = sh(`bash -n "${path.join(sandbox, 'gate.sh')}"`).status === 0;
  if (!l1) { out({ lock1: false, lock2: false, lock3: false, promote: false, reason: 'LOCK1 FAIL: composed gate.sh syntax error' }); process.exit(1); }

  // LOCK2 GREEN — artifact/ currently holds the gate-passing snapshot
  const l2 = sh(`cd "${sandbox}" && bash gate.sh >/dev/null 2>&1; echo $?`, { cwd: sandbox }).stdout.trim() === '0';
  if (!l2) {
    const why = sh(`cd "${sandbox}" && bash gate.sh 2>&1 | tail -1`, { cwd: sandbox }).stdout.trim();
    out({ lock1: true, lock2: false, lock3: false, promote: false, reason: `LOCK2 FAIL: composed gate does not pass the gate-passing snapshot: ${why}` });
    process.exit(1);
  }

  // LOCK3 RED — rebuild artifact/ from the canary build text
  const canaryText = canaryArg && fs.existsSync(canaryArg)
    ? fs.readFileSync(canaryArg, 'utf8')
    : (fs.existsSync(path.join(runDir, 'artifact-build.txt')) ? fs.readFileSync(path.join(runDir, 'artifact-build.txt'), 'utf8') : null);
  if (!canaryText) { out({ lock1: true, lock2: true, lock3: false, promote: false, reason: 'no canary build text (artifact-build.txt) — supply canaryBuild arg' }); process.exit(1); }
  const secs = extract(canaryText);
  if (!secs.length) { out({ lock1: true, lock2: true, lock3: false, promote: false, reason: 'canary has no extractable === sections' }); process.exit(1); }
  sh(`rm -rf "${path.join(sandbox, 'artifact')}" && mkdir -p "${path.join(sandbox, 'artifact')}"`);
  for (const [name, body] of secs) fs.writeFileSync(path.join(sandbox, 'artifact', name), body);
  const l3out = sh(`cd "${sandbox}" && bash gate.sh 2>&1 | tail -1`, { cwd: sandbox });
  const l3 = l3out.status !== 0 || /GATE FAIL/.test(l3out.stdout);
  if (!l3) { out({ lock1: true, lock2: true, lock3: false, promote: false, reason: 'LOCK3 FAIL: fixture passed the canary — it cannot catch the defect (wall, not gate)' }); process.exit(1); }

  out({ lock1: true, lock2: true, lock3: true, promote: true, reason: `red-check caught canary: ${l3out.stdout.trim().slice(0, 100)}` });
  process.exit(0);
} finally {
  sh(`rm -rf "${SB}"`);
}
