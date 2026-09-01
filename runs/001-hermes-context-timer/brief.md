build brief → B1

state: s0 := S_0 {A1–A9 resolved, no open items, must_keep = [source path /opt/data/workspace/hermes-context/, dry-run zero writes, user units no root]}
Δ :=
  1. create sync-hermes-context.sh:
     a. SRC := ${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}; DST := ${HERMES_CONTEXT_DST:-/workspace/hermes-context/}
        expect: both env-overridable, literal defaults present
     b. parse --dry-run flag; set DRYRUN=1
        expect: --dry-run sets mode, no other behavior change
     c. rsync branch: if command -v rsync -> run `rsync -a --delete "$SRC"/ "$DST"/` (or --dry-run); else fallback branch
        expect: contents-level sync, trailing slashes correct, no nesting (A4/Q4)
     d. fallback branch: `cp -a "$SRC"/. "$DST"/` then recursive reconciliation deleting stale entries ∀ depth (walk SRC relative paths; delete DST paths not in SRC, dirs included); mirror symlinks as-is
        expect: end state identical to rsync branch (A5/A7/A9)
     e. dry-run gate: all writes (mirror ops AND log append) guarded by DRYRUN; DST untouched
        expect: exit 0, zero bytes written anywhere (A6)
     f. real-run logging: one-line summary (timestamp, mode=rsync|fallback, counts copied/deleted, exit) >> ~/.cache/hermes-context/sync.log (mkdir -p, outside DST)
        expect: log outside DST always (A8)
     g. safety: never write to SRC; never delete script's own entrypoint path; verify step compares mirror_class {contents, dir structure recursive, symlinks}; mismatch -> exit != 0
        expect: A2, A8, self_verify honored
  2. create hermes-context.service: [Unit] desc; [Service] Type=oneshot; ExecStart=%h/.local/bin/sync-hermes-context.sh
     expect: ExecStart literal present, user-level
  3. create hermes-context.timer: OnCalendar=*-*-* 00/6:00:00; Persistent=true; [Install] WantedBy=timers.target
     expect: every 6h, systemctl --user installable, no root
  4. create README.md: install (cp to ~/.local/bin, units to ~/.config/systemd/user, systemctl --user enable --now hermes-context.timer), source-change workflow, --dry-run test, sync strategy section (recursive exact mirror, A5/A7/A9 semantics, rsync/fallback convergence)
     expect: all four topics covered, must_keep phrasing intact
  5. self-check pass: shellcheck-clean intent; simulate dry-run mentally → confirm zero writes
     expect: no write paths reachable under DRYRUN=1

accept:
  - [ ] 4 files exist: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md
  - [ ] grep confirms HERMES_CONTEXT_SRC default /opt/data/workspace/hermes-context/ and HERMES_CONTEXT_DST default /workspace/hermes-context/
  - [ ] grep confirms `rsync -a --delete` with trailing-slash contents semantics and fallback cp -a branch
  - [ ] fallback branch deletes stale subtrees recursively (no depth limit)
  - [ ] DRYRUN=1 path: no mkdir, no rsync/cp without --dry-run, no log write — statically verifiable in code
  - [ ] log path ~/.cache/hermes-context/sync.log; no log/entrypoint path inside DST
  - [ ] service ExecStart points outside DST; timer OnCalendar 6h; no root/systemctl system anywhere
  - [ ] verify routine exits != 0 on any mirror_class mismatch
  - [ ] must_keep strings all present verbatim or semantically exact

constraints:
  - A1–A9 invariants all hold; writes only to DST (+ log dir outside DST)
  - no root anywhere; standalone executable without systemd
  - no timestamps/metadata/hardlink verification (A9 out-of-scope)
  - entrypoints never inside DST; sync never deletes own entrypoint
  - script must fail nonzero, never warn-and-exit-0, on mirror mismatch

deliverable:
  - sync-hermes-context.sh
  - hermes-context.service
  - hermes-context.timer
  - README.md