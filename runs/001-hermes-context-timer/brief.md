state: s0 := SRC=/opt/data/workspace/hermes-context/ (exists: INDEX.md, agents/, config/); DST=/workspace/hermes-context/; artifact dir /workspace/hdcs/artifacts/hermes-context-freshness/ empty; no deliverables built yet. Invariants A2–A13 binding as registered.

Δ := 
1. mkdir -p /workspace/hdcs/artifacts/hermes-context-freshness/
   → expected: dir exists, empty.
2. Write sync-hermes-context.sh (bash, set -euo pipefail):
   a. Parse --dry-run flag; resolve SRC=${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}, DST=${HERMES_CONTEXT_DST:-/workspace/hermes-context/} via realpath.
   b. A12 guard: if realpath(SRC)==realpath(DST) ∨ either is ancestor/descendant of other ∨ DST resolves through symlink into SRC → exit nonzero, zero writes, message to stderr.
   c. Log path: ${HERMES_CONTEXT_LOG:-$HOME/.cache/hermes-context/sync.log}; assert realpath(log) not inside realpath(DST) (A8); mkdir -p log dir only on real runs.
   d. Real run: mkdir staging dir on same filesystem as DST (e.g. DST/../.hc-stage.$$); copy SRC→staging (rsync -a --delete SRC/ stage/ if rsync ∈ PATH, else cp -a SRC/. stage/ then reconcile deletions by diffing and removing stale entries recursively — A4/A5/A7 semantics).
   e. A13 verify: content-compare staging vs SRC recursively (diff -r or per-file cmp, incl. symlink targets); fail → rm staging, exit nonzero.
   f. Touch DST: rsync -a --delete stage/ DST/ (or mv/reconcile equivalent achieving identical A9 end state); rm staging.
   g. Dry-run: compute planned changes (rsync --dry-run --delete if available; else read-only diff listing) → print to stdout only; ZERO writes to DST, staging, log, or any target (A6).
   h. Real run success → append one-line log entry (timestamp, mode, status) to log file.
   i. Idempotent: second consecutive real run = no-op changes, exit 0.
   → expected: script exists, bash -n passes, shellcheck passes (or no errors), executable bit set.
3. Write hermes-context.service: [Unit] Description=...; [Service] Type=oneshot; ExecStart=%h/.local/bin/sync-hermes-context.sh (fallback: absolute artifact path documented in README).
   → expected: file exists, ExecStart points outside DST.
4. Write hermes-context.timer: [Timer] OnCalendar=6h (OnUnitActiveSec=6h equivalent accepted); Persistent=true; [Install] WantedBy=timers.target.
   → expected: file exists, 6h cadence, user-unit form (no root, no system paths).
5. Write README.md: install steps (copy script to ~/.local/bin, units to ~/.config/systemd/user/, systemctl --user enable --now hermes-context.timer), source-change note (auto-mirrored ≤6h or run script manually), --dry-run test instructions, A7 section stating recursive exact-mirror with stale deletion at all depths, KNOWN_LIMITATIONS section (newline-in-filename corpora; hostile env DST→log dir) with repro notes.
   → expected: file exists; contains sections install/dry-run/sync-strategy/limitations; A7 wording correct.
6. Self-check pass: bash -n all shell; grep must_keep items present; confirm no path in deliverables writes to SRC.
   → expected: all checks exit 0.

accept: 
- All 4 files exist in /workspace/hdcs/artifacts/hermes-context-freshness/ and are non-empty.
- bash -n sync-hermes-context.sh exits 0; script is executable.
- Script contains: realpath-based A12 guard before any write; staging dir creation; recursive content-verify of staging vs SRC before touching DST; nonzero exit on verify fail; --dry-run branch with no mkdir/redirect/rsync-write to DST or log; log path default ~/.cache/hermes-context/sync.log with outside-DST assertion.
- rsync branch uses -a --delete; fallback branch achieves identical A9 end state incl. recursive stale deletion.
- .service ExecStart resolves outside /workspace/hermes-context/; .timer cadence = 6h; both are user units (no root, no /etc/systemd/system).
- README contains correct A7 recursive-deletion statement and KNOWN_LIMITATIONS with repro notes.
- grep for "dry-run", "--delete", "realpath", "systemctl --user" each hits in expected files.

constraints: [A2 no writes to SRC ever; A4 fallback = A9-identical semantics, no nesting; A5/A7 exact mirror, stale deleted recursively; A6 dry-run zero writes incl. logs; A8 log+install paths outside DST; A9 verify fail = nonzero, never warn+exit0; A11/A12/A13 guards+order=law: stage→verify→touch DST; A10 exotic triggers → KNOWN_LIMITATIONS not FAIL; no root anywhere; deliverable_set exactly the 4 files]

deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md — all in /workspace/hdcs/artifacts/hermes-context-freshness/]