# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: `sync-hermes-context.sh:118-126` labels the staging copy as “verified” but only checks that it is non-empty; it never compares the staged tree’s file contents, recursive structure, or symlink targets with `SRC`. The fallback then begins destructive reconciliation at `sync-hermes-context.sh:128` and can remove paths from `DST` without the required verified source copy established elsewhere (A11).

## Packet
```yaml
reg: {domain: cs-programming, canon: shell/systemd engineering nouns — identifiers (HERMES_CONTEXT_SRC, HERMES_CONTEXT_DST, --dry-run, --delete, OnCalendar, systemctl --user), rsync/cp -a semantics, realpath}
intent: deliver artifact dir {sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md} implementing standing one-way mirror SRC -> DST; rsync --delete primary, cp -a fallback with recursive delete-reconciliation; --dry-run zero-write; systemd USER timer @6h + standalone executable; self-verification per A9 class with nonzero-exit FAIL
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical source/destination paths? -> A: SRC=/opt/data/workspace/hermes-context/ (host mount per kb digests), DST=/workspace/hermes-context/ (exists: INDEX.md, agents/, config/) [A1]"
  - "Q2: sync direction? -> A: host -> workspace one-way, no write-back [A2]"
  - "Q3: scheduler mechanism? -> A: systemctl --user timer; script standalone when systemd absent [A3]"
  - "Q4: rsync availability? -> A: may be absent; cp -a/tar-pipe fallback with identical mirror semantics; src/ -> dst/ contents [A4]"
  - "Q5: stale-file policy? -> A: exact mirror, deletion both paths [A5]"
  - "Q6: dry-run write scope? -> A: zero writes incl. logs; byte-identity gate [A6]"
  - "Q7: fallback delete depth? -> A: recursive subtree deletion at every depth [A7]"
  - "Q8: log + install placement? -> A: log outside DST always (~/.cache default); installs outside mirrored tree [A8]"
  - "Q9: mirror equivalence class? -> A: contents+structure+symlinks only; verify FAILs nonzero on mismatch [A9]"
  - "Q10: severity bar? -> A: FAIL on normal-operation defects only; exotic -> KNOWN_LIMITATIONS [A10]"
  - "Q11: destructive-misconfig guard? -> A: SRC==DST guard; no rm -rf DST pre-verified-copy [A11]"
  - "Q12: identity check form? -> A: realpath-based equality/ancestor/symlink-into-SRC guards, both paths, pre-destructive [A12]"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff:
  state: S_0 + Delta -> S_1
  report: [+done, -resolved, +open, +validation]
constraints:
  - "log file lives outside DST unconditionally (A8); no carve-outs"
  - "install paths outside mirrored tree; sync never removes own entrypoints (A8)"
  - "no rm -rf DST before verified source copy exists elsewhere (A11)"
  - "path-identity guards run before ANY destructive operation, both sync paths (A12)"
  - "self-verification: contents+structure+symlinks recursive, FAIL nonzero on mismatch (A9)"
  - "dry-run gate: DST byte-identical after run (A6)"
  - "fallback deletes recursively to converge with rsync --delete end state (A5,A7)"
paths:
  - /opt/data/workspace/hermes-context/
  - /workspace/hermes-context/
  - "~/.cache/hermes-context-sync.log (default log, outside DST)"
  - "~/.local/bin/sync-hermes-context.sh or /workspace/hdcs/bin/sync-hermes-context.sh (install)"
  - "~/.config/systemd/user/hermes-context.service, hermes-context.timer"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
