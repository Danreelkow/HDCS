# template: git-scope-false-positive

Defect class extracted from an evidence run under /workspace/hdcs.

- gate catch: gate caught an unscoped git query reading outside /workspace/hdcs
- invoked law: A1
- minimal repro: git status --porcelain executed with cwd outside /workspace/hdcs

## usage
    bash -n templates/git-scope-false-positive/gate.sh
    bash templates/git-scope-false-positive/gate.sh

Exit 0 means the compliant fixture passes and the mutant fails.

## layout
- task.md
- gate.sh
- fixtures/compliant/compliant.sh
- fixtures/mutant/mutant.sh
- README.md
