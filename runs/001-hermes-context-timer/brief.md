state: s0 := {SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/, artifact_dir=/workspace/hdcs/artifacts/hermes-context-sync/, LOG default ~/.cache/hermes-context-sync.log, A1-A15 resolved, Q16/Q17 open→KNOWN_LIMITATIONS}. Δ :=
1. Write sync-hermes-context.sh:
   1a. Config via env: SRC, DST, LOG (default ~/.cache/hermes-context-sync.log), ART_DIR (default /workspace/hdcs/artifacts/hermes-context-sync/). Expected: script sources env, no hardcoded-only paths.
   1b. realpath guard A12 pre-ANY-op: canonicalize SRC,DST; reject exit≠0 zero-writes if equal, ancestor/descendant, or DST symlink-resolves into SRC (A11). Expected: guard trips before any write, incl. log.
   1c. --dry-run mode: rsync -aN --delete --dry-run path; if fallback path, compute plan via NUL-delimited find traversal, diff-only, NO writes incl. LOG (A6). Expected: byte-identical tree before/after dry-run.
   1d. Real path: rsync -a --delete if rsync present; else NUL-delimited find | cpio/tar-pipe or cp -a + prune of stale entries — same convergence ∀ depth (A4/A5/A7). Never rm -rf DST before a verified copy exists elsewhere (A11).
   1e. Self-verify A9: recursive compare contents (cmp), structure (file set), symlinks (targets) via NUL-delimited traversal; mismatch exit≠0. Expected: seeded mismatch → nonzero exit.
   1f. Log: real-run only, 1 line, append (A14); LOG forced outside DST (if LOG ∈ DST or unset-safe default ~/.cache, A8). Exit codes: 0 ok, ≠0 verify/guard fail; exotic → KNOWN_LIMITATIONS note in README, non-blocking (A10).
2. Write hermes-context.service: ExecStart=%h/.local/bin/sync-hermes-context.sh (fallback /workspace/hdcs/bin), Type=oneshot. Expected: no root, User default --user scope.
3. Write hermes-context.timer: OnCalendar=*-*-* 00/6:00:00 (every 6h), Persistent=true, unit binding to service. Expected: systemctl --user compatible.
4. Write README.md: usage (standalone + systemd --user enable), env vars, dry-run semantics, fallback convergence recursive claim (A7 correct), KNOWN_LIMITATIONS for Q16 (newline-in-filename, NUL-traversal scope) and Q17 (LOG∈DST real-run churn only).
5. Place scripts in artifact_dir; verify all four files present and shellcheck-clean (if available) — non-blocking if shellcheck absent.
accept:
- 4 files exist: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md in artifact_dir.
- bash sync-hermes-context.sh --dry-run: exit 0, tree DST byte-identical before/after, LOG unmodified/absent (A6).
- Real run (rsync present): exit 0, DST == SRC recursively {contents, structure, symlinks}; stale test file deleted; 1-line appended to LOG; re-run idempotent (no changes, A13).
- Real run (rsync hidden via PATH shim): fallback converges identically, exit 0 (A4/A7).
- Seeded mismatch post-sync → verify exit≠0.
- SRC==DST invocation and DST-inside-SRC invocation → exit≠0, zero writes.
- .timer: `systemctl --user` parseable, OnCalendar 6h; service ExecStart points at script path.
constraints: [A5,A6,A7,A8,A9,A10,A11,A12,A13,A14 per shared context; must_keep 3/3 verbatim; no rm -rf DST pre verified-copy; no writes outside {DST, LOG, artifact_dir}; Q16/Q17 → README KNOWN_LIMITATIONS, non-blocking]
deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md] in /workspace/hdcs/artifacts/hermes-context-sync/