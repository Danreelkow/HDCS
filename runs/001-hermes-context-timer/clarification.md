# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: `sync-hermes-context.sh` lines 36–45 reject only strict nesting (`DST` inside `SRC` or `SRC` inside `DST`) and do not reject `SRC == DST`. In fallback mode, lines 77–81 execute `rm -rf` against `"$DST"` before copying; with equal paths this deletes the source tree, violating A2 one-way/no-writeback and causing data loss. The rsync path likewise lacks an equality guard. `README.md` KNOWN_LIMITATIONS only acknowledges other degenerate `DST` choices and does not provide a compliant safeguard for this plausible destructive misconfiguration, which fails A10.

## Packet
```yaml
reg: {domain: cs-programming, canon: "rsync flags (--delete/--dry-run), systemd user units (systemctl --user, OnCalendar), POSIX shell (cp -a, tar pipe), exit-code contracts"}
intent: >
  deliver artifact dir {sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md}
  implementing standing one-way sync SRC -> DST (defaults /opt/data/workspace/hermes-context/ -> /workspace/hermes-context/),
  exact-mirror semantics (A5/A7/A9), rsync primary + cp/tar fallback (A4), --dry-run zero-write purity (A6),
  systemd USER timer every 6h + standalone script mode (A3), one-line summary log outside DST per run (A8).
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical SRC/DST? -> A: SRC=/opt/data/workspace/hermes-context/ (host mount), DST=/workspace/hermes-context/ (exists: INDEX.md, agents/, config/) [A1]"
  - "Q2: sync direction? -> A: one-way host -> workspace, no writeback [A2]"
  - "Q3: scheduler? -> A: systemctl --user timer, 6h; script standalone-capable if systemd absent [A3]"
  - "Q4: rsync missing? -> A: detect + cp -a/tar-pipe fallback, identical mirror semantics [A4]"
  - "Q5: stale files? -> A: exact mirror, delete stale, recursive, both paths converge [A5,A7]"
  - "Q6: dry-run logging? -> A: zero writes incl. logs; DST byte-identical gate [A6]"
  - "Q7: log/install placement? -> A: LOG always outside DST (~/.cache default); installs outside mirrored tree [A8]"
  - "Q8: mirror equivalence class? -> A: contents+structure+symlinks only; verify fails nonzero on mismatch [A9]"
  - "Q9: severity bar? -> A: FAIL on normal-operation defects only; exotic -> KNOWN_LIMITATIONS [A10]"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - "A5_mirror: both sync paths converge to identical end state, stale deleted"
  - "A6_dryrun_purity: --dry-run zero writes incl. log files; DST byte-identical post-run"
  - "A7_recursive: fallback reconciles stale subtrees at every depth"
  - "A8_placement: log + installed entrypoints live outside DST, never inside mirrored tree"
  - "A9_equiv_class: verify contents+structure+symlinks recursively; mismatch -> nonzero exit"
  - "A10_severity: FAIL bar = normal-operation defects; exotic triggers -> KNOWN_LIMITATIONS"
  - "no_resurrect: A5/A6/A7/A8/A9/A10 rulings bind all downstream seats"
paths:
  - /workspace/hermes-context/
  - /opt/data/workspace/hermes-context/
  - "~/.cache/hermes-context/sync.log"
  - "~/.local/bin/sync-hermes-context.sh"
  - "~/.config/systemd/user/hermes-context.service"
  - "~/.config/systemd/user/hermes-context.timer"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
