state: s0 := DST exists (/workspace/hermes-context/ with INDEX.md, agents/, config/); SRC canonical at /opt/data/workspace/hermes-context/; no artifact_dir yet; invariants A2,A5,A6,A8,A11,A12 active.
Δ := [step 1: mkdir -p artifact_dir/
  -> output: dir containing 4 empty files; output: `ls` shows the 4 filenames below
step 2: write artifact_dir/sync-hermes-context.sh; script implements:
  (a) realpath identity guard (A12): compare realpath(SRC) vs realpath(DST); on equal/ancestor/descendant/symlink-into-SRC -> exit 0, zero writes, both paths checked pre-destructive
  (b) log always to ~/.cache/hermes-context/sync.log, never inside DST; dry-run skips log creation entirely (A6, A8)
  (c) --dry-run: rsync --dry-run mode or read-only listing; zero writes incl. logs (A6)
  (d) primary path: rsync -a --delete SRC/ -> DST/ (A5)
  (e) fallback if rsync absent (A4, A7): verified copy of SRC to temp dir first, then rm -rf DST and move temp contents into place; recursive stale-subtree deletion at all depths; contents-sync, no nesting
  (f) post-sync verify (A9): recursive compare of contents, dir structure, symlink targets; on mismatch -> nonzero exit + FAIL to stderr, never warn-exit-0
  (g) sync never deletes its own entrypoints (~/.local/bin script, systemd units live outside mirrored tree) (A8)
  -> output: executable script, shell -n clean
step 3: write artifact_dir/hermes-context.service (user unit, ExecStart=%h/.local/bin/sync-hermes-context.sh, no root); output: unit text present, contains ExecStart line
step 4: write artifact_dir/hermes-context.timer (user unit, OnCalendar=*-*-* 0/6:00:00, Persistent=true); output: unit text present, contains OnCalendar line
step 5: write artifact_dir/README.md documenting must_keep: source path /opt/data/workspace/hermes-context/, dry-run zero-writes, user-level systemd no root; output: README present, all 3 must_keep strings appear verbatim
step 6: test matrix (per A1–A12): dry-run on live DST -> DST byte-identical pre/post (checksum gate, log file not created); real sync -> DST == SRC on contents/structure/symlinks; delete marker file in DST, re-sync -> deleted in both paths; fallback path forced (PATH without rsync) -> identical end state as rsync path; identity guard: run with SRC=DST -> exit 0, zero writes
  -> output: all matrix checks pass with nonzero-on-fail assertions]
accept:
  - artifact_dir contains exactly: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md
  - sync-hermes-context.sh passes `bash -n`; rsync primary path present (--delete)
  - fallback path converges to same end state as rsync path (recursive, stale deleted)
  - --dry-run: zero writes incl. no log file; DST byte-identical pre/post
  - verify enforces contents+structure+symlinks; mismatch -> nonzero exit
  - realpath identity guard fires (exit 0, no writes) on SRC==DST / ancestor / descendant / symlink-into-SRC
  - log path ~user/.cache/hermes-context/sync.log (outside DST); install path ~/.local/bin (outside mirrored tree)
  - units are user-level (systemctl --user); no root anywhere
  - README.md contains all 3 must_keep strings verbatim
constraints: ["no writes to SRC, ever", "no rm -rf DST before verified copy of SRC elsewhere", "no writes during dry-run (incl. logs)", "no root / no system-level units", "log & install paths outside mirrored tree", "no_resurrect: no accumulate-only or inside-DST-log designs"]
deliverable: ["artifact_dir/sync-hermes-context.sh", "artifact_dir/hermes-context.service", "artifact_dir/hermes-context.timer", "artifact_dir/README.md"]