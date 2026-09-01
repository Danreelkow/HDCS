state: s0 := SRC=/opt/data/workspace/hermes-context/ (exists: INDEX.md, agents/, config/); DST=/workspace/hermes-context/ (exists, same seed content); ART=4 files to build; no script/units exist yet; LOG default ~/.cache/hermes-context-sync.log.

Δ :=
1. Write sync-hermes-context.sh implementing: env defaults SRC/DST/LOG; --dry-run flag; A12 realpath guards (refuse clean nonzero, zero writes, if SRC==DST realpath, ancestor/descendant, or DST symlink-resolves into SRC); A11 guard (refuse destructive op unless verified copy of SRC exists elsewhere); rsync detection -> rsync_path `rsync -a --delete $SRC/ $DST/` else cp_path (stage to temp dir outside DST, cp -a SRC/ stage/, recursive reconcile stage->DST incl. stale subtree deletion); A13 order: stage -> verify (A9 class: contents+structure+symlinks, recursive diff) -> atomically touch DST; self-verify FAIL nonzero on mismatch, never warn-exit-0; write one-line summary to LOG only on real runs (never in --dry-run, never inside DST); exit 0 on success.
   Expected output: executable script at ART/sync-hermes-context.sh, `bash -n` passes, `shellcheck` clean or deviations documented in header comment.
2. Write hermes-context.service: [Service] Type=oneshot, ExecStart=%h path to installed sync-hermes-context.sh (or absolute install path outside DST per A8).
   Expected output: ART/hermes-context.service with ExecStart referencing non-DST install path, no User=/root directives.
3. Write hermes-context.timer: [Timer] OnCalendar=*-*-* 0/6:00:00, Persistent=true, [Install] WantedBy=default.target.
   Expected output: ART/hermes-context.timer with OnCalendar 6h cadence, WantedBy=default.target.
4. Write README.md: install steps (script -> ~/.local/bin or /workspace/hdcs/bin, units -> ~/.config/systemd/user/, `systemctl --user enable --now hermes-context.timer`), standalone usage, --dry-run usage, KNOWN_LIMITATIONS section (newline-in-filename corpora; hostile env where DST==log dir; per A10).
   Expected output: ART/README.md documenting all four paths; never describes unverified copy as "verified" (A13 wording).
5. Self-check pass over ART: run script with --dry-run against test fixture dirs (temp SRC/DST with nested subdirs, stale file in DST, symlink); confirm zero writes to DST and no log file created; run real sync; confirm A5/A7 exact mirror incl. stale deletion; run with rsync absent (PATH shim) confirm cp_path parity; run guards (SRC==DST, DST symlink into SRC) confirm clean nonzero refusal.
   Expected output: checklist in handoff report: dry-run byte-identity PASS, mirror equality both paths PASS, stale-subtree deletion PASS, guard refusals PASS (nonzero, no writes), verify-fail exits nonzero PASS.

accept:
- [ ] ART contains exactly: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md
- [ ] `bash -n sync-hermes-context.sh` exits 0
- [ ] --dry-run: DST mtime+content byte-identical pre/post; no LOG file created anywhere
- [ ] rsync_path and cp_path each produce DST == SRC exactly (contents+structure+symlinks recursive); stale files/subtrees deleted
- [ ] verify mismatch -> exit nonzero (not 0)
- [ ] SRC==DST realpath / ancestor / DST-symlink-into-SRC -> clean nonzero exit, zero writes
- [ ] LOG default ~/.cache/hermes-context-sync.log; never inside DST; install paths outside mirrored tree
- [ ] units: systemctl --user compatible, OnCalendar 6h, WantedBy=default.target, no root
- [ ] README documents install, standalone use, dry-run, KNOWN_LIMITATIONS

constraints:
- no root anywhere; user units only
- rsync -a --delete with src/ trailing slash; cp_path must reach identical end state (A5/A7)
- dry-run = zero writes of any kind (A6)
- stage -> verify -> touch DST order; SRC survival > freshness (A11/A13)
- self-verify fails nonzero on A9 mismatch; never warn-exit-0 (A9)
- no_resurrect: A5, A6, A7, A9, A11, A12, A13
- exotics -> KNOWN_LIMITATIONS, not silent suppression (A10)

deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]