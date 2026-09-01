# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: sync-hermes-context.sh lines 112–113 and 133–134 explicitly exclude a log located inside DST from both rsync and fallback reconciliation, and lines 151–154 then rewrite that log after mirroring. This violates the packet’s exact recursive invariant “DST end state == SRC end state” and the README’s own exact-mirror claim (README “Mirror semantics,” lines 35–38).  
EVIDENCE: README installation lines 7–10 place the script at `/workspace/hermes-context/artifact/sync-hermes-context.sh`, while the service’s `ExecStart` (hermes-context.service, line 6) uses that path. Because `artifact/` is inside DST, the normal `--delete` mirror (script line 112) or fallback reconciliation (lines 125–134) deletes the installed script whenever `artifact/` is absent from SRC, making the installed user service nonfunctional after synchronization.

## Packet
```yaml
reg: {domain: cs-devops-shell-systemd, canon: "exact identifiers rsync/tar/systemd.unit (OnCalendar, WantedBy=timers.target), env vars HERMES_CONTEXT_SRC|DST|LOG, mirror semantics (--delete, recursive reconcile)"}
intent: "build artifact dir containing: sync-hermes-context.sh (rsync primary; tar/cp -a + recursive reconcile fallback; env-driven SRC/DST with defaults; --dry-run zero-write incl. logs; idempotent; one-line summary log per real run) + hermes-context.service/.timer (systemctl --user, 6h cadence, no root) + README.md (install, source change, dry-run test, mirror semantics). Goal: DST = exact recursive one-way mirror of SRC (host->workspace)."
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical SRC/DST paths? -> A: SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/ (exists: INDEX.md, agents/, config/) [A1]"
  - "Q2: sync direction? -> A: one-way host->workspace; nothing writes back to host mount [A2]"
  - "Q3: systemd scope? -> A: user units (systemctl --user); script must also run standalone without systemd [A3]"
  - "Q4: rsync absent? -> A: detect and fall back to cp -a/tar-pipe; contents src/ -> dst, never nesting [A4]"
  - "Q5: stale-file policy? -> A: exact mirror, stale deleted; rsync --delete; fallback reconciles identically, recursive forall depth [A5,A7]"
  - "Q6: dry-run write surface? -> A: zero writes incl. log files even if HERMES_CONTEXT_LOG in DST; gate = DST byte-identical pre/post [A6]"
  - "Q7: cadence? -> A: timer every 6h, user-level [A3+spec]"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff:
  state: S_0 + Delta -> S_1
  report:
    - "+done"
    - "-resolved"
    - "+open"
    - "+validation"
constraints:
  - "forall run: no_writes(SRC) (one-way host->workspace) [A2]"
  - "DR -> zero writes forall target (dst contents and logs); byte-identity gate [A6]"
  - "forall path in {RS,FB}: DST end state == SRC end state, recursive [A5_mirror]"
  - "no_root_required; units user-scoped [MUST_KEEP]"
  - "SRC verbatim /opt/data/workspace/hermes-context/ [MUST_KEEP]"
  - "rsync absence -> FB, semantics identical [A4]"
  - "script idempotent; one-line summary log per real run"
paths:
  - "/opt/data/workspace/hermes-context/ (SRC, canonical)"
  - "/workspace/hermes-context/ (DST)"
  - "<artifact_dir>/sync-hermes-context.sh"
  - "<artifact_dir>/hermes-context.service"
  - "<artifact_dir>/hermes-context.timer"
  - "<artifact_dir>/README.md"
  - "~/.config/systemd/user/ (unit install target)"
budgets: {tokens: 12000, lines: 60, fix_cycles: 2, questions: 2}
```
