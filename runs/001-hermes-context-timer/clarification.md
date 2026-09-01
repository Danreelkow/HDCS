# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: sync-hermes-context.sh, lines 23–31, and README.md, lines 8–12: the packet’s canonical log identifier is `HERMES_CONTEXT_LOG`, but the artifact instead invents and uses `HERMES_CONTEXT_LOG_DIR` and `LOG_DIR`; `HERMES_CONTEXT_LOG` is unsupported. sync-hermes-context.sh, staging block lines 163–185: `mktemp -d` is performed under the unvalidated `TMPDIR` candidate before checking the instantiated stage against `SRC`/`DST`; if `TMPDIR` is `SRC` or `DST`, the script writes into a guarded path before the A11/A13 verification gate, then removes it and refuses. This violates the required stage → verify → touch ordering and the no-write-to-source/untouched-DST guarantees.

## Packet
```yaml
reg: {domain: cs-programming, canon: bash/rsync/systemd-user-unit vocabulary — exact flags (--delete, --dry-run, mktemp -d, realpath), unit directives (OnCalendar, WantedBy=default.target), identifiers HERMES_CONTEXT_SRC/DST/LOG}
intent: >
  deliver artifact dir: sync-hermes-context.sh (rsync primary, cp-fallback with recursive
  reconcile; SRC/DST via env with production defaults; --dry-run zero-write; idempotent;
  one-line summary log in real runs only; guards A11-A23) + hermes-context.service/.timer
  (systemctl --user, OnCalendar=every 6h, standalone-executable script) + README.md
  (install, source change, --dry-run test, sync-strategy states recursive mirror A7).
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical SRC/DST? -> A: A1/A17 — /opt/data/workspace/hermes-context/ -> /workspace/hermes-context/, env override is the contract"
  - "Q2: sync direction? -> A: A2 one-way host->workspace"
  - "Q3: no systemd? -> A: A3 script standalone-executable"
  - "Q4: rsync absent? -> A: A4 cp -a/tar-pipe fallback, identical A5 semantics"
  - "Q5: stale files? -> A: A5/A7 exact recursive mirror, delete stale subtrees both paths"
  - "Q6: dry-run logging? -> A: A6 zero writes incl. logs; A16 dry-run must not create DST"
  - "Q7: log/install placement? -> A: A8 outside DST always (~/.cache log, ~/.local/bin entrypoints)"
  - "Q8: mirror equivalence class? -> A: A9 contents+structure+symlinks only; self-verify fails nonzero on mismatch"
  - "Q9: severity bar? -> A: A10 normal-operation FAILs only; exotic -> +open"
  - "Q10: destructive misconfig? -> A: A11-A13 SRC==DST guard, verified (content-compared) staging before any DST touch"
  - "Q11: path guards scope? -> A: A14/A15 concrete owned paths, boundary-aware; A18 degenerate refusals; A19 closed law list"
  - "Q12: staging order? -> A: A20/A23 validate parent as pure string -> mktemp under validated parent -> re-validate"
  - "Q13: DST symlink? -> A: A22 refuse, never replace"
  - "Q14: unset vs empty vars? -> A: A23 unset->default, set-but-empty->refuse"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "A5/A7: both sync paths converge to identical recursive end state"
  - "A6/A16: --dry-run zero writes, DST byte-identical, absent DST stays absent"
  - "A11/A13: stage -> content-verify -> touch DST; no rm -rf before verified copy"
  - "A12/A14/A15/A18/A19: refusal law closed; refusals cite A-numbers; component-boundary compare"
  - "A20/A22/A23: stage ordering, symlink-DST refuse, unset/empty var semantics"
  - "A9: self-verification enforces contents+structure+symlinks, nonzero exit on mismatch"
  - "A8: log + entrypoints outside DST; no_resurrect: installed entrypoints never deleted by sync"
paths:
  - "/opt/data/workspace/hermes-context/ (SRC default, deployed production value)"
  - "/workspace/hermes-context/ (DST default)"
  - "~/.cache/hermes-context/sync.log (log, outside DST)"
  - "~/.local/bin/sync-hermes-context.sh (entrypoint install, outside DST)"
  - "~/.config/systemd/user/hermes-context.service, hermes-context.timer"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
