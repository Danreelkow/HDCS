// HDCS Control Room + reasoning tool — HOST half (hdcs-1/pkg-7)
// Remount: paste into cordis_define code.host (plugin kind:'existing', pluginId 'hdcs-1').
//
// GUARD LAWS learned 2026-09-03 (pkg-2..pkg-6 all rejected, pkg-7 accepted):
//  L1  Tools must be minted by harness.defineTool({...}) FIRST, then
//      harness.registerTool(ctx, tool) — registering a raw literal throws.
//  L2  parameters must stay OPEN: no `additionalProperties: false` — the
//      implicit parameter root is open for dynamic tools.
//  L3  output is REQUIRED: { schema, render, presentationMeta? }.
//      render(args, value) must return an ARRAY of content blocks —
//      plain objects with a string `type` tag: [{ type:'text', text:'...' }].
//      render output = what the MODEL sees; execute value = what the UI sees.
//  L4  Every property listed in any schema needs exactly ONE type from
//      string/number/integer/boolean/null/array/object/json (or a oneOf).
//      Union arrays (`type:['boolean','null']`) and empty schemas (`{}`)
//      both throw JsonSchemaError. Undeclared fields ride additionalProperties.
//  L5  registerTool belongs in ctx.effect(...) so stop/update removes it.

return {
  apply(ctx) {
    const fs = ctx.get('fs')
    if (fs === undefined) {
      console.error('[hdcs-control-room] fs service unavailable — Host half idle')
      return
    }
    const ROOT = '/workspace/hdcs'

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
    async function mtimeOf(p) {
      try {
        const t = await fs.resolve(p); const info = await fs.stat(t)
        if (!info) return null
        if (typeof info.mtimeMs === 'number') return info.mtimeMs
        if (info.mtime) { const ms = new Date(info.mtime).getTime(); return Number.isFinite(ms) ? ms : null }
        return null
      } catch (e) { return null }
    }

    async function latestRun() {
      const names = await listNames(ROOT + '/runs')
      let best = null, bestM = -1
      for (const n of names) {
        const m = (await mtimeOf(ROOT + '/runs/' + n)) || 0
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
      const vfull = v ? v.trim() : ''
      if (vfull) sections.push({ label: 'S4 — mechanical probe of the verdict (v.txt)', text: vfull })
      return { run: run, summary: summary, verdict: verdict, gate: gatePass, s4: s4Pass, sections: sections }
    }

    harness.handle('hdcs:snapshot', async () => {
      const out = { ok: true, root: ROOT, queue: { pending: [], claimed: [], parked: [], promoted: [] }, runs: [], laws: [], tail: '' }
      try {
        const qnames = await listNames(ROOT + '/queue')
        for (const n of qnames) {
          if (n.endsWith('.json')) {
            const e = await readJson(ROOT + '/queue/' + n)
            out.queue.pending.push({ task: e && e.task ? String(e.task) : n.replace(/\.json$/, ''), laps: e && typeof e.laps === 'number' ? e.laps : null, maxLaps: e && typeof e.maxLaps === 'number' ? e.maxLaps : null })
          } else if (n.endsWith('.claimed')) {
            out.queue.claimed.push(n.replace(/\.json\.claimed$/, '').replace(/\.claimed$/, ''))
          } else if (n === 'parked' || n === 'promoted') {
            const pnames = await listNames(ROOT + '/queue/' + n)
            for (const pn of pnames) {
              if (!pn.endsWith('.json')) continue
              const e = await readJson(ROOT + '/queue/' + n + '/' + pn)
              const note = await readHead(ROOT + '/queue/' + n + '/' + pn.replace(/\.json$/, '.note.txt'), 400)
              out.queue[n].push({ task: e && e.task ? String(e.task) : pn.replace(/\.json$/, ''), laps: e && typeof e.laps === 'number' ? e.laps : null, maxLaps: e && typeof e.maxLaps === 'number' ? e.maxLaps : null, note: note ? note.trim() : '' })
            }
          }
        }
      } catch (e) { console.error('[hdcs] queue read failed:', e) }
      try {
        const rnames = await listNames(ROOT + '/runs')
        for (const r of rnames) {
          const dir = ROOT + '/runs/' + r
          const state = await readJson(dir + '/state.json')
          let verdict = null
          const vhead = await readHead(dir + '/s4-verdict.txt', 60)
          if (vhead) { const m = /VERDICT:\s*(PASS|FAIL)/.exec(vhead); verdict = m ? m[1] : 'present' }
          const proposed = await readHead(dir + '/answers.md.proposed', 700)
          out.runs.push({ name: r, gatePass: state ? state.gate_pass === true : null, s4Pass: state ? state.s4_pass === true : null, verdict: verdict, proposed: proposed ? { excerpt: proposed.trim() } : null, mtime: await mtimeOf(dir) })
        }
        out.runs.sort(function (a, b) { return String(a.name).localeCompare(String(b.name)) })
      } catch (e) { console.error('[hdcs] runs read failed:', e) }
      try {
        const lawsText = await readHead(ROOT + '/LAWS.md', 20000)
        if (lawsText) for (const line of lawsText.split('\n')) { const m = /^##\s+(.+)$/.exec(line); if (m) out.laws.push(m[1].slice(0, 110)) }
      } catch (e) { console.error('[hdcs] laws read failed:', e) }
      try {
        const t = await fs.resolve(ROOT + '/driver.log')
        const text = await fs.readText(t)
        out.tail = text.slice(-3000).split('\n').slice(-10).join('\n').trim()
      } catch (e) { /* optional */ }
      return out
    })

    harness.handle('hdcs:reasoning', async (args) => {
      const run = String((args && args.run) || '').replace(/[^a-zA-Z0-9._-]/g, '') || (await latestRun())
      if (!run) return { ok: false, error: 'no runs found' }
      return buildReasoning(run)
    })

    const hdcsReasoningTool = harness.defineTool({
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
    ctx.effect(() => harness.registerTool(ctx, hdcsReasoningTool))
  },
}
