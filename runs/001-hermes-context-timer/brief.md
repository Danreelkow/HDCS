state: s0 := SRC=/opt/data/workspace/hermes-context/ (read-only host mount, holds INDEX.md, agents/, config/); DST=/workspace/hermes-context/ (exists); no artifact dir yet. Required artifact set: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md. Log at ~/.cache/hermes-context/sync.log; entrypoint install target ~/.local/bin; units at ~/.config/systemd/user/.

Δ :=
1. Create artifact dir /workspace/hdcs/artifacts/hermes-context/ containing four files.
   Expected: dir exists with exactly sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md.
2. Write sync-hermes-context.sh (bash, set -euo pipefail):
   a. Defaults: SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/; flags: --dry-run, --src=, --dst=.
   b. A12/A14 gate: resolve realpath(SRC), realpath(DST), realpath(stage), realpath(log parent), realpath(entrypoint dir). Refuse (exit nonzero, zero writes) iff: SRC==DST, either contains the other, DST symlink-into-SRC, or DST boundary-contains any owned concrete path (stage dir, resolved log parent, resolved entrypoint dir) via component-split containment. Stage via mktemp -d; refuse if stage resolves inside SRC or DST (TMPDIR included).
   c. A13 staging: copy SRC contents -> stage (rsync -a --delete if available, else cp -a + recursive reconcile deleting stale files/subtrees at every depth). Then content-compare stage vs SRC per A9 class (contents + recursive structure + symlinks levels 1-3; ignore metadata/timestamps/hardlinks). Verify fail -> exit nonzero, never warn-and-exit-0, never touch DST.
   d. A6 dry-run: --dry-run performs ZERO writes of any kind — no stage, no log, no DST mutation; prints planned actions only; exit 0.
   e. A11 ordering: only after stage verify passes, sync stage -> DST (same dual path), then delete stage. Never rm -rf DST before verified copy exists in stage.
   f. Logging: append to ~/.cache/hermes-context/sync.log (mkdir -p, outside DST); skipped entirely in dry-run.
   g. Self-verify post-sync: compare DST vs SRC per A9 class; mismatch -> exit nonzero.
   h. Standalone-capable: no systemd dependency in script body.
   Expected: script passes bash -n; --help exits 0; grep shows A12 realpath guards precede any rm/destructive op; grep shows verify-before-DST-touch ordering.
3. Write hermes-context.service (user unit): ExecStart=%h/.local/bin/sync-hermes-context.sh, Type=oneshot.
   Expected: grep confirms ExecStart and Type=oneshot; no root/User= directives.
4. Write hermes-context.timer (user unit): OnCalendar=*-*-* 00/6:00:00, Persistent=true, Unit=hermes-context.service.
   Expected: grep confirms OnCalendar 6h cadence and Persistent=true.
5. Write README.md: usage (standalone run, --dry-run, install entrypoint to ~/.local/bin, systemctl --user enable --now hermes-context.timer), log location, KNOWN_LIMITATIONS section (newline-in-filename corpora; exotic env combos beyond A14 guard).
   Expected: README mentions all four ops and KNOWN_LIMITATIONS.
6. chmod +x sync-hermes-context.sh.
   Expected: executable bit set.

accept:
- Artifact dir contains exactly the four named files; script executable; bash -n clean on script.
- SRC and DST defaults appear verbatim in script.
- Script contains: realpath identity/ancestor/symlink-into-SRC checks before any destructive op; boundary-aware concrete-owned-path guard (component split, no string prefix); mktemp stage refused if resolving inside SRC/DST.
- Order in script: stage -> A9 content-compare -> only then DST write; self-verify exits nonzero on mismatch.
- --dry-run path: no mktemp, no log write, no DST write (code inspection: dry-run branch returns before any write syscall path).
- Dual path present: rsync --delete branch and cp -a + recursive reconcile branch; both delete stale entries recursively.
- Units: user-level (no root), OnCalendar 6h, Persistent=true, ExecStart points to ~/.local/bin entrypoint.
- Log path outside DST (~/.cache/hermes-context/sync.log); entrypoint outside mirrored tree.
- README documents standalone use, dry-run, install, timer enable, KNOWN_LIMITATIONS.

constraints: [SRC/DST defaults verbatim, A6 zero-write dry-run incl. logs, A9 verify nonzero on mismatch, A11-A13 destructive ordering is law, A14/A15 boundary-aware concrete guard no over-broad wall, no writes to host mount SRC, log/entrypoints never inside DST, user-level systemd only, script standalone-capable]

deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]