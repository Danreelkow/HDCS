# HDCS — the hcdl register loop

**HDCS is a loop that makes LLMs reason in a constructed technical language instead of
plain prose — and reverse-translates the result back for humans.**

The premise: LLM reasoning is a self-talk loop started by the input. The language of the
input selects which part of the model's training distribution the loop runs in. Prose
activates the fuzzy, conversational regions; a dense, domain-locked, mathematically
structured register activates the formal ones — papers, specs, formal code. HDCS applies
that register to everything machine-facing (packets, briefs, artifacts, inter-agent
traffic), and keeps humans out of it entirely: a translator stage converts your request
**in**, and a debrief stage converts the verified result **out**.

The primary claim is **quality**. Token efficiency is a side effect of precision, not the
goal — dense language is cheaper because fluff died, but it exists because precise terms
replace vague guesswork.

---

## The register — two parts

### Part I — the language

hcdl is a domain-locked technical register, not a compression trick:

- **Post-grad register only.** Every noun is the precise term for the thing. No vernacular
  paraphrases ("checks if the file is old" → `staleness test: floor(age_days) ≥ AGE_DAYS`).
- **Domain-locked.** The register travels with the task's domain — a rotation tool reasons
  in filesystem/lifecycle terms; a network tool in protocol terms. The packet carries the
  domain lock.
- **Lossless in, lossless out.** Nothing may be dropped crossing the boundary in either
  direction. S5's reverse-translation is gated by its own mechanical check.

### Part II — the notation

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

A worked flavor of the register (one task law, twice):

> Plain: "The rotation script must move every file older than 14 days into the archive,
> preserving the folder structure, and it must never run as root."

> hcdl: `∀ f ∈ RUNS_DIR: floor(age_days(f)) ≥ AGE_DAYS -> mv(f, ARCHIVE_DIR/rel(f)) ∧
> preserve(rel(f))`; `¬root`; `dry_run ≡ zero_write`

The point is not that the second is shorter. It is that the second **cannot be
misread** — "older than" now has exactly one meaning (`≥ AGE_DAYS`, the boundary case
included), and the set it quantifies over is explicit.

---

## The loop

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

`selfupgrade/` is a zero-LLM layer that runs laps from a task queue and routes outcomes:
a scheduler (one lap at a time, oldest first), an outcome classifier (exit-code routing;
a finding class repeated across laps is the *promote* signal), and a self-test suite.
The endgame: the loop repairs and hardens itself — with operator approval required for
law and gate amendments.

## Generalization battery

One shared kernel, four delivered task classes and one security-critical stress test:

| Run | Task | Outcome |
|-----|------|---------|
| 001 | hermes-context freshness timer (systemd deliverable) | DELIVERED |
| 002 | sync runbook (no mechanical gate — pure S4 judgment) | DELIVERED |
| 003 | code-index query refactor | DELIVERED |
| 004 | anti-fabrication dossier (judge re-observes every cited URL) | DELIVERED |
| 005 | runs-log rotation triad (boundary, mirror, path-law contracts) | findings → permanent fixtures |

## Quick start

```bash
node loop.mjs runs/<task> --budget <n>
```

A task is a directory with two files: `task.md` — the register (intent, artifacts, laws,
MUST_KEEPs) — and `gate.sh` — the mechanical acceptance contract (`exit 0` = GATE PASS).
The kernel does the rest and reports outcomes. Exit codes: `0` delivered, `1` fail,
`2` needs-clarification, `3` budget exhausted.

HDCS is provider-neutral: stages route to whatever models you configure in `seats.json`.
Cross-family discipline applies — the builder and the judge should never share a family,
because the judge that shares the builder's biases certifies them.

## Layout

```
loop.mjs        the kernel (S1..S5, gate ladder, snapshot discipline, cache)
seats.json      stage routing config (models are yours to choose)
prompts/        stage system prompts
gates/          packet validator, reverse-translation gate, seat runner
guards/         packet pin guard
runs/           one dir per task: task.md + gate.sh + all lap evidence
selfupgrade/    the zero-LLM self-upgrade loop
```

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — free to use, study, modify, and share for any
noncommercial purpose. No selling.
