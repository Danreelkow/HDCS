// HDCS Control Room — Host half (dynamic Cordis plugin)
// Reads /workspace/hdcs (queue, runs, LAWS.md, driver.log) via the fs Service
// and serves a compact JSON snapshot to the Client half over Package-private RPC.
//
// Mount: cordis_define code.host = this file's contents (plain JS function body).

return {
  apply(ctx) {
    const fs = ctx.get('fs')
    if (fs === undefined) {
      console.error('[hdcs-control-room] fs service unavailable — Host half idle')
      return
    }
    const ROOT = '/workspace/hdcs'

    async function readJson(p) {
      try {
        const t = await fs.resolve(p)
        return JSON.parse(await fs.readText(t))
      } catch (e) { return null }
    }
    async function readHead(p, chars) {
      try {
        const t = await fs.resolve(p)
        return (await fs.readText(t)).slice(0, chars)
      } catch (e) { return null }
    }
    async function listNames(p) {
      try {
        const t = await fs.resolve(p)
        const es = await fs.listDir(t)
        return es.map(e => String(e.name))
      } catch (e) { return [] }
    }
    async function mtimeOf(p) {
      try {
        const t = await fs.resolve(p)
        const info = await fs.stat(t)
        if (!info) return null
        if (typeof info.mtimeMs === 'number') return info.mtimeMs
        if (info.mtime) { const ms = new Date(info.mtime).getTime(); return Number.isFinite(ms) ? ms : null }
        return null
      } catch (e) { return null }
    }

    harness.handle('hdcs:snapshot', async () => {
      const out = {
        ok: true,
        root: ROOT,
        queue: { pending: [], claimed: [], parked: [], promoted: [] },
        runs: [],
        laws: [],
        tail: ''
      }

      try {
        const qnames = await listNames(ROOT + '/queue')
        for (const n of qnames) {
          if (n.endsWith('.json')) {
            const e = await readJson(ROOT + '/queue/' + n)
            out.queue.pending.push({
              task: e && e.task ? String(e.task) : n.replace(/\.json$/, ''),
              laps: e && typeof e.laps === 'number' ? e.laps : null,
              maxLaps: e && typeof e.maxLaps === 'number' ? e.maxLaps : null
            })
          } else if (n.endsWith('.claimed')) {
            out.queue.claimed.push(n.replace(/\.json\.claimed$/, '').replace(/\.claimed$/, ''))
          } else if (n === 'parked' || n === 'promoted') {
            const pnames = await listNames(ROOT + '/queue/' + n)
            for (const pn of pnames) {
              if (!pn.endsWith('.json')) continue
              const e = await readJson(ROOT + '/queue/' + n + '/' + pn)
              const note = await readHead(ROOT + '/queue/' + n + '/' + pn.replace(/\.json$/, '.note.txt'), 400)
              out.queue[n].push({
                task: e && e.task ? String(e.task) : pn.replace(/\.json$/, ''),
                laps: e && typeof e.laps === 'number' ? e.laps : null,
                maxLaps: e && typeof e.maxLaps === 'number' ? e.maxLaps : null,
                note: note ? note.trim() : ''
              })
            }
          }
        }
      } catch (e) { console.error('[hdcs-control-room] queue read failed:', e) }

      try {
        const rnames = await listNames(ROOT + '/runs')
        for (const r of rnames) {
          const dir = ROOT + '/runs/' + r
          const state = await readJson(dir + '/state.json')
          let verdict = null
          const vhead = await readHead(dir + '/s4-verdict.txt', 60)
          if (vhead) {
            const m = /VERDICT:\s*(PASS|FAIL)/.exec(vhead)
            verdict = m ? m[1] : 'present'
          }
          const proposed = await readHead(dir + '/answers.md.proposed', 700)
          out.runs.push({
            name: r,
            gatePass: state ? state.gate_pass === true : null,
            s4Pass: state ? state.s4_pass === true : null,
            verdict: verdict,
            proposed: proposed ? { excerpt: proposed.trim() } : null,
            mtime: await mtimeOf(dir)
          })
        }
        out.runs.sort(function (a, b) { return String(a.name).localeCompare(String(b.name)) })
      } catch (e) { console.error('[hdcs-control-room] runs read failed:', e) }

      try {
        const lawsText = await readHead(ROOT + '/LAWS.md', 20000)
        if (lawsText) {
          for (const line of lawsText.split('\n')) {
            const m = /^##\s+(.+)$/.exec(line)
            if (m) out.laws.push(m[1].slice(0, 110))
          }
        }
      } catch (e) { console.error('[hdcs-control-room] laws read failed:', e) }

      try {
        const t = await fs.resolve(ROOT + '/driver.log')
        const text = await fs.readText(t)
        out.tail = text.slice(-3000).split('\n').slice(-10).join('\n').trim()
      } catch (e) { /* driver.log optional */ }

      return out
    })
  },
}
