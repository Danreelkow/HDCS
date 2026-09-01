# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: sync-hermes-context.sh lines 60 and 83-86 use `mkdir -p "$DST"` and then operate through `$DST` without rejecting a pre-existing destination symlink; lines 107-108 verify only `[ -d "$DST" ]`, which follows symlinks. Thus a symlinked DST can cause writes outside DST and still pass verification, violating A2, A5, and A9. The fallback loops at lines 62-66 and 68-88 consume `find` output with `read -r rel` line-by-line, so filenames containing newlines are split and cannot be mirrored losslessly. Lines 19-20 hard-code the log under `$HOME/.cache/hermes-context` but never ensure it is outside an env-overridden `$DST`; setting `HERMES_CONTEXT_DST` to that path places logs inside the mirrored tree, violating A8.

## Packet
```yaml
reg: {domain: cs-programming, canon: shell/systemd vocabulary — rsync flags, ExecStart/OnCalendar, systemctl --user, env vars, exit codes; identifiers literal}
intent: >
  deliver artifact dir: sync-hermes-context.sh + hermes-context.service + hermes-context.timer
  + README.md. sync-hermes-context.sh: SRC := env HERMES_CONTEXT_SRC (default
  /opt/data/workspace/hermes-context/), DST := env HERMES_CONTEXT_DST (default
  /workspace/hermes-context/); primary rsync -a --delete src/ -> dst/; fallback cp -a +
  recursive stale-subtree reconciliation when rsync absent; --dry-run => zero writes incl.
  logs, DST byte-identical; one-line summary log per real run to log path outside DST.
  units: systemd --user, no root, timer OnCalendar every 6h. README: install, source change,
  --dry-run test, sync-strategy (recursive mirror semantics per A5/A7).
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical src/dst? -> A: A1 — src /opt/data/workspace/hermes-context/, dst /workspace/hermes-context/"
  - "Q2: sync direction? -> A: A2 — one-way host -> workspace; nothing writes back to host mount"
  - "Q3: systemd or cron? -> A: A3 — systemctl --user preferred; script standalone-capable (cron/installer callable)"
  - "Q4: rsync absent? -> A: A4 — detect + cp -a fallback; sync src/ CONTENTS into dst, no nesting"
  - "Q5: stale dst files? -> A: A5 — exact mirror, stale DELETED, both paths converge identically"
  - "Q6: dry-run logging? -> A: A6 — zero writes of any kind, logs skipped in dry-run"
  - "Q7: deletion depth in fallback? -> A: A7 — recursive, stale subtrees ∀ depth"
  - "Q8: log/install placement? -> A: A8 — log outside DST always (~/.cache default); entrypoints outside mirrored tree (~/.local/bin or /workspace/hdcs/bin)"
  - "Q9: mirror equivalence class? -> A: A9 — contents+structure+symlinks only; verify fails nonzero on mismatch; metadata/hardlink complaints out-of-scope"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "∀ run -> DST exact mirror of SRC (contents+structure+symlinks, recursive); A5/A7/A9"
  - "--dry-run => zero writes incl. log files; DST byte-identical post-run; A6"
  - "sync one-way host -> workspace; SRC never written; A2"
  - "log path outside DST always; entrypoints outside mirrored tree; A8"
  - "rsync absent -> cp -a fallback w/ identical convergence semantics; A4/A5"
  - "no root: user units, systemctl --user, standalone script; A3"
paths:
  - /workspace/hermes-context/          # DST default
  - /opt/data/workspace/hermes-context/ # SRC default (MUST_KEEP)
  - "~/.cache/hermes-context/sync.log"  # log default (outside DST)
  - "~/.local/bin/sync-hermes-context.sh" # install entrypoint (outside DST)
  - "~/.config/systemd/user/hermes-context.service"
  - "~/.config/systemd/user/hermes-context.timer"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
