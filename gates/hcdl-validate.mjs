#!/usr/bin/env node
// hcdl packet validator v1 — mechanical (zero-LLM) gate for hdcs/1 state packets.
// Spec: /workspace/plans/hcdl-spec-v1.md §3,§6. Usage:
//   node hcdl-validate.mjs <packet.yaml> [--strict] [--must-keep "<fact>" ...] [--max-lines N]
// Exit: 0 PASS, 1 FAIL, 2 usage error. Never throws.

import { createRequire } from 'module';
const require2 = createRequire(import.meta.url);
const yaml = require2('/workspace/dsh-src/node_modules/js-yaml');

const EXPECTED_KEYS = ['reg', 'intent', 'must_keep', 'resolved', 'workflow', 'handoff', 'constraints', 'paths', 'budgets'];
const MARKERS = ['S_0 + Delta -> S_1', '+done', '-resolved', '+open', '+validation'];
const FORBIDDEN = ['chain-of-thought', 'private reasoning'];
const LIST_FIELDS = ['must_keep', 'resolved', 'constraints', 'paths'];

const args = process.argv.slice(2);
const file = args.find(a => !a.startsWith('--'));
const strict = args.includes('--strict');
const mustKeep = [];
let maxLines = 60;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--must-keep') mustKeep.push(args[++i] ?? '');
  if (args[i] === '--max-lines') maxLines = parseInt(args[++i], 10);
}
if (!file || Number.isNaN(maxLines)) {
  console.error('usage: node hcdl-validate.mjs <packet.yaml> [--strict] [--must-keep "<fact>" ...] [--max-lines N]');
  process.exit(2);
}

const violations = [];
const notes = [];
let checks = 0;
const V = (check, detail) => violations.push(`VIOLATION: ${check} — ${detail}`);

let raw;
try { raw = await import('fs').then(fs => fs.readFileSync(file, 'utf8')); }
catch (e) { console.error(`usage: cannot read ${file}: ${e.message}`); process.exit(2); }

let text = raw;
try {
  checks++;
  if (text.includes('```')) {
    if (strict) V('fence-or-marker', '``` fence present (strict mode)');
    else { text = text.replace(/^```.*$/gm, '').trimStart(); notes.push('NOTE: fence-wrapped (auto-stripped)'); }
  }
  checks++;
  if (strict && text.includes('---')) V('fence-or-marker', '--- second-document marker present (strict mode)');

  let doc;
  checks++;
  try { doc = yaml.load(text); }
  catch (e) { V('yaml-parse', `${e.name}: ${(e.message || '').split('\n')[0]}`); doc = undefined; }

  if (doc !== undefined) {
    checks++;
    if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) V('mapping', 'contract is not a mapping');
    else {
      checks++;
      const keys = Object.keys(doc);
      const extra = keys.filter(k => !EXPECTED_KEYS.includes(k));
      const missing = EXPECTED_KEYS.filter(k => !keys.includes(k));
      if (extra.length || missing.length) V('key-set', `top-level keys mismatch — extra: [${extra}], missing: [${missing}]`);

      checks++;
      const wf = doc.workflow || {};
      const wfChecks = [
        ['phases', wf.phases, ['plan', 'scoped-build', 'verify', 'deliver']],
        ['builders', wf.builders, 'dynamic'],
        ['verifier', wf.verifier, 'decorrelated'],
        ['gate', wf.gate, 'READY|NOT_READY'],
        ['max_fix_cycles', wf.max_fix_cycles, 2],
      ];
      for (const [name, got, want] of wfChecks) {
        const same = Array.isArray(want) ? JSON.stringify(got) === JSON.stringify(want) : got === want;
        if (!same) V(`workflow:${name}`, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
      }

      checks++;
      const ho = doc.handoff || {};
      if (ho.state !== 'S_0 + Delta -> S_1') V('handoff:state', `got ${JSON.stringify(ho.state)}, want "S_0 + Delta -> S_1"`);
      if (JSON.stringify(ho.report) !== JSON.stringify(['+done', '-resolved', '+open', '+validation']))
        V('handoff:report', `got ${JSON.stringify(ho.report)}, want ["+done","-resolved","+open","+validation"]`);

      checks++;
      for (const f of LIST_FIELDS) if (!Array.isArray(doc[f])) V(`list-type:${f}`, `got ${typeof doc[f]}, want list`);

      checks++;
      for (const f of LIST_FIELDS) if (Array.isArray(doc[f]) && doc[f].length === 0 && f !== 'resolved') V(`empty-list:${f}`, 'present but empty — losslessness suspect');
    }

    checks++;
    for (const m of MARKERS) if (!text.includes(m)) V('marker', `missing: ${m}`);

    checks++;
    for (const f of FORBIDDEN) if (text.toLowerCase().includes(f)) V('forbidden', `contains: ${f}`);

    checks++;
    if (mustKeep.length) {
      const low = text.toLowerCase();
      for (const k of mustKeep) if (k.toLowerCase() && !low.includes(k.toLowerCase())) V('must-keep', `missing: ${k}`);
    }
  }

  checks++;
  const lines = text.split('\n').length;
  if (lines > maxLines) V('line-cap', `${lines} lines > cap ${maxLines}`);

  for (const n of notes) console.log(n);
  for (const v of violations) console.log(v);
  const verdict = violations.length === 0 ? 'PASS' : 'FAIL';
  console.log(`hcdl: ${verdict} (${checks} checks, ${lines} lines${mustKeep.length ? `, ${mustKeep.length} must_keep` : ''})`);
  process.exit(violations.length === 0 ? 0 : 1);
} catch (e) {
  V('internal', e.message);
  for (const v of violations) console.log(v);
  console.log(`hcdl: FAIL (${checks + 1} checks, ? lines)`);
  process.exit(1);
}
