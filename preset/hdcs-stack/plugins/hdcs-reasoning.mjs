// HDCS reasoning tool — static preset row (hdcs-stack/plugins/hdcs-reasoning.mjs).
// Mounted once with the preset's standing composition; every agent on the
// hdcs-stack preset can call it. Reads the kernel loop's run tree under
// /workspace/hdcs and surfaces what the loop reasoned in: the hcdl register
// (S1), build brief (S2), mechanical gate output, adversarial judge verdict
// (S4), and the v.txt probe — rendered as a card in the conversation flow.
//
// Guard-law shape (learned from the dynamic runner 2026-09-03, pkg-2..pkg-7):
// open parameters (no additionalProperties:false), required
// output { schema, render -> content-block array }, exactly one type per
// declared schema property (or oneOf). The static registry enforces the same
// output contract: `tool "…" must declare output { schema, render,
// presentationMeta? }`.
export const name = 'hdcs-reasoning'
export const inject = ['tools']

const ROOT = '/workspace/hdcs'

export async function apply(ctx) {
  const fs = ctx.get('fs')
  if (fs === undefined) {
    console.error('[hdcs-reasoning] fs service unavailable — tool idle')
    return
  }

  async function readJson(p) {
    try { const t = await fs.resolve(p); return JSON.parse(await fs.readText(t)) } catch (e) { return null }
  }
  async function readHead(p, chars) {
    try { const t = await fs.resolve(p); return (await fs.readText(t)).slice(0, chars) } catch (e) { return null }
  }
  async function readTail(p, chars) {
    try { const t = await fs.resolve(p); const s = await fs.readText(t); return s.length > chars ? s.slice(-chars) : s } catch (e) { return null }
  }
  async function listNames(p) {
    try { const t = await fs.resolve(p); const es = await fs.listDir(t); return es.map(e => String(e.name)) } catch (e) { return [] }
  }

  async function latestRun() {
    const names = await listNames(ROOT + '/runs')
    let best = null, bestM = -1
    for (const n of names) {
      let m = 0
      try { const t = await fs.resolve(ROOT + '/runs/' + n); const info = await fs.stat(t); if (info) m = typeof info.mtimeMs === 'number' ? info.mtimeMs : (info.mtime ? new Date(info.mtime).getTime() : 0) } catch (e) { /* skip */ }
      if (m > bestM) { bestM = m; best = n }
    }
    return best
  }

  async function buildReasoning(run) {
    const dir = ROOT + '/runs/' + run
    const state = await readJson(dir + '/state.json')
    const s4Pass = state ? state.s4_pass === true : null
    const gatePass = state ? state.gate_pass === true : null
    const v = await readTail(dir + '/v.txt', 120)
    const vMatch = v ? /PASS \(([^)]*)\)/.exec(v) : null
    const verdict = s4Pass === true ? 'PASS' : s4Pass === false ? 'FAIL' : '—'
    const summary = run + ' · gate ' + (gatePass === true ? 'PASS' : gatePass === false ? 'FAIL' : '—') + ' · S4 ' + verdict + (vMatch ? ' · hcdl ' + vMatch[0] : '')
    const sections = []
    const context = await readHead(dir + '/context.hcdl', 1500)
    if (context) sections.push({ label: 'S1 — context.hcdl (the register it reasons in)', text: context })
    const brief = await readHead(dir + '/brief.md', 800)
    if (brief) sections.push({ label: 'S2 — build brief', text: brief })
    const gate = await readTail(dir + '/gate-out.txt', 900)
    if (gate) sections.push({ label: 'GATE — mechanical verdict output', text: gate })
    const s4v = await readTail(dir + '/s4-verdict.txt', 1400)
    if (s4v) sections.push({ label: 'S4 — adversarial judge verdict', text: s4v })
    if (v && v.trim()) sections.push({ label: 'S4 — mechanical probe of the verdict (v.txt)', text: v.trim() })
    return { run: run, summary: summary, verdict: verdict, gate: gatePass, s4: s4Pass, sections: sections }
  }

  ctx.tools.register({
    name: 'hdcs_reasoning',
    description: 'Read the HDCS loop reasoning for a run: the hcdl register it reasoned in (S1), the build brief (S2), mechanical gate output, and the adversarial judge verdict (S4). Call this whenever reporting HDCS loop status or after a lap completes, so the register reasoning renders in the chat.',
    parameters: {
      type: 'object',
      properties: {
        run: { type: 'string', description: 'Run name, e.g. 007-creator-mode. Defaults to the most recently modified run.' }
      }
    },
    execute: async function (args) {
      const run = String((args && args.run) || '').replace(/[^a-zA-Z0-9._-]/g, '') || (await latestRun())
      if (!run) return { run: '', summary: 'no runs found', verdict: '', sections: [] }
      return buildReasoning(run)
    },
    output: {
      schema: {
        type: 'object',
        properties: {
          run: { type: 'string' },
          summary: { type: 'string' },
          verdict: { type: 'string' },
          sections: {
            type: 'array',
            items: {
              type: 'object',
              properties: { label: { type: 'string' }, text: { type: 'string' } },
              additionalProperties: true
            }
          }
        },
        additionalProperties: true
      },
      render: function (args, value) {
        if (!value || typeof value !== 'object') return [{ type: 'text', text: String(value) }]
        const parts = [String(value.summary || value.run || '')]
        const secs = Array.isArray(value.sections) ? value.sections : []
        for (const s of secs) parts.push('— ' + String(s.label) + ' —\n' + String(s.text || ''))
        return [{ type: 'text', text: parts.join('\n\n') }]
      }
    }
  })
}
