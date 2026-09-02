A1: Baseline of record is source/query-code-index.mjs; its md5 must equal the live
    tool when the gate runs. The refactor replaces exactly that one file.
A2: Exit codes are the contract: 0 on hit, 1 on no-symbols miss, 2 on usage error.
A4: Telemetry (one JSONL line per query) and the try/catch freshness check are
    features, not accidents — preserve both observably.
A6: stdout rows keep the exact double-space join over name, kind, pkg, file:line, doc.
A9: Testing happens in a tmp layout replica; the gate never writes to the workspace
    except run-dir bookkeeping.
A10: S4 judges internal quality (structure, naming, dead code) but behavior wins ties.
