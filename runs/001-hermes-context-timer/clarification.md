# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict:

VERDICT: FAIL
EVIDENCE: `sync-hermes-context.sh:61-64` invokes `rsync -a --delete` while `sync-hermes-context.sh:66-69` excludes the artifact files from synchronization; this adds undeclared deletion/protection scope and means the destination is not a lossless contents mirror of `SRC/`. `sync-hermes-context.sh:83-85` and `sync-hermes-context.sh:96-98` use `cp -a`/tar without deletion, so fallback behavior diverges from the rsync path and stale destination files are never reconciled. `sync-hermes-context.sh:27-28` appends to `LOG_FILE` even for `--dry-run`; if `HERMES_CONTEXT_LOG` points into `HERMES_CONTEXT_DST`, the required zero-write dry run mutates the destination.

## Packet
```yaml
reg: {domain: cs-programming, canon: "shell/systemd ops vocabulary — rsync flags, ExecStart, OnCalendar, systemctl --user, exit codes, env var defaults"}
intent: >
  goal := build standing sync of Hermes context host->workspace.
  artifact_dir := {sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md}.
  sync := rsync -a (fallback cp -a / tar pipe if rsync not in PATH) of CONTENTS of
  HERMES_CONTEXT_SRC (default /opt/data/workspace/hermes-context/) into
  HERMES_CONTEXT_DST (default /workspace/hermes-context/), one-way host->workspace,
  no nesting (src/ -> dst/). --dry-run => zero writes. Idempotent; one-line summary log per run.
  Timer := systemd USER unit, OnCalendar every 6h; script standalone-executable when systemd absent.
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical source path? -> A: /opt/data/workspace/hermes-context/ (host-side Hermes context mount, per kb digests)"
  - "Q2: destination? -> A: /workspace/hermes-context/ (exists; holds INDEX.md, agents/, config/)"
  - "Q3: sync direction? -> A: one-way host -> workspace; no writes back to host mount"
  - "Q4: privilege model? -> A: systemctl --user units; no root"
  - "Q5: systemd absent? -> A: script must run standalone (cron/installer invokes it directly)"
  - "Q6: rsync absent? -> A: detect and fall back to cp -a semantics (or tar pipe)"
  - "Q7: sync granularity? -> A: contents of src dir into dst (src/ -> dst/), never nest source dir inside destination"
  - "Q8: schedule? -> A: every 6 hours via user timer"
  - "Q9: any remaining ambiguity? -> A: none — all decisions derivable from MUST_KEEP + operator answers A1-A4 + derived Q5-Q8; no-ambiguity certified"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff:
  state: S_0 + Delta -> S_1
  report:
    - "+done"
    - "-resolved"
    - "+open"
    - "+validation"
constraints:
  - "no_root: units installed under ~/.config/systemd/user/, systemctl --user only"
  - "one_way: sync direction host -> workspace only; no writes to HERMES_CONTEXT_SRC"
  - "dry_run: --dry-run => zero mutations of HERMES_CONTEXT_DST (rsync --dry-run / read-only fallback)"
  - "idempotent: repeated runs converge to identical dst state"
  - "fallback: rsync in PATH ? rsync : cp -a (or tar pipe); failure of both => nonzero exit + logged error"
  - "contents_sync: src/ -> dst/ (trailing-slash semantics), never /dst/src-basename"
  - "logging: exactly one summary line per run (mode, direction, files transferred/skipped, exit status)"
  - "no_resurrect: none cited (no prior ids supplied)"
paths:
  - "/workspace/hermes-context/"
  - "/workspace/hermes-context/sync-hermes-context.sh"
  - "/workspace/hermes-context/hermes-context.service"
  - "/workspace/hermes-context/hermes-context.timer"
  - "/workspace/hermes-context/README.md"
  - "/opt/data/workspace/hermes-context/"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
