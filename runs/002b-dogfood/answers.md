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
A9 (CLOSED-WORLD DOCTRINE, operator Danreelkow 2026-09-02): the runbook documents the tool AS
    DELIVERED — every claim must trace to the packet facts (I1..I7) or be verifiable against the
    artifact itself; inventing mechanisms (env files, canonicalization behaviors, refusal details)
    is a defect, not helpfulness. Ambiguity resolves by DELETING the unsupported claim, never by
    elaborating it. Install instructions must work from an arbitrary working directory (cd into
    the artifact dir or use explicit paths — this is correctness, not invention).
A7 INSTANTIATION (operator-delegate 2026-09-02, lap 1 evidence): every command block in the
    runbook must be executable verbatim from an arbitrary cwd — emit the literal
    `cd /workspace/hdcs/runs/001-hermes-context-timer/artifact` (or explicit absolute paths)
    as a command line, never as prose. "Change directory" describing without emitting = defect.
A10 (EXAMPLE-vs-EXECUTABLE, operator-delegate 2026-09-02, lap 2 evidence): the verbatim-
    executability requirement applies to INSTRUCTION blocks (install, verify, rollback — the
    operator runs these as-written). Configuration EXAMPLES may use placeholder values
    (/path/to/other/source) iff (a) the line is explicitly marked as an example (comment
    prefix `# example:`) and (b) the section shows the mechanism itself (export syntax,
    scoping). A marked example is documentation, not a runnable command — flagging it as a
    cwd/executability defect is a false positive (gate becoming wall).
