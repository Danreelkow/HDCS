build brief — worker B1

state: s0 := artifact_dir contains nothing yet; conf values fixed by packet (RUNS_DIR=/workspace/hdcs/runs, ARCHIVE_DIR=/workspace/.hdcs-rotate/archive, AGE_DAYS=14, PATTERN=*.txt, KEEP=50); laws L_rot/L_stale/L_modes/L_paths/L_idem/L_verify/L_status/L_conf in shared context; open: none.

Δ := 
1. Write hdcs-runs-rotation.conf — exactly 5 KEY=VALUE lines, no blanks/comments:
   expected output: file with lines RUNS_DIR=/workspace/hdcs/runs, ARCHIVE_DIR=/workspace/.hdcs-rotate/archive, AGE_DAYS=14, PATTERN=*.txt, KEEP=50; `grep -c '=' conf` = 5; `wc -l` = 5.
2. Write rotate-hdcs-runs.sh (bash, set -euo pipefail):
   a. parse conf: read KEY=VALUE lines; ignore blank/# lines; any other non-empty non-comment line → exit nonzero (L_conf).
   b. env overrides HDCS_RUNS_DIR/HDCS_ARCHIVE_DIR; set-but-empty env → refuse citing A4, exit nonzero, zero writes.
   c. path law: refuse RUNS_DIR==ARCHIVE_DIR, containment either direction (realpath -m), degenerate '', '.', '/' — cite A-number in message, zero writes.
   d. default (no --apply): dry-run — list would-archive files (epoch check: age=$(( $(date +%s) - $(stat -c %Y f) )); age >= AGE_DAYS*86400), print plan, write nothing anywhere.
   e. --apply: mkdir -p ARCHIVE_DIR; for each stale f (same epoch boundary, PATTERN match under RUNS_DIR): move to ARCHIVE_DIR preserving relative path, on name collision append rotation suffix (name.1, name.2, …); then prune ARCHIVE_DIR per PATTERN to newest KEEP entries.
   f. expected outputs: `bash -n` clean; dry-run on fixture leaves RUNS_DIR and ARCHIVE_DIR mtimes/contents untouched (`find ARCHIVE_DIR | wc -l` unchanged, no new dirs); --apply moves a 15-day-old fixture file, keeps a 13-day-old file; second --apply produces byte-identical ARCHIVE_DIR (`cksum` listing diff empty); archived bytes match originals via cmp.
3. Write verify-rotation.sh (read-only grader):
   a. parse conf same rules (L_conf); scratch only via mktemp -d outside RUNS_DIR/ARCHIVE_DIR/artifact trees.
   b. checks: conf parses; no stale f under RUNS_DIR (epoch boundary, accumulator FLAG=0; set inside find/while; test after loop — no bare `[ cond ] && exit 1`); archive intact: newest KEEP present and matches recorded listing (cksum).
   c. exit 0 iff all pass; fresh PATTERN files never fail; verify writes nothing to RUNS_DIR/ARCHIVE_DIR/artifact.
   d. expected outputs: `bash -n` clean; on post-apply fixture exit 0; on fixture with a fresh stale-planted file exit nonzero; `find RUNS_DIR ARCHIVE_DIR -newer <marker>` empty after verify run.
4. Write README.md: usage, modes, path law, idempotence, boundary semantics, KNOWN_LIMITATIONS (exotic filenames, concurrent writes — A7).
   expected output: README mentions dry-run default, --apply, A4 refusal, A7 limitations.

accept:
- [ ] conf: exactly 5 lines, exact values per must_keep; parser rejects a 6th junk line (test: append junk → nonzero).
- [ ] dry-run default: zero writes to RUNS_DIR, ARCHIVE_DIR, state (snapshot before/after identical).
- [ ] --apply: stale file (floor(age)>=14) moved, path preserved, bytes cmp-identical, suffix on collision; fresh file untouched.
- [ ] second --apply: ARCHIVE_DIR cksum-listing byte-identical to first (idempotence, A5).
- [ ] path law: RUNS_DIR==ARCHIVE_DIR, containment, '', '.', '/' each refused citing A-number, zero writes; set-but-empty env refused.
- [ ] verify: exit 0 on clean post-apply state; nonzero on planted stale or broken conf; accumulator pattern used (no bare `[ ] && exit 1`); verify leaves trees untouched.
- [ ] no root, no logrotate anywhere (`grep -ri logrotate *.sh` empty); bash+coreutils only.
- [ ] all four deliverables exist, `bash -n` clean on both scripts.

constraints:
- bash+coreutils only (find, cmp, realpath, cksum, mktemp, stat, date); no root; no logrotate (A2)
- dry-run default zero-write (A1); --apply sole writing mode
- stale boundary: explicit epoch seconds, age >= AGE_DAYS*86400; no bare -mtime +N (L_stale)
- path refusals cite A-number, zero writes (A4)
- verify strictly read-only vs artifact/RUNS/ARCHIVE trees; scratch via mktemp -d elsewhere (A6)
- conf ships exactly 5 KEY=VALUE lines; builders never invent conf values
- exotic filenames / concurrent writes documented as KNOWN_LIMITATIONS, not FAIL (A7)

deliverable:
- hdcs-runs-rotation.conf
- rotate-hdcs-runs.sh
- verify-rotation.sh
- README.md