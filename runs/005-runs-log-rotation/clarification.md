# Clarification needed — 005-runs-log-rotation

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: `verify-rotation.sh` violates A7: the `find` commands feeding the process-substitution loops at the stale scan (`done < <(find "$RUNS" ... -print0)`, line 94), archive scan (`done < <(find "$ARCH" ... -print0)`, line 114), and fresh scan (later `done < <(find "$RUNS" ... -print0)`) have their exit statuses discarded. The subsequent `find ... >/dev/null` commands are separate scans and do not accumulate the status of the scans actually supplying the checks. Additionally, line 33 uses an unchecked pipeline, `grep -E ... | grep -vcE ...`, contrary to A7’s prohibition on bare pipeline status/checks.

## Packet
```yaml
reg: {domain: cs-programming, canon: "bash/coreutils scripting vocabulary — find -newermt, cmp, cksum, realpath, fd redirection, exit codes, KEY=VALUE parsing"}
intent: "deliver self-contained rotation pair for /workspace/hdcs/runs/: conf + rotate-hdcs-runs.sh (DRY-RUN default, --apply move+prune) + verify-rotation.sh (zero-write consistency check) + README.md; pure bash+coreutils, no root, no logrotate"
must_keep:
  - "default mode is dry-run that performs no writes"
  - "no root required and no logrotate dependency"
  - "archived originals land outside the runs directory"
  - "the config defines exactly the five keys RUNS_DIR, ARCHIVE_DIR, AGE_DAYS, PATTERN, KEEP"
  - "the conf values are exactly RUNS_DIR=/workspace/hdcs/runs, ARCHIVE_DIR=/workspace/.hdcs-rotate/archive, AGE_DAYS=14, PATTERN=*.txt, KEEP=50 (builders never invent conf values)"
resolved:
  - "Q1: dry-run write scope? -> A: A1 — zero writes; no ARCHIVE_DIR creation, no state files; --apply only writing mode"
  - "Q2: toolchain? -> A: A2 — bash + coreutils (find, cmp, realpath, cksum); logrotate invocation = defect; no root"
  - "Q3: path refusal law? -> A: A4 — identity, containment either way, degenerate ('', '.', '/'); cite A-number; env overrides; set-but-empty refuses"
  - "Q4: idempotence contract? -> A: A5 — move-once via age threshold; second --apply byte-identical no-op; cmp archived vs original; names preserved + rotation suffix"
  - "Q5: verify exit semantics? -> A: A6 — exit 0 iff conf parses ∧ no stale file under RUNS_DIR ∧ archive listing intact; fresh PATTERN match must NOT fail"
  - "Q6: stale boundary? -> A: floor(age_days) >= AGE_DAYS; implement explicitly, not bare -mtime +N (excludes [N,N+1) band)"
  - "Q7: verify status-check pattern? -> A: flag accumulator for EVERY check; never bare command/pipeline status"
  - "Q8: exotic filenames / concurrent writes? -> A: A7 — KNOWN_LIMITATIONS, not FAIL"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "no_resurrect: logrotate, root, sudo, bare -mtime +N, bare pipeline status checks in verify, writes in dry-run or verify"
  - "conf contains exactly 5 keys with operator-fixed values; no comment lines"
  - "prune touches ARCHIVE_DIR only; dry-run prunes nothing"
  - "verify mktemp targets outside artifact dir and tree, or fd redirection only"
paths:
  - "artifact_dir: <operator-supplied artifact dir>"
  - hdcs-runs-rotation.conf
  - rotate-hdcs-runs.sh
  - verify-rotation.sh
  - README.md
  - "RUNS_DIR: /workspace/hdcs/runs"
  - "ARCHIVE_DIR: /workspace/.hdcs-rotate/archive"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
