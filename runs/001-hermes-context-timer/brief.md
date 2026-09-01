brief: hcdl register
state: s0 := {src=/opt/data/workspace/hermes-context/, dst=/workspace/hermes-context/, artifacts absent, no units installed}.
Δ := [
  step1: create /workspace/hermes-context/artifacts/ (or cwd artifact dir) and write sync-hermes-context.sh implementing: env defaults HERMES_CONTEXT_SRC=/opt/data/workspace/hermes-context/, HERMES_CONTEXT_DST=/workspace/hermes-context/, HERMES_CONTEXT_LOG=${HERMES_CONTEXT_DST:-}/.sync-hermes-context.log (default ~/.cache/hermes-context-sync.log, overridable via HERMES_CONTEXT_LOG); --dry-run flag propagates to rsync --dry-run and to fallback (compute-and-compare only); rsync path uses rsync -a --delete "${SRC}/" "${DST}/"; fallback path: if rsync absent, tar-pipe or cp -a plus recursive deletion of dst entries absent from src (find-based, prune nothing, delete stale files, dirs, subtrees at every depth); never write inside SRC; log one summary line (timestamp, mode, status) per real run only; exit 0 on success standalone.
    expect: file exists; grep matches: 'HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/', '--delete', '--dry-run' handling branch, fallback branch with 'command -v rsync' check, exit 0 path.
  step2: write hermes-context.service: [Unit] Description=Hermes context mirror sync; [Service] Type=oneshot; ExecStart=%h path or absolute path to sync-hermes-context.sh (no --dry-run).
    expect: file exists; contains '[Service]' and 'Type=oneshot' and 'ExecStart='.
  step3: write hermes-context.timer: [Unit] Description=...; [Timer] OnCalendar=*-*-* */6:00:00; Persistent=true; Unit=hermes-context.service; [Install] WantedBy=timers.target.
    expect: file exists; contains 'OnCalendar=*-*-* */6:00:00' and 'WantedBy=timers.target'.
  step4: write README.md documenting paths, env vars, dry-run purity, fallback semantics, install via cp to ~/.config/systemd/user/ + systemctl --user daemon-reload + systemctl --user enable --now hermes-context.timer, standalone usage.
    expect: file exists; mentions ~/.config/systemd/user/ and 'systemctl --user'.
]
accept: [
  1. sync-hermes-context.sh passes bash -n.
  2. sh sync-hermes-context.sh --dry-run with HERMES_CONTEXT_LOG pointed at a canary file: canary mtime+content byte-identical before/after; exit 0.
  3. real run: DST contents == SRC contents (diff -r clean); stale file created in DST subtree at depth>=2 is removed after run; no new files appear in SRC.
  4. run with PATH stripped of rsync (fallback): diff -r SRC DST clean; same stale-subtree deletion observed; exit 0.
  5. sync of SRC contents into DST does not create ${DST}/hermes-context nesting (test: marker file in SRC appears at DST/marker, not DST/<src-basename>/marker).
  6. real run appends exactly one line to HERMES_CONTEXT_LOG; dry-run appends zero.
  7. hermes-context.service and hermes-context.timer exist, contain expected directives, install to ~/.config/systemd/user/ per README; no root required anywhere.
]
constraints: ["no writes to /opt/data/workspace/hermes-context/ ever", "dry-run = zero writes including logs", "rsync --delete primary; fallback converges byte-identically, recursive deletion at every depth", "user units only, systemctl --user, no root", "src/ contents -> dst/, no nesting", "script exits 0 standalone without systemd"]
deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]