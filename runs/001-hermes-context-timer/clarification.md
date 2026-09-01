# Clarification needed — 001-hermes-context-timer

## Gate output (after repair round)
```
GATE FAIL: real run exited nonzero: sync-hermes-context: DST is not a directory: /tmp/hdcs-gate-dst

```

## Open questions recorded by S1
(none recorded)

## Packet
```yaml
reg: {domain: cs-devops-shell, canon: "bash/systemd identifiers (rsync --delete, systemctl --user, mktemp -d, realpath, Unit=OnCalendar), POSIX path semantics, systemd user-unit vocabulary"}
intent: "standing_sync := sync(SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/, direction=one-way, semantics=exact_mirror(A9), trigger=systemd --user timer OnCalendar=every-6h, fallback=standalone exec). Deliverables: sync-hermes-context.sh (env-configurable SRC/DST, --dry-run zero-write, idempotent, one-line summary), hermes-context.service + hermes-context.timer (user units), README.md (install, change-source, dry-run test). Dual sync paths (rsync primary, cp -a/tar fallback) -> identical end state A5/A7."
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical SRC/DST -> A: SRC=/opt/data/workspace/hermes-context/ (A1), DST=/workspace/hermes-context/ (exists, INDEX.md, agents/, config/)"
  - "Q2: sync direction -> A: host -> workspace one-way, no writeback (A2)"
  - "Q3: systemd availability -> A: user timer; script must also run standalone sans systemd (A3)"
  - "Q4: rsync availability -> A: detect, fallback cp -a/tar pipe, contents-sync not nesting (A4)"
  - "Q5: mirror or accumulate -> A: exact mirror, --delete equivalent, recursive deletion both paths (A5, A7)"
  - "Q6: dry-run scope -> A: zero writes incl. log files; DST byte-identical post-run (A6)"
  - "Q7: log/install placement -> A: log outside DST always (~/.cache default); install paths outside mirrored tree (A8)"
  - "Q8: mirror equivalence class -> A: contents+structure+symlinks only; no metadata/timestamps/hardlinks; verify fails nonzero (A9)"
  - "Q9: severity bar -> A: FAIL iff normal-operation reachable; exotic env combos -> KNOWN_LIMITATIONS (A10)"
  - "Q10: destructive guards -> A: realpath identity guard, stage->verify->touch-DST ordering, content-compared verification (A11, A12, A13)"
  - "Q11: env-interaction guard class -> A: generalized protected-path guard over owned concrete paths, boundary-aware compare (A14, A15)"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "∀ sync path -> DST end == SRC end, recursive, A9 class only"
  - "--dry-run -> zero writes, DST byte-identical"
  - "order: stage -> verify(content-compare) -> touch DST; ∀ destructive op precondition verified copy"
  - "guards: realpath identity (A12), SRC==DST (A11), protected-path boundary-aware (A14/A15)"
  - "log ∉ DST; install paths ∉ mirrored tree"
  - "user units only, no root; standalone-exec fallback"
paths:
  - /opt/data/workspace/hermes-context/
  - /workspace/hermes-context/
  - "~/.local/bin or /workspace/hdcs/bin (entrypoints)"
  - "~/.cache/... (log, default, outside DST)"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
