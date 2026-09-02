# Clarification needed — 004-dossier-headless-automation

## Gate output (after repair round)
```
GATE FAIL: route claim mismatch for https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html: gate observed 'botwall', dossier does not state it

```

## Open questions recorded by S1
(none recorded)

## Packet
```yaml
reg: {domain: cs-programming/headless-web-automation, canon: exact local identifiers from scrapers-README.md (Pyrocrawl, Camoufox, node fetch), HTTP status codes (401/403/404/418/429/5xx), TAB-separated register parsing}
intent: >
  produce DOSSIER.md for operator: (1) route model citing scrapers-README.md —
  tier1 := plain node fetch when stack_file defines it sufficient; tier2 := local
  Pyrocrawl service when stack_file defines it for challenged routes; tier3 :=
  Camoufox browser engine when stack_file defines it for botwall-class pages;
  (2) per-URL register: ∀ u ∈ reg_file(15) -> row{url, expected class, observed
  status, exact local command} with claims matching observed reality; (3)
  maintenance: re-verify loop, add-URL procedure, route-class-change semantics.
  No flags/routes outside stack_file. Botwalls = findings with observed code;
  dead = network_error ∨ 404 ∨ 5xx, ≤1 tolerated, explicitly labeled.
must_keep:
  - classifies every registered URL with an observed, re-verifiable status
  - names the exact local command that fetches each registered page
  - documents the bot-walled entries as bot-walled with the observed code
resolved:
  - "Q1: which artifact is register of record? -> A: source/urls.txt, TAB-separated URL + expected class (A1)"
  - "Q2: ground truth for routes/commands/flags? -> A: source/scrapers-README.md exclusively; no invented flags/routes (A4)"
  - "Q3: observed vs expected class mismatch? -> A: document observed as finding, not error (A4)"
  - "Q4: what counts as dead vs botwall? -> A: botwall := {401,403,418,429} documented with code; dead := network_error ∨ 404 ∨ 5xx (A5)"
  - "Q5: gate enforcement? -> A: gate re-fetches all URLs; contradicting route-class claim FAILS (A9)"
  - "Q6: dead-URL tolerance? -> A: ≤1 at gate time; dead row explicitly labeled (A10)"
  - "Q7: remaining ambiguities? -> A: none — route tiers, command syntax, and class semantics all resolve against stack_file verbatim; builder extracts exact commands at build time"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "∀ route/flag/command taught ∈ scrapers-README.md definitions; no_resurrect: invented-flags"
  - "∀ per-URL claim re-observable at gate run time; no_resurrect: unverifiable-status"
  - "botwall rows carry observed code verbatim; dead rows explicitly labeled; count(dead) ≤ 1"
  - "DOSSIER.md section order fixed: route model, per-URL register, maintenance"
  - "observed ≠ expected ⇒ documented finding, ¬ correction to expected"
paths:
  - DOSSIER.md
  - source/urls.txt
  - source/scrapers-README.md
budgets: {tokens: 60000, lines: 60, fix_cycles: 2, questions: 2}
```
