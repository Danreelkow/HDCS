A1 (SCOPE-DISCIPLINE, operator-delegate 2026-09-02): a git query executed inside a directory
    that is not itself a repository resolves to the ENCLOSING repository — any health check on
    a subtree MUST scope the query to that subtree (git -C <parent> status --porcelain -- <subtree>)
    or explicitly refuse; an unscoped parent-walk status misattributes unrelated dirt to the
    audited subtree. Refusal wording: fail "A1: git query unscoped — parent-repo state is not subtree state".
A2 (BEHAVIOR-PRESERVATION, 2026-09-02): the repair keeps every currently-passing check and the
    CLI contract (positional root arg, BACKUP_DOCTOR_TMP_ROOT, DSH_HOME, exit 0/1 semantics)
    unchanged; read-only discipline unchanged (no network, bounded subprocesses).
A1 CLARIFICATION (operator-delegate, 2026-09-02, after live lap): "scope or refuse" resolves
    as — when an enclosing repository EXISTS, the check MUST scope the query to the audited
    subtree and report the subtree's own state (clean subtree -> PASS even with dirty parent);
    refuse (FAIL) only when the subtree sits inside NO repository at all. A permanent refusal
    on a clean, committed subtree is as wrong as a parent-walk false positive: the verdict
    must reflect the subtree's disk truth.
A3 (EXIT-SEMANTICS, operator-delegate 2026-09-02, live lap 2): the contract is exit 0 when
    every check passes, exit 1 when ANY check fails. The exit code is a VERDICT, never a
    count of failures — individual failures are reported as FAIL lines, not encoded in the
    exit code (a doctor that exits 2 on two failures breaks every caller's `if doctor; then`
    contract). Refusal wording: fail "A3: exit code must be 0|1, not a failure count".
