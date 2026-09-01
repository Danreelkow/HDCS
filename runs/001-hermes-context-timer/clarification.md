# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict:

VERDICT: FAIL
EVIDENCE: The fallback is not an exact mirror for all paths. In `sync-hermes-context.sh:35-40`, `list_entries` enumerates only top-level entries, and the reconciliation at `sync-hermes-context.sh:77-81` deletes only top-level destination entries absent from the source. If `DST/a/stale` exists while `SRC/a` exists without `stale`, `cp -a` at `sync-hermes-context.sh:74-75` leaves `DST/a/stale` behind, so fallback does not converge to the `rsync --delete` end state required by A5. README.md also incorrectly claims exact identical end states in its “Sync strategy” section.

## Packet
```yaml
reg: {domain: cs-programming, canon: shell/systemd ops vocabulary — rsync flags (--delete, --dry-run), systemd unit directives (OnCalendar, WantedBy=default.target), env vars HERMES_CONTEXT_SRC/DST/LOG, idempotency, cp -a fallback}
intent: >
  Build artifact dir hermes-context-sync/ := {sync-hermes-context.sh, hermes-context.service,
  hermes-context.timer, README.md} implementing standing one-way mirror
  /opt/data/workspace/hermes-context/ -> /workspace/hermes-context/ (contents, no nesting).
  Primary path: rsync --delete --dry-run-capable. Fallback path: cp -a + reconciliation
  pass deleting dst entries absent from src. Idempotent ∀ runs; converge to identical
  end state rsync-path ∧ fallback-path. --dry-run => zero writes ∀ paths (dst AND log).
  systemd --user timer every 6h; script standalone-runnable without systemd.
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical src/dst? -> A: src=/opt/data/workspace/hermes-context/ (A1); dst=/workspace/hermes-context/ (exists: INDEX.md, agents/, config/) (A1)"
  - "Q2: sync direction? -> A: host -> workspace one-way; no write-back to host mount (A2)"
  - "Q3: execution mode? -> A: systemd --user preferred; script must run standalone without systemd (A3)"
  - "Q4: rsync absent? -> A: detect; fallback cp -a semantics (or tar pipe); sync CONTENTS src/ -> dst, never nest src inside dst (A4)"
  - "Q5: mirror semantics for fallback? -> A: exact mirror, stale files DELETED; cp fallback reconciles identically to rsync --delete; no accumulate-only mode (A5)"
  - "Q6: dry-run purity? -> A: --dry-run performs ZERO writes incl. log files; if HERMES_CONTEXT_LOG inside dst, dry-run must not touch it; logging only in real-run; gate: dry-run leaves dst byte-identical (A6)"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: ["+done", "-resolved", "+open", "+validation"]}
constraints:
  - "one-way host -> workspace; no write-back to /opt/data/workspace/hermes-context/ (A2)"
  - "rsync path: rsync --delete; fallback path: cp -a + deletion pass; identical end state ∀ paths (A5)"
  - "--dry-run => zero writes ∀ fs targets incl. HERMES_CONTEXT_LOG (A6)"
  - "no_root: systemd units are user units (systemctl --user, WantedBy=default.target) (A3)"
  - "script standalone-capable sans systemd ∧ sans rsync (A3, A4)"
  - "no_resurrect: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md — single artifact dir"
  - "+done detail: locked reg=cs-programming; folded A1..A6 into spec; mirror+reconcile fixed ∀ paths; dry-run purity gate (byte-identical dst, zero writes incl. log)"
  - "-resolved detail: Q1..Q6 closed by operator rulings (evidence: resolved list)"
  - "+open detail: none — ∀ ambiguity ∈ {src, dst, direction, scheduler, fallback, mirror, dry-run} has recorded operator answer"
  - "+validation detail: verify asserts (a) rsync --delete ∧ fallback reconcile -> identical dst end-state, (b) --dry-run dst byte-identical + zero log writes, (c) no src-dir nesting in dst, (d) User-level units (default.target), no root"
paths:
  - /opt/data/workspace/hermes-context/
  - /workspace/hermes-context/
  - "artifact-dir: hermes-context-sync/{sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md}"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
