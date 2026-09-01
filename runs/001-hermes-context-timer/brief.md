state: s0 := validated hdcs/1 packet; SRC=/opt/data/workspace/hermes-context/; DST=${HERMES_CONTEXT_DST:-/workspace/hermes-context/}; log=~/.cache/hermes-context/sync.log; artifact dir = artifact_dir/.
Δ :=
1. Create artifact_dir/, write sync-hermes-context.sh:
   1a. parse --dry-run flag; if set: perform rsync --dry-run OR fallback tree-compare; print plan to stdout; exit 0 → expected: zero writes anywhere, no log entry, DST untouched (created or not).
   1b. guards before any write (both paths): realpath exists? SRC readable? exit nonzero cleanly → expected: guard refusals = exit≠0, stderr message, zero writes.
   1c. identity/boundary guard A12+A14: refuse when realpath(SRC)==realpath(DST), DST ancestor/descendant of SRC, DST resolves through symlink into SRC, or realpath(DST)==/ inside owned concrete paths (mktemp stage dir, resolved log parent dir, entrypoint dir) via component-split comparison (not string prefix) → expected: clean nonzero exit, no writes.
   1d. mktemp -d stage dir (outside DST & SRC trees, e.g. under ${TMPDIR:-/tmp} after guard check) → expected: stage dir created, path recorded.
   1e. copy SRC→stage: rsync -a --delete if rsync present; else tar-pipe (tar -C SRC -cf - . | tar -C stage -xf -) with cp -a reconcile fallback for --delete (delete-in-stage stale entries at every depth) → expected: stage mirrors SRC contents (A9).
   1f. self-verify stage vs SRC: content-compare (cmp per file), structure walk, symlink target check; mismatch → rm -rf stage, exit nonzero → expected: verified_copy only on full match; nonzero on staging mismatch.
   1g. touch DST: mkdir -p DST (A16); rsync -a --delete stage/ DST/ or cp -a + recursive reconcile deleting stale subtrees at every depth → expected: DST end state == SRC end state.
   1h. one-line summary to ~/.cache/hermes-context/sync.log (mkdir -p its parent first, outside mirrored tree); log only on real runs → expected: single line, timestamp + files synced/deleted count.
2. Write hermes-context.service (systemctl --user, ExecStart pointing at script), hermes-context.timer (OnCalendar=00/6:00, OnUnitActiveSec=6h, Persistent=true) → expected: user-level units, no root.
3. Write README.md: install to ~/.local/bin/ (outside DST), enable timer, --dry-run test procedure, statement that sync is exact recursive mirror (contents+structure+symlinks, stale deleted), fallback equivalence, KNOWN_LIMITATIONS section (A10/A15 adversarial env combos cited) → expected: all MUST_KEEP lines verbatim.
4. chmod +x sync-hermes-context.sh → expected: standalone-executable.

accept:
- [ ] sync-hermes-context.sh --dry-run with DST absent: exit 0, DST still nonexistent, no log file created.
- [ ] rsync path: after real run, find DST -printf matches SRC structure exactly; contents equal; symlinks preserved; stale subtree at depth≥1 deleted.
- [ ] cp/tar fallback path (rsync hidden from PATH): identical end state to rsync path.
- [ ] SRC==DST (or DST under SRC via symlink): exit≠0, no stage dir created, no log write.
- [ ] Simulated staging mismatch (corrupt one staged file): exit≠0, DST untouched.
- [ ] HERMES_CONTEXT_DST set to resolved log-parent dir: refused nonzero, no writes.
- [ ] Log: exactly one line per real run; no log entry for dry-runs.
- [ ] Units: systemctl --user enable hermes-context.timer works without root; OnCalendar=00/6:00 present.
- [ ] README contains all three MUST_KEEP lines verbatim + KNOWN_LIMITATIONS section.

constraints:
- A2 one-way only; never write to SRC.
- A6+A16: dry-run zero writes incl. logs, never creates DST.
- A8: log parent + entrypoints never inside SRC or DST.
- A11: strict stage → verify → touch ordering; no DST deletion before verified_copy.
- A13: "verified" only for content-compared copies; never warn-and-exit-0 on mismatch.
- A14/A15: owned-path guard on concrete instantiated paths, component-boundary compare, not string prefix, not generic ancestors (/tmp, TMPDIR).
- POSIX exit codes; bash strictly; no root anywhere.
- Line budget: script ≤ ~250 lines, README concise.

deliverable: [artifact_dir/sync-hermes-context.sh, artifact_dir/hermes-context.service, artifact_dir/hermes-context.timer, artifact_dir/README.md]