# 006 — backup-doctor: git-scope repair

## ARTIFACTS
- backup-doctor.sh — repaired version of the current script (verbatim in source/)

## ACCEPTANCE
- FIXTURE A (trap): audited subtree fully committed, but its PARENT repo dirty OUTSIDE the
  subtree -> the subtree-clean check must PASS; overall exit 0.
- FIXTURE B: genuine uncommitted change INSIDE the audited subtree -> check FAILs; exit 1.
- All other checks (dsh-src, export, umbrella-remotes, staged-secrets, AGENTS.md) keep
  passing on healthy fixtures, byte-compatible CLI contract.
- The defect is structural: git status executed in a non-repo dir walks UP to the enclosing
  repository and misattributes unrelated dirt (live-found on the real machine: 13 umbrella
  entries reported against a fully-committed hdcs/).
