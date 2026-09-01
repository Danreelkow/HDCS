build brief → B1

state: s0 := SRC=/opt/data/workspace/hermes-context/ (host mount, read-only target); DST=/workspace/hermes-context/ (exists, holds INDEX.md, agents/, config/); no artifacts yet. Goal: standing 6h user-level one-way mirror SRC→DST, exact mirror class per A9, dry-run zero-write, standalone-capable.

Δ:
1. Write sync-hermes-context.sh:
   1a. Parse `--dry-run` flag; set DRYRUN=1.
   1b. Guards: reject SRC==DST (exit nonzero); reject missing SRC; resolve DST log-dir adversarial case (if DST under log path, abort). Expected: script exits nonzero on SRC==DST with message, no writes.
   1c. rsync path: `rsync -a --delete SRC/ DST/` (trailing slashes → contents, no nesting). Dry-run: `rsync -a --delete --dry-run` and suppress log write. Expected: mirror contents of SRC into DST, stale subtrees deleted ∀ depth.
   1d. cp fallback (no rsync): copy SRC/* to staging dir under ~/.cache/hermes-context/stage.$$, verify copy exists and non-empty (source survival check), then reconcile DST recursively: delete stale files/subtrees ∀ depth, cp -a new/changed items, then remove staging. Never `rm -rf DST` before verified copy exists. Expected: end state identical to rsync path (A5).
   1e. Self-verify post-sync: recursive diff SRC vs DST comparing contents+structure+symlinks (ignore metadata/timestamps/hardlinks). Mismatch → exit nonzero with diff report; never warn-and-exit-0. Expected: exit 0 iff exact mirror equivalence class holds.
   1f. Logging: append to ~/.cache/hermes-context/sync.log only on real runs; dry-run performs zero writes anywhere incl. log. Expected: dry-run leaves DST and log byte-identical pre/post (checkable via checksums).
2. Write hermes-context.service: Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh, User-level (no root). Expected: valid systemd user unit grammar.
3. Write hermes-context.timer: OnCalendar=00/6:00:00 (every 6h), Persistent=true, WantedBy=timers.target. Expected: valid user timer, 6h cadence.
4. Write README.md: install steps (cp script to ~/.local/bin, units to ~/.config/systemd/user/, `systemctl --user enable --now hermes-context.timer`), standalone usage (`~/.local/bin/sync-hermes-context.sh`), cron note for systemd-less hosts, dry-run usage, KNOWN_LIMITATIONS section listing L1 (newline filenames break cp fallback, repro `touch $'a\nb'`) and L2 (DST=log-dir adversarial config). Expected: README covers all items.
5. Place artifacts in /workspace/hdcs/bin/ (entrypoint-legal per A8, ¬ inside mirrored tree). Expected: 4 files present, none inside SRC or DST.

accept:
- [ ] /workspace/hdcs/bin/sync-hermes-context.sh exists, `bash -n` passes, executable bit set
- [ ] `SRC==DST` invocation exits nonzero, zero writes
- [ ] rsync present: run → `diff -r SRC DST` clean; stale subtree created in DST then run → gone (A7)
- [ ] rsync absent (PATH-restricted test): cp fallback run → end state identical to rsync run on same fixture (A5)
- [ ] `--dry-run`: checksums of DST and ~/.cache/hermes-context/sync.log byte-identical pre/post (A6)
- [ ] post-sync verification: introduce DST mismatch → script exits nonzero (A9)
- [ ] hermes-context.service + .timer parse via `systemd-analyze verify` (user units)
- [ ] README documents install, standalone run, cron fallback, dry-run, KNOWN_LIMITATIONS (L1, L2)
- [ ] no artifact inside SRC or DST; log only in ~/.cache/hermes-context/ (A8)
- [ ] no code path writes to SRC (A2); no `rm -rf DST` before verified copy exists (A11)

constraints:
- A2: writes only to DST; never SRC
- A4: contents of SRC → DST, never nest SRC inside DST; cp fallback when rsync missing
- A5: rsync and cp paths yield identical end state
- A6: --dry-run → zero writes ∀ targets incl. log
- A8: log ∈ ~/.cache/hermes-context/; entrypoints ∈ ~/.local/bin ∨ /workspace/hdcs/bin
- A9: verify enforces contents+structure+symlinks recursive; mismatch → nonzero exit, never warn-0
- A11: reject SRC==DST; source survival > freshness; no DST destruction pre-verified-copy
- no_resurrect: no accumulate-only fallback, no dry-run logging, no non-recursive reconciliation, no DST-placed artifacts, no warn-and-exit-0 verification
- L1/L2 documented as KNOWN_LIMITATIONS, not fixed

deliverable:
- /workspace/hdcs/bin/sync-hermes-context.sh
- /workspace/hdcs/bin/hermes-context.service
- /workspace/hdcs/bin/hermes-context.timer
- /workspace/hdcs/bin/README.md