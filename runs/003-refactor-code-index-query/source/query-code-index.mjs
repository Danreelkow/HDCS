#!/usr/bin/env node
// Query the dsh-src code index.
// Usage: node query-code-index.mjs <substring> [--kind class|function|interface|type|const|enum|method|property] [--pkg <name>] [--limit N]
import fs from 'node:fs'
import { execSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'

const usage = () => {
  console.error('usage: node query-code-index.mjs <substring> [--kind class|function|interface|type|const|enum|method|property] [--pkg <name>] [--limit N]')
}
const die = (msg, code = 1) => { console.error(msg); process.exit(code) }

const args = process.argv.slice(2)
let sub = null, kind = null, pkg = null, limit = 10
for (let i = 0; i < args.length; i++) {
  const a = args[i]
  if (a === '--kind') kind = args[++i]
  else if (a === '--pkg') pkg = args[++i]
  else if (a === '--limit') limit = parseInt(args[++i], 10)
  else if (a === '-h' || a === '--help') { usage(); process.exit(0) }
  else if (sub === null) sub = a
  else die(`unexpected argument: ${a}\n` , 2)
}
if (!sub) { usage(); process.exit(2) }
if (!Number.isFinite(limit) || limit < 1) die('--limit must be a positive integer', 2)
limit = Math.min(limit, 200) // bounded output

const indexPath = fileURLToPath(new URL('../code-index/index.json', import.meta.url))
const repoPath = '/workspace/dsh-src'

// Pull-based freshness: if the repo moved since the build, rebuild inline
// (~2.5s) so every query serves current data even without the cron watchdog.
// Best-effort — a failed rebuild must never block a query (stale beats dead).
try {
  const cur = JSON.parse(fs.readFileSync(indexPath, 'utf8'))
  const liveHead = execSync(`git -C ${repoPath} rev-parse --short=7 HEAD`, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim()
  const liveDirty = createHash('sha1').update(execSync(`git -C ${repoPath} status --porcelain`, { stdio: ['ignore', 'pipe', 'ignore'] }).toString()).digest('hex').slice(0, 10)
  const meta = cur.meta || {}
  if (meta.repoHead !== liveHead || meta.repoDirtyHash !== liveDirty) {
    console.error('-- index stale (repo moved since build); rebuilding inline... --')
    execSync('node ' + fileURLToPath(new URL('./build-code-index.mjs', import.meta.url)), { stdio: ['ignore', 'inherit', 'inherit'] })
  }
} catch (e) {
  console.error(`-- freshness check skipped: ${e.message} --`)
}

let index
try { index = JSON.parse(fs.readFileSync(indexPath, 'utf8')) } catch (e) { die(`cannot read index at ${indexPath}: ${e.message}`) }

const needle = sub.toLowerCase()
const t0 = Date.now()
const hits = index.symbols.filter((s) =>
  (!kind || s.kind === kind) &&
  (!pkg || s.pkg === pkg || s.pkg.includes(pkg)) &&
  s.name.toLowerCase().includes(needle),
)

// Usage telemetry (JSONL, one line per query) — answers "is the index used?"
// Best-effort only: a logging failure must never break a query.
try {
  fs.appendFileSync(
    fileURLToPath(new URL('../code-index/usage.log', import.meta.url)),
    JSON.stringify({ ts: new Date().toISOString(), sub, kind, pkg, hits: hits.length, ms: Date.now() - t0 }) + '\n',
  )
} catch {}

if (hits.length === 0) die(`no symbols matching "${sub}"${kind ? ` [kind=${kind}]` : ''}${pkg ? ` [pkg=${pkg}]` : ''} in index (${index.symbols.length} symbols, generated ${index.generated})`)

for (const h of hits.slice(0, limit)) {
  console.log([h.name, h.kind, h.pkg, `${h.file}:${h.line}`, h.doc || ''].join('  '))
}
console.error(`-- ${hits.length} hit(s), showing ${Math.min(limit, hits.length)} --`)
