#!/usr/bin/env node
// pin-guard.mjs — managed seat-routing verification for the HDCS loop.
// Belt-and-suspenders: asserts that the model pins hard-coded in the hdcs-stack
// preset rows still agree with the roster of record (hdcs/seats.json), and that
// no excluded model is pinned anywhere. Zero LLM, exits 1 on drift.
// Run: node /workspace/hdcs/guards/pin-guard.mjs
import fs from 'node:fs';

const PRESET = '/data/dsh-home/.agent-presets/hdcs-stack/agent.cordis.yml';
const ROSTER = '/workspace/hdcs/seats.json';
const seats = JSON.parse(fs.readFileSync(ROSTER, 'utf8'));
const yml = fs.readFileSync(PRESET, 'utf8');

// Extract the `model:` line inside a named tool row block (text-level: the
// preset YAML carries harness-dialect !!js tags, so no full parse).
function pinFor(rowId) {
  const block = yml.match(new RegExp(`- id: ${rowId}\\b[\\s\\S]*?(?=\\n    - id: |\\n- id: |$)`));
  if (!block) return null;
  const m = block[0].match(/^\s+model:\s*(\S+)\s*$/m);
  return m ? m[1] : null;
}

const expected = {
  'tool-subagent-worker': seats.s3,   // B1 builder seat
  'tool-subagent-gpt': seats.s4,      // S4 verifier seat (cross-family vs s3)
};
const aux = (yml.match(/^\s+summarizationModel:\s*(\S+)\s*$/m) || [])[1] || null;

const violations = [];
const rows = [];
for (const [row, want] of Object.entries(expected)) {
  const got = pinFor(row);
  rows.push([row, got ?? '(unpinned — inherits picker!)', want]);
  if (got !== want) violations.push(`${row}: pinned '${got}' but roster of record says '${want}'`);
}
rows.push(['compaction/aux (summarizationModel)', aux ?? '(unpinned — inherits default!)', seats.s2]);
if (aux !== seats.s2) violations.push(`aux summarizer: pinned '${aux}' but roster backbone is '${seats.s2}'`);

// No excluded model may appear as ANY model pin in the preset.
for (const m of yml.matchAll(/^\s+(?:model|summarizationModel):\s*(\S+)\s*$/gm)) {
  if (seats.excluded[m[1]]) violations.push(`excluded model pinned: ${m[1]} (${seats.excluded[m[1]].split(';')[0]})`);
}

console.log('HDCS seat-pin guard — ' + PRESET);
for (const [row, got, want] of rows) console.log(`  ${row.padEnd(38)} pinned=${got.padEnd(24)} roster=${want}`);
if (violations.length) {
  console.log('\nVIOLATIONS:');
  for (const v of violations) console.log('  ✗ ' + v);
  process.exit(1);
}
console.log('\nALL PINS AGREE with the roster of record; no excluded model pinned. ✓');
