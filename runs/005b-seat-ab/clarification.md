# Clarification needed — 005b-seat-ab

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: In both `rotate-hdcs-runs.sh` lines 26–38 and `verify-rotation.sh` lines 26–38, A4 degenerate-path validation occurs before `realpath -m` and is not repeated afterward. Thus a value such as `RUNS_DIR=/tmp/..` canonicalizes to `/` without refusal. Additionally, `inside()` at lines 21–24 fails when `parent=/` because its `"$parent/"*` pattern becomes `"//*"`, so `/` is not recognized as containing `/workspace/.hdcs-rotate/archive`. `--apply` can therefore proceed with `RUNS_DIR=/`, violating A4’s required refusal of `/` and its zero-write-on-refusal rule.

## Packet
```yaml
reg: {domain: cs-programming, canon: shell/cli engineering vocabulary — flags, exit codes, fd redirection, find predicates, coreutils binaries, KEY=VALUE parsing}
intent: deliver self-contained rotation pair + verifier + README for /workspace/hdcs/runs/*.txt artifacts; dry-run default (zero-write); --apply rotates STALE files to ARCHIVE_DIR preserving relpath, prunes to newest KEEP; verify exits 0 iff conf parses ∧ ¬PENDING ∧ INTACT; pure bash+coreutils, no root, no logrotate.
must_keep:
  - default mode is dry-run that performs no writes
  - no root required and no logrotate dependency
  - archived originals land outside the runs directory
  - the config defines exactly the five keys RUNS_DIR, ARCHIVE_DIR, AGE_DAYS, PATTERN, KEEP
  - the conf values are exactly RUNS_DIR=/workspace/hdcs/runs, ARCHIVE_DIR=/workspace/.hdcs-rotate/archive, AGE_DAYS=14, PATTERN=*.txt, KEEP=50 (builders never invent conf values)
resolved:
  - "Q1: is dry-run permitted to create dirs/state? -> A: no (A1: zero-write; --apply only writing mode)"
  - "Q2: toolset? -> A: pure bash + coreutils find/cmp/realpath/cksum; logrotate invocation = defect (A2)"
  - "Q3: path degeneracy rules? -> A: A4 — refuse identity, containment either way, '', '.', '/'; cite A-number; zero writes on refusal"
  - "Q4: env override semantics? -> A: HDCS_RUNS_DIR / HDCS_ARCHIVE_DIR > conf; set-but-empty refuses (A4)"
  - "Q5: idempotence contract? -> A: A5 — move-once threshold, 2nd --apply byte-identical ARCHIVE_DIR, cmp-verified bytes, names preserved + suffix"
  - "Q6: verify semantics? -> A: A6 — exit0 iff conf parses ∧ no STALE under RUNS_DIR ∧ archive listing intact; fresh matching file ¬fail"
  - "Q7: stale boundary? -> A: STALE := floor(age) >= AGE_DAYS; implement explicitly, bare -mtime +N banned (excludes [N,N+1) band)"
  - "Q8: status-check pattern? -> A: flag accumulator (STALE_FOUND=0; set in find/while loop; test after); every verify status check uses it; verify writes nothing (fd redirection or mktemp outside tree)"
  - "Q9: exotic filenames / concurrency? -> A: A7 — KNOWN_LIMITATIONS, ¬FAIL"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - zero writes in dry-run mode (A1)
  - no logrotate invocation; no root (A2)
  - refuse degenerate/overlapping paths citing A4; set-but-empty env refuses (A4)
  - idempotent move-once rotation; cmp-verified archive bytes (A5)
  - stale boundary floor(age)>=AGE_DAYS implemented explicitly, ¬bare -mtime +N
  - verify: flag-accumulator status checks only; verify writes nothing (A6)
  - exotic filenames + concurrency = KNOWN_LIMITATIONS (A7)
  - no_resurrect: none cited
paths:
  - artifact_dir/hdcs-runs-rotation.conf
  - artifact_dir/rotate-hdcs-runs.sh
  - artifact_dir/verify-rotation.sh
  - artifact_dir/README.md
budgets: {tokens: 12000, lines: 60, fix_cycles: 2, questions: 2}
```
