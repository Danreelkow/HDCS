# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: `sync-hermes-context.sh:87` places STAGE under `${TMPDIR}` without verifying it is outside DST and SRC; `sync-hermes-context.sh:122` then recursively deletes DST, so `TMPDIR=$HERMES_CONTEXT_DST` can delete the only verified copy, while `TMPDIR=$HERMES_CONTEXT_SRC` writes into the read-only source and violates A2/A11. `sync-hermes-context.sh:39-40` fixes the log under `$HOME/.cache` but never rejects DST resolving to that path (or to `~/.local/bin`); after `sync-hermes-context.sh:139-148` verification, `log_line` can create `sync.log` inside DST, violating A8 and exact-mirror semantics despite the README Guards/Logging claims that the log is never under DST.

## Packet
```yaml
reg: {domain: cs-shell-systemd, canon: rsync(1) flags (--delete/-a/--dry-run), systemctl --user units (.service/.timer, OnCalendar), realpath(1), tar-pipe/cp -a fallback, idempotent-sync semantics}
intent: >
  build standing sync SRC=/opt/data/workspace/hermes-context/ -> DST=$HERMES_CONTEXT_DST
  (default /workspace/hermes-context), one-way host->workspace, exact-mirror semantics
  (A5/A7/A9 class: contents+structure+symlinks, recursive, stale deleted);
  two convergence paths: rsync --delete primary, cp -a/tar-pipe fallback with identical
  end state; guarded (A11/A12) destructive phase ordered stage->verify->reconcile (A13);
  --dry-run => zero writes ∀ incl. logs (A6); systemd USER units @6h cadence, no root (A3);
  deliverables: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md.
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical source path? -> A: /opt/data/workspace/hermes-context/ (A1); DST /workspace/hermes-context/ exists (INDEX.md, agents/, config/)"
  - "Q2: sync direction? -> A: one-way host->workspace, no writeback (A2)"
  - "Q3: scheduling mechanism? -> A: systemd --user timer 6h; script standalone-capable sans systemd (A3)"
  - "Q4: rsync absent? -> A: fallback cp -a/tar-pipe, identical mirror semantics (A4)"
  - "Q5: mirror vs accumulate? -> A: exact mirror, stale deleted, recursive, both paths converge (A5,A7)"
  - "Q6: dry-run logging? -> A: zero writes incl. logs, DST byte-identical post dry-run (A6)"
  - "Q7: log/install placement? -> A: log in ~/.cache, installs in ~/.local/bin, both ∉ DST ∀ exceptions (A8)"
  - "Q8: mirror equivalence class? -> A: contents+structure+symlinks only; metadata/timestamps/hardlinks excluded; verify fails nonzero (A9)"
  - "Q9: severity bar? -> A: FAIL on normal-operation defects only; exotic -> KNOWN_LIMITATIONS non-blocking (A10)"
  - "Q10: destructive guards? -> A: SRC==DST guard; no rm -rf DST before verified copy (A11); realpath identity/ancestor/descendant guard both paths (A12)"
  - "Q11: verified definition? -> A: content-compared staging copy; order stage->verify->touch DST; README wording law (A13)"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - must_keep trio enforced verbatim in script+units+README
  - "∀ sync path: A12 realpath guard pre-flight, clean nonzero exit, no writes on violation"
  - "A13 ordering: stage -> A9-class content verify -> reconcile DST; verify fail => nonzero, DST untouched"
  - "A6: --dry-run => zero writes ∀ filesystem incl. log target"
  - "A8: log ∈ ~/.cache, bin ∈ ~/.local/bin, never inside DST; no post-mirror rewrite carve-outs"
  - "A9: self-verification enforces contents+structure+symlinks recursive; mismatch => nonzero exit"
  - "no_resurrect: A2 (one-way), A5, A7, A8, A11, A12, A13 violations in any fix cycle => FAIL"
paths:
  - artifact_dir: ./hermes-context-freshness/ (sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md)
  - src: /opt/data/workspace/hermes-context/
  - dst: /workspace/hermes-context/
  - install: ~/.local/bin/sync-hermes-context.sh, ~/.config/systemd/user/hermes-context.{service,timer}
  - log: ~/.cache/hermes-context/sync.log
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
