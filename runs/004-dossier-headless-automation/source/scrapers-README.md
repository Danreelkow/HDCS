# scrapers — agent-side scrape frontend

One command for agents to "look at" any URL through the local scraper stack,
with the Swiss-classifieds (tutti.ch) recipe baked in.

## Usage

```bash
node /workspace/scrapers/scrape.mjs <url> [--json] [--engine auto|camoufox|pyrocrawl] [--country CH] [--session id] [--timeout ms]
```

- Default output: page `<title>` + extracted text (camoufox) or markdown (pyrocrawl).
- `--json`: full payload incl. `proxy_cc`, `screenshot` path, `images`, `trace`, timing.
- Exit 1 + diagnostic on no-content (e.g. bot-check page reached).

## Routing logic

| Target | Engine | Why |
|---|---|---|
| tutti.ch / ricardo.ch / anibis.ch | **Camoufox :8896 `/browse` with `country=CH`** | Both sit behind DataDome-class bot walls. CH residential exit passes the passive check (verified 2026-08-30); default datacenter exit gets an interactive CAPTCHA ("Fast geschafft… Fülle den Sicherheitscheck aus"). |
| normal sites | Pyrocrawl :3093 `POST /scrape` | Fast chain: politeness → proxy_pool → header_rotation → curl_cffi → html_to_md. Auto-fallback to Camoufox on failure. |

## Verified findings (2026-08-30, probes preserved in kb/dossiers/codebase-index.md)

1. **tutti.ch wall is total for plain HTTP**: site pages, `api.tutti.ch`, and even
   `robots.txt` return a 403 HTML challenge to any non-browser client (wget/node-fetch).
2. **Pyrocrawl cannot scrape tutti.ch or ricardo.ch** — and it HAS a camoufox
   plugin built in (manifest: fetch, prio 70, "Primary scrape engine"); the
   blocker is the politeness gate, not a missing engine. Verified via controls:
   readable robots + disallowed path → explicit `politeness blocked: robots`;
   readable + allowed → 200; unreadable (403-challenged) robots (tutti) →
   politeness errors, the anti_block chain never assembles, camoufox is never
   attempted (instant ~224 ms `500 "all providers failed"`). The `/scrape`
   `proxy` field ("direct" tested) does not bypass it. Operator-side fixes:
   politeness fail-open / per-domain allowlist, CH residential exit in
   proxy_pool + engine steering, or a camoufox→:8896 bridge plugin.
3. **Camoufox :8896 is the working path**: `GET /browse?country=CH&session=<id>&url=…`
   returns `{url, proxy_cc, title, screenshot, images, text}` — real listing content,
   price/condition/seller details included. `text` is rendered text (not markdown).
   A persistent `session` id keeps cookies; a fresh id re-rolls the passive check.
   The interactive CAPTCHA itself cannot be solved via this API (GET-only, no actions).
4. ricardo.ch works through camoufox even on the default exit; `country=CH` is
   harmless there and keeps one recipe for all Swiss classifieds.

## Etiquette

- Run sequentially — both engines throttle/fail under parallel bursts.
- Human-scale call rates; respect robots.txt/tou where accessible.
- `--session` reuse for multi-page crawls of the same site (keeps cookies,
  fewer re-challenges).
