build brief -> B1

state: s0 := {deps: bash+coreutils only (find,cmp,realpath,cksum) [A2]; writer: --apply sole writer [A1]; path law: refuse RUNS_DIR==ARCHIVE_DIR, containment either way, '', '.', '/', set-but-empty env, citing A-nums, pre-write, env>HDCS_* > conf [A4]; idempotence: age≥AGE_DAYS moved once, suffix on archived name, cmp-verified bytes, 2nd --apply zero-action [A5]; verify exit 0 iff conf parses ∧ no stale match under RUNS_DIR ∧ archived listing consistent [A6]; exotic names/races -> KNOWN_LIMITATIONS [A7]; conf keys exactly {RUNS_DIR,ARCHIVE_DIR,AGE_DAYS,PATTERN,KEEP}; targets: /workspace/hdcs/runs (runs), /workspace/.hdcs-rotate/archive (archive)}.

Δ:
1. Write hdcs-runs-rotation.conf: exactly 5 KEY=VALUE lines: RUNS_DIR=/workspace/hdcs/runs, ARCHIVE_DIR=/workspace/.hdcs-rotate/archive, AGE_DAYS=7, PATTERN=*.log, KEEP=5.
   expected: `grep -c '=' hdcs-runs-rotation.conf` = 5; keys exactly the schema set, no extra/missing.
2. Write rotate-hdcs-runs.sh:
   - resolve paths: env HDCS_RUNS_DIR/HDCS_ARCHIVE_DIR override conf; set-but-empty env -> refuse (A4).
   - validate: nonempty, ≠'.', ≠'/', ≠'' ; realpath both; refuse equal, refuse containment either direction; refusal message cites "A4"; exit ≥1 before any write/mkdir.
   - default (no --apply): dry-run — print planned moves (`<src> -> <dst>`), create nothing (no ARCHIVE_DIR, no state files); exit 0.
   - --apply: validate first (A4), then mkdir -p ARCHIVE_DIR; `find "$RUNS_DIR" -type f -name "$PATTERN" -mtime +"$AGE_DAYS"`; for each: destination name = basename + ".1" (increment suffix if exists: .2, .3…), `mv` then `cmp` src-gone/bytes; log each move.
   - KEEP: after moves, prune oldest archived matching entries beyond KEEP (applies only when KEEP≥0; KEEP<0 = unlimited).
   - second --apply: find returns empty -> zero mv, zero mkdir of new state, exit 0.
   - exit codes: 0 success/zero-action; ≥1 any refusal/failure.
   expected: `bash -n rotate-hdcs-runs.sh` clean; dry-run on fixture leaves `find /workspace -newer marker` empty except none.
3. Write verify-rotation.sh:
   - parse conf (same 5-key schema; malformed -> exit 2); apply A4 checks (refusals cite A4, exit ≥1).
   - exit 0 iff: (a) conf parses; (b) `find RUNS_DIR -type f -name PATTERN -mtime +AGE_DAYS` empty; (c) ARCHIVE_DIR (if exists) listing contains only files matching `<name>.<suffix>` pattern with valid cmp-consistent rotation naming (no duplicates of same basename+suffix).
   - else exit ≥1; no writes ever (verify is read-only).
   expected: `bash -n verify-rotation.sh` clean.
4. Write README.md: usage of both scripts, env overrides, exit codes, KEEP semantics, KNOWN_LIMITATIONS section covering exotic filenames/newlines/races per A7 (documented, not tool failure).
   expected: `grep -c KNOWN_LIMITATIONS README.md` ≥ 1.
5. Fixture self-test (dry context only): create temp RUNS_DIR/ARCHIVE_DIR under /tmp with old+new files; run dry-run -> assert no archive dir created; run --apply twice -> first moves old file with cmp-verified bytes, second is zero-action exit 0; run verify -> exit 0; run verify with stale file present -> exit ≥1.
   expected: scripted assertions all pass; zero writes into real /workspace/hdcs/runs during test (use /tmp paths only).

accept:
- [ ] `bash -n` clean on both .sh files
- [ ] conf contains exactly the 5 schema keys, no more, no fewer
- [ ] dry-run (default) on any input creates zero files/dirs anywhere (checked via before/after `find` snapshot)
- [ ] A4 refusals (equal, containment, '', '.', '/', set-but-empty env) each exit ≥1 with message containing "A4", zero writes
- [ ] --apply moves only files ≥AGE_DAYS matching PATTERN; each destination bytes-identical to source (cmp passes); name has rotation suffix; originals absent from RUNS_DIR after move
- [ ] second consecutive --apply: exit 0, zero mv/mkdir/log-lines, ARCHIVE_DIR listing byte-identical
- [ ] verify-rotation.sh: exit 0 on consistent state; exit ≥1 on (unparsable conf | stale match in RUNS_DIR | inconsistent archive listing); never writes
- [ ] README.md contains KNOWN_LIMITATIONS section mentioning exotic names/races
- [ ] no logrotate, no root, no non-coreutils deps anywhere in scripts

constraints:
- pure bash + coreutils only [A2]; no logrotate, no root
- DRY default: zero writes incl. no ARCHIVE_DIR/state creation [A1]
- A4 refusal precedes any write, cites A-numbers
- idempotence: move-once, cmp-verified, suffixed names [A5_move_once, A5_bytes]
- verify read-only, exit-status contract per A6
- exotic-name/race behavior documented in README KNOWN_LIMITATIONS, not code-failure [A7]

deliverable:
- hdcs-runs-rotation.conf
- rotate-hdcs-runs.sh
- verify-rotation.sh
- README.md