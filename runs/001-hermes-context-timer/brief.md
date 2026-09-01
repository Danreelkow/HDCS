state: s0 := packet hdcs/1 validated; A5/A6/A13/A17/A18 active; no_resurrect none; artifact set = 4 files; SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/ defaults; env override = gate contract; open item = env-algebra → KNOWN_LIMITATIONS only.
Δ := 
1. Write sync-hermes-context.sh (bash, set -euo pipefail):
   1a. Parse --dry-run flag; resolve SRC/DST from HERMES_CONTEXT_SRC/DST env else defaults; log path ~/.cache/hermes-context/sync.log (outside DST).
   1b. Guards (pre-write, both modes): SRC/DST nonempty, ≠ "/", ≠ ".", realpath-resolvable SRC; refuse if realpath SRC == realpath DST; refuse if either is ancestor/descendant of other; component-boundary check DST parent owned by invoking user.
   1c. If dry-run: run rsync -rlptgoD --delete --dry-run SRC DST (or cp-fallback dry-run = listing only), print plan to stdout, write nothing anywhere, exit 0. Expected output: script exits 0, zero files created/modified, DST nonexistent if absent.
   1d. Real run: mkdir -p ~/.cache/hermes-context; stage into temp dir on DST filesystem (mktemp -d "${DST}.stage.XXXXXX"); rsync -a --delete SRC/ stage/ ; if rsync unavailable: rm -rf stage/* then cp -a SRC/. stage/ then reconcile deletions (remove stage entries absent from SRC, recursive).
   1e. Verify: recursive content comparison stage vs SRC (diff -r --no-dereference or per-file cmp; symlinks compared by target; structure + contents + symlink targets must match). Expected output: mismatch → nonzero exit, stage discarded, DST untouched.
   1f. Touch DST: only after verify passes — mkdir -p DST if absent; atomically replace DST contents with stage (rsync --delete from stage to DST, or mv-based swap); remove stage. Log to sync.log (real runs only).
   1g. Standalone mode: script runs identically without systemd. Expected output: exit 0 on success, nonzero on any guard/verify failure.
2. Write hermes-context.service: [Unit] Description=Hermes context mirror sync; [Service] Type=oneshot; ExecStart=%h/.local/bin/sync-hermes-context.sh. Expected output: valid user unit, no root, no User= directive.
3. Write hermes-context.timer: [Timer] OnCalendar=*-*-* 00/6:00:00; Persistent=true; [Install] WantedBy=timers.target. Expected output: 6h cadence, user-timer compatible.
4. Write README.md: usage, dry-run semantics, env override contract (HERMES_CONTEXT_SRC/DST), install steps (systemctl --user enable --now hermes-context.timer), KNOWN_LIMITATIONS section citing env-algebra beyond A14 guard as open/non-blocking. Expected output: doc references all four must_keep items.
5. Self-check pass: bash -n script; systemd-analyze verify both units (if available). Expected output: no syntax errors.

accept:
  1. All four files exist and are non-empty.
  2. bash -n sync-hermes-context.sh → exit 0.
  3. Script contains: guard block before any write op; --dry-run path with zero write ops (no mkdir, no touch, no log write); stage→verify→touch-DST ordering (verify precedes any DST mutation); --delete or equivalent recursive-delete fallback.
  4. Script refuses: realpath(SRC)==realpath(DST); ancestor/descendant pair; SRC or DST ∈ {"/", "", "."}.
  5. Units contain no User=/root; timer OnCalendar yields 6h interval; WantedBy=timers.target.
  6. Log path and entrypoint install path both outside /workspace/hermes-context/.
  7. README contains strings "HERMES_CONTEXT_SRC", "HERMES_CONTEXT_DST", "dry-run", "KNOWN_LIMITATIONS".
  8. grep of script for defaults shows /opt/data/workspace/hermes-context/ and /workspace/hermes-context/.

constraints: ["A5: DST end state == SRC end state, recursive, both sync paths", "A6: dry-run → zero writes incl. logs; DST nonexistent post-dry-run", "A13: stage → verify(content-compared) → touch DST; no destruction before verification", "A17: env override = gate contract; deployed paths = defaults only", "A18: realpath identity + component-boundary + degenerate-path refusals, pre-destruction", "no root anywhere; systemd --user only", "log + entrypoint outside mirrored tree", "env-algebra beyond A14 → KNOWN_LIMITATIONS, non-blocking", "≤60 lines per file not required but brief ≤60 lines total"]
deliverable: ["sync-hermes-context.sh", "hermes-context.service", "hermes-context.timer", "README.md"]