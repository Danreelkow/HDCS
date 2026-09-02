Task: behavior-preserving refactor of the code-index query tool

/workspace/kb/tools/query-code-index.mjs (73 lines) answers every session's code-
navigation queries. Refactor it for clarity and structure WITHOUT changing any
observable behavior. The verbatim baseline is in source/query-code-index.mjs.

Deliverable (single file): query-code-index.mjs — the refactored tool.
Internals are free: restructure functions, rename internals, delete dead code.
Observable behavior is contract: flags --kind/--pkg/--limit/-h; exit 0 on hit,
1 on no-symbols miss, 2 on usage error; stdout rows 'name  kind  pkg  file:line
doc' (double-space join); stderr '-- N hit(s) --' summary; one JSONL telemetry
line per query appended to the sibling code-index/usage.log; pull-based
freshness check that degrades (stale-beats-dead, never blocks a query); index
path resolved relative to the script's own location; repo path /workspace/dsh-src.

MUST_KEEP: preserves every documented CLI flag, exit code, and output format of the baseline
MUST_KEEP: keeps usage telemetry appended to kb/code-index/usage.log on every query
MUST_KEEP: keeps the pull-based freshness check with stale-beats-dead degradation
