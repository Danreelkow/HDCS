# Clarification needed — 001-hermes-context-timer

## Gate output (after repair round)
```
GATE FAIL: README does not document the service ExecStart location: /.local/bin/sync-hermes-context (docs must match the unit)

```

## Open questions recorded by S1
(none recorded)

## Packet
```yaml
reg: {domain: cs-programming, canon: shell/systemd ops vocabulary — rsync flags, systemctl --user, unit directives, realpath, exit codes}
intent: >
  deliver artifact dir with sync-hermes-context.sh (rsync primary, cp/tar fallback,
  --dry-run zero-write, idempotent, one-line summary log, A11/A12/A13/A14 guards,
  A9-class self-verification) + hermes-context.service/.timer (systemctl --user,
  OnCalendar every 6h) + README (install, source-change, dry-run test, A7 sync-strategy
  wording); standing one-way mirror SRC -> DST per A5/A9.
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical SRC/DST? -> A: /opt/data/workspace/hermes-context/ -> /workspace/hermes-context/ (A1)"
  - "Q2: sync direction? -> A: one-way host -> workspace, no writeback (A2)"
  - "Q3: scheduler? -> A: user timer, standalone fallback (A3)"
  - "Q4: rsync absent? -> A: cp -a/tar fallback, contents-sync, no nesting (A4)"
  - "Q5: stale files? -> A: exact recursive mirror, delete, both paths converge (A5/A7)"
  - "Q6: dry-run writes? -> A: zero writes incl. logs; DST byte-identical (A6)"
  - "Q7: log/entrypoint placement? -> A: outside DST always (A8)"
  - "Q8: mirror equivalence class? -> A: contents+structure+symlinks only (A9)"
  - "Q9: severity bar? -> A: A10; destructive-misconfig guards A11/A12; verified-copy A13; env-class A14"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "MUST_KEEP verbatim: source path /opt/data/workspace/hermes-context/"
  - "MUST_KEEP: dry-run performs no writes (zero-write, incl. logs, A6)"
  - "MUST_KEEP: systemd user units, no root (A3)"
  - "A5/A7/A9: recursive exact mirror, both sync paths, self-verify nonzero on mismatch"
  - "A8: log + entrypoints outside mirrored tree"
  - "A11/A12/A13: guard realpath identity; stage -> verify -> touch DST; no rm -rf pre-verified-copy"
  - "A14: refuse DST colliding with script-owned paths (log/stage/entrypoints/TMPDIR); env theme closed"
  - "A10: FAIL bar = normal-operation defects only; exotics -> KNOWN_LIMITATIONS in +open"
paths:
  - /workspace/hdcs/artifact/sync-hermes-context.sh
  - /workspace/hdcs/artifact/hermes-context.service
  - /workspace/hdcs/artifact/hermes-context.timer
  - /workspace/hdcs/artifact/README.md
  - /workspace/hdcs/artifact/context.hcdl
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
