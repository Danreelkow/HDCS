// driver.mjs — zero-LLM HDCS lap scheduler. One tick = oldest queued task, one lap, classify, route.
// Env overrides (for sandboxed selftests): HDCS_ROOT, HDCS_QUEUE_DIR, HDCS_RUNS_DIR.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.env.HDCS_ROOT || '/workspace/hdcs';
const QUEUE = process.env.HDCS_QUEUE_DIR || path.join(ROOT, 'queue');
const RUNS = process.env.HDCS_RUNS_DIR || path.join(ROOT, 'runs');
const TICK_MS = 10 * 60 * 1000;

const parked = path.join(QUEUE, 'parked');
const promoted = path.join(QUEUE, 'promoted');
for (const d of [QUEUE, parked, promoted]) fs.mkdirSync(d, { recursive: true });

const move = (src, dstDir, note) => {
  fs.mkdirSync(dstDir, { recursive: true });
  const dst = path.join(dstDir, path.basename(src));
  fs.renameSync(src, dst);
  if (note) fs.writeFileSync(dst.replace(/\.json$/, '.note.txt'), note + '\n');
};

function route(task, exitCode) {
  const r = spawnSync('node', [new URL('./classify.mjs', import.meta.url).pathname, task, String(exitCode)], {
    cwd: ROOT,
    encoding: 'utf8',
    env: { ...process.env, HDCS_ROOT: ROOT, HDCS_QUEUE_DIR: QUEUE, HDCS_RUNS_DIR: RUNS },
  });
  let v = null;
  try { v = JSON.parse(r.stdout.trim().split('\n').pop()); } catch {}
  if (!v || typeof v.verdict !== 'string') {
    console.log(`[driver] classify failed for ${task} (code ${exitCode}) — parking for safety`);
    return { verdict: 'park', reason: 'classify-unparseable' };
  }
  return v;
}

function tick() {
  const entries = fs.readdirSync(QUEUE)
    .filter(f => /^TASK-.+\.json$/.test(f))
    .map(f => ({ f, m: fs.statSync(path.join(QUEUE, f)).mtimeMs }))
    .sort((a, b) => a.m - b.m); // oldest first
  if (!entries.length) return false;
  const { f } = entries[0];
  const p = path.join(QUEUE, f);
  let e;
  try { e = JSON.parse(fs.readFileSync(p, 'utf8')); } catch (err) {
    move(p, parked, `unparseable queue entry: ${err.message}`);
    return true;
  }
  const task = e.task;
  const budget = Number(e.budget) || 0.12;
  const maxLaps = Number(e.maxLaps) || 3;
  const lapsDone = Number(e.laps) || 0;
  console.log(`[driver] lap ${lapsDone + 1}/${maxLaps} for ${task} (budget ${budget})`);
  const lap = spawnSync('node', ['loop.mjs', path.join('runs', task), '--budget', String(budget)], {
    cwd: ROOT, encoding: 'utf8', env: { ...process.env },
  });
  const code = lap.status === null ? 1 : lap.status;
  fs.appendFileSync(path.join(ROOT, 'driver.log'), `[${new Date().toISOString()}] ${task} lap exit ${code}\n`);
  const v = route(task, code);
  const remaining = maxLaps - (lapsDone + 1);
  if (v.verdict === 'delivered') {
    move(p, parked, `DELIVERED (exit 0) — ${v.reason || 'loop reported delivery'}`);
  } else if (v.verdict === 'promote') {
    if (process.env.HDCS_PROMOTE !== '0') {
      const pr = spawnSync('node', [new URL('./promote.mjs', import.meta.url).pathname, task], {
        cwd: ROOT, encoding: 'utf8', env: { ...process.env, HDCS_ROOT: ROOT, HDCS_QUEUE_DIR: QUEUE, HDCS_RUNS_DIR: RUNS },
      });
      let pv = null; try { pv = JSON.parse((pr.stdout || '').trim().split('\n').pop()); } catch {}
      console.log(`[driver] promote flow: ${pv ? pv.reason : 'unparseable'}`);
      const dstNote = `PROMOTED — ${v.reason} | promote-flow: ${pv ? pv.reason : 'failed'}`;
      if (v.taskParked) move(p, parked, `PARKED (task) — ${dstNote}`);
      else move(p, promoted, dstNote);
      return { verdict: 'promote', reason: v.reason, promoteFlow: pv };
    }
    move(p, promoted, `PROMOTED — ${v.reason}`);
  } else if (v.verdict === 'park') {
    move(p, parked, `PARKED — ${v.reason}`);
  } else if (remaining <= 0) {
    move(p, parked, `EXHAUSTED — maxLaps reached while verdict was ${v.verdict}: ${v.reason || ''}`);
  } else {
    fs.writeFileSync(p, JSON.stringify({ ...e, laps: lapsDone + 1 }, null, 2) + '\n');
    console.log(`[driver] requeued ${task} (verdict ${v.verdict}, ${remaining} lap(s) left): ${v.reason || ''}`);
  }
  return true;
}

const once = process.argv.includes('--once');
let busy = false;
const run = () => {
  if (busy) return;
  busy = true;
  try { tick(); } catch (err) { console.error('[driver] tick error:', err.message); }
  busy = false;
};
if (once) { const ran = tick(); console.log(ran ? '[driver] --once: ran one tick' : '[driver] --once: queue empty'); process.exit(0); }
setInterval(run, TICK_MS);
console.log(`[driver] watching ${QUEUE} every ${TICK_MS / 60000} min`);
run();
