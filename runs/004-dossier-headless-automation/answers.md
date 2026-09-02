A1: source/urls.txt is the register of record (URL + expected class, TAB-separated);
    source/scrapers-README.md is the ground truth for the local route stack.
A4: No invented statuses, flags, or routes. Every per-URL claim must be
    re-observable by the gate at run time. Claims must match observed reality,
    not the expected class, when the two differ (a changed status is a finding
    to document, not an error to hide).
A5: Document pages as observed: bot-walls (401/403/418/429) are documented
    findings with their code; only network errors or 404/5xx count as dead.
A9: The gate re-fetches every registered URL; a route-class claim that
    contradicts the gate's own observation FAILS.
A10: At most one dead URL is tolerated at gate time; a dead URL's row must say
    so explicitly rather than silently.
