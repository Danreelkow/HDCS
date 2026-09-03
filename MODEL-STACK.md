# The Model Stack — what we route where, and why

> **You don't have to use this.** HDCS is model-agnostic: the loop, register, gates,
> and seats are config, not code. This document describes the roster *we* run in
> production — measured on our bench, tuned for cost — so the reasoning is on record
> and you can retarget every seat to your own models.

## The idea: seats, not a model

HDCS never runs "on one model". Every stage is a **seat** with its own pin, chosen for
what that stage actually does. The two laws that shape everything:

1. **Cross-family grading** — the model that *builds* never *judges* its own work.
   Producer and verifier must not share a model family. If one seat changes family,
   the other moves in the same edit.
2. **Cost-first** — pay for judgment, not for typing. The cheapest model that passes
   its bench profile holds the seat; expensive reasoning models only sit where
   divergence (a second family grading) or register quality demands it.

## Active seats (in-chat stack, DSH preset)

| Stage | Seat | Model | Why |
|---|---|---|---|
| S1/S2/S5 — translate, orchestrate, debrief | session model | `openai/gpt-5.6-luna` | Operator's first chair: uncapped reasoning in prod, thinks *in the register*; the register is the product at this seat |
| S3 — build | `subagent_worker` | `z-ai/glm-5.3-flash` | Bench: 6/6 builds, ~0 reasoning share — cheap, fast, follows atomic briefs; overthinking is wasted at a seat that just implements |
| S4 — adversarial judge | `subagent_gpt` | `openai/gpt-5.6-luna` | Cross-family vs the glm builder; planner/verifier bench profile 6/6; overthinking is a *feature* in a judge |
| Mechanical steps | `nova-micro` tier | `amazon/nova-micro-v1` | Bench 5/7 with per-step expected outputs + mechanical end-state verification; excellent tool-use, not a text-audit model |

## Aux seats (:free tier, distinct vendors on purpose)

| Job | Model | Why |
|---|---|---|
| Session titler | `nvidia/nemotron-3.5-lightning:free` | $0 mechanical text work |
| Session context | `thinkingmachines/inkling-small:free` | $0; distinct vendor = rate-limit resilience |
| Compaction summarizer | `z-ai/glm-5.3-flash` | Lossless condensation bar; bench-proven |

Aux shops the **whole provider catalog**, not a whitelist — free tier for mechanical
work, different vendors per seat so one rate limit never stalls the loop.

## Excluded (operator order + bench evidence)

| Model | Reason |
|---|---|
| `qwen/qwen3-coder-next` | run-to-run variance: 0/5 vs 4/6 on the *identical* brief |
| `qwen/qwen3.8-max` | operator-excluded |
| `x-ai/grok-4.6` | 79–85% reasoning share = slow and pricey |
| `deepseek/deepseek-v4-flash-0731` | provider ignores reasoning caps → uncontrollable starvation |
| `z-ai/glm-5` | starved in both bench sweeps (12k tokens, 0 visible output) |

## Pinning mechanics

- Pins are **per-model, never route-level** — a route-level pin 404s non-pinned
  models (live-verified), and `allow_fallbacks: false` is what excludes degraded or
  quantized upstream tiers (the fp4-Relace lesson).
- Subprovider choice matters as much as model choice.
- **Model ids are never frozen in prose.** The roster of record is
  `seats.json` (kernel/batch) and the delegation rows of the agent preset (in-chat);
  documentation follows them, not the reverse.

## Bench provenance

Roster decisions come from the 2026-08-31 bench sweeps (two valid runs, 90-record
role matrix + staged flash/non-flash runs) plus wild production runs. Key profiles
behind the seats above: GPT-5.6-luna planner/verifier 6/6; Nova Micro tool-worker
7/9 + 1/1 with correct handoff markers; GLM-5.3-flash builder 6/6 at ~zero reasoning
share; every densifier candidate failed the YAML contract until the hcdl spec
pinned the exact schema — the register, not the model, was the missing piece.

**Bench candidate, not seated:** `gemini-3.8-flash` — flagged 2026-09-03 by the
operator as the replacement for the 3.7-flash verifier profile (3.7 benched 5/6 + 1/1).
It stays a candidate until it runs its own bench profile; a model never gets a seat
on announcement, only on evidence.

## Retargeting it

Swap any seat by editing its pin (preset delegation rows / `seats.json`) — keep the
cross-family law intact and record the change. The loop's gates are mechanical
(`gate.sh`) and adversarial (S4); they grade the *artifacts*, so any family that can
follow an atomic brief can build here.
