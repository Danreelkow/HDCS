// HDCS phase cue tool — static preset row (hdcs-stack/plugins/hdcs-phase.mjs).
// The agent calls hdcs_phase at every loop phase boundary; each call renders
// as a compact phase-pipeline card in the conversation flow, so the operator
// SEES the loop working (S1 → S2 → S3 → S4 → S5, current phase highlighted).
// Pure chat-surface cue: no disk I/O, no loop mutation. The kernel loop's own
// run tree remains the durable record.
export const name = 'hdcs-phase'
export const inject = ['tools']

const PHASES = ['S1', 'S2', 'S3', 'S4', 'S5']
const STATUSES = ['start', 'done', 'fail']

export async function apply(ctx) {
  ctx.tools.register({
    name: 'hdcs_phase',
    description: 'Announce an HDCS loop phase transition; renders a visual phase-pipeline cue in the chat. Call at every phase boundary: S1 start (register locked) / S1 done; S2 done (packet validated); S3 start (N workers dispatched) / S3 done; S4 done (gate verdict); S5 done (debrief delivered). Keep note to one line of plain language.',
    parameters: {
      type: 'object',
      properties: {
        phase: { type: 'string', description: 'Phase: S1 | S2 | S3 | S4 | S5' },
        status: { type: 'string', description: 'start | done | fail' },
        note: { type: 'string', description: 'One line, plain language: what is happening right now.' }
      }
    },
    execute: async function (args) {
      const phase = String((args && args.phase) || '').toUpperCase().trim()
      const status = String((args && args.status) || '').toLowerCase().trim()
      const note = String((args && args.note) || '').slice(0, 200)
      if (PHASES.indexOf(phase) === -1) return { phase: '', status: '', note: '', error: 'phase must be one of ' + PHASES.join('|') }
      if (STATUSES.indexOf(status) === -1) return { phase: '', status: '', note: '', error: 'status must be one of ' + STATUSES.join('|') }
      return { phase: phase, status: status, note: note }
    },
    output: {
      schema: {
        type: 'object',
        properties: {
          phase: { type: 'string' },
          status: { type: 'string' },
          note: { type: 'string' }
        },
        additionalProperties: true
      },
      render: function (args, value) {
        if (!value || typeof value !== 'object') return [{ type: 'text', text: String(value) }]
        const p = String(value.phase || '?')
        const s = String(value.status || '')
        return [{ type: 'text', text: 'HDCS phase ' + p + ' ' + s.toUpperCase() + (value.note ? ' — ' + String(value.note) : '') }]
      }
    }
  })
}
