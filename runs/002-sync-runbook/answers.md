A1: Runbook target is the run-001 sync tool; the system-facts block in task.md is
    the accuracy contract; nothing else about the tool may be asserted.
A3: Plain imperative English; every hcdl register term (A-number, packet, seat)
    must be explained or omitted from the runbook body.
A4: No invented flags/env vars/paths. If the facts block does not name it, the
    runbook may not teach it.
A5: Document the tool AS DELIVERED (including its refusals), not an idealized version.
A6: Sections in the mandated order; every section non-empty; rollback section must
    name the concrete restore action, not "reinstall".
A7: S4 rubric: FAIL if any command in the runbook would fail as written against the
    run-001 artifact, or if a MUST_KEEP section is missing or hollow.
