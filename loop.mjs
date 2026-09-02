#!/usr/bin/env node
// loop.mjs — HDCS MVP loop v0.1: cost-first roster, mechanical gates at every seam.
// usage: node loop.mjs <task-dir> [--budget 0.25]
// stages: S1 translate (validate, repair <=2, escalate 1) -> S2 brief -> S3 worker
//         (+ artifact extraction + task gate.sh) -> S5 egress (reverse-gate, fallback 1)
// S4 judgment gate: skipped in v0.1 when the mechanical gate covers the deliverable.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const seats = JSON.parse(fs.readFileSync(path.join(HERE, 'seats.json'), 'utf8'));
const taskDir = path.resolve(process.argv[2] ?? '.');
const bi = process.argv.indexOf('--budget');
const budget = Number(bi > -1 ? process.argv[bi + 1] : 0.25);
const runName = path.basename(taskDir);
fs.mkdirSync(path.join(taskDir, 'results'), { recursive: true });
process.chdir(taskDir);

const task = fs.readFileSync('task.md', 'utf8');
const answers = fs.existsSync('answers.md') ? fs.readFileSync('answers.md', 'utf8') : '';
const mustKeeps = [...task.matchAll(/MUST_KEEP:\s*(.+)/g)].map(m => m[1].trim());
const costs = [];
const log = m => console.log(`[loop] ${m}`);
const outcomes = {};
// --- resume checkpoints (operator directive: retry the part that failed, not the whole lap) ---
const fresh = process.argv.includes('--fresh');
const stateFile = 'state.json';
const state = (fs.existsSync(stateFile) && !fresh) ? JSON.parse(fs.readFileSync(stateFile, 'utf8')) : {};
process.on('exit', () => { try { fs.writeFileSync(stateFile, JSON.stringify(state, null, 1)); } catch {} });
const fileAt = f => { try { return fs.statSync(f).mtimeMs; } catch { return 0; } };
const digest = s => createHash('md5').update(s).digest('hex');
// --- operator patch P4 (2026-09-02): lossless section extraction. Capture runs to the next FULL
// section header (or end of string), then wrapper fences are stripped. The old fence-terminator
// lookahead truncated any artifact whose body legitimately contains ``` fences (writing-class
// artifacts) — caught by run 002: 103-line build extracted as 15 lines.
const extractSections = s => [...s.matchAll(/=== ([\w.\-/]+) ===\r?\n([\s\S]*?)(?=\n=== [\w.\-/]+ ===|$)/g)]
  .map(([, name, body]) => [name, body.replace(/^\s*```[\w.-]*\r?\n/, '').replace(/\r?\n?```\s*$/, '')]);

function seat(name, model, sysFile, userText, maxTok = 32768, reasonCap = 65536) {
  const sys = path.join(HERE, 'prompts', sysFile);
  fs.writeFileSync('in.txt', userText);
  for (let tryN = 0; tryN < 2; tryN++) {
    try {
      execFileSync('node', [path.join(HERE, 'gates', 'seat.mjs'), name, model, sys, 'in.txt', String(maxTok), '0.2', String(reasonCap)], { stdio: 'inherit' });
      break;
    } catch (e) {
      if (tryN === 1) { log(`${name}: seat call failed twice (${String(e.message).split('\n')[0].slice(0, 60)}) — treating as empty response`); return ''; }
      log(`${name}: seat call failed, retrying once`);
    }
  }
  const r = JSON.parse(fs.readFileSync(`results/${name}.json`, 'utf8'));
  costs.push({ seat: name, model, cost: r.usage?.cost ?? 0 });
  return r.text ?? '';
}
const fence = t => (t.match(/```yaml\n([\s\S]*?)\n```/) || t.match(/```\n([\s\S]*?)\n```/) || [])[1] ?? null;
const total = () => costs.reduce((s, c) => s + c.cost, 0);
const checkBudget = stage => { if (total() > budget) { log(`BUDGET EXCEEDED at ${stage} ($${total().toFixed(4)} > $${budget})`); report(); process.exit(3); } };
function report() {
  console.log('\n=== COST REPORT ===');
  for (const c of costs) console.log(`${c.seat.padEnd(14)} ${c.model.padEnd(32)} $${c.cost.toFixed(5)}`);
  console.log(`TOTAL: $${total().toFixed(4)} / budget $${budget}`);
  console.log('OUTCOMES:', JSON.stringify(outcomes));
}

// --- S1 (checkpointed: cached while answers.md/task.md/prompts are unchanged) ---
const s1User = task + (answers ? '\n\n=== OPERATOR ANSWERS ===\n' + answers : '');
const promptAt = fs.readdirSync(path.join(HERE, 'prompts')).reduce((m, f) => Math.max(m, fileAt(path.join(HERE, 'prompts', f))), 0);
const s1valid = state.s1_at && fileAt('answers.md') <= state.s1_at && fileAt('task.md') <= state.s1_at && fileAt(path.join(HERE, 'prompts', 's1-system.txt')) <= state.s1_at && fs.existsSync('packet.yaml') && fs.existsSync('s1-out.txt');
const s1replayed = !!s1valid;
if (s1replayed) { outcomes.s1 = 'PASS'; log('s1: CACHED (inputs unchanged since last pass — zero spend)'); }
else {
let packetFile = null;
let model = seats.s1;
for (const attempt of ['s1', 's1-repair', 's1-repair2', 's1-escalate']) {
  checkBudget('s1');
  const prev = packetFile ? fs.readFileSync(packetFile, 'utf8') : null;
  const text = seat(attempt, model, 's1-system.txt', prev
    ? `VALIDATOR OUTPUT:\n${fs.readFileSync('v.txt', 'utf8')}\n\nYOUR PREVIOUS PACKET:\n${prev}\n\nResend ONE corrected yaml fence fixing every violation. Constants stay literal (gate: READY|NOT_READY, state: S_0 + Delta -> S_1). No top-level +open key. No prose outside the fence.`
    : s1User, 32768);
  fs.writeFileSync('s1-out.txt', text);
  const f = fence(text);
  if (!f) { log(`${attempt}: NO FENCE`); fs.writeFileSync('v.txt', 'no yaml fence in response'); continue; }
  fs.writeFileSync('packet.yaml', f); packetFile = 'packet.yaml';
  const args = [path.join(HERE, 'gates', 'hcdl-validate.mjs'), 'packet.yaml', ...mustKeeps.flatMap(k => ['--must-keep', k])];
  let out;
  try { out = execFileSync('node', args, { encoding: 'utf8' }); }
  catch (e) { out = [e.stdout, e.stderr].filter(Boolean).join(''); }
  fs.writeFileSync('v.txt', out);
  log(`${attempt}: ${/hcdl: PASS/.test(out) ? 'PASS' : 'FAIL'}`);
  if (/hcdl: PASS/.test(out)) { outcomes.s1 = 'PASS'; state.s1_at = Date.now(); break; }
  if (attempt === 's1-repair2') { model = seats.s1_escalate; log(`escalating S1 to ${model}`); }
}
}
if (outcomes.s1 !== 'PASS') { log('S1 never passed; aborting'); outcomes.s1 = 'FAIL'; report(); process.exit(1); }
const packet = fs.readFileSync('packet.yaml', 'utf8');

// --- context register (hcdl shared context, readable by every seat) ---
const s1out = fs.readFileSync('s1-out.txt', 'utf8');
const ctxM = s1out.match(/=== context\.hcdl ===\r?\n([\s\S]*?)(?=\n=== |\n```|$)/);
if (ctxM) { fs.writeFileSync('context.hcdl', ctxM[1].trim() + '\n'); log('context.hcdl: ' + ctxM[1].trim().split('\n').length + ' lines'); }
const shared = fs.existsSync('context.hcdl') ? '=== SHARED CONTEXT (hcdl register of record) ===\n' + fs.readFileSync('context.hcdl', 'utf8') + '\n' : '';
// --- operator patch P1 (2026-09-02): source/ verbatim channel — lossless raw sources to S2/S3/S4 ---
const sourcesBlock = (() => {
  const srcDir = path.join(taskDir, 'source');
  if (!fs.existsSync(srcDir)) return '';
  const files = fs.readdirSync(srcDir).filter(f => !f.startsWith('.')).sort();
  return files.length ? `\n\n=== RAW SOURCES (verbatim, operator-provided — do not truncate or paraphrase) ===\n${files.map(f => `=== source/${f} (verbatim) ===\n${fs.readFileSync(path.join(srcDir, f), 'utf8')}`).join('\n\n')}` : '';
})();

// --- S2 (checkpointed: cached while packet/prompts unchanged) ---
const s2valid = s1replayed && state.s2_at && fileAt('brief.md') <= state.s2_at && fileAt(path.join(HERE, 'prompts', 's2-system.txt')) <= state.s2_at && fs.existsSync('brief.md');
const s2Cached = !!s2valid;
let brief;
if (s2Cached) { brief = fs.readFileSync('brief.md', 'utf8'); outcomes.s2 = 'BRIEF cached'; log('s2: CACHED (packet unchanged — zero spend)'); }
else {
checkBudget('s2');
brief = seat('s2', seats.s2, 's2-system.txt', `${shared}=== hdcs/1 PACKET ===\n${packet}${sourcesBlock}`, 32768);
fs.writeFileSync('brief.md', brief);
state.s2_at = Date.now();
outcomes.s2 = 'BRIEF ' + brief.length + ' chars';
}

// --- S3 (worker + repair round; artifacts CACHED and re-verified against the CURRENT gate for free) ---
let build = fs.existsSync('artifact-build.txt') ? fs.readFileSync('artifact-build.txt', 'utf8') : null;
let s3cached = false;
if (s2Cached && state.gate_pass && build && state.s3_hash === digest(build) && fs.existsSync('gate.sh') && state.gate_at >= fileAt('gate.sh') && state.gate_at >= fileAt(path.join(HERE, 'prompts', 's3-system.txt'))) {
  fs.mkdirSync('artifact', { recursive: true });
  for (const f of fs.readdirSync('artifact')) fs.rmSync(path.join('artifact', f), { recursive: true, force: true });
  for (const [, name, body] of extractSections(build)) if (!name.includes('/') && !name.includes('..')) fs.writeFileSync(path.join('artifact', name), body.trimStart() + '\n');
  let g = '', ok = true;
  try { g = execFileSync('bash', ['gate.sh'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }); }
  catch (e) { ok = false; g = [e.stdout, e.stderr].filter(Boolean).join(''); }
  fs.writeFileSync('gate-out.txt', g);
  if (ok && /GATE PASS/.test(g)) { outcomes.s3 = 'PASS'; s3cached = true; log('s3: CACHED — artifacts re-verified against current gate (zero seat spend)'); }
  else { log('s3: cached artifacts fail the current gate (gate/prompts changed) — full rebuild'); build = null; }
}
if (!s3cached && !state.gate_pass) { if (build) log('s3: no recorded gate pass for these artifacts (cold state) — full rebuild'); build = null; }
if (!s3cached) {
checkBudget('s3');
const s3attempts = (build && s2Cached && state.gate_pass) ? ['s3', 's3-repair'] : ['s3', 's3-alt', 's3-repair'];
const gateFails = [];
const s4evidence = (!gateFails.length && fs.existsSync('s4-verdict.txt')) ? `\n\nS4 JUDGE VERDICT from the previous lap (fix its findings — the gate baseline is green, KEEP it green):\n${fs.readFileSync('s4-verdict.txt', 'utf8')}` : '';
for (const attempt of s3attempts) {
  const input = attempt === 's3-repair'
    ? `${shared}ACCEPTANCE CONTRACT (gate.sh — build to this exactly: every env var name, file name, behavior):\n${fs.existsSync('gate.sh') ? fs.readFileSync('gate.sh', 'utf8') : '(no mechanical gate)'}\n\nBUILD BRIEF:\n${brief}${sourcesBlock}`
    : `${shared}GATE OUTPUTS (ensemble attempts):\n${(gateFails.length ? gateFails.join('\n---\n') : 'GATE PASS (baseline is green)')}${s4evidence}\n\nTHE ORIGINAL BUILD BRIEF (honor it):\n${brief}${sourcesBlock}\n\nYOUR PREVIOUS ARTIFACTS (keep everything that already passed; the judge names specific lines — REWRITE those lines completely, then re-read your output against the verdict):\n${build}\n\nReturn corrected sections (same format: === <filename> ===), fixing every gate failure — a stated contract applies to ALL instances (if SRC is renamed, DST and every unit/README reference rename together, never just the cited one). BEFORE answering, validate yourself: every section complete and balanced (the script must pass bash -n), no truncation, no placeholders — a malformed section is worse than no answer.`;
  build = seat(attempt, seats.s3, 's3-system.txt', input, 32768);
  if (!build.trim()) { outcomes.s3 = 'FAIL'; state.gate_pass = false; log(`${attempt}: empty response — previous artifacts left untouched on disk`); break; }
  fs.writeFileSync('artifact-build.txt', build);
  fs.mkdirSync('artifact', { recursive: true });
  for (const f of fs.readdirSync('artifact')) fs.rmSync(path.join('artifact', f), { recursive: true, force: true });
  const sections = extractSections(build);
  for (const [, name, body] of sections) if (!name.includes('/') && !name.includes('..')) fs.writeFileSync(path.join('artifact', name), body.trimStart() + '\n');
  log(`artifacts: ${sections.map(s => s[1]).join(', ') || 'NONE'}`);
  if (!fs.existsSync('gate.sh')) { outcomes.s3 = 'NO GATE (artifacts extracted)'; break; }
  let g = '', ok = true;
  try { g = execFileSync('bash', ['gate.sh'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }); }
  catch (e) { ok = false; g = [e.stdout, e.stderr].filter(Boolean).join(''); }
  fs.writeFileSync('gate-out.txt', g);
  log('gate: ' + g.trim().split('\n').pop());
  if (ok && /GATE PASS/.test(g)) { outcomes.s3 = 'PASS'; state.gate_pass = true; state.gate_at = Date.now(); state.s3_hash = digest(build); break; }
  gateFails.push(attempt + ': ' + g.trim().split('\n').pop());
  if (attempt === 's3-repair') {
    outcomes.s3 = 'FAIL'; state.gate_pass = false;
    if (fs.existsSync('artifact-build.gatepass.txt')) {
      fs.copyFileSync('artifact-build.gatepass.txt', 'artifact-build.txt');
      state.gate_pass = true; state.s3_hash = digest(fs.readFileSync('artifact-build.txt', 'utf8'));
      log('restored gate-passing snapshot — next lap repairs from the clean baseline');
    }
  }
  else log('S3 gate failed; running repair round');
}
}

// --- S4: decorrelated judgment gate — fires only when something was produced ---
// Operator policy: skip S4 when nothing was produced (that needs clarification, not a verdict).
// Ungated artifacts (NO GATE) still count as produced -> S4 judges them.
if (outcomes.s3 === 'PASS' || outcomes.s3.startsWith('NO GATE')) {
  let s4verdict = '';
  const s4valid = s3cached && state.s4_pass && build && state.s4_hash === digest(build) && fs.existsSync('s4-verdict.txt');
  if (s4valid) { s4verdict = fs.readFileSync('s4-verdict.txt', 'utf8'); outcomes.s4 = 'PASS'; log('s4: CACHED — artifacts unchanged since judge PASS (straight to egress)'); }
  else
  for (let s4round = 0; s4round < 2; s4round++) {
    checkBudget(s4round ? 's4-reverify' : 's4');
    const artifacts = fs.existsSync('artifact') ? fs.readdirSync('artifact').join(', ') : '';
    const gateOut = fs.existsSync('gate-out.txt') ? fs.readFileSync('gate-out.txt', 'utf8') : '(no mechanical gate ran)';
    s4verdict = seat(s4round ? 's4-reverify' : 's4', seats.s4, 's4-system.txt', `${shared}hdcs/1 PACKET:\n${packet}\n\nMECHANICAL GATE OUTPUT:\n${gateOut}\n\nARTIFACT FILES: ${artifacts}\n\nARTIFACT CONTENTS:\n${fs.existsSync('artifact-build.txt') ? fs.readFileSync('artifact-build.txt', 'utf8') : ''}${sourcesBlock}`, 32768);
    fs.writeFileSync('s4-verdict.txt', s4verdict);
    outcomes.s4 = /VERDICT:\s*PASS/i.test(s4verdict) ? 'PASS' : (/VERDICT:\s*FAIL/i.test(s4verdict) ? 'FAIL' : 'UNPARSED');
    log(`S4: ${outcomes.s4}`);
    if (outcomes.s4 !== 'FAIL' || s4round === 1) break;
    // doctrine option (operator-approved 2026-09-01): ONE S4->S3 feedback repair before human routing
    log('S4 FAIL -> feedback repair round (judge evidence fed to builder)');
    if (state.gate_pass && fs.existsSync('artifact-build.txt')) fs.copyFileSync('artifact-build.txt', 'artifact-build.gatepass.txt');
    const fb = seat('s3-feedback', seats.s3, 's3-system.txt', `${shared}ACCEPTANCE CONTRACT (gate.sh — every fix MUST keep satisfying this; env names, file names, behaviors):\n${fs.existsSync('gate.sh') ? fs.readFileSync('gate.sh', 'utf8') : '(no mechanical gate)'}\n\nGATE OUTPUT:\n${gateOut}\n\nS4 JUDGE VERDICT (fix every finding EXCEPT where the verdict contradicts the gate contract or the A-law in SHARED CONTEXT — contract and law win over the verdict):\n${s4verdict}\n\nTHE ORIGINAL BUILD BRIEF (honor it):\n${brief}\n\nYOUR PREVIOUS ARTIFACTS (keep everything that already passed the gate — minimal diff, no placeholders, complete valid shell in every section):\n${fs.readFileSync('artifact-build.txt', 'utf8')}\n\nReturn corrected sections (same format: === <filename> ===).`, 32768);
    if (!fb.trim()) { log('s3-feedback: empty response — keeping gate-passing artifacts'); break; }
    fs.writeFileSync('artifact-build.txt', fb);
    fs.mkdirSync('artifact', { recursive: true });
  for (const f of fs.readdirSync('artifact')) fs.rmSync(path.join('artifact', f), { recursive: true, force: true });
    for (const [, name, body] of extractSections(fb)) if (!name.includes('/') && !name.includes('..')) fs.writeFileSync(path.join('artifact', name), body.trimStart() + '\n');
    if (fs.existsSync('gate.sh')) {
      let g = '', ok = true;
      try { g = execFileSync('bash', ['gate.sh'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }); }
      catch (e) { ok = false; g = [e.stdout, e.stderr].filter(Boolean).join(''); }
      fs.writeFileSync('gate-out.txt', g);
      log('gate: ' + g.trim().split('\n').pop());
      if (!(ok && /GATE PASS/.test(g))) {
        outcomes.s3 = 'FAIL'; state.gate_pass = false;
        log('feedback repair broke the mechanical gate');
        if (fs.existsSync('artifact-build.gatepass.txt')) {
          fs.copyFileSync('artifact-build.gatepass.txt', 'artifact-build.txt');
          state.gate_pass = true; state.s3_hash = digest(fs.readFileSync('artifact-build.txt', 'utf8'));
          log('restored gate-passing snapshot — next lap repairs from the clean baseline with S4 evidence');
        }
        break;
      }
    } else log('no gate: feedback repair accepted, S4 re-judges');
  }
  if (outcomes.s4 === 'PASS' && !s4valid) { state.s4_pass = true; state.s4_hash = digest(fs.readFileSync('artifact-build.txt', 'utf8')); }
  else if (outcomes.s4 !== 'PASS') state.s4_pass = false;
  if (outcomes.s4 === 'PASS') outcomes.route = 'DELIVERED';
  else if (outcomes.s4 === 'FAIL') { outcomes.route = 'NEEDS-CLARIFICATION'; fs.writeFileSync('clarification.md', `# Clarification needed — ${runName}\n\nS4 FAIL verdict (after feedback repair):\n\n${s4verdict}\n\n## Packet\n\`\`\`yaml\n${packet}\n\`\`\`\n`); }
} else if (outcomes.s3 === 'FAIL') {
  log('S3 gate failed after repair; routing to clarification (no S4/S5 spend)');
  const opens = [...packet.matchAll(/Q\d+[^\n]*/g)].map(m => m[0]).filter(l => /OPEN/i.test(l));
  fs.writeFileSync('clarification.md', `# Clarification needed — ${runName}\n\n## Gate output (after repair round)\n\`\`\`\n${fs.readFileSync('gate-out.txt', 'utf8')}\n\`\`\`\n\n## Open questions recorded by S1\n${opens.length ? opens.map(o => '- ' + o).join('\n') : '(none recorded)'}\n\n## Packet\n\`\`\`yaml\n${packet}\n\`\`\`\n`);
  outcomes.route = 'NEEDS-CLARIFICATION';
}

// --- S5 (skip when nothing was produced) ---
if (outcomes.route === 'NEEDS-CLARIFICATION') {
  log('egress skipped: nothing to debrief until clarification');
} else {
  checkBudget('s5');
  const s5probes = JSON.parse(fs.readFileSync(path.join(taskDir, 'probes.json'), 'utf8'));
  const s5terms = Object.entries(s5probes).map(([k, v]) => `- ${k} — acceptable forms: ${v.join(' / ')}`).join('\n');
  let s5model = seats.s5;
  for (const [attempt, m] of [['s5', s5model], ['s5-fallback', seats.s5_fallback]]) {
    seat(attempt, m, 's5-system.txt', `LOSSLESS TERMS — your debrief is mechanically probed; EACH requirement below must appear using one of its acceptable forms, verbatim:\n${s5terms}\n\n=== hdcs/1 PACKET (reverse-translate this) ===\n${packet}`, 32768);
    const args = [path.join(HERE, 'gates', 'reverse-gate.mjs'), `results/${attempt}.json`, `debrief-${attempt}.txt`, path.join(taskDir, 'probes.json')];
    let out;
    try { out = execFileSync('node', args, { encoding: 'utf8' }); }
    catch (e) { out = [e.stdout, e.stderr].filter(Boolean).join(''); }
    log(out.trim());
    if (/PASS/.test(out)) { outcomes.s5 = 'PASS (' + attempt + ')'; break; }
    outcomes.s5 = 'FAIL';
  }
}

report();
if (outcomes.route === 'NEEDS-CLARIFICATION') process.exit(2);
process.exit(Object.values(outcomes).some(v => v.startsWith('FAIL')) ? 1 : 0);
