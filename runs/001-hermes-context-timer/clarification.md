# Clarification needed — 001-hermes-context-timer

## Gate output (after repair round)
```
GATE FAIL: real run exited nonzero: sync-hermes-context.sh: line 162: mode_unused: unbound variable

```

## Open questions recorded by S1
(none recorded)

## Packet
```yaml
reg: {domain: cs-programming/ops-automation, canon: rsync mirror semantics, systemd user units/timers, idempotent sync, realpath path-safety guards}
intent: >
  build artifact dir {sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md} :=
    standing 6h user-level sync of SRC=/opt/data/workspace/hermes-context/ -> DST=/workspace/hermes-context/;
    rsync primary (--delete, -a) w/ cp -a fallback (recursive reconcile, stale-subtree deletion);
    exact mirror per MIRROR_CLASS; --dry-run zero-write incl. logs; idempotent; one-line real-run log OUTSIDE DST;
    path-safety guards per A-law {A11..A22}; stage->content-verify->touch-DST order ∀ destructive paths;
    user units only (systemctl --user), script standalone-capable.
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical SRC/DST? -> A: SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/ (A1)"
  - "Q2: sync direction? -> A: one-way host->workspace (A2)"
  - "Q3: systemd scope? -> A: user units + standalone script fallback (A3)"
  - "Q4: rsync absent? -> A: cp -a fallback, identical mirror semantics (A4)"
  - "Q5: stale files? -> A: deleted, recursive, both paths (A5,A7)"
  - "Q6: dry-run writes logs? -> A: never, zero-write incl. DST absent post-dry-run (A6,A16)"
  - "Q7: mirror equivalence class? -> A: contents+structure+symlinks only (A9)"
  - "Q8: destructive-misconfig? -> A: guarded per A11/A12/A14/A15/A18; closed list per A19"
  - "Q9: DST symlink? -> A: refuse, never replace (A22)"
  - "Q10: deployed paths restrict env override? -> A: no; env override is the gate contract (A17)"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "no_resurrect: A5 exact-mirror recursion, A6 dry-run purity, A13 stage->verify->touch order, A15 concrete-path gate calibration, A19 closed path-law list, A20 pure-string stage validation, A22 refuse-not-replace"
  - "refusals cite an A-number or are defects (A19)"
  - "verification enforces A9 class, nonzero exit on mismatch"
  - "entrypoints + logs live outside DST tree (A8)"
paths:
  - "/workspace/hermes-context/ (artifact dir)"
  - "~/.cache/hermes-context/ (log, default, outside DST)"
  - "~/.local/bin/ or /workspace/hdcs/bin/ (entrypoints)"
  - "~/.config/systemd/user/ (unit install target)"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
