# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict:

VERDICT: FAIL
EVIDENCE: `sync-hermes-context.sh:59-64` runs the fallback tar pipeline without `set -o pipefail` or equivalent status handling; a failing source-side `tar` can be masked by a successful receiving `tar`, leaving an incomplete destination while `status` remains 0. `sync-hermes-context.sh:68-73` tests stale entries with `[ ! -e "${SRC}${rel}" ]`, so dangling symlinks in the destination are not deleted (`-e` is false for them); additionally, failures from `rm -rf` inside the pipeline are not propagated into `status`, so fallback synchronization is not guaranteed to converge or report failure. `README.md` states at its log-path entry that the log is `${HERMES_CONTEXT_DST}/.sync-hermes-context.log` “if set,” but `sync-hermes-context.sh:12` defaults to `${HOME}/.cache/hermes-context-sync.log` and never derives a destination-relative log path; the documented behavior is therefore inaccurate.

## Packet
```yaml
reg: {domain: cs-programming, canon: shell/systemd operations vocabulary — rsync --delete/--dry-run, cp -a fallback, systemctl --user, user units, environment-variable defaults, exact-mirror idempotency, recursive convergence, exit status}
intent: >
  deliver artifact dir containing sync-hermes-context.sh, hermes-context.service,
  hermes-context.timer, and README.md implementing one-way exact-mirror freshness
  synchronization from /opt/data/workspace/hermes-context/ to /workspace/hermes-context/.
  rsync is primary; cp -a or tar-pipe fallback is semantically equivalent.
  --dry-run performs zero writes, including log writes.
  systemd user timer runs at 6h cadence; the script remains standalone-capable without systemd.
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical source path? -> A: /opt/data/workspace/hermes-context/ (host-side Hermes context mount, kb digests)"
  - "Q2: canonical destination path? -> A: /workspace/hermes-context/ (existing destination containing INDEX.md, agents/, and config/)"
  - "Q3: synchronization direction? -> A: host -> workspace, one-way; no writes to the host source mount"
  - "Q4: scheduling and execution mode? -> A: systemctl --user timer at 6h cadence; script also executes standalone without systemd"
  - "Q5: rsync unavailable? -> A: detect absence and use cp -a or tar-pipe fallback; timer remains functional on minimal hosts"
  - "Q6: source/destination topology? -> A: synchronize source contents src/ -> dst/; never nest the source directory inside destination"
  - "Q7: mirror semantics? -> A: exact mirror with recursive stale-entry deletion; rsync uses --delete; fallback converges to the identical end state"
  - "Q8: dry-run purity? -> A: zero writes of any kind, including log files; HERMES_CONTEXT_LOG inside destination remains untouched; destination is byte-identical after dry-run"
  - "Q9: fallback deletion depth? -> A: recursive convergence at every depth, including stale subtrees; DST becomes byte-identical to SRC for synchronized paths"
  - "NO_AMBIGUITY: Q1-Q9 have recorded operator answers; default log path, ~/.config/systemd/user/ installation directory, and OnCalendar expression are derivable implementation choices; no Q->A: OPEN entries exist"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff:
  state: S_0 + Delta -> S_1
  report: ["+done", "-resolved", "+open", "+validation"]
constraints:
  - "one-way sync host -> workspace; no write-back to /opt/data/workspace/hermes-context/; no_resurrect: A1"
  - "exact-mirror semantics: stale files and directories deleted recursively at every depth; rsync --delete and cp-fallback paths converge byte-identically; no_resurrect: A2"
  - "--dry-run performs zero writes of any kind, including log files; destination remains byte-identical after execution; no_resurrect: A3"
  - "HERMES_CONTEXT_SRC default := /opt/data/workspace/hermes-context/; HERMES_CONTEXT_DST default := /workspace/hermes-context/; no_resurrect: A4"
  - "synchronize contents src/ -> dst/; never create source-directory nesting in destination; no_resurrect: A5"
  - "systemd user units only via systemctl --user; no root required; script exits 0 standalone without systemd; no_resurrect: A6"
  - "detect rsync absence and invoke cp -a or tar-pipe fallback preserving exact-mirror and recursive-convergence semantics; no_resurrect: A7"
  - "emit one-line summary log per real run only; HERMES_CONTEXT_LOG is not modified during dry-run; no_resurrect: A8"
paths:
  - /workspace/hermes-context/
  - /opt/data/workspace/hermes-context/
  - sync-hermes-context.sh
  - hermes-context.service
  - hermes-context.timer
  - README.md
budgets: {tokens: 12000, lines: 60, fix_cycles: 2, questions: 2}
```
