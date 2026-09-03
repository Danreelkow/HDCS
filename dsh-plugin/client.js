// HDCS reasoning tool card + Control Room — CLIENT half (hdcs-1/pkg-7)
// Remount: paste into cordis_define code.client (plugin kind:'existing', pluginId 'hdcs-1').
//
// Two surfaces, both DSH-native (per operator directive 2026-09-03: no extra
// windows — extend what DSH already has):
//   1. tool.call.toolview keyed 'hdcs_reasoning' — the card for the dynamic
//      hdcs_reasoning tool. Renders IN the conversation flow, collapsed to a
//      one-line header (Think-style), expands in place to the register/brief/
//      gate/verdict sections. No overlay, no dock.
//   2. settings.section 'hdcs-control-room' — the Control Room page.
//
// Card contract: reads props.result (execute's value). If the card ever
// receives rendered content blocks instead, it falls back to rendering their
// text (extractResult handles arrays of {type,text}).

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
      '.hdcs-cr .hdcs-chip .lap { color:var(--dsw-alias-label-secondary,#888); }',
      '.hdcs-cr .hdcs-proposed { border-left:3px solid var(--dsw-alias-brand-primary,#58a6ff); }',
      '.hdcs-cr .hdcs-pre { margin:6px 0 0; white-space:pre-wrap; word-break:break-word; font-size:11.5px; line-height:1.55; font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; color:var(--dsw-alias-label-secondary,#999); max-height:260px; overflow:auto; }',
      '.hdcs-cr .hdcs-runline { display:flex; align-items:center; gap:10px; padding:5px 0; border-bottom:1px dashed var(--dsw-alias-border-l1,rgba(128,128,128,.15)); font-size:12.5px; flex-wrap:wrap; }',
      '.hdcs-cr .hdcs-runname { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; min-width:220px; }',
      '.hdcs-cr .hdcs-tag { font-size:10.5px; padding:1px 7px; border-radius:5px; border:1px solid var(--dsw-alias-border-l1,rgba(128,128,128,.3)); color:var(--dsw-alias-label-secondary,#888); }',
      '.hdcs-cr .hdcs-tag.pass { color:var(--dsw-alias-state-success-primary,#3fb950); border-color:currentColor; }',
      '.hdcs-cr .hdcs-tag.fail { color:var(--dsw-alias-state-error-primary,#f85149); border-color:currentColor; }',
      '.hdcs-cr .hdcs-law { font-size:12px; padding:3px 0; }',
      '.hdcs-cr .hdcs-law .num { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; color:var(--dsw-alias-brand-primary,#58a6ff); margin-right:8px; }',
      '.hdcs-cr .hdcs-empty { color:var(--dsw-alias-label-secondary,#888); font-size:12px; font-style:italic; }',
      '.hdcs-cr .hdcs-foot { font-size:11px; color:var(--dsw-alias-label-secondary,#888); }',
      '.hdcs-cr .hdcs-note { font-size:11.5px; color:var(--dsw-alias-label-secondary,#888); margin:4px 0 0; white-space:pre-wrap; }',
      '.hdcs-tv { margin:2px 0; border:1px solid var(--dsw-alias-border-l1,rgba(128,128,128,.22)); border-radius:9px; background:var(--dsw-alias-bg-layer-1,rgba(127,127,127,.05)); overflow:hidden; }',
      '.hdcs-tv .hdcs-tv-head { display:flex; align-items:center; gap:8px; padding:7px 12px; cursor:pointer; user-select:none; font-size:12px; color:var(--dsw-alias-label-secondary,#999); }',
      '.hdcs-tv .hdcs-tv-head:hover { color:var(--dsw-alias-label-primary,#ccc); }',
      '.hdcs-tv .hdcs-tv-glyph { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; color:var(--dsw-alias-brand-primary,#58a6ff); letter-spacing:1.5px; font-size:11.5px; }',
      '.hdcs-tv .hdcs-tv-run { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; color:var(--dsw-alias-label-primary,#ccc); }',
      '.hdcs-tv .hdcs-tv-verdict { margin-left:auto; font-size:10.5px; padding:1px 7px; border-radius:5px; border:1px solid var(--dsw-alias-border-l1,rgba(128,128,128,.3)); color:var(--dsw-alias-label-secondary,#888); }',
      '.hdcs-tv .hdcs-tv-verdict.pass { color:var(--dsw-alias-state-success-primary,#3fb950); border-color:currentColor; }',
      '.hdcs-tv .hdcs-tv-verdict.fail { color:var(--dsw-alias-state-error-primary,#f85149); border-color:currentColor; }',
      '.hdcs-tv .hdcs-tv-chev { font-size:10px; opacity:.7; }',
      '.hdcs-tv .hdcs-tv-body { border-top:1px solid var(--dsw-alias-border-l1,rgba(128,128,128,.18)); padding:8px 12px 10px; display:flex; flex-direction:column; gap:8px; }',
      '.hdcs-tv .hdcs-tv-lbl { font-size:9.5px; text-transform:uppercase; letter-spacing:.14em; color:var(--dsw-alias-label-secondary,#888); }',
      '.hdcs-tv pre { margin:0; white-space:pre-wrap; word-break:break-word; font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; font-size:11.5px; line-height:1.6; color:var(--dsw-alias-label-secondary,#b8b8bc); }',
      '.hdcs-tv .hdcs-tv-sec.verdict pre { color:var(--dsw-alias-label-primary,#ddd); }'
    ].join('\n'))

    function extractResult(props) {
      let r = props && (props.result !== undefined ? props.result : (props.output !== undefined ? props.output : (props.state && props.state.result !== undefined ? props.state.result : null)))
      if (typeof r === 'string') { try { r = JSON.parse(r) } catch (e) { return { summary: r.slice(0, 140), sections: [] } } }
      if (Array.isArray(r)) {
        const texts = []
        for (const b of r) { if (b && typeof b === 'object' && typeof b.text === 'string') texts.push(b.text) }
        if (texts.length) return { summary: texts[0].split('\n')[0].slice(0, 140), sections: [{ label: 'tool result', text: texts.join('\n\n') }] }
        return null
      }
      if (!r || typeof r !== 'object') return null
      return r
    }

    function HdcsToolCard(props) {
      const [open, setOpen] = React.useState(false)
      const r = extractResult(props)
      if (!r) return null
      const sections = Array.isArray(r.sections) ? r.sections : []
      const verdict = String(r.verdict || '')
      const vClass = verdict.indexOf('PASS') === 0 ? ' pass' : verdict.indexOf('FAIL') === 0 ? ' fail' : ''
      return React.createElement('div', { className: 'hdcs-tv' },
        React.createElement('div', { className: 'hdcs-tv-head', onClick: function () { setOpen(!open) } },
          React.createElement('span', { className: 'hdcs-tv-glyph' }, '∴ Δ ∀'),
          React.createElement('span', null, 'HDCS reasoning'),
          r.run ? React.createElement('span', { className: 'hdcs-tv-run' }, String(r.run)) : null,
          verdict ? React.createElement('span', { className: 'hdcs-tv-verdict' + vClass }, verdict) : null,
          React.createElement('span', { className: 'hdcs-tv-chev' }, open ? '▾' : '▸')),
        open ? React.createElement('div', { className: 'hdcs-tv-body' },
          sections.map(function (s, i) {
            return React.createElement('div', { className: 'hdcs-tv-sec' + (String(s.label).indexOf('S4') === 0 ? ' verdict' : ''), key: i },
              React.createElement('div', { className: 'hdcs-tv-lbl' }, String(s.label)),
              React.createElement('pre', null, String(s.text || '')))
          })) : null)
    }

    slots.inject('tool.call.toolview', () => slots.register(
      { name: 'tool.call.toolview', key: 'hdcs_reasoning' },
      (props) => React.createElement(HdcsToolCard, props)))

    function ControlRoom() {
      const [snap, setSnap] = React.useState(null)
      const [err, setErr] = React.useState('')
      React.useEffect(() => {
        let alive = true
        const load = async () => {
          try { const r = await host.call('hdcs:snapshot'); if (alive) { setSnap(r); setErr('') } }
          catch (e) { if (alive) setErr(String((e && e.message) || e)) }
        }
        load()
        const stop = ctx.interval(load, 8000)
        return () => { alive = false; stop() }
      }, [])
      if (err) return React.createElement('div', { className: 'hdcs-cr' }, React.createElement('h2', null, 'HDCS Control Room'), React.createElement('span', { className: 'hdcs-pill' }, React.createElement('span', { className: 'hdcs-dot err' }), 'link error: ' + err))
      if (!snap || !snap.ok) return React.createElement('div', { className: 'hdcs-cr' }, React.createElement('h2', null, 'HDCS Control Room'), React.createElement('div', { className: 'hdcs-empty' }, 'connecting to /workspace/hdcs …'))
      const q = snap.queue
      const pending = Array.isArray(q.pending) ? q.pending : []
      const claimed = Array.isArray(q.claimed) ? q.claimed : []
      const parked = Array.isArray(q.parked) ? q.parked : []
      const promoted = Array.isArray(q.promoted) ? q.promoted : []
      const busy = (pending.length + claimed.length) > 0
      const proposedRuns = snap.runs.filter(function (r) { return r.proposed })
      const laws = Array.isArray(snap.laws) ? snap.laws : []
      return React.createElement('div', { className: 'hdcs-cr' },
        React.createElement('div', null,
          React.createElement('div', { className: 'hdcs-row' },
            React.createElement('h2', null, 'HDCS Control Room'),
            React.createElement('span', { className: 'hdcs-pill' }, React.createElement('span', { className: 'hdcs-dot' + (busy ? ' busy' : '') }), busy ? 'loop active' : 'idle')),
          React.createElement('div', { className: 'hdcs-sub' }, snap.root + ' · refreshes every 8s · read-only')),
        React.createElement('div', { className: 'hdcs-panel', key: 'q' },
          React.createElement('h3', null, 'Queue'),
          pending.length === 0 && claimed.length === 0 && parked.length === 0 && promoted.length === 0
            ? React.createElement('div', { className: 'hdcs-empty' }, 'idle — queue empty, all laps settled')
            : React.createElement('div', null,
              pending.map(function (t, i) { return React.createElement('span', { className: 'hdcs-chip', key: 'p' + i }, t.task, t.laps != null ? React.createElement('span', { className: 'lap' }, ' ' + t.laps + '/' + (t.maxLaps == null ? '?' : t.maxLaps)) : null) }),
              claimed.map(function (n, i) { return React.createElement('span', { className: 'hdcs-chip', key: 'c' + i }, n + ' (running)') }),
              parked.map(function (t, i) { return React.createElement('div', { key: 'k' + i }, React.createElement('span', { className: 'hdcs-chip' }, t.task + ' (parked)'), t.note ? React.createElement('div', { className: 'hdcs-note' }, String(t.note).slice(0, 300)) : null) }),
              promoted.map(function (t, i) { return React.createElement('span', { className: 'hdcs-chip', key: 'pr' + i }, t.task + ' (promoted)') }))),
        React.createElement('div', { className: 'hdcs-panel hdcs-proposed', key: 'prop' },
          React.createElement('h3', null, 'Law drafts — awaiting operator decision (A29)'),
          proposedRuns.length === 0 ? React.createElement('div', { className: 'hdcs-empty' }, 'no .proposed drafts pending') :
            proposedRuns.map(function (r, i) { return React.createElement('div', { key: 'd' + i }, React.createElement('div', { className: 'hdcs-runname' }, r.name), React.createElement('pre', { className: 'hdcs-pre' }, String(r.proposed.excerpt || ''))) })),
        React.createElement('div', { className: 'hdcs-panel', key: 'r' },
          React.createElement('h3', null, 'Runs'),
          snap.runs.map(function (r, i) {
            return React.createElement('div', { className: 'hdcs-runline', key: i },
              React.createElement('span', { className: 'hdcs-runname' }, r.name),
              React.createElement('span', { className: 'hdcs-tag' + (r.gatePass === true ? ' pass' : r.gatePass === false ? ' fail' : '') }, 'gate ' + (r.gatePass === true ? 'PASS' : r.gatePass === false ? 'FAIL' : '—')),
              React.createElement('span', { className: 'hdcs-tag' + (r.s4Pass === true ? ' pass' : r.s4Pass === false ? ' fail' : '') }, 'S4 ' + (r.s4Pass === true ? 'PASS' : r.s4Pass === false ? 'FAIL' : '—')),
              r.verdict === 'PASS' ? React.createElement('span', { className: 'hdcs-tag pass' }, 'judge PASS') : r.verdict === 'FAIL' ? React.createElement('span', { className: 'hdcs-tag fail' }, 'judge FAIL') : null,
              r.mtime ? React.createElement('span', { className: 'hdcs-tag' }, new Date(r.mtime).toISOString().slice(0, 16).replace('T', ' ')) : null)
          })),
        React.createElement('div', { className: 'hdcs-panel', key: 'l' },
          React.createElement('h3', null, 'Canon laws — LAWS.md'),
          laws.map(function (l, i) {
            const idx = l.indexOf(' — ')
            return React.createElement('div', { className: 'hdcs-law', key: i }, React.createElement('span', { className: 'num' }, idx > 0 ? l.slice(0, idx) : l.slice(0, 6)), idx > 0 ? l.slice(idx + 3) : l.slice(6))
          })),
        React.createElement('div', { className: 'hdcs-panel', key: 't' },
          React.createElement('h3', null, 'Driver log (tail)'),
          snap.tail ? React.createElement('pre', { className: 'hdcs-pre' }, snap.tail) : React.createElement('div', { className: 'hdcs-empty' }, 'no driver.log yet')),
        React.createElement('div', { className: 'hdcs-foot' }, 'Approvals happen in HDCS chat — this panel never mutates the loop (A29).'))
    }

    slots.inject('settings.section', () => slots.register(
      { name: 'settings.section', id: 'hdcs-control-room', order: 95, label: 'HDCS' },
      () => React.createElement(ControlRoom)))
  },
}
