# TASK-007 — Creator mode v1: the template factory

## Problem (human speech)
Today every new HDCS task is hand-authored by the operator (task.md + gate.sh written from
scratch). That is the bottleneck for "route all real work through the loop". We need the loop
to MANUFACTURE new task templates itself: given a finding class (a recurring defect shape with
evidence from a real run), produce a reusable template directory that a future task can
instantiate with one command.

## Deliverable
`selfupgrade/create-template.mjs` + `templates/` directory. Interface:

    node selfupgrade/create-template.mjs --from runs/<run> --class "<one-line class name>"

Behavior:
1. Reads the named run's evidence (answers.md, s4-verdict.txt, gate-out.txt if present).
2. Extracts the defect class: what the gate caught, which law was invoked, the minimal repro.
3. Emits `templates/<slug>/` containing:
   - `task.md` — skeleton with the class's MUST_KEEP list, closed-world constraints, and
     instantiation slots ({{PARAM}}) marked with `# example:` per A10
   - `gate.sh` — mechanical gate for the class, bash -n clean, exit 0=compliant / 1=defect
   - `fixtures/compliant/` — a minimal fixture the gate PASSES
   - `fixtures/mutant/` — a minimal mutation the gate FAILS (A4: canary-discriminating)
   - `README.md` — one paragraph: what class this catches, how to instantiate

## MUST_KEEP
- gate.sh must FAIL on fixtures/mutant and PASS on fixtures/compliant (A4 law, no exceptions)
- template generation must be deterministic: same run evidence -> byte-identical template
- no placeholders outside `# example:`-marked lines (A10)
- factory exits 0 on success, 2 on usage error, 1 if it cannot extract a class from evidence
- works from arbitrary cwd (A9); reads only files under /workspace/hdcs (A1 scope-and-report)

## Acceptance gate (contract for builders)
gate.sh for THIS task must verify at least: (a) create-template.mjs exists and passes bash -n
syntax check on emitted gate.sh; (b) running the factory against runs/006-backup-doctor-git-scope
produces templates/git-scope-false-positive/ with all 5 files; (c) the generated gate.sh PASSES
on the compliant fixture and FAILS on the mutant (run both, check exit codes); (d) determinism:
two factory runs produce identical output (diff clean).

## Constraints
- Closed world: behaviors come from THIS task statement + existing loop source only; invented
  mechanisms (new deps, network calls) = defect (A9)
- Behavior preservation: existing driver/classify/promote paths untouched (A2)
- Budget-conscious: reuse existing kernel patterns (spawnSync, atomic writes) over invention
