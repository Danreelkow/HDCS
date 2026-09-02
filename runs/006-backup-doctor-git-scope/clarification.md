# Clarification needed — 006-backup-doctor-git-scope

## Gate output (after repair round)
```
GATE FAIL: FIXTURE B: expected exit 1, got 2

```

## Open questions recorded by S1
(none recorded)

## Packet
```yaml
reg: {domain: cs-shell-git, canon: git plumbing/status vocabulary — git -C, --porcelain, pathspec-limited status, exit codes, repo-walk discovery (GIT_DIR / rev-parse), fixture-based acceptance tests}
intent: >
  repair backup-doctor.sh subtree-clean check: eliminate unscoped git-status parent-walk
  misattribution; ∀ audited subtree S -> query scoped via
  git -C <enclosing_repo> status --porcelain -- <S>; verdict reflects S's disk truth only;
  pass committed subtree despite dirty parent (FIXTURE A -> exit 0);
  fail genuine dirt inside S (FIXTURE B -> exit 1); refuse only when S in no repo.
must_keep:
  - "FIXTURE A (trap): audited subtree fully committed, but its PARENT repo dirty OUTSIDE the subtree -> the subtree-clean check must PASS; overall exit 0."
  - "FIXTURE B: genuine uncommitted change INSIDE the audited subtree -> check FAILs; exit 1."
  - "byte-compatible CLI contract"
resolved:
  - "Q1: scope-or-refuse when enclosing repo exists? -> A: SCOPE (operator-delegate clarification): git -C <parent> status --porcelain -- <subtree>; clean subtree => PASS even with dirty parent; refuse (FAIL, exit 1, message 'A1: git query unscoped — parent-repo state is not subtree state') only when subtree ∈ no repo at all"
  - "Q2: behavior change allowed outside the defective check? -> A: NO (A2): all passing checks, CLI contract, env vars, exit semantics, read-only discipline preserved"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "A1: every git health query scoped to audited subtree via pathspec; unscoped parent-walk status forbidden"
  - "A1 refusal wording verbatim: fail \"A1: git query unscoped — parent-repo state is not subtree state\""
  - "A2: preserve dsh-src, export, umbrella-remotes, staged-secrets, AGENTS.md checks + CLI contract (positional root arg, BACKUP_DOCTOR_TMP_ROOT, DSH_HOME, exit 0/1)"
  - "read-only discipline: no network, bounded subprocesses"
paths:
  - source/backup-doctor.sh
  - artifact/backup-doctor.sh
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
