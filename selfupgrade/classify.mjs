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
if (code === 3) { out({ verdict: 'park', reason: 'budget exhausted', repetitions: 0 }); process.exit(0); }
if (code !== 1 && code !== 2) { out({ verdict: 'park', reason: `unknown exit code ${code}`, repetitions: 0 }); process.exit(0); }

// exit 1 = FAIL, exit 2 = S4-hold (NEEDS-CLARIFICATION): both carry judge evidence worth
// tracking — a class that repeats across laps is the promote signal regardless of which
// exit code carried it (live-found defect: S4-hold objections rode exit 2 and were invisible).
// exit 1 has TWO sources: gate failure (S3 build fails gate.sh) or S4 FAIL. The evidence
// must come from the actual cause — live-found: a gate-failed lap left a STALE s4-verdict
// and the class described the wrong defect (author blocks then could never red the canary).
const gateOutPath = path.join(RUNS, task, 'gate-out.txt');
let gateFailLine = '';
try {
  gateFailLine = (fs.readFileSync(gateOutPath, 'utf8').split('\n').find(l => /GATE FAIL/.test(l)) || '').trim();
} catch {}
// P4 (2026-09-02, live-found on 006): gate-out.txt accumulates across laps — a stale GATE FAIL
// line must only be trusted when the FINAL state says the gate actually failed (kernel P2 now
// grades exit by final state: exit 1 + gate_pass true = the gate did NOT fail this lap).
let gatePassFinal = null;
try { gatePassFinal = JSON.parse(fs.readFileSync(path.join(RUNS, task, 'state.json'), 'utf8')).gate_pass; } catch {}
let evLine = '';
if (code === 1 && gateFailLine && gatePassFinal !== true) {
  evLine = gateFailLine;
} else {
  const verdictPath = path.join(RUNS, task, 's4-verdict.txt');
  let vtxt = '';
  try { vtxt = fs.readFileSync(verdictPath, 'utf8'); } catch {
    out({ verdict: code === 2 ? 'park' : 'requeue', reason: code === 2 ? 'needs-clarification (human seam); no s4-verdict.txt to class' : 'exit 1 with no gate failure and no s4-verdict.txt', repetitions: 1 });
    process.exit(0);
  }
  evLine = (vtxt.split('\n').find(l => /^EVIDENCE:/i.test(l)) || vtxt.split('\n').find(l => /^VERDICT:/i.test(l)) || vtxt.split('\n').find(l => l.trim()) || '').trim();
}
// finding class v2: cited A-numbers are the stable signature (S4 rephrases every lap but
// cites the same laws); word-prefix fallback only when the evidence cites nothing.
const anums = [...new Set((evLine.toLowerCase().match(/a\d+/g) || []))].sort();
const findingClass = anums.length
  ? anums.join(' ')
  : (evLine.toLowerCase().replace(/[^\w\s]/g, '').split(/\s+/).slice(0, 6).join(' ') || 'empty-verdict');

fs.mkdirSync(HISTORY, { recursive: true });
const histPath = path.join(HISTORY, `${task}.jsonl`);
fs.appendFileSync(histPath, JSON.stringify({ at: new Date().toISOString(), code, findingClass }) + '\n');
const reps = fs.readFileSync(histPath, 'utf8').trim().split('\n')
  .map(l => { try { return JSON.parse(l).findingClass; } catch { return null; } })
  .filter(c => c === findingClass).length;

if (code === 2) {
  // S4-hold: task parks at the human seam REGARDLESS (kernel contract). But a class
  // repeated >=3x is harvested: promote fires the fixture/law author -> .proposed only (A29).
  if (reps >= 3) out({ verdict: 'promote', taskParked: true, reason: `exit-2 class repeated ${reps}x: "${findingClass}" — harvesting proposal; task stays parked (human seam)`, repetitions: reps });
  else out({ verdict: 'park', reason: `needs-clarification (human seam); class "${findingClass}" seen ${reps}x`, repetitions: reps });
  process.exit(0);
}
if (reps >= 2) out({ verdict: 'promote', reason: `finding class repeated ${reps}x: "${findingClass}"`, repetitions: reps });
else out({ verdict: 'requeue', reason: `exit 1, finding class "${findingClass}"`, repetitions: reps });
