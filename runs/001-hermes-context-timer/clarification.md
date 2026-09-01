# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: `sync-hermes-context.sh:7` permits `HERMES_CONTEXT_SRC` to override the packet-mandated fixed source `/opt/data/workspace/hermes-context/`, inventing scope and violating the fixed SRC requirement. More critically, `sync-hermes-context.sh:48,52-54` checks only whether the resolved log directory is inside DST (`under "$LOGDIR_R" "$DST_R"`), but does not reject DST being inside the owned log directory. Thus a DST such as `$HOME/.cache/hermes-context/workspace` is accepted even though the log parent is inside the mirrored tree, violating A8/A14/A15 and allowing the post-sync log write at `sync-hermes-context.sh:93-94` to modify DST outside mirror semantics.

## Packet
```yaml
reg: {domain: cs-programming/shell-systemd-tooling, canon: exact identifiers rsync/tar/cp -a, systemctl --user, OnCalendar, mktemp -d, realpath, OnUnitActiveSec, POSIX exit codes}
intent: >
  build one artifact dir delivering standing one-way mirror sync SRC=/opt/data/workspace/hermes-context/
  -> DST=$HERMES_CONTEXT_DST(default /workspace/hermes-context): sync-hermes-context.sh (rsync
  primary w/ --delete, cp/tar fallback w/ identical A9-mirror semantics, --dry-run pure, guards,
  stage->verify->touch order, one-line summary log per real run), hermes-context.service +
  hermes-context.timer systemd USER units firing every 6h, README.md (install, source change,
  --dry-run test, correct recursive-mirror sync-strategy statement).
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical SRC? -> A: /opt/data/workspace/hermes-context/ (kb host-mount digest; A1)"
  - "Q2: direction? -> A: host -> workspace one-way, no write-back (A2)"
  - "Q3: root units ok? -> A: NO — systemctl --user only; script must run standalone if systemd absent (A3)"
  - "Q4: rsync missing? -> A: fallback cp -a/tar-pipe; sync CONTENTS src/ -> dst, never nest (A4)"
  - "Q5: mirror semantics? -> A: EXACT mirror, stale files deleted, both paths converge (A5, A7 recursive)"
  - "Q6: dry-run scope? -> A: zero writes of ANY kind incl. logs; DST byte-identical or nonexistent (A6, A16)"
  - "Q7: equivalence class of mirror? -> A: contents + structure + symlinks (recursive); NOT metadata/timestamps/hardlinks; self-verification FAILs nonzero on mismatch (A9)"
  - "Q8: log & install placement? -> A: log parent + entrypoints outside mirrored tree, always, no carve-outs (A8)"
  - "Q9: severity bar? -> A: FAIL only on normal-op-reachable defects; exotic env triggers -> KNOWN_LIMITATIONS (A10)"
  - "Q10: destructive misconfig? -> A: guard SRC==DST identity via realpath + ancestor/descendant/symlink-into-SRC; never rm -rf DST before verified copy; stage -> verify -> touch DST (A11, A12, A13 content-compared)"
  - "Q11: env-var attack class? -> A: generalized owned-path guard on concrete instantiated paths (stage dir, resolved log file parent, entrypoint dir), boundary-aware comparison, never generic ancestors; A15 calibrates A14 gate-not-wall"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - all MUST_KEEP lines verbatim (source /opt/data/workspace/hermes-context/, pure dry-run, user units no root)
  - A5+A7: both sync paths converge recursively to identical end state; fallback != divergent feature
  - A6+A16: dry-run = zero writes, does not create DST; gate compares byte-identity/nonexistence
  - A8: log + entrypoints never inside mirrored tree; no post-mirror rewrite exceptions
  - A9: self-verify enforces contents+structure+symlinks, exit nonzero on mismatch, never warn-and-exit-0
  - A10: judge classifies per severity bar; cites all, blocks only normal-op defects
  - A11+A12+A13: no destructive DST op before content-compared verified staging copy; realpath identity guards, clean nonzero no-writes refusals
  - A14+A15: owned-path guard on concrete paths, component-boundary comparison, not string prefix, not ancestors
  - A16: real run mkdir -p DST if absent; dry-run must leave DST nonexistent
  - no_resurrect: [A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16]
paths:
  - /opt/data/workspace/hermes-context/          # SRC, fixed
  - /workspace/hermes-context/                   # DST default
  - artifact_dir/sync-hermes-context.sh
  - artifact_dir/hermes-context.service
  - artifact_dir/hermes-context.timer
  - artifact_dir/README.md
  - ~/.cache/hermes-context/sync.log             # log: outside DST, always
  - ~/.local/bin/                                # entrypoint install: outside mirrored tree
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
