# Clarification needed — 002-sync-runbook

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: RUNBOOK.md lines 4–4 assert unsupported tool behavior: “exact recursive copy (including symlinks, with stale extras removed)” is not stated in the facts block. Lines 19–19 additionally assert that the command “prints what would be synced” and exits 0, although the facts only guarantee that `--dry-run` performs zero writes. Lines 64–64 add unsupported verification-specific conditions (“destination missing, or contents differ”); the facts only specify nonzero exit on a mirror mismatch. These violate the closed-world requirement that every tool claim be in the facts block.

## Packet
```yaml
reg: {domain: cs-technical-writing, canon: runbook authoring vocabulary — imperative commands, systemd user units, env vars, exit codes, rsync mirror semantics}
intent: |
  author RUNBOOK.md := operator runbook for run-001 hermes-context sync tool;
  audience := new operator, zero prior context;
  sections := [what-it-does, test-with---dry-run, install, configure-src, schedule-timer, verify-sync, rollback-bad-sync, troubleshooting-A-numbers] in mandated order, ∀ section non-empty;
  closed_world: ∀ tool claim -> ∈ facts block; refusals cite only {A8,A9,A10,A14,A14c,A22,A23};
  executable_bar: ∀ command -> succeeds as written against runs/001-hermes-context-timer/artifact/
must_keep:
  - "documents HERMES_CONTEXT_SRC and HERMES_CONTEXT_DST exactly"
  - "includes a --dry-run test the operator can run before installing"
  - "states the documented rollback for a bad sync"
resolved:
  - "Q1: scope of tool claims? -> A: facts block is the accuracy contract; nothing else assertable (A1/A4)"
  - "Q2: register of runbook prose? -> A: plain imperative English; hcdl terms explained or omitted (A3)"
  - "Q3: rsync internal flags user-facing? -> A: no; teach only --dry-run and --verify (A4)"
  - "Q4: refusals documented? -> A: yes, as delivered (A5)"
  - "Q5: rollback content? -> A: concrete restore — remove bad HERMES_CONTEXT_DST, re-sync from configured HERMES_CONTEXT_SRC; not 'reinstall' (A6)"
  - "Q6: acceptance? -> A: S4 rubric — no command fails as written; MUST_KEEP sections non-hollow (A7)"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - closed_world: no env var, flag, default, or behavior beyond facts block asserted as the tool's
  - refusal_register := {A8, A9, A10, A14, A14c, A22, A23}; unregistered citation -> describe condition without citation
  - install must teach mkdir -p / install -D (target dirs not assumed to exist)
  - example operator paths allowed only when clearly marked as examples
  - sections in mandated order; rollback names concrete data-restore action
  - no_resurrect: rsync flags --checksum/--delete/--itemize-changes must not appear as tool flags
paths:
  - runs/001-hermes-context-timer/artifact/sync-hermes-context.sh
  - runs/001-hermes-context-timer/artifact/hermes-context.service
  - runs/001-hermes-context-timer/artifact/hermes-context.timer
  - runs/001-hermes-context-timer/artifact/README.md
  - RUNBOOK.md
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
