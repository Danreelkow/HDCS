# HDCS — the hcdl register loop

**HDCS is a loop that makes LLMs reason in a constructed dense technical register — and
reverse-translates the result back for humans.**

[![License: PolyForm NC](https://img.shields.io/badge/license-PolyForm%20NC-blue)](LICENSE)
![node](https://img.shields.io/badge/node-%3E%3D18-brightgreen)
![bash](https://img.shields.io/badge/bash-mechanical%20gates-informational)
![LLM-agnostic](https://img.shields.io/badge/LLM--agnostic-provider%20neutral-orange)
![self-upgrading](https://img.shields.io/badge/self--upgrading-queue%20%2B%20promote-blueviolet)
![status](https://img.shields.io/badge/status-first%20self--authored%20law%3A%20approved-success)

## What is this

LLM reasoning is a self-talk loop started by the input, and the language of the input
selects which part of the model's training distribution that loop runs in. Prose
activates the fuzzy, conversational regions; a dense, domain-locked, mathematically
structured register activates the formal ones — papers, specs, formal code.

HDCS applies that register to everything machine-facing — packets, briefs, artifacts,
inter-agent traffic — and keeps humans out of it entirely. Your request is translated
**in** (S1); the work happens in hcdl; the result is verified twice, once mechanically
(a zero-LLM bash gate) and once adversarially (a decorrelated judge); then it is
reverse-translated **out** (S5).

The primary claim is **quality**. Token efficiency is a side effect of precision, not the
goal — dense language is cheaper because fluff died, but it exists because precise terms
replace vague guesswork.

---

## The loop

```
human -> S1 -packet-> S2 -brief-> S3 ladder -artifact-> GATE -pass-> S4 -verdict-> S5 -> human
                                   ^                    |             |
                                   |                    | gate fail   | S4 objection
                                   +<-------------------+-------------+
                         (repair lap re-enters S3 from the last clean snapshot)
```

```
S1 clarify/translate    human request -> hcdl packet (`hdcs/1`), forced ask-or-certify
S2 orchestrate          packet -> build brief (MUST_KEEP pins survive the funnel)
S3 build                ensemble ladder: s3 -> s3-alt -> s3-repair
  gate                  zero-LLM mechanical gate (bash fixtures) — GATE PASS or repair
S4 judge                a decorrelated model judges the artifact against the packet
S5 debrief              reverse-translation to plain text for the human
```

The stages are deliberately asymmetric: everything up to the gate is construction, the
gate is mechanical truth, S4 is adversarial reading. **S4 is free-speaking by design** —
it may object to anything, in its own words, unconstrained by line budgets — and every
objection it raises is treated as real until proven otherwise. The battery's verdict:
11 laps in, every single S4 objection traced back to a genuine defect — in the artifact,
the register, or the gate itself.

## Why a register

hcdl is a domain-locked technical register, not a compression trick. Every noun is the
precise term for the thing — no vernacular paraphrases ("checks if the file is old" ->
`staleness test: floor(age_days) >= AGE_DAYS`). The register travels with the task's
domain: a rotation tool reasons in filesystem/lifecycle terms, a network tool in protocol
terms; the packet carries the domain lock. Lossless in, lossless out — nothing may be
dropped crossing the boundary in either direction, and S5's reverse-translation is gated
by its own mechanical check.

Where the language ends, mathematics takes over — structural and quantified statements
that prose cannot express compactly or exactly:

| Notation | Reading |
|----------|---------|
| `∀ x ∈ S: P(x)` | universal — every element of the set must satisfy the predicate |
| `∃ x ∈ S: P(x)` | existential — at least one must |
| `∧ ∨ ¬` | and, or, not — logical connectives in conditions |
| `->` | implication and transformation ("A -> B": if A then B; A becomes B) |
| `:=` | definition — the left side is *defined* as the right side |
| `Δ`, `∴`, `∵` | change, therefore, because — derivation markers |

One task law, twice:

> Plain: "The rotation script must move every file older than 14 days into the archive,
> preserving the folder structure, and it must never run as root."

> hcdl: `∀ f ∈ RUNS_DIR: floor(age_days(f)) ≥ AGE_DAYS -> mv(f, ARCHIVE_DIR/rel(f)) ∧
> preserve(rel(f))`; `¬root`; `dry_run ≡ zero_write`

The point is not that the second is shorter. It is that the second **cannot be
misread** — "older than" now has exactly one meaning (`≥ AGE_DAYS`, the boundary case
included), and the set it quantifies over is explicit.

## Design doctrine

- **Gate, not wall** — a failed gate triggers a repair round with the failure output, not
  a termination. Two rounds max, then route to a human with the evidence.
- **Retry the part that failed** — unchanged stages replay from cache at zero cost;
  only the failing seam re-runs.
- **Snapshot discipline** — if a repair breaks a passing gate, the kernel restores the
  gate-passing snapshot (files + text) and the next lap repairs from the clean baseline.
- **Register of record** — the artifact's own source is the only authority for behavior
  claims; the judge re-observes live (runs the script, re-checks URLs), never trusts prose.
- **MUST_KEEP** — non-negotiables pinned in the packet so they survive the S2 funnel.
- **Lesson into fixture** — a finding class that repeats becomes a permanent mechanical
  gate fixture, not a prompt plea.
- **Gate-aware draws** — every builder draw receives the gate script verbatim as the
  acceptance contract: builders build to the same ground truth the gate judges with.

## The self-upgrade loop

`selfupgrade/` is a zero-LLM layer that runs the loop from a task queue:

- **Scheduler** — oldest task first, parallel workers (`--workers=N`).
- **Outcome classifier** — exit-code routing; a finding class repeated across laps is the
  *promote* signal.
- **Promote path** — a promoted finding class becomes a permanent mechanical gate fixture.
- **Law drafting** — the loop can draft register laws, but nothing merges without a
  human: operator approval is required for every law and gate amendment.

Proof points (2026-09-02):

- The loop drafted its own first law. **A8, anti-fabrication**: a verifier must re-derive
  its verdict from the artifact on disk — recorded notes may index, never attest. The
  operator approved it; it is canon in `LAWS.md`.
- Task 006: a real-world bug (a doctor script's git false positive) was routed through
  the loop and fixed in 3 laps, the register refined live (A1 scope-and-report,
  A3 exit-code-is-verdict).

Three operator modes:

1. **Self-upgrade** — the queue drives its own hardening laps.
2. **Creator mode** — a template factory for new task classes.
3. **General agent** — an agent drives the loop for arbitrary work.

## Generalization battery

One shared kernel; four delivered task classes, one security-critical stress test, and
one real-world bug routed through the loop:

| Run | Task | Outcome |
|-----|------|---------|
| 001 | hermes-context freshness timer (systemd deliverable) | DELIVERED |
| 002 | sync runbook (no mechanical gate — pure S4 judgment) | DELIVERED |
| 003 | code-index query refactor | DELIVERED |
| 004 | anti-fabrication dossier (judge re-observes every cited URL) | DELIVERED |
| 005 | runs-log rotation triad (boundary, mirror, path-law) | findings → permanent fixtures |
| 006 | backup-doctor git-scope repair (real-world bug routed through the loop) | DELIVERED |

002b re-delivered the runbook under a closed-world doctrine after the judge caught
invented mechanisms and a rollback bug. 005 was the security-critical stress test: its
findings now run as permanent gate fixtures.

## Quick start

```bash
node loop.mjs runs/<task> --budget <n>
```

Drive the queue with parallel workers:

```bash
node selfupgrade/driver.mjs --once --workers=3
```

A task is just two files: `task.md` — the register (intent, artifacts, laws, MUST_KEEPs)
— and `gate.sh` — the mechanical acceptance contract (`exit 0` = GATE PASS). The kernel
does the rest and reports outcomes. Exit codes: `0` delivered, `1` fail,
`2` needs-clarification, `3` budget exhausted.

HDCS is provider-neutral: stages route to whatever models you configure in `seats.json`.
Cross-family discipline applies — the builder and the judge should never share a family,
because the judge that shares the builder's biases certifies them.

## HDCS Control Room (DSH plugin)

The Control Room is a live dashboard for the loop — queue depth, lap progress, gate and
S4 verdicts, law drafts — rendered inside the DSH harness UI while the loop runs.

It is a dynamic Cordis plugin reading the same files the loop writes (`queue/`, `runs/`,
`LAWS.md`) — no separate backend, no sync layer.

## Layout

```
loop.mjs        the kernel (S1..S5, gate ladder, snapshot discipline, cache)
seats.json      stage routing config (models are yours to choose)
prompts/        stage system prompts
gates/          packet validator, reverse-translation gate, seat runner
guards/         packet pin guard
runs/           one dir per task: task.md + gate.sh + all lap evidence
queue/          the self-upgrade task queue
LAWS.md         the canon law register (operator-approved)
selfupgrade/    the zero-LLM self-upgrade loop (scheduler, classifier, promote)
```

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — free to use, study, modify, and share for any
noncommercial purpose. No selling.
