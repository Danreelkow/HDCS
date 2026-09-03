# HDCS DSH plugin — reasoning tool card + Control Room

Dynamic Cordis plugin (session-local) with **two DSH-native surfaces** and **zero
extra windows** (operator directive 2026-09-03: extend what DSH already has —
no composer strips, no floating overlays):

1. **`hdcs_reasoning` model tool** — when the agent reports HDCS loop status it
   calls this tool; its call card renders **in the conversation flow** beside
   the Think blocks: collapsed to `∴ Δ ∀ HDCS reasoning · <run> · PASS ▸`,
   expands in place to the actual artifacts the loop reasoned in (S1
   `context.hcdl`, S2 brief, GATE output, S4 judge verdict, `v.txt` probe).
   The card view is registered at `tool.call.toolview` key `hdcs_reasoning`.
2. **Control Room** — an "HDCS" page in DSH Settings (`settings.section`,
   order 95): queue, parked tasks with notes, law drafts (`.proposed`, A29
   seam), run verdicts, canon laws, driver log tail. Read-only, 8 s refresh.

## Files

- `host.js` — fs-reading host half: RPC `hdcs:snapshot` + `hdcs:reasoning`,
  dynamic tool `hdcs_reasoning` (defineTool → registerTool inside ctx.effect).
- `client.js` — tool card view + settings page (plain JS, React.createElement).

## Mount (any DSH session)

```
cordis_define:
  plugin: { kind: "existing", pluginId: "hdcs-1" }   # or kind:"new", idPrefix:"hdcs" after a recycle
  code.host   = contents of host.js   (plain JS function body)
  code.client = contents of client.js (plain JS function body)
then: cordis_run(mode: "run" | "update")
```

Dynamic plugins die on ANY harness process recycle (plugins + grants + current
package). This directory is the remount source of record — keep it in sync with
the live pkg.

## Tool-registration guard laws (each cost one rejected run to learn, 2026-09-03)

1. `harness.defineTool({...})` mints the tool; `harness.registerTool(ctx, tool)`
   registers it. Passing a raw literal to registerTool throws.
2. `parameters` must stay **open** — no `additionalProperties: false`.
3. `output` is **required**: `{ schema, render, presentationMeta? }`.
   `render(args, value)` returns an **array of content blocks** — plain objects
   with a string `type` tag: `[{ type: 'text', text: '…' }]`. Render output is
   what the model sees; `execute`'s return value is what the card UI reads.
4. Schema compiler accepts exactly one type per declared property
   (`string/number/integer/boolean/null/array/object/json`) or `oneOf`. Union
   arrays (`type:['boolean','null']`) and empty schemas (`{}`) both throw
   `JsonSchemaError`. Undeclared fields flow through `additionalProperties: true`.
5. `registerTool` belongs inside `ctx.effect(...)` so stop/update unwinds it.

## Card data contract

The card reads `props.result` (falls back to `props.output` / `props.state.result`,
then to rendered `{type,text}` blocks). Tool result shape:
`{ run, summary, verdict: 'PASS'|'FAIL'|'—', gate, s4, sections: [{label, text}] }`.

## Deployment prerequisite

Web CSP must allow `script-src 'unsafe-eval'` (dynamic client halves evaluate
via `new Function`). Fixed 2026-09-02 in
`dsh-src/packages/host/webserver/src/security-headers.ts`. Symptom when missing:
`client-half-failed: evaluate: call to Function() blocked by CSP` — and after a
server restart the GUI auto-reconnects without reloading, so hard-refresh once
or the stale page keeps the old CSP.
