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


const once = process.argv.includes('--once');
const workersArg = process.argv.find(a => /^--workers=\d+$/.test(a));
const N = workersArg ? parseInt(workersArg.split('=')[1], 10) : 1;

// Atomic claim: rename TASK-x.json -> TASK-x.json.claimed (same fs). Disjoint tasks run
// concurrently; the same task can never be claimed twice. Claims are released by the
// routing step (rename back before route/requeue).
const claim = () => {
  const entries = fs.readdirSync(QUEUE)
    .filter(f => /^TASK-.+\.json$/.test(f))
    .map(f => ({ f, m: fs.statSync(path.join(QUEUE, f)).mtimeMs }))
    .sort((a, b) => a.m - b.m);
  for (const { f } of entries) {
    const p = path.join(QUEUE, f);
    const claimed = p + '.claimed';
    try { fs.renameSync(p, claimed); } catch { continue; } // lost the race — try next
    let entry = null;
    try { entry = JSON.parse(fs.readFileSync(claimed, 'utf8')); } catch { entry = { task: f, unparseable: true, error: 'bad json' }; }
    return { json: f, claimed, entry };
  }
  return null;
};
const release = c => { try { fs.renameSync(c.claimed, path.join(QUEUE, c.json)); } catch {} };
const releaseAs = (c, dstDir, note) => {
  fs.mkdirSync(dstDir, { recursive: true });
  const dst = path.join(dstDir, c.json);
  try { fs.renameSync(c.claimed, dst); } catch {}
  if (note) fs.writeFileSync(dst.replace(/\.json$/, '.note.txt'), note + '\n');
};

function tick() {
  const c = claim();
  if (!c) return false;
  const p = path.join(QUEUE, c.json);
  let e;
  try { e = c.entry; } catch (err) {
    releaseAs(c, parked, `unparseable queue entry: ${err.message}`);
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
    releaseAs(c, parked, `DELIVERED (exit 0) — ${v.reason || 'loop reported delivery'}`);
  } else if (v.verdict === 'promote') {
    if (process.env.HDCS_PROMOTE !== '0') {
      const pr = spawnSync('node', [new URL('./promote.mjs', import.meta.url).pathname, task], {
        cwd: ROOT, encoding: 'utf8', env: { ...process.env, HDCS_ROOT: ROOT, HDCS_QUEUE_DIR: QUEUE, HDCS_RUNS_DIR: RUNS },
      });
      let pv = null; try { pv = JSON.parse((pr.stdout || '').trim().split('\n').pop()); } catch {}
      console.log(`[driver] promote flow: ${pv ? pv.reason : 'unparseable'}`);
      const dstNote = `PROMOTED — ${v.reason} | promote-flow: ${pv ? pv.reason : 'failed'}`;
      releaseAs(c, v.taskParked ? parked : promoted, dstNote);
      return { verdict: 'promote', reason: v.reason, promoteFlow: pv };
    }
    releaseAs(c, promoted, `PROMOTED — ${v.reason}`);
  } else if (v.verdict === 'park') {
    releaseAs(c, parked, `PARKED — ${v.reason}`);
  } else if (remaining <= 0) {
    releaseAs(c, parked, `EXHAUSTED — maxLaps reached while verdict was ${v.verdict}: ${v.reason || ''}`);
  } else {
    // write updated entry into the CLAIMED file, then release — no race window
    fs.writeFileSync(c.claimed, JSON.stringify({ ...e, laps: lapsDone + 1 }, null, 2) + '\n');
    release(c);
    console.log(`[driver] requeued ${task} (verdict ${v.verdict}, ${remaining} lap(s) left): ${v.reason || ''}`);
  }
  return true;
}

if (once && N === 1) { const ran = tick(); console.log(ran ? '[driver] --once: ran one tick' : '[driver] --once: queue empty'); process.exit(0); }
if (N > 1) {
  // N-worker drain: TRUE parallelism via N child driver processes. Each child loops
  // sync ticks on disjoint atomically-claimed tasks (spawnSync blocks, so concurrency
  // must come from processes, not promises). Parent exits when all children drain.
  console.log(`[driver] ${N} workers draining ${QUEUE}`);
  const { spawn } = await import('node:child_process');
  const kids = [];
  for (let i = 0; i < N; i++) {
    kids.push(new Promise(res => {
      const kid = spawn(process.execPath, [new URL('./driver.mjs', import.meta.url).pathname, '--worker'], {
        cwd: ROOT, env: { ...process.env, HDCS_WORKER_ID: String(i) }, stdio: ['ignore', 'inherit', 'inherit'],
      });
      kid.on('exit', code => { console.log(`[driver] worker-${i} drained (exit ${code})`); res(); });
    }));
  }
  Promise.all(kids).then(() => { console.log('[driver] queue drained'); process.exit(0); });
} else if (process.env.HDCS_WORKER_ID !== undefined) {
  // child worker: drain the queue synchronously, then exit
  while (true) {
    let more = false;
    try { more = tick() !== false; } catch (err) { console.error('[driver] worker tick error:', err.message); process.exit(1); }
    if (!more) break;
  }
  process.exit(0);
} else {
  let busy = false;
  const run = () => {
    if (busy) return;
    busy = true;
    try { tick(); } catch (err) { console.error('[driver] tick error:', err.message); }
    busy = false;
  };
  setInterval(run, TICK_MS);
  console.log(`[driver] watching ${QUEUE} every ${TICK_MS / 60000} min`);
  run();
}
