state: s0 := reg_file=source/urls.txt (15 URLs, TAB URL+expected class; 1 botwall, 14 open). stack_file=source/scrapers-README.md defines: scrape.mjs CLI (`node /workspace/scrapers/scrape.mjs <url> [--json] [--engine auto|camoufox|pyrocrawl] [--country CH] [--session id] [--timeout ms]`), routing table (tutti/ricardo/anibis → Camoufox :8896 `/browse?country=CH&session=<id>&url=…`; normal sites → Pyrocrawl :3093 `POST /scrape`), verified findings (tutti 403 wall total for plain HTTP; Pyrocrawl politeness-blocked on tutti/ricardo; Camoufox working path). No registered URL is tutti/ricardo/anibis. botwall_codes={401,403,418,429}; dead=network_error∨404∨5xx. DOSSIER.md sections: [route_model, per_url_register, maintenance].

Δ := 
1. Read source/scrapers-README.md verbatim; extract exact commands/flags/routes. Expected: command inventory = scrape.mjs CLI, Pyrocrawl :3093 POST /scrape, Camoufox :8896 GET /browse — nothing else.
2. Read source/urls.txt TAB-parsed. Expected: 15 rows, 14 expected=open, 1 expected=botwall (platform.deepseek.com/api-docs/).
3. For each of 15 URLs, run `node /workspace/scrapers/scrape.mjs <url> --json` sequentially (etiquette: no parallel bursts), record observed_status (HTTP code or network_error; exit-1 diagnostic → record diagnostic code). Expected: 15 observed statuses, one per URL, matching gate re-fetch.
4. Classify each URL by observed result: botwall_codes → "bot-walled" + code; dead → "dead" + label; else open. Expected: classification table; observed≠expected rows flagged as findings, expected column left verbatim.
5. Write DOSSIER.md section route_model: tier1 plain node fetch only where stack_file supports it (stack_file does NOT define plain node fetch as sufficient for any tier — cite finding 1 re wget/node-fetch 403 on tutti only; do not generalize); tier2 Pyrocrawl :3093 POST /scrape for normal sites (cite routing table); tier3 Camoufox :8896 /browse country=CH for botwall-class pages (cite routing table + finding 3). Expected: every claim carries a stack_file citation; zero invented flags/routes.
6. Write per_url_register: 15 rows {url, route_class, observed_status, exact_local_command}. Expected: exact_local_command = literal `node /workspace/scrapers/scrape.mjs <url> --json` (or `--engine camoufox --country CH` variant only if observed status demands tier3 and stack_file citation covers it); deepseek row = "bot-walled" + observed code.
7. Write maintenance: re_verify_procedure (re-run step 3 sequentially, diff against register, observed≠expected → finding), add_url_procedure (append TAB row to source/urls.txt, run step 3, add register row), route_class_change_semantics (observed class change is a documented finding; expected column in reg_file is never edited to match observation).
8. Verify dead count ≤1; if >1, halt and report NOT_READY. Expected: count(dead)≤1 or halt.

accept:
- DOSSIER.md exists, sections in order [route_model, per_url_register, maintenance], ≤60 lines total brief respected in deliverable content.
- per_url_register has exactly 15 rows, one per reg_file URL, verbatim URLs, TAB-parse fidelity (A1).
- Every row has observed_status re-observable by gate re-fetch (A4); every route/command claim cites stack_file (fidelity).
- deepseek row reads "bot-walled" + observed code verbatim (A5).
- count(dead)≤1, dead row explicitly labeled (A10).
- No observed≠expected row corrected silently; each is a documented finding (A4/A9).
- Zero flags/routes/commands absent from scrapers-README.md.

constraints:
- no_resurrect: invented-flags — every flag/command verbatim from stack_file.
- no_resurrect: unverifiable-status — every status claim gate re-observable.
- Sequential fetches only; human-scale call rates (stack_file etiquette).
- observed ≠ expected ⇒ finding, never edit reg_file.
- Section order fixed; no prose outside DOSSIER.md's three sections.

deliverable: [DOSSIER.md]