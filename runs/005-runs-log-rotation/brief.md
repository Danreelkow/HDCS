state: s0 := {artifact_dir := <operator-supplied artifact dir>; conf := hdcs-runs-rotation.conf with exactly 5 keys, values verbatim RUNS_DIR=/workspace/hdcs/runs, ARCHIVE_DIR=/workspace/.hdcs-rotate/archive, AGE_DAYS=14, PATTERN=*.txt, KEEP=50, no comments; rotate := rotate-hdcs-runs.sh (dry-run default, --apply sole writing mode); verify := verify-rotation.sh (zero-write); README.md; toolchain := bash ∧ coreutils(find,cmp,realpath,cksum); no root, no logrotate; stale ⇔ floor(age_days) >= AGE_DAYS; verify exit 0 ⇔ conf parses ∧ ¬∃ stale under RUNS_DIR ∧ archive listing intact; fresh PATTERN match ¬fail; idempotence: second --apply byte-identical no-op; prune touches ARCHIVE_DIR only; exotic filenames/concurrency → KNOWN_LIMITATIONS}

Δ:
1. Write hdcs-runs-rotation.conf — expect: file with exactly the 5 KEY=VALUE lines above, no comments, no extra keys, byte-exact values.
2. Write rotate-hdcs-runs.sh — expect: bash script; default (no args) = dry-run printing planned moves/prunes, zero writes (no ARCHIVE_DIR mkdir, no state files); `--apply` sole writing mode: mkdir -p ARCHIVE_DIR, move stale files (stale test computed explicitly, e.g. epoch arithmetic floor((now-mtime)/86400) >= AGE_DAYS, never bare `-mtime +N`) from RUNS_DIR to ARCHIVE_DIR, names preserved + rotation suffix (e.g. `.1` on collision), cmp archived vs original before removing source, prune ARCHIVE_DIR to KEEP newest (never RUNS_DIR); path law A4 enforced on RUNS_DIR/ARCHIVE_DIR (identity, containment either direction, degenerate '', '.', '/' → refuse citing A-number; env override allowed; set-but-empty → refuse); second --apply run byte-identical no-op.
3. Write verify-rotation.sh — expect: zero-write checker; every check via flag accumulator (never bare pipeline status); checks: conf parses with exactly 5 keys + verbatim values; no stale file under RUNS_DIR (same explicit boundary); archive listing intact (names preserved + suffixes, no orphans); fresh PATTERN match does NOT fail; mktemp only outside artifact dir and tree or fd redirection only; exit 0 iff all pass.
4. Write README.md — expect: usage (dry-run default, --apply), conf keys table, stale boundary explanation, idempotence note, KNOWN_LIMITATIONS section (exotic filenames, concurrent writes → not FAIL).
5. chmod +x both scripts — expect: executable bits set.
6. Self-check dry-run — expect: running rotate-hdcs-runs.sh (no args) produces zero writes anywhere; exit 0.

accept:
- conf: `grep -c '=' conf` = 5; each line matches operator-fixed values verbatim; no comment lines.
- dry-run: before/after `find /workspace -newer /tmp/marker` empty; no ARCHIVE_DIR created.
- --apply: stale file moved to ARCHIVE_DIR with cmp equal; name preserved + suffix; RUNS_DIR pruned never; second --apply run output byte-identical (`diff run1.log run2.log` empty) and no further changes.
- stale boundary: file with age exactly AGE_DAYS-1 day 23h NOT moved; age >= AGE_DAYS moved (explicit computation, no bare `-mtime +N` in scripts: `grep -n 'mtime +[0-9]'` empty).
- verify: exit 0 on clean state; exit ≠0 when stale file planted; fresh PATTERN match present → still exit 0; verify creates no files (`strace`-free check: run with `TMPDIR` outside tree, tree mtime unchanged); all checks via flag accumulator (`grep -nE '\|\| *(exit|false)' verify-rotation.sh` shows no bare-status reliance).
- path law: RUNS_DIR=ARCHIVE_DIR, one containing the other, '', '.', '/' → refuse with A4 cited; set-but-empty env override → refuse.
- no logrotate, no sudo/root anywhere: `grep -inE 'logrotate|sudo' *.sh README.md` empty.
- KNOWN_LIMITATIONS present in README.md.

constraints: [A1 zero writes in dry-run and verify; A2 bash+coreutils only, logrotate ⇒ defect, no root; A4 path refusal law with cited A-number; A5 move-once idempotence; A6 exit semantics + explicit stale boundary; A7 flag accumulator for every verify check; conf exactly 5 keys, operator-fixed values, no comments; prune touches ARCHIVE_DIR only; verify mktemp outside artifact dir/tree or fd redirection only; exotic filenames/concurrency → KNOWN_LIMITATIONS not FAIL]

deliverable: [hdcs-runs-rotation.conf, rotate-hdcs-runs.sh, verify-rotation.sh, README.md]