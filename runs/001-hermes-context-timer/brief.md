state: s0 := SRC=/opt/data/workspace/hermes-context/ (exists: INDEX.md, agents/, config/), DST=/workspace/hermes-context/ (exists), artifacts target /workspace/hdcs/bin/ with ~/.local/bin/ standalone fallback, log ~/.cache/hermes-context/, no artifacts yet, open=[].
Δ :=
1. Write /workspace/hdcs/bin/sync-hermes-context.sh (bash, set -euo pipefail):
   1a. Env: HERMES_CONTEXT_SRC default /opt/data/workspace/hermes-context/, HERMES_CONTEXT_DST default /workspace/hermes-context/, HERMES_CONTEXT_LOG_DIR default ~/.cache/hermes-context/ [A17].
   1b. Guards before any write: realpath both paths; reject SRC==DST (exit 2), SRC ancestor of DST or vice versa (exit 2), DST symlink resolving into SRC (exit 2); refusal exits produce zero writes [A11,A12,A14,A15].
   1c. --dry-run mode: compute plan only; zero writes to DST, log dir, or anywhere — no mkdir, no log append; DST left nonexistent if absent [A6,A16]; exit 0.
   1d. Real run: stage to mktemp -d (outside DST), populate via `rsync -a --delete SRC/ stage/` if rsync present, else `cp -a SRC/. stage/` plus recursive reconcile deleting stale subtrees at all depths [A4,A5,A7].
   1e. Self-verify staged copy vs SRC at A9 class (contents, structure, symlinks; ignore metadata/times/hardlinks), diff -r based; verification or staging failure -> exit nonzero, DST untouched [A9,A13].
   1f. Only after verify passes: mkdir -p DST, atomically reconcile DST from stage (rsync --delete or mv/reconcile), preserve stage until DST write completes; source never modified [A11,A13].
   1g. Log: one line per real run to $HERMES_CONTEXT_LOG_DIR/hermes-context.log (mkdir -p log dir; never under DST); dry-run logs nothing [A6,A8].
   1h. Idempotent: repeated runs converge to identical DST state.
   Expected 1: executable script at /workspace/hdcs/bin/sync-hermes-context.sh (mode +x), passes bash -n; --dry-run on test tree leaves DST byte-identical (nonexistent if absent), exit 0; real run mirrors full tree incl. nested stale-subtree deletion; guard tests (SRC==DST, ancestor, symlink-into-SRC) exit 2 with zero writes; self-verify exits nonzero when staged copy corrupted.
2. Write systemd user units /workspace/hdcs/bin/hermes-context.service and /workspace/hdcs/bin/hermes-context.timer:
   2a. Service: [Unit] Description; [Service] Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh (or /workspace/hdcs/bin path as installed), no root, User= implied user-level.
   2b. Timer: [Timer] OnCalendar=6h (OnUnitActiveSec=6h/OnBootSec fallback), Persistent=true; [Install] WantedBy=timers.target.
   Expected 2: both files parse via `systemd-analyze verify` (user-unit context) or clean accept when systemd absent; no RootDirectory/root directives; script runs standalone via direct invocation without systemd.
3. Write /workspace/hdcs/bin/hermes-context-README.md (named README.md within deliverable dir): install steps (copy entrypoints to ~/.local/bin or use /workspace/hdcs/bin, systemctl --user enable --now hermes-context.timer), source-change note (edit SRC, next timer tick syncs), dry-run test procedure, env override documentation, standalone fallback instructions.
   Expected 3: README.md present, documents all three flows, references exact env identifiers HERMES_CONTEXT_SRC/DST.
4. Place verified copies of entrypoint script in /workspace/hdcs/bin/ (primary) and document ~/.local/bin/ fallback in README.
   Expected 4: ls of /workspace/hdcs/bin/ shows all four artifacts; script -h/--help works.
accept:
- [ ] /workspace/hdcs/bin/sync-hermes-context.sh exists, executable, bash -n clean.
- [ ] bash script --dry-run: exit 0, zero filesystem writes; DST nonexistent if previously absent (test in sandbox dirs).
- [ ] Real run: DST contents+structure+symlinks == SRC (A9 class); stale nested subtree removed after deletion from SRC (A5,A7).
- [ ] Guards: SRC==DST, ancestor relationship, DST-symlink-into-SRC each -> exit ≠0, no writes (A11,A12,A14,A15).
- [ ] Staging-failure injection -> script exits ≠0, DST unmodified (A13).
- [ ] Log line written only on real runs, located under ~/.cache/hermes-context/ never under DST (A6,A8).
- [ ] hermes-context.service + hermes-context.timer valid user units, 6h cadence, no root; script standalone-capable (A3,A4).
- [ ] README.md present with install/source-change/dry-run instructions.
- [ ] HERMES_CONTEXT_SRC/DST overrides honored end-to-end in test (A17).
constraints:
- one-way SRC->DST, no writeback, source never modified [A2,A11]
- dry-run = zero writes anywhere, DST stays nonexistent [A6,A16]
- stage -> verify -> destroy/reconcile DST; never rm -rf DST unverified [A11,A13]
- guards: realpath identity/ancestor/symlink-into-SRC, concrete instantiated paths, component-boundary not string-prefix [A12,A14,A15]
- log + entrypoints outside mirrored tree [A8]
- equivalence = contents+structure+symlinks only [A9]
- deployed defaults = production paths; env override is the contract [A17]
- FAIL on normal-operation defects; adversarial residue -> KNOWN_LIMITATIONS + open [A10]
deliverable:
- /workspace/hdcs/bin/sync-hermes-context.sh
- /workspace/hdcs/bin/hermes-context.service
- /workspace/hdcs/bin/hermes-context.timer
- /workspace/hdcs/bin/README.md