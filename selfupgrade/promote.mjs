// promote.mjs — self-upgrade §2.3 flow: PROMOTE verdict -> fixture-author seat -> 3 mechanical locks -> gate.sh.proposed.
// Usage: node promote.mjs <task>   (run dir = $HDCS_RUNS_DIR/<task>)
// Env: HDCS_ROOT, HDCS_RUNS_DIR, HDCS_HISTORY_DIR; HDCS_AUTHOR_CMD overrides the seat call
// (selftest seam; invoked as `bash -c "$HDCS_AUTHOR_CMD"` with $PROMOTE_USERFILE in, $PROMOTE_OUT json out).
// Output: one JSON line {promote, reason, proposed?}. Exit 0 iff a .proposed file landed.
// A29: this NEVER touches gate.sh/answers.md — only *.proposed, operator merges.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.env.HDCS_ROOT || '/workspace/hdcs';
const RUNS = process.env.HDCS_RUNS_DIR || path.join(ROOT, 'runs');
const HERE = new URL('.', import.meta.url).pathname;
const out = v => console.log(JSON.stringify(v));
const sh = (cmd, o = {}) => spawnSync('bash', ['-c', cmd], { encoding: 'utf8', ...o });

const task = process.argv[2];
const run = task && path.join(RUNS, task);
if (!task || !fs.existsSync(path.join(run, 'gate.sh'))) {
  out({ promote: false, reason: 'bad-usage: need task with gate.sh' });
  process.exit(1);
}
const verdict = (() => { try { return fs.readFileSync(path.join(run, 's4-verdict.txt'), 'utf8'); } catch { return ''; } })();
const finding = (verdict.split('\n').find(l => /^EVIDENCE:/i.test(l)) || verdict.split('\n')[0] || '').trim();
if (!finding) { out({ promote: false, reason: 'no finding evidence in s4-verdict.txt' }); process.exit(1); }

const histPath = path.join(process.env.HDCS_HISTORY_DIR || path.join(ROOT, 'selfupgrade', 'history'), `${task}.jsonl`);
const reps = (() => { try { return fs.readFileSync(histPath, 'utf8').trim().split('\n').filter(Boolean).length; } catch { return 0; } })();
const gateSrc = fs.readFileSync(path.join(run, 'gate.sh'), 'utf8');
const canary = fs.existsSync(path.join(run, 'artifact-build.txt')) ? fs.readFileSync(path.join(run, 'artifact-build.txt'), 'utf8').slice(0, 12000) : '(none)';

// 1. author: fixture-author seat (cross-family vs builder) — or $HDCS_AUTHOR_CMD in selftests
fs.mkdirSync(path.join(ROOT, 'results'), { recursive: true });
const userFile = path.join(ROOT, 'results', `promote-${task}-user.txt`);
fs.writeFileSync(userFile, `FINDING (repeated ${reps}x, class: see evidence):\n${finding}\n\n=== GATE (current gate.sh, verbatim) ===\n${gateSrc}\n\n=== ARTIFACT (convicted build = canary) ===\n${canary}\n`);
const resPath = path.join(ROOT, 'results', 'fixture_author.json');
const authorCmd = process.env.HDCS_AUTHOR_CMD;
const seatRun = authorCmd
  ? sh(authorCmd, { env: { ...process.env, PROMOTE_USERFILE: userFile, PROMOTE_OUT: resPath } })
  : sh(`node "${path.join(ROOT, 'gates', 'seat.mjs')}" fixture_author "${JSON.parse(fs.readFileSync(path.join(ROOT, 'seats.json'), 'utf8')).fixture_author}" "${path.join(ROOT, 'prompts', 'fixture-author-system.txt')}" "${userFile}"`, { cwd: ROOT });
if (seatRun.status !== 0 || !fs.existsSync(resPath)) {
  out({ promote: false, reason: `author seat failed (exit ${seatRun.status}) — operator reviews finding manually` });
  process.exit(1);
}
let text = '';
try { text = JSON.parse(fs.readFileSync(resPath, 'utf8')).text || ''; } catch { text = ''; }
const m = text.match(/```[a-zA-Z]*\n([\s\S]*?)\n```/);
const block = m ? m[1] : '';
if (!block.trim()) { out({ promote: false, reason: 'author returned no fenced block' }); process.exit(1); }

// 2. locks: compose via promote-fixture.mjs against the canary already in the run dir
const blockFile = path.join(ROOT, 'results', `promote-${task}-block.txt`);
fs.writeFileSync(blockFile, block);
const locks = sh(`node "${path.join(HERE, 'promote-fixture.mjs')}" "${run}" "${blockFile}"`, { encoding: 'utf8' });
let v = null;
try { v = JSON.parse(locks.stdout.trim().split('\n').pop()); } catch {}
if (!v || !v.promote) {
  // Fixture path failed — class may not be mechanically testable → law-drafter fallback (§2.4, A29).
  const lawRes = path.join(ROOT, 'results', 'law_drafter.json');
  const lawUser = path.join(ROOT, 'results', `law-${task}-user.txt`);
  const answers = (() => { try { return fs.readFileSync(path.join(run, 'answers.md'), 'utf8').slice(0, 8000); } catch { return '(none — new task register)'; } })();
  fs.writeFileSync(lawUser, `FINDING (repeated ${reps}x; fixture locks rejected: ${v ? v.reason : 'unparseable'} — likely not mechanically testable):\n${finding}\n\n=== REGISTER (answers.md verbatim) ===\n${answers}\n`);
  const lawSeat = authorCmd
    ? sh(authorCmd, { env: { ...process.env, PROMOTE_USERFILE: lawUser, PROMOTE_OUT: lawRes } })
    : sh(`node "${path.join(ROOT, 'gates', 'seat.mjs')}" law_drafter "${JSON.parse(fs.readFileSync(path.join(ROOT, 'seats.json'), 'utf8')).law_drafter}" "${path.join(ROOT, 'prompts', 'law-drafter-system.txt')}" "${lawUser}"`, { cwd: ROOT });
  let lawText = '';
  try { lawText = JSON.parse(fs.readFileSync(lawRes, 'utf8')).text || ''; } catch {}
  const lm = lawText.match(/```[a-zA-Z]*\n([\s\S]*?)\n```/);
  if (lawSeat.status === 0 && lm && /A\d+/.test(lm[1]) && /DRAFT/.test(lm[1])) {
    fs.writeFileSync(path.join(run, 'answers.md.proposed'), lm[1] + '\n');
    out({ promote: false, law_proposed: true, reason: `fixture locks rejected (${v ? v.reason : 'unparseable'}) → answers.md.proposed landed (law-drafter; A29: operator merges)` });
    process.exit(0);
  }
  out({ promote: false, reason: `locks rejected: ${v ? v.reason : 'unparseable'}; law fallback failed — operator reviews finding manually` });
  process.exit(1);
}

// 3. land .proposed (A29: never the live gate)
fs.writeFileSync(path.join(run, 'gate.sh.proposed'), gateSrc.replace(/(\necho "GATE PASS"\s*$)/, '\n' + block + '$1'));
fs.writeFileSync(path.join(run, 'promoted-fixture.txt'), `task: ${task}\nreps: ${reps}\nfinding: ${finding}\nlocks: ${JSON.stringify(v)}\nblock:\n${block}\n`);
out({ promote: true, reason: `gate.sh.proposed landed (${v.reason})`, proposed: path.join(run, 'gate.sh.proposed') });
process.exit(0);
