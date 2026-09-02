# HDCS — the hcdl register loop

HDCS (hcdl register) is an LLM loop in which every machine-facing artifact is written in a
dense domain-locked technical register with mathematical notation (`∀ ∃ ∈ ∧ ∨ ¬ Δ ∴ ∵`, `->`,
`:=`). **Quality lift is the primary claim; token saving is the side effect of precision.**

A five-stage pipeline takes one human request and delivers a verified artifact:

```
S1 clarify/translate   human request -> hcdl packet (`hdcs/1`, 9 keys, forced ask-or-certify)
S2 orchestrate         packet -> build brief (MUST_KEEP pins survive the funnel)
S3 build               ensemble ladder: s3 -> s3-alt -> s3-repair, each draw sees the gate contract
  gate                 zero-LLM mechanical gate (bash fixtures; every S4 finding class becomes one)
S4 judge               decorrelated model judges artifact vs packet (2 rounds, 1 feedback repair)
S5 debrief             reverse-translation to plain text for the human
```

## Design doctrine

- **Gate, not wall** — a failed gate triggers a repair round with the failure output, not a
  termination. Two rounds max, then route to human with the evidence.
- **Retry the part that failed** — S1/S2 cached while inputs are unchanged; S3 cached and
  re-verified against the gate (zero LLM spend on unchanged artifacts).
- **Snapshot discipline** — if a feedback repair breaks a passing gate, the kernel restores
  the gate-passing snapshot (files + text) and the next lap repairs from the clean baseline.
- **Register of record** — the artifact's own source is the only authority for behavior and
  citation claims; the judge re-observes live (URLs, runs, listings), never trusts prose.
- **MUST_KEEP** — non-negotiables pinned in the packet so they survive the S2 brief funnel.
- **Lesson into fixture** — a finding class that repeats becomes a permanent mechanical gate
  fixture, not a prompt plea.
- **Gate-aware draws** — every builder draw receives `gate.sh` verbatim as the acceptance
  contract (build to the same ground truth the gate judges with).

## Kernel hardening (caught live by the generalization battery)

| # | Catch |
|---|-------|
| P1 | source/ channel — artifacts can cite their own inputs for verification |
| P2 | no-gate feedback repair path for writing-class tasks |
| P4 | lossless extraction — fenced artifacts no longer truncated at fence terminators |
| P5 | snapshot restore re-extracts files + text (failed builds no longer masquerade as baseline) |
| P6 | gate-aware draws — contract-first prompts for the whole ladder |
| P7 | `HDCS_SEATS` env override for parallel seat A/B experiments |

## Self-upgrade stack

`selfupgrade/` is a zero-LLM loop that runs laps from a task queue and routes outcomes:
`driver.mjs` (queue scheduler, oldest-first, never concurrent), `classify.mjs` (exit-code
routing; repeated finding classes are the promote signal), `selftest.sh` (12 fixtures /
17 assertions). The endgame: the loop repairs and hardens itself, with operator approval
required for law and gate amendments.

## Battery (generalization test, one shared kernel)

| Run | Task | Outcome |
|-----|------|---------|
| 001 | hermes-context freshness timer | DELIVERED (installed via its own README) |
| 002 | sync runbook (no mechanical gate, pure S4) | DELIVERED |
| 003 | code-index query refactor | DELIVERED |
| 004 | anti-fabrication dossier (judge re-observes 15 URLs) | DELIVERED |
| 005 | runs-log rotation triad (boundary + mirror + verify contracts) | in flight |

Typical lap cost: $0.005–0.015.

## Quick start

```bash
node loop.mjs runs/<task> --budget 0.12
```

A task is a directory with `task.md` (the register: intent, artifacts, laws, MUST_KEEPs)
and `gate.sh` (the mechanical acceptance contract; `exit 0` = GATE PASS). The kernel does
the rest and writes a cost report + outcome JSON. Exit codes: `0` delivered, `1` fail,
`2` needs-clarification, `3` budget.

## Layout

```
loop.mjs        the kernel (S1..S5, gate ladder, snapshot discipline, cache)
seats.json      model routing per stage
prompts/        stage system prompts
gates/          packet validator, reverse-translation gate, seat runner
guards/         packet pin guard
runs/           one dir per task: task.md + gate.sh + all lap evidence
selfupgrade/    the zero-LLM self-upgrade loop
```

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — free to use, study, modify, and share for any
noncommercial purpose. No selling.  -  Plant a tree commit to opensource
