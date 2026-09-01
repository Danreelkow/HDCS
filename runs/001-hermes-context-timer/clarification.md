# Clarification needed — 001-hermes-context-timer

## Gate output (after repair round)
```
GATE FAIL: destination not parameterized (contract: read env HERMES_CONTEXT_DST, required)

```

## Open questions recorded by S1
(none recorded)

## Packet
```yaml
reg: {domain: cs-ops-scripting, canon: shell/systemd/rsync vocabulary — identifiers like --delete, --dry-run, ExecStart, OnCalendar, realpath, cp -a}
intent: >
  artifact_dir with sync-hermes-context.sh + hermes-context.service + hermes-context.timer
  + README.md; standing sync /opt/data/workspace/hermes-context/ -> /workspace/hermes-context/;
  rsync primary (--delete), cp/tar fallback with identical mirror semantics;
  --dry-run zero-writes; user-level systemd timer @6h; standalone-capable; guarded, self-verifying.
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical SRC/DST? -> A: /opt/data/workspace/hermes-context/ -> /workspace/hermes-context/ (A1)"
  - "Q2: sync direction? -> A: one-way host->workspace (A2)"
  - "Q3: systemd scope? -> A: user units; script standalone-capable (A3)"
  - "Q4: rsync absent? -> A: cp -a/tar fallback, contents-sync, no nesting (A4)"
  - "Q5: mirror semantics? -> A: exact mirror, recursive delete both paths (A5, A7)"
  - "Q6: dry-run log writes? -> A: zero writes incl. logs; DST byte-identical gate (A6)"
  - "Q7: log/install placement? -> A: outside DST always (~/.cache, ~/.local/bin) (A8)"
  - "Q8: verification class? -> A: contents+structure+symlinks recursive; FAIL nonzero on mismatch (A9)"
  - "Q9: severity bar? -> A: FAIL normal-op only; exotic -> KNOWN_LIMITATIONS (A10)"
  - "Q10: SRC==DST guard? -> A: realpath identity guard, no-writes refusal, no rm -rf before verified copy (A11, A12)"
  - "Q: remaining ambiguity? -> A: none; ∀ residual classified KNOWN_LIMITATIONS per A10"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "MUST_KEEP verbatim in must_keep (3 entries)"
  - "A5/A7: both sync paths converge to identical end state, recursive"
  - "A6: --dry-run zero writes; gate = DST byte-identical pre/post"
  - "A8: log outside DST; install paths outside mirrored tree"
  - "A9: verify enforces contents+structure+symlinks; mismatch -> nonzero exit"
  - "A11/A12: realpath identity guard pre-destructive, both paths; no rm -rf DST before verified SRC copy"
  - "no_resurrect: S4 verdicts A5-A12 govern; superseded accumulate-only/inside-DST-log designs may not reappear"
paths:
  - "/opt/data/workspace/hermes-context/"
  - "/workspace/hermes-context/"
  - "~/.cache/hermes-context/sync.log (log, outside DST)"
  - "~/.local/bin/sync-hermes-context.sh (install)"
  - "~/.config/systemd/user/hermes-context.{service,timer}"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
