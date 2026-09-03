# Clarification needed — 007-creator-mode

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: `selfupgrade/create-template.mjs:48-93` extracts only law tokens and a heuristic first line containing “repro” or “git”, but `taskMd()` at lines 96-123 and `readmeMd()` at lines 176-196 always emit the hard-coded unscoped-git defect class and fixtures. Thus evidence for any other extractable class produces an invented git-scope template instead of losslessly emitting the extracted gate catch, invoked law, and minimal repro required by the packet. `selfupgrade/create-template.mjs:200-208` also accepts duplicate flags and does not validate that all three option values are present; malformed usage can reach `path.resolve(undefined)` and terminate with a runtime error rather than the required exit 2.

## Packet
```yaml
reg: {domain: cs-programming, canon: "node ESM CLI, spawnSync, bash gate scripts, fixture-based canary testing, atomic file writes, kebab-case slugs, {{PARAM}} template slots"}
intent: >
  build factory CLI create-template.mjs: ingest run evidence (answers.md, s4-verdict.txt,
  gate-out.txt) -> extract defect class (gate catch, invoked law, minimal repro) ->
  emit templates/<slug>/ with task.md (MUST_KEEP + closed-world constraints + {{PARAM}}
  slots marked `# example:`), bash -n clean gate.sh (exit 0=compliant | 1=defect),
  fixtures/compliant (gate PASSES), fixtures/mutant (gate FAILS, A4), README.md.
  Deterministic output; exit 0|2|1 per spec. Reference instantiation:
  runs/006-backup-doctor-git-scope -> templates/git-scope-false-positive/.
must_keep:
  - "gate.sh must FAIL on fixtures/mutant and PASS on fixtures/compliant (A4 law, no exceptions)"
  - "template generation must be deterministic: same run evidence -> byte-identical template"
  - "no placeholders outside `# example:`-marked lines (A10)"
  - "factory exits 0 on success, 2 on usage error, 1 if it cannot extract a class from evidence"
  - "works from arbitrary cwd (A9); reads only files under /workspace/hdcs (A1 scope-and-report)"
resolved:
  - "Q1: which run seeds the reference template? -> A: runs/006-backup-doctor-git-scope -> templates/git-scope-false-positive (operator-specified acceptance item b)"
  - "Q2: what if evidence files are missing/partial? -> A: factory proceeds with ∃-subset; zero extractable class -> exit 1"
  - "Q3: slug derivation? -> A: kebab-case of --class string; collision with existing template dir -> overwrite deterministically (byte-identical anyway)"
  - "Q4: gate.sh portability? -> A: bash, bash -n clean, POSIX-safe fixtures invocation, exit codes 0/1 only"
  - "Q5: determinism mechanism? -> A: no timestamps, fixed file write order, stable serialization; verified via diff of two runs (acceptance d)"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "closed world: behaviors from this task statement + existing loop source only; new deps/network = defect (A9)"
  - "behavior preservation: driver/classify/promote paths untouched (A2)"
  - "reuse kernel patterns: spawnSync, atomic writes over invention"
  - "acceptance gate (a)-(d): factory exists + emitted gate.sh bash -n clean; reference instantiation produces 5 files; canary pair exit codes verified; determinism diff clean"
  - "no_resurrect: A1, A2, A4, A9, A10 cited"
paths:
  - selfupgrade/create-template.mjs
  - templates/git-scope-false-positive/task.md
  - templates/git-scope-false-positive/gate.sh
  - templates/git-scope-false-positive/fixtures/compliant/
  - templates/git-scope-false-positive/fixtures/mutant/
  - templates/git-scope-false-positive/README.md
  - runs/006-backup-doctor-git-scope/
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
