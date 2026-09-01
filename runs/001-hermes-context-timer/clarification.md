# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: sync-hermes-context.sh:41-50 explicitly accepts a pre-existing DST symlink whose target is outside SRC (“DST symlink resolving OUTSIDE SRC is ACCEPTED”), and sync-hermes-context.sh:153-154 plus README.md “Sync strategy” state that it is replaced. This contradicts A18, which requires refusal of DST symlinks resolving outside SRC with an A12 refusal. Also, sync-hermes-context.sh:74-76 validates only the constructed string `"$LOGDIR_R/stage.$$"`; sync-hermes-context.sh:112-116 then runs `mkdir -p -- "$STAGE"` without refusing an existing stage symlink or resolving the instantiated stage path. A pre-existing `stage.$$` symlink into DST/SRC can therefore make the rsync/tar staging writes operate on a protected tree before verification, violating A14/A15 and A13’s stage-before-touch-DST ordering.

## Packet
```yaml
reg: {domain: cs-programming, canon: shell/systemd/rsync sync tooling — exact identifiers (rsync --delete, systemctl --user, mktemp -d, realpath), unit-file fields, POSIX path semantics}
intent: >
  deliver standing one-way mirror sync SRC=/opt/data/workspace/hermes-context/ -> DST=/workspace/hermes-context/
  artifact dir {sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md};
  script: rsync --delete primary, cp/tar fallback with identical recursive mirror convergence (A5/A7),
  --dry-run zero writes (A6), staged verified-copy order (A13/A20), guards A11/A12/A14/A15/A18,
  log outside DST (A8), self-verification nonzero-fail on A9-class mismatch;
  units: systemctl --user, timer OnCalendar every 6h, no root (A3);
  README: install, source change via env (A17), --dry-run test, sync-strategy states recursive convergence
must_keep:
  - source path is /opt/data/workspace/hermes-context/
  - dry-run mode that performs no writes
  - systemd user units, no root required
resolved:
  - "Q1: canonical SRC/DST -> A: A1 (paths fixed as deployed defaults)"
  - "Q2: sync direction -> A: A2 one-way host->workspace"
  - "Q3: no systemd? -> A: A3 script standalone-capable"
  - "Q4: no rsync? -> A: A4 cp/tar fallback, contents-sync"
  - "Q5: stale files? -> A: A5 exact mirror, delete"
  - "Q6: dry-run writes logs? -> A: A6 no, zero writes"
  - "Q7: fallback deletion depth -> A: A7 recursive"
  - "Q8: log/entrypoint placement -> A: A8 outside DST/tree"
  - "Q9: mirror class scope -> A: A9 contents+structure+symlinks only"
  - "Q10: severity bar -> A: A10 FAIL vs KNOWN_LIMITATIONS"
  - "Q11: rm -rf ordering -> A: A11 verified copy first"
  - "Q12: identity guard -> A: A12 realpath"
  - "Q13: verified definition -> A: A13 content-compare, stage->verify->touch, incl. rsync path"
  - "Q14: protected paths -> A: A14 concrete owned paths"
  - "Q15: guard breadth -> A: A15 gates not walls"
  - "Q16: DST pre-existence -> A: A16 real-run mkdir -p; dry-run none"
  - "Q17: env override scope -> A: A17 mandated, defaults are deployed config"
  - "Q18: degenerate paths -> A: A18 refuse /, empty, .; component tests"
  - "Q19: ownership checks -> A: A19 none; law list closed"
  - "Q20: staging order + reserved names -> A: A20 pure-compute then create; mktemp prunelist"
  - "Q21: exotic filenames -> A: A21 KNOWN_LIMITATIONS"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff:
  state: S_0 + Delta -> S_1
  report: [+done, -resolved, +open, +validation]
constraints:
  - MIRROR = A9 class; both sync paths converge identically (A5, recursive A7)
  - dry-run: zero writes of any kind incl. logs; DST absent stays absent (A6, A16)
  - order: compute-stage-path (pure) -> validate guards -> create stage -> content-verify -> touch DST (A11/A13/A20); applies to rsync path too (A21 note)
  - guards before any destructive op: A12 realpath identity, A14/A15 concrete owned paths (log dir, stage, entrypoint), A18 degenerate; refusals cite A-number, zero writes (A19, C4)
  - no invented scope: no ownership checks; law list closed (A19)
  - reserved namespace: never overwrite mirror files with script bookkeeping (A20)
  - log always outside DST; install entrypoints outside mirrored tree (A8)
  - env HERMES_CONTEXT_SRC/DST override is contract-mandated; deployed defaults are production values (A17)
  - no_resurrect: verdict-supersession per A17 (env-scope verdict wrong); A15 (run017 wall), A16 (run019 wall), A20 (run025)
paths:
  - SRC: /opt/data/workspace/hermes-context/
  - DST: /workspace/hermes-context/
  - artifact_dir: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]
  - log: ~/.cache/hermes-context/sync.log (default, outside DST)
  - entrypoints: ~/.local/bin or /workspace/hdcs/bin
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
