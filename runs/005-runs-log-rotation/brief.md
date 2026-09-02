build brief → B1
state: s0 := gate READY; packet hdcs/1 folded; targets: conf + rotate script (dry-run default, --apply) + verifier + README; RUNS_DIR=/workspace/hdcs/runs, ARCHIVE_DIR=/workspace/.hdcs-rotate/archive; bash+coreutils only.
Δ:
1. Write hdcs-runs-rotation.conf: RUNS_DIR, ARCHIVE_DIR, PATTERN="*", AGE_DAYS="30" with comment header. → expected: file parses as shell source; grep finds all four keys.
2. Write rotate-hdcs-runs.sh:
   - a. source conf; env vars override conf (RUNS_DIR, ARCHIVE_DIR, PATTERN, AGE_DAYS). → expected: RUNS_DIR=x ./rotate-hdcs-runs.sh --dry-run uses x.
   - b. default mode (no args) = dry-run: list would-move files via find -type f -name "$PATTERN" -mtime +$AGE_DAYS, print actions, exit 0, zero writes. → expected: no ARCHIVE_DIR creation; RUNS_DIR mtimes/contents unchanged after dry-run.
   - c. --apply: validate paths per A4 first — RUNS_DIR==ARCHIVE_DIR → refuse citing A4 (identity); ARCHIVE_DIR inside RUNS_DIR or vice versa → refuse (containment); RUNS_DIR nonexistent/non-dir → refuse (degenerate). All refusals: stderr message with A-number, exit 2, zero writes. → expected: each case exits 2, no writes.
   - d. for each candidate: rel=$(realpath --relative-to "$RUNS_DIR" "$f"); dest="$ARCHIVE_DIR/$rel"; mkdir -p dirname(dest); mv to name-preserving suffixed name if dest exists (append .1, .2, … before extension or at end); mv once; cmp "$src" "$dest" post-move; on cmp mismatch print error exit 3. → expected: bytes identical (cmp exit 0); original gone from RUNS_DIR; tree structure mirrored under ARCHIVE_DIR outside RUNS_DIR.
   - e. second --apply run: no candidates remain matching PATTERN+AGE that were moved; run exits 0 with no moves. → expected: idempotent no-op.
   - f. no logrotate anywhere; no root checks; set -euo pipefail.
3. Write verify-rotation.sh: parse conf (source), check no pending rotation (no RUNS_DIR files matching PATTERN older than AGE_DAYS), check archive consistent (every archived file cmp-verifiable against nothing pending; archive exists only if moves made; all archived paths outside RUNS_DIR). Exotic filenames/race conditions → print KNOWN_LIMITATIONS warning, not FAIL. Exit 0 ⇔ conf parses ∧ no pending rotation ∧ archive consistent (A6). → expected: exit 0 on clean state; nonzero on pending or inconsistent archive.
4. Write README.md: usage, dry-run default (A1), toolchain/no-root/no-logrotate (A2), path-law refusals (A4), idempotence (A5), verifier criteria (A6), KNOWN_LIMITATIONS section (A7). → expected: section headers present for each A-number and KNOWN_LIMITATIONS.
5. Self-test in sandbox dirs (not /workspace/hdcs/runs): create tmp runs with old/new files, run dry-run, --apply twice, verify. → expected: dry-run zero-write; apply moves old only; second apply no-op; verify exit 0.
accept:
1. dry-run creates nothing: test dir unchanged, no ARCHIVE_DIR after dry-run (A1).
2. grep -L logrotate on all four artifacts returns nothing (A2/no_resurrect).
3. identity/containment/degenerate each exit 2 with cited A-number, zero writes (A4).
4. cmp succeeds on every moved file; second --apply moves 0 files, exit 0 (A5).
5. verify-rotation.sh exits 0 post-rotation; exits nonzero if a stale file is planted in RUNS_DIR (A6).
6. README contains KNOWN_LIMITATIONS section (A7).
7. all four files exist at deliverable paths; bash -n passes on all scripts.
constraints: [A1 dry-run zero-write, A2 bash+coreutils only no root no logrotate, A4 refuse+cite+zero-write, A5 move-once cmp-verified name-preserving suffix, A6 exit-0 criteria, A7 exotic→KNOWN_LIMITATIONS not FAIL, archived files outside RUNS_DIR, env-over-conf precedence, ≤60 lines brief]
deliverable: [hdcs-runs-rotation.conf, rotate-hdcs-runs.sh, verify-rotation.sh, README.md]