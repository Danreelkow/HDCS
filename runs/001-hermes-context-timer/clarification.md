# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: `sync-hermes-context.sh` lines 10–11 define the default `DST` with a trailing slash (`/workspace/hermes-context/`), while lines 157–166 mutate using the raw `$DST` rather than canonical `$DST_R`. After removing a missing or non-identical destination at line 162 or 164, line 166 executes `mv "$STAGE" "$DST"`; with the required default trailing-slash destination path, `mv` can fail because the destination does not yet exist as a directory. Thus a normal initial/non-identical sync does not reliably create the required exact mirror, violating the packet’s A5/A13 delivery behavior.

## Packet
```yaml
reg: {domain: cs-programming, canon: shell/systemd/rsync identifiers (rsync --delete, cp -a, systemctl --user, OnUnitActiveSec, mktemp -d, realpath), hcdl A-law}
intent: >
  deliver artifact dir: sync-hermes-context.sh (rsync, env-parameterized SRC/DST,
  --dry-run zero-write, idempotent, exact-mirror A5/A9, cp fallback converging identically,
  guard set A11/A12/A14/A15/A18/A20, stage->verify->mutate order A13) +
  hermes-context.service/.timer user units (OnCalendar every 6h, no root) + README
  (install, source change, dry-run test, A7-correct sync-strategy section).
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical SRC/DST? -> A: /opt/data/workspace/hermes-context/ -> /workspace/hermes-context/ (A1, A17: deployed defaults, env override is contract)"
  - "Q2: sync direction/semantics? -> A: host->workspace one-way, exact mirror recursive, stale subtrees deleted, both paths converge (A2, A5, A7, A9)"
  - "Q3: systemd absent? -> A: script standalone-capable; user timer preferred (A3)"
  - "Q4: rsync absent? -> A: cp -a fallback, reconcile identical to --delete (A4, A5)"
  - "Q5: dry-run writes? -> A: zero writes incl. log; nonexistent DST not created (A6, A16)"
  - "Q6: log/staging/install placement? -> A: log outside DST always; entrypoints outside mirrored tree; concrete-path boundary guards (A8, A14, A15)"
  - "Q7: verification bar? -> A: A9 class contents+structure+symlinks, nonzero on mismatch, content-compared staging (A9, A13)"
  - "Q8: severity/stopping? -> A: A10 normal-operation bar; residual adversarial env = KNOWN_LIMITATIONS non-blocking"
  - "Q9: degenerate/identity paths? -> A: component-test refusals for /,empty,.; realpath identity guards; refusals cite A-numbers (A18, A19)"
  - "Q10: staging order? -> A: pure string-resolve stage path, validate, then create; reserved namespace never collides with mirror files (A20)"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "A5/A7/A9 exact-mirror convergence, recursive, both sync paths"
  - "A6/A16 dry-run zero-write incl. log; leaves nonexistent DST uncreated"
  - "A11/A13 stage -> content-verify -> mutate; never rm -rf DST before verified copy"
  - "A12/A14/A15/A18/A19/A20 guard set; refusals clean nonzero, zero writes, cite A-number"
  - "A3/A4 no-root user units; rsync-optional standalone script"
paths:
  - "/opt/data/workspace/hermes-context/"
  - "/workspace/hermes-context/"
  - "~/.local/bin (entrypoints, outside mirrored tree)"
  - "~/.cache (log parent, outside DST)"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 0}
```
