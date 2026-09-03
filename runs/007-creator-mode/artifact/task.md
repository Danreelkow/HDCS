# task: git-scope-false-positive

## MUST_KEEP
- gate catch: gate caught an unscoped git query reading outside /workspace/hdcs
- invoked law: A1
- minimal repro: git status --porcelain executed with cwd outside /workspace/hdcs

## constraints
- closed world: no new dependencies, no network access
- all filesystem reads are scoped to /workspace/hdcs
- gate.sh exit 0 = compliant fixture passes; exit 1 = defect reproduced

# example: scope root: {{SCOPE_ROOT}}
# example: repro command: {{REPRO}}

