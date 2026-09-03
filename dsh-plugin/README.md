# HDCS Control Room — DSH plugin

A read-only live dashboard over the HDCS loop, rendered as an **"HDCS" page in
DSH Settings** (dynamic Cordis plugin, session-local).

Panels: queue (pending / running / parked / promoted) · law drafts awaiting the
operator (`.proposed`, A29 seam) · run verdicts (GATE / S4 / judge) · canon
laws (`LAWS.md`) · driver log tail. Refreshes every 8 s. It never mutates the
loop — approvals and rulings happen in the HDCS chat.

## Mount (one step, any DSH session)

```
cordis_define:
  plugin: { kind: "new", idPrefix: "hdcs" }
  name: "HDCS Control Room"
  purpose: <one line>
  code.host   = contents of host.js   (plain JS function body)
  code.client = contents of client.js (plain JS function body)
then: cordis_run(mode: "run")
```

The Host half reads `/workspace/hdcs` through the DSH `fs` Service and serves a
compact JSON snapshot over Package-private RPC (`hdcs:snapshot`). The Client
half registers a `settings.section` slot component. No files are written.

## Deployment prerequisite

The web server CSP baseline must allow `script-src 'unsafe-eval'`: dynamic
client halves are evaluated with `new Function` (cordis-client-runner,
`evaluateClientHalf`). Fixed 2026-09-02 in
`dsh-src/packages/host/webserver/src/security-headers.ts`; takes effect when
the harness process restarts. Symptom when missing:
`client-half-failed: evaluate: call to Function() blocked by CSP`.
