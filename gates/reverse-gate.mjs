#!/usr/bin/env node
// reverse-gate.mjs — mechanical egress gate: losslessness probes + notation ban + line cap.
// usage: node reverse-gate.mjs <results.json> <out.txt> <probes.json>
import fs from 'node:fs';
const [inFile, outFile, probesFile] = process.argv.slice(2);
const r = JSON.parse(fs.readFileSync(inFile, 'utf8'));
const text = (r.text ?? '').trim();
fs.writeFileSync(outFile, text);
const probes = JSON.parse(fs.readFileSync(probesFile, 'utf8'));
const notation = /[∀∃∈∧∨¬Δ∴∵≥≤→⟶]|:=|S_\d|->/;
const failed = [];
for (const [name, variants] of Object.entries(probes)) {
  if (!variants.some(v => text.toLowerCase().includes(v.toLowerCase()))) failed.push(name);
}
const lines = text.split('\n').length;
const hits = (text.match(new RegExp(notation, 'g')) || []).length;
const pass = failed.length === 0 && hits === 0 && lines <= 40;
console.log(`${inFile}: ${pass ? 'PASS' : 'FAIL'} | lossless ${failed.length === 0 ? 'OK' : 'MISSING: ' + failed.join(',')} | notation hits ${hits} | lines ${lines}`);
process.exit(pass ? 0 : 1);
