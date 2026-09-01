#!/usr/bin/env node
// seat.mjs — raw-model seat runner (OpenRouter REST, the PoC's model bypass).
// One seat = one completion with an explicit provider+model, no preset, no
// persona plumbing — exactly the control surface the loop's seat routing needs.
// Usage: node seat.mjs <seat> <model> <system-file> <user-file> [maxTokens=4096] [temp=0.2]
// Writes results/<seat>.json {seat, model, http, ms, usage, error, text} and
// prints a one-line summary. Exit 0 on HTTP 200 with nonempty text, 1 otherwise.
import fs from 'node:fs';

const [seat, model, sysFile, usrFile, maxT = '4096', temp = '0.2', rMax = ''] = process.argv.slice(2);
if (!seat || !model || !sysFile || !usrFile) {
  console.error('usage: node seat.mjs <seat> <model> <system-file> <user-file> [maxTokens] [temp]');
  process.exit(2);
}
const envText = fs.readFileSync('/data/dsh-home/dsh.env', 'utf8');
const m = envText.match(/OPENROUTER_API_KEY\s*=\s*"?([^"\s]+)"?/);
if (!m) { console.error('OPENROUTER_API_KEY not found in /data/dsh-home/dsh.env'); process.exit(2); }
const key = m[1];

const system = fs.readFileSync(sysFile, 'utf8');
const user = fs.readFileSync(usrFile, 'utf8');
const t0 = Date.now();
let res, body;
try {
  res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    signal: AbortSignal.timeout(420000),
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', 'X-Title': 'dsh-poc-yamlguard' },
    body: JSON.stringify({
      model, max_tokens: parseInt(maxT, 10), temperature: parseFloat(temp),
      ...(rMax ? { reasoning: { max_tokens: parseInt(rMax, 10) } } : {}),
      messages: [{ role: 'system', content: system }, { role: 'user', content: user }],
    }),
  });
  body = await res.json();
} catch (e) {
  body = { error: { message: `fetch failed: ${e.message}` } };
  res = { status: 0 };
}
const ms = Date.now() - t0;
const text = body.choices?.[0]?.message?.content ?? '';
const reasoning = body.choices?.[0]?.message?.reasoning ?? null;
const reasoning_details = body.choices?.[0]?.message?.reasoning_details ?? null;
const finish = body.choices?.[0]?.finish_reason ?? null;
const usage = body.usage ?? {};
const err = body.error?.message ?? null;
fs.mkdirSync('results', { recursive: true });
fs.writeFileSync(`results/${seat}.json`, JSON.stringify({ seat, model, http: res.status, ms, usage, finish, error: err, system, user, text, reasoning, reasoning_details }, null, 2));
const ok = res.status === 200 && text.length > 0;
console.log(`${seat}: http=${res.status} ms=${ms} in=${usage.prompt_tokens ?? '?'} out=${usage.completion_tokens ?? '?'} chars=${text.length}${err ? ' ERR: ' + err : ''}`);
process.exit(ok ? 0 : 1);
