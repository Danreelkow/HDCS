state: s0 := { factory: selfupgrade/create-template.mjs ABSENT; templates/git-scope-false-positive/ ABSENT; evidence runs/006-backup-doctor-git-scope/{answers.md,s4-verdict.txt,gate-out.txt} PRESENT; laws A1,A2,A4,A8,A9,A10 in force; deps: node ESM, spawnSync only }.
Δ :=
1. Read runs/006-backup-doctor-git-scope/{answers.md,s4-verdict.txt,gate-out.txt}; extract defect class (gate catch, invoked law A1, minimal repro: unscoped git query).
   → expected: class fields identified; slug `git-scope-false-positive` (kebab-case of --class).
2. Write selfupgrade/create-template.mjs (node ESM):
   - CLI: `node selfupgrade/create-template.mjs --evidence <run-dir> --class <slug> --out templates/<slug>`; usage error → exit 2.
   - Ingest evidence files; ∃-subset tolerated; zero extractable class → exit 1 with message.
   - Emit 5 artifacts in fixed order: task.md, gate.sh, fixtures/compliant/, fixtures/mutant/, README.md; atomic writes (tmp+rename); no timestamps; stable serialization.
   - task.md: MUST_KEEP block + closed-world constraints + {{PARAM}} slots, each slot line prefixed `# example:`.
   - gate.sh: bash, POSIX-safe fixture invocation, exit 0=compliant / 1=defect.
   - All fs reads resolved under /workspace/hdcs (A1); cwd-independent (A9); no new deps (A9); no driver/classify/promote edits (A2).
   → expected: file exists, `node --check` passes.
3. Run factory on reference evidence.
   → expected: exit 0; templates/git-scope-false-positive/ contains exactly task.md, gate.sh, fixtures/compliant/, fixtures/mutant/, README.md.
4. Validate emitted gate: `bash -n templates/git-scope-false-positive/gate.sh` → clean; run gate on fixtures.
   → expected: gate.sh(fixtures/compliant)=0; gate.sh(fixtures/mutant)=1 (A4).
5. Determinism check: run factory twice to temp dirs under /workspace/hdcs; diff.
   → expected: byte-identical trees (A_det, Q5).
6. A10 scan: grep for `{{` in emitted template.
   → expected: every occurrence on a line containing `# example:`.
accept:
  a. selfupgrade/create-template.mjs exists, `node --check` clean, exit codes 0/2/1 per spec (usage error test → 2; empty-evidence run → 1).
  b. templates/git-scope-false-positive/ has exactly the 5 required artifacts.
  c. bash -n clean; gate.sh(compliant)=0 ∧ gate.sh(mutant)=1.
  d. two-run diff empty (byte-identical).
  e. A10: all {{PARAM}} on `# example:` lines; A1: no read outside /workspace/hdcs; A2: driver/classify/promote untouched (git status clean on those paths).
constraints: [closed world, no new deps/network (A9); A2 preserve; A4 canary pair mandatory; A10 slot marking; deterministic output, no timestamps; reads scoped to /workspace/hdcs].
deliverable: [selfupgrade/create-template.mjs, templates/git-scope-false-positive/task.md, templates/git-scope-false-positive/gate.sh, templates/git-scope-false-positive/fixtures/compliant/, templates/git-scope-false-positive/fixtures/mutant/, templates/git-scope-false-positive/README.md].