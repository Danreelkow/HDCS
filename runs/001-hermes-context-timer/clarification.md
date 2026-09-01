# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: `sync-hermes-context.sh`, cp_path reconciliation block (the `comm -z -13 ... "$WORK/stale.list"` loop followed by `cp -a "$STAGE/." "$RDST/"`): stale detection removes only paths absent from the stage, not paths whose type changes. For example, if SRC contains regular file `x` while DST contains directory `x`, `x` appears in both listings, is not removed, and `cp -a` cannot replace the directory with the file; the fallback therefore does not converge to the exact A5/A7 mirror end state. The analogous source-directory/DST-file transition is also not reconciled.

`README.md`, Install section: it states the script may be installed at either `~/.local/bin/sync-hermes-context.sh` or `/workspace/hdcs/bin/`, but `hermes-context.service`, `[Service]` `ExecStart=%h/.local/bin/sync-hermes-context.sh`, supports only the former location. Installing at the documented second location produces a user service that cannot start.

## Packet
```yaml
reg: {domain: cs-devops-scripting, canon: shell/systemd/rsync vocabulary — rsync flags (--delete, --dry-run), systemctl --user unit directives (OnCalendar, WantedBy=default.target), POSIX test/realpath/tar, env-var defaults, exit codes}
intent: >
  standing sync service keeping DST=$HERMES_CONTEXT_DST (default /workspace/hermes-context/)
  an exact A9-class mirror of SRC=$HERMES_CONTEXT_SRC (default /opt/data/workspace/hermes-context/),
  host->workspace one-way, via rsync_path (--delete) with cp_path fallback (recursive reconcile),
  systemd USER timer every 6h, script standalone-capable, --dry-run zero-write,
  self-verifying (nonzero exit on mismatch), guards A11/A12/A13 pre-destructive;
  artifact := {sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md}
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical SRC/DST paths? -> A: SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/ (A1)"
  - "Q2: sync direction? -> A: host->workspace one-way, no writeback (A2)"
  - "Q3: scheduling mechanism? -> A: systemctl --user; script also works standalone without systemd (A3)"
  - "Q4: behavior when rsync absent? -> A: fallback cp -a / tar-pipe with identical recursive-mirror semantics (A4)"
  - "Q5: stale-file semantics? -> A: exact mirror, --delete equivalent, recursive subtree deletion both paths (A5/A7)"
  - "Q6: dry-run scope? -> A: zero writes of any kind incl. logs; DST byte-identical after (A6)"
  - "Q7: log/install placement? -> A: log outside DST always (default ~/.cache); installs outside mirrored tree (A8)"
  - "Q8: mirror equivalence class? -> A: contents+structure+symlinks recursive only; metadata/timestamps/hardlinks excluded; verify fails nonzero (A9)"
  - "Q9: severity bar? -> A: A10 normal-operation FAILs only; exotics -> KNOWN_LIMITATIONS"
  - "Q10: destructive guards? -> A: SRC==DST + realpath identity/ancestor guards; stage->verify(A13)->touch DST order (A11/A12/A13)"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "mk units USER-level only (systemctl --user, WantedBy=default.target); no root"
  - "rsync_path := rsync -a --delete with src/ trailing slash; cp_path reconciles recursively to identical end state (A5/A7)"
  - "--dry-run: zero writes incl. HERMES_CONTEXT_LOG inside DST; gate = DST byte-identical post-run (A6)"
  - "LOG path defaults ~/.cache/, never inside DST; installed entrypoints never inside mirrored tree (A8)"
  - "A11/A12/A13 guards: realpath identity + ancestor/descendant check before ANY destructive op; stage->content-verify->touch DST; SRC survival outranks freshness"
  - "self-verification exits nonzero on A9-class mismatch; never warn-and-exit-0"
  - "no_resurrect: A5_mirror, A6_purity, A7_recursive, A9_class, A11_guard, A12_identity, A13_verified"
paths:
  - "/workspace/hermes-context/ (DST, exists: INDEX.md, agents/, config/)"
  - "/opt/data/workspace/hermes-context/ (SRC, canonical host mount)"
  - "~/.cache/hermes-context-sync.log (default LOG, outside DST)"
  - "~/.config/systemd/user/hermes-context.service, ~/.config/systemd/user/hermes-context.timer"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
