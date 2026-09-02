// classify.mjs — exit-code router. `node classify.mjs <task> <exitCode>` -> one JSON line:
// { verdict, reason, repetitions }
// Env overrides: HDCS_ROOT, HDCS_RUNS_DIR, HDCS_HISTORY_DIR.
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.env.HDCS_ROOT || '/workspace/hdcs';
const RUNS = process.env.HDCS_RUNS_DIR || path.join(ROOT, 'runs');
const HISTORY = process.env.HDCS_HISTORY_DIR || path.join(ROOT, 'selfupgrade', 'history');
const [task, codeArg] = process.argv.slice(2);
const out = verdict => console.log(JSON.stringify(verdict));

if (!task || !/^\d+$/.test(codeArg || '')) {
  out({ verdict: 'park', reason: 'bad-usage', repetitions: 0 });
  process.exit(0);
}
const code = Number(codeArg);

if (code === 0) { out({ verdict: 'delivered', reason: 'exit 0', repetitions: 0 }); process.exit(0); }
if (code === 2) { out({ verdict: 'park', reason: 'needs-clarification (human seam)', repetitions: 0 }); process.exit(0); }
if (code === 3) { out({ verdict: 'park', reason: 'budget exhausted', repetitions: 0 }); process.exit(0); }
if (code !== 1) { out({ verdict: 'park', reason: `unknown exit code ${code}`, repetitions: 0 }); process.exit(0); }

// exit 1 = FAIL: extract finding class from the judge verdict, track repetitions.
const verdictPath = path.join(RUNS, task, 's4-verdict.txt');
let vtxt = '';
try { vtxt = fs.readFileSync(verdictPath, 'utf8'); } catch {
  out({ verdict: 'requeue', reason: 'exit 1 with no s4-verdict.txt', repetitions: 1 });
  process.exit(0);
}
const evLine = (vtxt.split('\n').find(l => /^EVIDENCE:/i.test(l)) || vtxt.split('\n').find(l => /^VERDICT:/i.test(l)) || vtxt.split('\n').find(l => l.trim()) || '').trim();
const findingClass = evLine.toLowerCase().replace(/[^\w\s]/g, '').split(/\s+/).slice(0, 6).join(' ') || 'empty-verdict';

fs.mkdirSync(HISTORY, { recursive: true });
const histPath = path.join(HISTORY, `${task}.jsonl`);
fs.appendFileSync(histPath, JSON.stringify({ at: new Date().toISOString(), code, findingClass }) + '\n');
const reps = fs.readFileSync(histPath, 'utf8').trim().split('\n')
  .map(l => { try { return JSON.parse(l).findingClass; } catch { return null; } })
  .filter(c => c === findingClass).length;

if (reps >= 2) out({ verdict: 'promote', reason: `finding class repeated ${reps}x: "${findingClass}"`, repetitions: reps });
else out({ verdict: 'requeue', reason: `exit 1, finding class "${findingClass}"`, repetitions: reps });
