## route_model

The stack (`source/scrapers-README.md`) defines one agent CLI: `node /workspace/scrapers/scrape.mjs <url> [--json] [--engine auto|camoufox|pyrocrawl] [--country CH] [--session id] [--timeout ms]` (README, Usage). It is backed by two local services (README, Routing logic):

- tier2 — Pyrocrawl :3093 `POST /scrape` for normal sites; fast chain politeness → proxy_pool → header_rotation → curl_cffi → html_to_md, auto-fallback to Camoufox on failure (README, routing table row "normal sites").
- tier3 — Camoufox :8896 `GET /browse?country=CH&session=<id>&url=…` for bot-wall-class pages (README, routing table row "tutti.ch / ricardo.ch / anibis.ch" + verified finding 3: "Camoufox :8896 is the working path").
- tier1 — plain node fetch: the stack_file does NOT define plain node fetch as sufficient for any tier. Its only statement on plain HTTP is verified finding 1, scoped to tutti.ch: the wall is total for plain HTTP (wget/node-fetch → 403 HTML challenge). This finding is tutti-specific and is not generalized; no registered URL is a Swiss classifieds domain, so no row here claims tier1 sufficiency.

Etiquette applied (README, Etiquette): fetches run strictly sequentially, human-scale rates.

## per_url_register

Register of record: `source/urls.txt`, TAB-parsed verbatim (A1). All 15 URLs fetched sequentially via `node /workspace/scrapers/scrape.mjs <url> --json`; observed_status is the HTTP code returned at fetch time (A4). Expected class is quoted from the register and never edited.

| # | url | expected (reg_file) | route_class | observed_status | exact_local_command |
|---|---|---|---|---|---|
| 1 | https://platform.deepseek.com/api-docs/ | botwall | bot-walled | 403 | `node /workspace/scrapers/scrape.mjs https://platform.deepseek.com/api-docs/ --json` |
| 2 | https://docs.z.ai/ | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://docs.z.ai/ --json` |
| 3 | https://platform.openai.com/docs/api-reference | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://platform.openai.com/docs/api-reference --json` |
| 4 | https://nodejs.org/docs/latest-v22.x/api/ | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://nodejs.org/docs/latest-v22.x/api/ --json` |
| 5 | https://nodejs.org/api/esm.html | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://nodejs.org/api/esm.html --json` |
| 6 | https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html | botwall | open | 200 | `node /workspace/scrapers/scrape.mjs https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html --json` |
| 7 | https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html | botwall | open | 200 | `node /workspace/scrapers/scrape.mjs https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html --json` |
| 8 | https://man7.org/linux/man-pages/man1/find.1.html | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://man7.org/linux/man-pages/man1/find.1.html --json` |
| 9 | https://www.gnu.org/software/coreutils/manual/html_node/index.html | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://www.gnu.org/software/coreutils/manual/html_node/index.html --json` |
| 10 | https://www.gnu.org/software/bash/manual/bash.html | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://www.gnu.org/software/bash/manual/bash.html --json` |
| 11 | https://git-scm.com/book/en/v2 | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://git-scm.com/book/en/v2 --json` |
| 12 | https://camoufox.com/ | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://camoufox.com/ --json` |
| 13 | https://github.com/BurntSushi/ripgrep | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://github.com/BurntSushi/ripgrep --json` |
| 14 | https://sqlite.org/docs.html | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://sqlite.org/docs.html --json` |
| 15 | https://man7.org/linux/man-pages/man1/cmp.1.html | open | open | 200 | `node /workspace/scrapers/scrape.mjs https://man7.org/linux/man-pages/man1/cmp.1.html --json` |

**FINDING 1**: rows 6 and 7 (freedesktop systemd man pages) carry expected=botwall in the register but observed 200 (open) at gate-time fetch. Per A4/A9 the observed≠expected discrepancy is documented here; the expected column in `source/urls.txt` is left verbatim and never edited.

All rows use the tier2 path (Pyrocrawl :3093 `POST /scrape` behind the default auto engine; README routing table "normal sites"). Each row's exact_local_command fetches that row's own registered URL. No row demanded the tier3 Camoufox variant: the only bot-walled observation (deepseek) manifests as an exit-1 no-content diagnostic with HTTP 403 challenge, and the stack_file's tier3 recipe (routing table + finding 3) is defined for the Swiss-classifieds domains, not deepseek — no registered URL is tutti/ricardo/anibis, so no `--engine camoufox --country CH` row is warranted.

dead count = 0 (≤ 1, A10 satisfied; no dead rows present).

## maintenance

**re_verify_procedure**: re-run step 3 sequentially — for each register row, `node /workspace/scrapers/scrape.mjs <url> --json` — recording observed_status. Diff against the per_url_register above. Any observed≠expected becomes a documented finding (A4/A9); the expected column in `source/urls.txt` is never edited. Deepseek row must still read "bot-walled" + the observed code. Re-check dead count ≤ 1; if > 1, halt and report NOT_READY.

**add_url_procedure**: append a TAB row (`<url>\t<expected_class>`) to `source/urls.txt`. Run the sequential fetch per step 3. Classify by observed result (botwall_codes {401,403,418,429} → "bot-walled"+code; network_error/404/5xx → "dead"+label; else open) and add one register row {url, route_class, observed_status, exact_local_command} with the literal command above. If the target is a Swiss classifieds domain (tutti/ricardo/anibis), use the tier3 recipe per README routing table (Camoufox :8896, `country=CH`).

**route_class_change_semantics**: a route-class change on re-verification (e.g. open → bot-walled) is a documented finding in this dossier. The expected column in the register of record (`source/urls.txt`) is never edited to match observation; claims always state observed_status as re-observed at gate time (A4), and any contradiction between a route-class claim and the gate observation fails (A9).
