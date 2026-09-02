# Clarification needed — 005-runs-log-rotation

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: `verify-rotation.sh:70` rejects archives with more than `KEEP` files (`[ "$count" -le "$KEEP" ] || fail ...`), but A6 defines exit 0 solely by conf parsing, no pending PATTERN file, archived files existing, and listing consistency; the added KEEP-limit condition causes nonzero exit when all A6 conjuncts hold. `hdcs-runs-rotation.conf:1` also adds a comment line despite the packet specifying a conf consisting of exactly the five `KEY=VALUE` lines.

## Packet
```yaml
reg: {domain: cs-shell-ops, canon: bash/coreutils file-ops vocabulary — find -mtime, realpath, cmp, cksum, mkdir -p, KEY=VALUE conf parsing via source-safe read}
intent: >
  deliver self-contained rotation pair for /workspace/hdcs/runs: conf file
  (exactly RUNS_DIR, ARCHIVE_DIR, AGE_DAYS, PATTERN, KEEP), rotate-hdcs-runs.sh
  (DRY-RUN default zero-write; --apply moves PATTERN files age ≥ AGE_DAYS from
  RUNS_DIR into ARCHIVE_DIR preserving relative path, env overrides, path-law
  refusals citing A-numbers, idempotent move-once), verify-rotation.sh
  (exit 0 iff A6 conjunct holds), README.md (install, configure, dry-run test,
  schedule). No root, no logrotate, bash + coreutils only.
must_keep:
  - "default mode is dry-run that performs no writes"
  - "no root required and no logrotate dependency"
  - "archived originals land outside the runs directory"
  - "the config defines exactly the five keys RUNS_DIR, ARCHIVE_DIR, AGE_DAYS, PATTERN, KEEP"
resolved:
  - "Q1: is dry-run allowed to create ARCHIVE_DIR or state files? -> A: no; A1: dry-run zero-write, --apply sole writing mode"
  - "Q2: toolchain envelope? -> A: A2: pure bash + coreutils (find, cmp, realpath, cksum); logrotate invocation = defect; no root"
  - "Q3: path safety law? -> A: A4: refuse identity, containment ∀ direction, degenerate ('', '.', '/'); refusal cites A-number, zero writes; env set-but-empty refuses"
  - "Q4: idempotence semantics? -> A: A5: move-once by age threshold; 2nd --apply zero-action no-op, ARCHIVE_DIR byte-identical via cksum; bytes verified with cmp; rotation suffix preserves names"
  - "Q5: verify exit criteria? -> A: A6: exit 0 iff conf parses ∧ no pending rotation ∧ archive listing intact; else nonzero"
  - "Q6: exotic filenames / concurrency? -> A: A7: KNOWN_LIMITATIONS, not FAIL; document in README"
  - "Q7: precedence? -> A: env HDCS_RUNS_DIR / HDCS_ARCHIVE_DIR override conf; conf overrides built-in defaults"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "dry-run default performs zero writes (A1) — MUST_KEEP"
  - "no root, no logrotate dependency (A2) — MUST_KEEP"
  - "archived originals land outside runs dir (A4 containment law) — MUST_KEEP"
  - "conf defines exactly five keys RUNS_DIR, ARCHIVE_DIR, AGE_DAYS, PATTERN, KEEP — MUST_KEEP"
  - "path law A4: refuse degenerate/overlap with cited A-number, zero writes on refusal"
  - "idempotence A5: second --apply byte-identical no-op"
paths:
  - /workspace/hdcs/runs
  - /workspace/.hdcs-rotate/archive
  - "<artifact-dir>/hdcs-runs-rotation.conf"
  - "<artifact-dir>/rotate-hdcs-runs.sh"
  - "<artifact-dir>/verify-rotation.sh"
  - "<artifact-dir>/README.md"
budgets: {tokens: 4000, lines: 60, fix_cycles: 2, questions: 2}
```
