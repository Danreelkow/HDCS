state: s0 := artifact dir empty; SRC=/opt/data/workspace/hermes-context/ exists with INDEX.md, agents/, config/; DST=/workspace/hermes-context/ exists; sync_ps two paths (rsync primary, cp-fallback); guards A11/A12/A13 unbuilt; user units absent.
Δ :=
  1. Create artifact dir /workspace/hdcs/hermes-context-artifact/ with sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md.
     Expected: 4 files exist; `ls` lists exactly them.
  2. Write sync-hermes-context.sh:
     - flag parsing: `--dry-run` sets DRYRUN=1; usage exit 2 on unknown flags.
     - A12 identity guard first: resolve realpath(SRC), realpath(DST); refuse clean exit 1 with no writes iff equal realpath, ancestor/descendant relation, or DST path contains a symlink component resolving into SRC. Run before any other action.
     - A11 guard: SRC==DST reject; no `rm -rf`/delete of DST before a staged copy of SRC is verified.
     - A13 order: stage SRC to temp staging dir (mktemp under ${TMPDIR:-/tmp}) -> verify staged tree vs SRC via content+structure+symlink recursive compare (A9 class; byte compare contents, symlink targets, dir structure; ignore metadata/timestamps) -> only on verify success touch DST; staging/verify failure -> exit nonzero, DST untouched.
     - Real run: prefer rsync (`rsync -a --delete SRC/ stage/`); if rsync absent, cp -a / tar-pipe fallback with recursive reconcile including stale-subtree deletion (A7). Both paths converge to same mirror end state.
     - Apply to DST: replace DST contents to mirror (delete stale recursively), via verified staging copy; entrypoints and logs outside DST never touched.
     - Logging: on real run append one line (timestamp, result, path count or error) to ${HERMES_CTX_LOG:-$HOME/.cache/hermes-context/log} (mkdir -p, outside DST). Dry-run: zero writes of any kind, incl. no log file.
     - Exit codes: 0 success/dry-run clean; nonzero on guard refusal, verify mismatch (never warn-exit-0).
     Expected: `bash -n sync-hermes-context.sh` passes; `shellcheck` (if present) no errors; script standalone-runnable without systemd (A3).
  3. Write hermes-context.service (Type=oneshot, ExecStart pointing at installed sync script, User-scoped, no root) and hermes-context.timer (OnCalendar=0 */6:00:00, Persistent=true, Unit=hermes-context.service).
     Expected: `systemd-analyze verify` (if available) clean; `grep OnCalendar` shows 6h cadence.
  4. Write README.md: install steps (script -> ~/.local/bin or /workspace/hdcs/bin; units -> ~/.config/systemd/user/; `systemctl --user daemon-reload && systemctl --user enable --now hermes-context.timer`), source-change note (next timer tick or manual run), dry-run test instructions, sync-strategy section stating exact-mirror semantics: recursive, stale deleted both sync paths (A7), fallback identical, "verified" only means content-compared staging vs SRC.
     Expected: grep finds "exact mirror", "--dry-run", "systemctl --user"; no claim of unverified-copy-as-verified.
  5. Self-test: `sync-hermes-context.sh --dry-run` on live SRC/DST -> exit 0; checksum DST (find -type f -exec sha256sum) pre/post identical; no log line written.
     Expected: dry-run exit 0, DST checksums identical pre/post, no log write.
  6. Self-test real run: run script; verify DST == SRC mirror (diff -r contents; symlink target compare recursive); run again -> idempotent, exit 0. Create stale file in DST, rerun, confirm deleted.
     Expected: diff -r SRC DST empty; second run exit 0 no errors; stale file removed.
  7. Guard tests: (a) HERMES_CONTEXT_DST=$SRC -> clean nonzero exit, no writes; (b) DST set to parent/ancestor of SRC -> nonzero; (c) DST via symlink resolving into SRC -> nonzero; each with no DST modification.
     Expected: three guard cases exit nonzero with refusal message; checksums unchanged.

accept:
  - Exactly 4 files in /workspace/hdcs/hermes-context-artifact/: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md
  - `--dry-run`: exit 0, DST sha256 manifest identical pre/post, no log file write (A6/V1)
  - Real run end state: `diff -r` SRC vs DST empty; all symlinks same targets, recursive; mismatch case (seeded) -> nonzero exit (A5/A7/A9/V2)
  - cp-fallback path (simulate rsync absent via PATH shim) yields identical mirror end state incl. stale deletion
  - Guard tests a/b/c exit nonzero, zero writes (A12/V3)
  - Audit: no destructive op on DST precedes staging-verify pass (A11/A13/V4)
  - Log path resolves outside DST; entrypoints not inside mirrored tree (A8)
  - Script runs standalone without systemd (A3); units are user units, no root
  - README contains MUST_KEEP phrases: "source path is /opt/data/workspace/hermes-context/", "dry-run mode that performs no writes", "systemd user units, no root required"

constraints:
  - A12 identity check before any destructive op; A11 no rm -rf DST pre verified copy; A13 stage->verify->touch DST
  - A9: mismatch -> nonzero exit, never warn-exit-0
  - No unverified-copy-as-verified; no accumulate-only fallback; no logs/artifacts inside DST
  - MUST_KEEP phrases verbatim in README

deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]