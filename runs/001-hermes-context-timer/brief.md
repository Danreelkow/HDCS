state: s0 := {artifact_dir: 4 files (sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md); SRC=/opt/data/workspace/hermes-context/ (A17 default, env SRC_DIR); DST=/workspace/hermes-context (env DST_DIR); log=~/.cache/hermes-context/ (env LOG_DIR, outside DST, real-run only); rsync primary, cp/tar fallback converging to A9 end state; A19 closed refusal list (A12, A14/A15, A18), refusals cite A-numbers, zero writes on refusal path; dry-run = zero writes, never creates DST (A6/A16); systemd user units Type=oneshot, OnUnitActiveSec=6h, no root (A3); verify compares SRC vs DST recursively (contents+structure+symlinks), exit nonzero on mismatch, staged via content-compared temp staging before DST destruction (A13)}
Δ := [
step1: write sync-hermes-context.sh with: `set -euo pipefail`; parse SRC_DIR=${SRC_DIR:-/opt/data/workspace/hermes-context/}, DST_DIR=${DST_DIR:-/workspace/hermes-context}, LOG_DIR=${LOG_DIR:-$HOME/.cache/hermes-context}; mode flag `--dry-run`; guards: SRC must exist and be a directory else refuse citing A14/A15 (exit 2, zero writes); refuse root execution citing A12; refuse DST==SRC or DST inside SRC citing A18; all refusal paths write nothing (A19/A20)
  → expected: script passes `bash -n`; grep shows all three refusal sites citing A-numbers; grep shows no write ops before guard completion.
step2: implement real-run sync: if rsync available → `rsync -a --delete "$SRC_DIR" "$DST_DIR"`; else fallback → stage to `$(mktemp -d)` under LOG_DIR, copy SRC there via `cp -a` or tar pipe, content-verify staging against SRC (A13), then swap: `mkdir -p DST`, rsync-style delete-stale via comparing SRC vs existing DST and removing extras, then move staged contents into DST
  → expected: both branches grep-present; fallback branch contains mktemp -d and stale-deletion loop; after both branches, on identical fixtures, `diff -r SRC DST` empty and symlink targets match.
step3: implement --dry-run: prints planned diff (would-create/would-update/would-delete) read-only; zero writes; never mkdir DST even if absent (A6/A16)
  → expected: on fixture where DST absent, `--dry-run` run then `test ! -e DST` passes; DST mtime+contents byte-identical pre/post run when present.
step4: implement verify subcommand/flag: recursive comparison of DST vs SRC (file contents, directory structure, symlink presence+targets, stale files flagged); any mismatch → exit nonzero listing mismatched paths
  → expected: on mirrored fixture exit 0; after adding a stale file to DST exit≠0 and stale path printed.
step5: real-run logging: append timestamped summary to $LOG_DIR/sync.log (mkdir -p LOG_DIR); no logging in dry-run mode
  → expected: after real run, log file exists under LOG_DIR; after dry-run, no log lines appended.
step6: write hermes-context.service: [Unit] Description; [Service] Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh
  → expected: grep Type=oneshot present; ExecStart references script path; no User= line (user unit, A3).
step7: write hermes-context.timer: [Timer] OnUnitActiveSec=6h, OnBootSec=10min, Persistent=true; [Install] WantedBy=timers.target
  → expected: grep OnUnitActiveSec=6h present.
step8: write README.md: usage (standalone exec, systemctl --user enable --now hermes-context.timer), env override mechanism (SRC_DIR/DST_DIR/LOG_DIR per A17 with deployed defaults), dry-run example, log location
  → expected: mentions all three env vars with defaults; contains one --dry-run example line.
step9: install: cp script → ~/.local/bin/ and units → ~/.config/systemd/user/; run `systemctl --user daemon-reload`; run end-to-end check: real run then verify exit 0; dry-run then confirm DST unchanged and no DST creation when absent
  → expected: `bash -n` clean; verify exit 0 post-real-run; dry-run on absent-DST fixture leaves DST nonexistent; `systemctl --user list-timers hermes-context.timer` shows 6h period.
]
accept: [
1. artifact dir contains exactly: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md
2. `bash -n ~/.local/bin/sync-hermes-context.sh` exit 0
3. real run → `diff -r /opt/data/workspace/hermes-context/ /workspace/hermes-context` empty; symlinks match targets; stale DST file removed → A9 mirror holds
4. fallback branch (rsync masked via PATH fixture) → same final state as rsync branch on identical SRC fixture (A5)
5. `--dry-run` run → exit 0, DST byte-identical (stat + diff), DST not created if absent (A6/A16)
6. verify with injected mismatch (stale file, modified content, changed symlink) → exit nonzero, paths listed
7. refusals: missing SRC, root user, DST-inside-SRC → exit nonzero, stderr cites A14/A15, A12, A18 respectively; zero writes (DST/log untouched)
8. service: Type=oneshot; timer: OnUnitActiveSec=6h; both installable as user units, `systemctl --user daemon-reload` succeeds, no root required (A3)
9. log written only under $LOG_DIR (default ~/.cache/hermes-context/), only in real-run mode
]
constraints: [
"A5/A7: fallback converges to identical end state as rsync --delete; recursive, symlinks preserved",
"A6/A16: dry-run zero writes, never creates DST; byte-identical DST",
"A13: staging content-compared before any DST destruction",
"A19/A20: refusals only via closed list (A12, A14/A15, A18), cite A-numbers, zero writes on refusal path",
"A3: systemd user units, Type=oneshot, OnUnitActiveSec=6h, standalone exec, no root",
"A17: SRC_DIR/DST_DIR/LOG_DIR env-parameterized; deployed defaults = production values; must_keep: source path /opt/data/workspace/hermes-context/",
"A2: sync host→workspace one-way only",
"log always outside DST"
]
deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]