Task: headless-automation dossier for the operator's URL register

The operator keeps a register of 15 documentation pages that headless tooling
must be able to fetch. The verbatim register is source/urls.txt (URL + expected
route class: open or botwall). The verbatim description of the local fetch
stack is source/scrapers-README.md. Write the dossier an operator follows.

Deliverable (single file): DOSSIER.md with sections in order:
1. Route model — when plain node fetch suffices, when to route through the
   local Pyrocrawl service, when a browser engine (Camoufox) is needed, and why
   (based on the scrapers README, cited).
2. Per-URL register — one row per registered URL: the URL, its route class, the
   status observed when you verified it, and the exact local command that
   fetches the page.
3. Maintenance — how to re-verify the register, how to add a URL, what a route
   class change means.

Rules: every per-URL claim must be re-observable (statuses/classes as defined
in source/urls.txt); bot-walled pages are findings, not failures — document
them as bot-walled with the observed code; do not teach flags or routes the
scrapers README does not define.

MUST_KEEP: classifies every registered URL with an observed, re-verifiable status
MUST_KEEP: names the exact local command that fetches each registered page
MUST_KEEP: documents the bot-walled entries as bot-walled with the observed code
