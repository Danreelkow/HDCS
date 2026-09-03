// HDCS Control Room — Client half (dynamic Cordis plugin)
// Renders the snapshot from 'hdcs:snapshot' as a "HDCS" page in DSH Settings.
// Refreshes every 8s; strictly read-only (approvals stay in the HDCS chat, A29).
//
// Mount: cordis_define code.client = this file's contents (plain JS function body).
// Requires: inject ['timer']; slots service; React/host/styles builtins.

return {
  inject: ['timer'],
  async apply(ctx) {
    const slots = ctx.get('slots')
    if (slots === undefined) return

    styles.insert([
      '.hdcs-cr { display:flex; flex-direction:column; gap:18px; max-width:860px; padding:4px 2px 32px; }',
      '.hdcs-cr h2 { margin:0; font-size:18px; letter-spacing:0.02em; }',
      '.hdcs-cr .hdcs-sub { color:var(--dsw-alias-label-secondary,#888); font-size:12.5px; margin-top:2px; }',
      '.hdcs-cr .hdcs-row { display:flex; align-items:center; gap:10px; flex-wrap:wrap; }',
      '.hdcs-cr .hdcs-pill { display:inline-flex; align-items:center; gap:6px; font-size:11.5px; padding:2px 10px; border-radius:999px; border:1px solid var(--dsw-alias-border-l1,rgba(128,128,128,.3)); }',
      '.hdcs-cr .hdcs-dot { width:8px; height:8px; border-radius:50%; background:var(--dsw-alias-state-success-primary,#3fb950); }',
      '.hdcs-cr .hdcs-dot.busy { background:var(--dsw-alias-state-warn-primary,#d29922); }',
      '.hdcs-cr .hdcs-dot.err { background:var(--dsw-alias-state-error-primary,#f85149); }',
      '.hdcs-cr .hdcs-panel { border:1px solid var(--dsw-alias-border-l1,rgba(128,128,128,.25)); border-radius:10px; background:var(--dsw-alias-bg-layer-1,rgba(127,127,127,.06)); padding:12px 14px; }',
      '.hdcs-cr .hdcs-panel > h3 { margin:0 0 8px; font-size:11px; text-transform:uppercase; letter-spacing:0.12em; color:var(--dsw-alias-label-secondary,#888); font-weight:600; }',
      '.hdcs-cr .hdcs-chip { display:inline-flex; align-items:center; gap:6px; font-size:12px; padding:3px 9px; margin:0 6px 6px 0; border-radius:7px; border:1px solid var(--dsw-alias-border-l1,rgba(128,128,128,.25)); background:var(--dsw-alias-bg-layer-2,rgba(127,127,127,.08)); font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; }',
      '.hdcs-cr .hdcs-chip .lap { color:var(--dsw-alias-label-secondary,#888); font-family:inherit; }',
      '.hdcs-cr .hdcs-proposed { border-left:3px solid var(--dsw-alias-brand-primary,#58a6ff); }',
      '.hdcs-cr .hdcs-pre { margin:6px 0 0; white-space:pre-wrap; word-break:break-word; font-size:11.5px; line-height:1.55; font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; color:var(--dsw-alias-label-secondary,#999); max-height:260px; overflow:auto; }',
      '.hdcs-cr .hdcs-runline { display:flex; align-items:center; gap:10px; padding:5px 0; border-bottom:1px dashed var(--dsw-alias-border-l1,rgba(128,128,128,.15)); font-size:12.5px; flex-wrap:wrap; }',
      '.hdcs-cr .hdcs-runline:last-child { border-bottom:none; }',
      '.hdcs-cr .hdcs-runname { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; min-width:220px; }',
      '.hdcs-cr .hdcs-tag { font-size:10.5px; padding:1px 7px; border-radius:5px; border:1px solid var(--dsw-alias-border-l1,rgba(128,128,128,.3)); color:var(--dsw-alias-label-secondary,#888); }',
      '.hdcs-cr .hdcs-tag.pass { color:var(--dsw-alias-state-success-primary,#3fb950); border-color:currentColor; }',
      '.hdcs-cr .hdcs-tag.fail { color:var(--dsw-alias-state-error-primary,#f85149); border-color:currentColor; }',
      '.hdcs-cr .hdcs-law { font-size:12px; padding:3px 0; }',
      '.hdcs-cr .hdcs-law .num { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; color:var(--dsw-alias-brand-primary,#58a6ff); margin-right:8px; }',
      '.hdcs-cr .hdcs-empty { color:var(--dsw-alias-label-secondary,#888); font-size:12px; font-style:italic; }',
      '.hdcs-cr .hdcs-foot { font-size:11px; color:var(--dsw-alias-label-secondary,#888); }',
      '.hdcs-cr .hdcs-note { font-size:11.5px; color:var(--dsw-alias-label-secondary,#888); margin:4px 0 0; white-space:pre-wrap; }'
    ].join('\n'))

    function Pill(props) {
      const cls = 'hdcs-dot' + (props.state === 'busy' ? ' busy' : props.state === 'err' ? ' err' : '')
      return React.createElement('span', { className: 'hdcs-pill' },
        React.createElement('span', { className: cls }), String(props.text))
    }
    function Tag(props) {
      const txt = props.ok === true ? 'PASS' : props.ok === false ? 'FAIL' : '—'
      const cls = 'hdcs-tag' + (props.ok === true ? ' pass' : props.ok === false ? ' fail' : '')
      return React.createElement('span', { className: cls }, props.label + ' ' + txt)
    }
    function Chip(props) {
      return React.createElement('span', { className: 'hdcs-chip' }, String(props.name),
        props.laps != null ? React.createElement('span', { className: 'lap' }, ' ' + String(props.laps) + '/' + String(props.maxLaps == null ? '?' : props.maxLaps)) : null)
    }

    function ControlRoom() {
      const [snap, setSnap] = React.useState(null)
      const [err, setErr] = React.useState('')
      React.useEffect(() => {
        let alive = true
        const load = async () => {
          try {
            const r = await host.call('hdcs:snapshot')
            if (alive) { setSnap(r); setErr('') }
          } catch (e) {
            if (alive) setErr(String((e && e.message) || e))
          }
        }
        load()
        const stop = ctx.interval(load, 8000)
        return () => { alive = false; stop() }
      }, [])

      if (err) {
        return React.createElement('div', { className: 'hdcs-cr' },
          React.createElement('h2', null, 'HDCS Control Room'),
          React.createElement(Pill, { state: 'err', text: 'link error: ' + err }))
      }
      if (!snap || !snap.ok) {
        return React.createElement('div', { className: 'hdcs-cr' },
          React.createElement('h2', null, 'HDCS Control Room'),
          React.createElement('div', { className: 'hdcs-empty' }, 'connecting to /workspace/hdcs …'))
      }

      const q = snap.queue
      const pending = Array.isArray(q.pending) ? q.pending : []
      const claimed = Array.isArray(q.claimed) ? q.claimed : []
      const parked = Array.isArray(q.parked) ? q.parked : []
      const promoted = Array.isArray(q.promoted) ? q.promoted : []
      const busy = (pending.length + claimed.length) > 0
      const proposedRuns = snap.runs.filter(function (r) { return r.proposed })
      const laws = Array.isArray(snap.laws) ? snap.laws : []

      const queuePanel = React.createElement('div', { className: 'hdcs-panel', key: 'q' },
        React.createElement('h3', null, 'Queue'),
        pending.length === 0 && claimed.length === 0 && parked.length === 0 && promoted.length === 0
          ? React.createElement('div', { className: 'hdcs-empty' }, 'idle — queue empty, all laps settled')
          : React.createElement('div', null,
            pending.length > 0 ? React.createElement('div', { className: 'hdcs-row', style: { marginBottom: '4px' } },
              pending.map(function (t, i) { return React.createElement(Chip, { key: 'p' + i, name: t.task, laps: t.laps, maxLaps: t.maxLaps }) })) : null,
            claimed.length > 0 ? React.createElement('div', { className: 'hdcs-row', style: { marginBottom: '4px' } },
              claimed.map(function (n, i) { return React.createElement(Chip, { key: 'c' + i, name: n + ' (running)' }) })) : null,
            parked.length > 0 ? React.createElement('div', null,
              parked.map(function (t, i) {
                return React.createElement('div', { key: 'k' + i, style: { marginBottom: '6px' } },
                  React.createElement(Chip, { name: t.task + ' (parked)', laps: t.laps, maxLaps: t.maxLaps }),
                  t.note ? React.createElement('div', { className: 'hdcs-note' }, String(t.note).slice(0, 300)) : null)
              })) : null,
            promoted.length > 0 ? React.createElement('div', null,
              promoted.map(function (t, i) { return React.createElement(Chip, { key: 'pr' + i, name: t.task + ' (promoted)' }) })) : null))

      const proposedPanel = React.createElement('div', { className: 'hdcs-panel hdcs-proposed', key: 'prop' },
        React.createElement('h3', null, 'Law drafts — awaiting operator decision (A29)'),
        proposedRuns.length === 0
          ? React.createElement('div', { className: 'hdcs-empty' }, 'no .proposed drafts pending')
          : proposedRuns.map(function (r, i) {
            return React.createElement('div', { key: 'd' + i, style: { marginBottom: '10px' } },
              React.createElement('div', { className: 'hdcs-runname' }, r.name),
              React.createElement('pre', { className: 'hdcs-pre' }, String(r.proposed.excerpt || '')))
          }))

      const runsPanel = React.createElement('div', { className: 'hdcs-panel', key: 'r' },
        React.createElement('h3', null, 'Runs'),
        snap.runs.length === 0
          ? React.createElement('div', { className: 'hdcs-empty' }, 'no runs yet')
          : snap.runs.map(function (r, i) {
            return React.createElement('div', { className: 'hdcs-runline', key: i },
              React.createElement('span', { className: 'hdcs-runname' }, r.name),
              React.createElement(Tag, { label: 'gate', ok: r.gatePass }),
              React.createElement(Tag, { label: 'S4', ok: r.s4Pass }),
              r.verdict === 'PASS' ? React.createElement(Tag, { label: 'judge', ok: true })
                : r.verdict === 'FAIL' ? React.createElement(Tag, { label: 'judge', ok: false }) : null,
              r.mtime ? React.createElement('span', { className: 'hdcs-tag' }, new Date(r.mtime).toISOString().slice(0, 16).replace('T', ' ')) : null)
          }))

      const lawsPanel = React.createElement('div', { className: 'hdcs-panel', key: 'l' },
        React.createElement('h3', null, 'Canon laws — LAWS.md'),
        laws.length === 0
          ? React.createElement('div', { className: 'hdcs-empty' }, 'canon not found')
          : laws.map(function (l, i) {
            const idx = l.indexOf(' — ')
            const num = idx > 0 ? l.slice(0, idx) : l.slice(0, 6)
            const rest = idx > 0 ? l.slice(idx + 3) : l.slice(6)
            return React.createElement('div', { className: 'hdcs-law', key: i },
              React.createElement('span', { className: 'num' }, num), rest)
          }))

      const tailPanel = React.createElement('div', { className: 'hdcs-panel', key: 't' },
        React.createElement('h3', null, 'Driver log (tail)'),
        snap.tail ? React.createElement('pre', { className: 'hdcs-pre' }, snap.tail) : React.createElement('div', { className: 'hdcs-empty' }, 'no driver.log yet'))

      return React.createElement('div', { className: 'hdcs-cr' },
        React.createElement('div', null,
          React.createElement('div', { className: 'hdcs-row' },
            React.createElement('h2', null, 'HDCS Control Room'),
            React.createElement(Pill, { state: busy ? 'busy' : 'ok', text: busy ? 'loop active' : 'idle' })),
          React.createElement('div', { className: 'hdcs-sub' }, snap.root + ' · refreshes every 8s · read-only')),
        queuePanel,
        proposedPanel,
        runsPanel,
        lawsPanel,
        tailPanel,
        React.createElement('div', { className: 'hdcs-foot' }, 'Approve or answer parked tasks and law drafts in the HDCS chat — this panel never mutates the loop.'))
    }

    slots.inject('settings.section', () => slots.register(
      { name: 'settings.section', id: 'hdcs-control-room', order: 95, label: 'HDCS' },
      () => React.createElement(ControlRoom)))
  },
}
