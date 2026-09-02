state: s0 := baseline source/query-code-index.mjs (73 lines, verbatim above) is behavior-of-record; live target /workspace/kb/tools/query-code-index.mjs; md5(baseline) == md5(live tool) required at gate; all invariants A1,A2,A4,A6,A9 hold; INV_bx: Δ==∅ observable.

Δ:
1. Read source/query-code-index.mjs; record md5 := md5sum of it. Expected: md5 hex string captured, file unmodified.
2. Rewrite /workspace/kb/tools/query-code-index.mjs internally only: restructure into named sections (argParse, freshnessCheck, telemetry, renderHits), rename locals for clarity, remove dead code if any. Preserve byte-for-byte observable behavior. Expected: single file rewritten; behavior steps 3–9 pass.
3. Preserve flag parse loop semantics: --kind/--pkg/--limit, -h/--help (usage→stderr, exit 0), first positional = substring, second positional → die exit 2; no substring → usage, exit 2; limit non-finite or <1 → die exit 2; limit clamped ≤200. Expected: helper function equivalent to baseline loop; verified by step 9.
4. Preserve index path resolution: fileURLToPath(new URL('../code-index/index.json', import.meta.url)) — resolved vs script location, not cwd. Expected: path expression retained semantically.
5. Preserve freshness check: try/catch, git head + dirty-hash comparison vs index.meta, inline rebuild via sibling build-code-index.mjs on mismatch, stderr '-- index stale...' message, catch prints '-- freshness check skipped: <msg> --', never blocks. Expected: block present, same messages, non-blocking.
6. Preserve telemetry: fs.appendFileSync to ../code-index/usage.log (script-relative), 1 JSONL line per query {ts, sub, kind, pkg, hits, ms}, wrapped in empty try/catch. Expected: append present before hit/miss output.
7. Preserve stdout rows: for hits.slice(0,limit), console.log of [name, kind, pkg, `${file}:${line}`, doc||''].join('  ') (double-space). Expected: identical row strings vs baseline on any input.
8. Preserve miss/summary stderr: no hits → die with verbatim no-symbols message, exit 1; else stderr `-- N hit(s), showing M --`. Expected: verbatim strings, exit codes 0/1/2 exact.
9. Self-test in tmp layout replica (A9): create tmp dir with kb/tools/ (refactored + stub build-code-index.mjs) and kb/code-index/index.json fixture; run ≥6 cases. Expected outputs:
   a. hit query → exit 0, row == baseline row byte-identical, stderr '-- N hit(s), showing M --', usage.log grew by 1 valid JSONL line.
   b. no-symbols miss → exit 1, verbatim miss message.
   c. --help / -h → exit 0, usage text on stderr.
   d. missing substring → exit 2, usage on stderr.
   e. bad --limit → exit 2, '--limit must be a positive integer'.
   f. extra positional → exit 2, 'unexpected argument: X'.
   g. missing index.json → exit 1-ish path: 'cannot read index at ...' via die (exit 1).
   h. corrupted index meta → freshness catch path prints skip line, query still serves (stale-beats-dead).
10. Run md5sum on refactored file only after all tests pass; do not modify source/query-code-index.mjs. Expected: only file changed = /workspace/kb/tools/query-code-index.mjs.

accept:
- md5(source/query-code-index.mjs) == md5(live /workspace/kb/tools/query-code-index.mjs) at gate time.
- All 9 behavior-surface cases (3a–3h) pass byte-identically vs baseline output run in same tmp replica (diff stdout+stderr+exit code == ∅).
- usage.log receives exactly 1 JSONL line per query run; line parses as JSON with keys ts,sub,kind,pkg,hits,ms.
- stdout rows are double-space joined [name,kind,pkg,file:line,doc].
- freshness: try/catch present; skip message on failure; query completes (exit ≠ crash) when rebuild fails.
- exactly one workspace file written: /workspace/kb/tools/query-code-index.mjs; tmp replica only for tests.

constraints: ["do not edit source/query-code-index.mjs or any other file (A1/A9)", "exit ∈ {0,1,2} verbatim (A2)", "row join double-space; stderr summary verbatim (A6)", "telemetry + freshness preserved observably, non-blocking (A4)", "fix cycles ≤ 2", "no prose in report beyond +done/-resolved/+open/+validation"]

deliverable: ["/workspace/kb/tools/query-code-index.mjs"]