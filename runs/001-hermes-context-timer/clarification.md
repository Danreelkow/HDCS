# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: hermes-context.timer:6 defines `OnCalendar=0 */6:00:00`, which is not a valid systemd calendar expression for a six-hour cadence; the user timer therefore cannot reliably load/run. The README repeats the same invalid expression at the install instructions’ timer description and does not provide a valid alternative such as `*-*-* 00/6:00:00`.

EVIDENCE: sync-hermes-context.sh:107-125 implements `tree_compare` using `[ -d "$b/$p" ]` and `[ -f "$b/$p" ]`, which follow symlinks, so a directory/file replaced by a symlink to a matching directory/file can be accepted as structurally equal. This violates A9’s recursive contents+structure+symlink equivalence requirement.

EVIDENCE: sync-hermes-context.sh:126-137 only enumerates candidate entries of types directory, regular file, and symlink, and likewise only records those types from SRC at lines 93-105. Special filesystem entries in SRC (for example FIFOs) are neither verified nor rejected as extras, so the script can report success without an exact recursive structure mirror.

EVIDENCE: sync-hermes-context.sh:36 sets `LOG_FILE` directly from `HERMES_CTX_LOG`, and README.md “Safety guards” permits that override without checking it is outside DST. A user setting `HERMES_CTX_LOG` inside `/workspace/hermes-context/` causes the log to be within the tree that lines 162-163 recursively delete, violating A8’s requirement that logs are always outside DST.

## Packet
```yaml
reg: {domain: cs-programming/ops-tooling, canon: shell/systemd vocabulary — rsync flags, realpath, systemctl --user units, OnCalendar, idempotence, exit codes}
intent: >
  Build artifact dir delivering standing fresh sync of Hermes context SRC -> DST:
  sync-hermes-context.sh (rsync primary, cp-fallback, --dry-run pure, idempotent,
  guarded per A11/A12/A13, one-line log per real run), hermes-context.service +
  hermes-context.timer (systemd USER, 6h cadence), README.md (install, source change,
  dry-run test, correct sync-strategy semantics). Both sync paths converge to exact
  mirror per A9 class, recursive.
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical source path? -> A: /opt/data/workspace/hermes-context/ (A1, kb-confirmed)"
  - "Q2: sync direction? -> A: host -> workspace one-way, no writeback (A2)"
  - "Q3: systemd scope? -> A: user units via systemctl --user; script also standalone-runnable (A3)"
  - "Q4: rsync unavailable? -> A: cp -a / tar-pipe fallback with identical mirror semantics (A4)"
  - "Q5: stale file policy? -> A: exact mirror, stale DELETED both paths (A5, A7 recursive)"
  - "Q6: dry-run logging? -> A: zero writes incl. logs; DST byte-identical post dry-run (A6)"
  - "Q7: log/install placement? -> A: log outside DST always (~/.cache default); entrypoints outside mirrored tree (A8)"
  - "Q8: mirror equivalence class? -> A: contents+structure+symlinks recursive only; metadata/hardlinks out-of-scope; verify fails nonzero on mismatch (A9)"
  - "Q9: severity bar? -> A: fail on normal-operation defects only; exotic -> +open KNOWN_LIMITATIONS (A10)"
  - "Q10: destructive misconfig? -> A: SRC==DST guarded; no rm -rf DST pre verified copy (A11)"
  - "Q11: identity check form? -> A: realpath-based incl. ancestor/descendant + symlink-through-SRC, clean nonzero refusal (A12)"
  - "Q12: verified copy definition? -> A: content-compared staging (A9 class) vs SRC; order stage->verify->touch DST (A13)"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "MUST_KEEP verbatim: source path is /opt/data/workspace/hermes-context/"
  - "MUST_KEEP verbatim: dry-run mode that performs no writes"
  - "MUST_KEEP verbatim: systemd user units, no root required"
  - "A11/A12/A13 guards precede any destructive op; no_resurrect: unverified-copy-as-verified, accumulate-only-fallback, log-inside-DST"
  - "A9 verify: nonzero exit on mismatch, never warn-exit-0"
paths:
  - "/opt/data/workspace/hermes-context/ (SRC)"
  - "/workspace/hermes-context/ (DST)"
  - "~/.cache/hermes-context/ (log, A8)"
  - "~/.local/bin or /workspace/hdcs/bin (install, A8)"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
