state: s0 := register locked (devops-shell-systemd); A1..A19 folded; PIPE law = guards -> stage -> verify_stage -> reconcile -> verify_final -> summary; no-ambiguity certified (Q20); deliverable dir with 4 files; defaults SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/, LOG=~/.cache/hermes-context/sync.log.
Δ := 
1. Write sync-hermes-context.sh (POSIX sh, set -euo pipefail):
   1a. Config block: HERMES_CONTEXT_SRC/DST/LOG env overrides over deployed defaults [C6]; log default ~/.cache/hermes-context/sync.log. Expected: script-top defaults match deployed values.
   1b. Guards (before ANY write): degenerate check SRC/DST ∈ {'/', empty, '.'} via component tests -> exit≠0 citing A18; realpath identity/ancestor/descendant/DST-symlink-into-SRC -> exit≠0 citing A12; compute own owned paths (mktemp stage parent, resolved log FILE parent, entrypoint dir) and refuse iff realpath(DST)==owned ∨ owned inside DST ∨ DST inside owned, boundary-aware component compare, citing A14/A15; log parent ∉ DST check citing A8. Expected: all refusals exit≠0, zero writes, cite an A-number.
   1c. --dry-run: after guards, print summary to stdout, exit 0 with ZERO writes — no log file, no stage dir, no mkdir DST. Expected: absent DST stays absent; existing DST byte-identical.
   1d. Real run: mktemp -d stage (script-owned, never TMPDIR-resolved staging inside SRC/DST); copy SRC contents -> stage (rsync -a --delete if available, else cp -a + prune, or tar pipe); CONTENTS sync src/ -> dst/, never nest [C7].
   1e. verify_stage: diff -r --no-dereference stage vs SRC (A9 class: contents+structure+symlink-targets); mismatch -> exit≠0, never warn-and-exit-0. Expected: verified copy established before DST touched [C3].
   1f. Reconcile: if DST is symlink -> remove it; mkdir -p DST; rsync -a --delete stage/ DST/ (or cp -a + recursive prune of stale subtrees ∀ depth). Never rm -rf DST before verified stage [A11].
   1g. verify_final: diff -r --no-dereference DST vs SRC; mismatch -> exit≠0. Expected: DST end == SRC end per MIRROR class, idempotent ∀ repeat runs [C1].
   1h. Summary to stdout; log file write ONLY in real-run mode, to LOG path (parent ∉ DST). trap cleanup of stage dir.
2. Write hermes-context.service: user unit, ExecStart=<entrypoint>/sync-hermes-context.sh, Environment=HERMES_CONTEXT_SRC=/opt/data/workspace/hermes-context/, Environment=HERMES_CONTEXT_DST=/workspace/hermes-context/. Expected: no root, no User= line.
3. Write hermes-context.timer: OnUnitActiveSec=6h (or OnCalendar=6h — latitude per A20), WantedBy=default.target, [Install] section. Expected: user-level, no root.
4. Write README.md: documents mirror semantics (recursive, stale subtrees pruned ∀ depth, both sync paths converge identical), stage->verify->reconcile->verify_final order, never calls unverified copy "verified" [C10]; user-unit install (daemon-reload + enable --now), env override for SRC/DST/LOG, --dry-run test, standalone/cron fallback. Expected: sync-strategy section states recursive convergence correctly.
5. Self-check pass: dry-run probe (absent DST stays absent; existing DST byte-identical); guard probes trip clean ≠0 zero-writes citing A-numbers; verify-failure path exits ≠0. Expected: all probes pass.

accept:
- 4 files present: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md.
- sh -n sync-hermes-context.sh passes; script runs with --dry-run: exit 0, stdout summary, no file/dir created anywhere (probe: absent DST stays absent).
- Real run (test SRC/DST fixtures via env override): DST == SRC per diff -r --no-dereference; stale subtree planted in DST is pruned; second run idempotent (byte-identical, exit 0).
- rsync-absent path (PATH-shimmed) converges to identical end state as rsync path.
- Guards: DST='/' / empty / '.' -> exit≠0 citing A18; DST==SRC (realpath, incl. symlink alias) -> exit≠0 citing A12; DST containing stage/log/entrypoint owned path -> exit≠0 citing A14/A15; all zero writes.
- verify_stage/verify_final mismatch (mutate staged copy) -> exit≠0.
- Log file appears only on real run, at HERMES_CONTEXT_LOG or ~/.cache default, never inside DST.
- Unit files contain no User=/root; timer has 6h cadence + WantedBy=default.target.
- README: no "verified" label on unverified copy; documents env override, dry-run, user-unit install, cron fallback.

constraints:
- C1..C10 as given; path-law CLOSED set {A12,A14,A15,A18,A19} — no invented refusals; every refusal cites an A-number.
- POSIX sh only (no bashisms); set -euo pipefail.
- No destructive op on DST before verified stage exists [A11,A13].
- Dry-run: zero writes of any kind [A6,A16].
- KL1/KL2 noted in README KNOWN_LIMITATIONS, non-blocking [A10].
- ≤60 lines per file not required but brief budget: stay within 16000 tokens.

deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]