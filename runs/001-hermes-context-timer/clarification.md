# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: `sync-hermes-context.sh` lines 46–58 purge only the contents of `DST` and run `cp -a "$SRC/." "$DST/"`; this does not copy the source root directory’s metadata onto the already-existing `DST` root, whereas `rsync -a --delete "$SRC" "$DST"` (lines 51–53) does, so the fallback and primary paths do not converge to an identical exact end state as required by A5. `README.md`, Fallback bullet, explicitly acknowledges another divergence: `cp -a` preserves hard-link relationships while `rsync -a` does not (`-H` is absent), contradicting its claim that both paths produce a “byte-identical end state.” The fallback verification (`sync-hermes-context.sh` lines 61–70) hashes only regular files, logs a warning on mismatch, and still exits successfully; it does not verify or enforce equality of symlinks, empty directories, metadata, or link topology.

## Packet
```yaml
reg: {domain: cs-programming, canon: "exact identifiers: rsync flags (--delete, --dry-run, -a), HERMES_CONTEXT_SRC/DST/LOG, cp -a, systemctl --user, systemd unit directives (OnCalendar, WantedBy=default.target)"}
intent: >
  build artifact dir with sync-hermes-context.sh + hermes-context.service +
  hermes-context.timer + README.md s.t. ∀ real run -> /workspace/hermes-context/
  becomes exact recursive mirror of /opt/data/workspace/hermes-context/ (host->dst,
  one-way, A2), idempotent (run^n == run^1), with rsync primary path and cp -a
  fallback path converging to identical end state (A5/A7), --dry-run producing zero
  writes of any kind incl. logs (A6), all persistent artifacts placed outside the
  mirrored tree (A8).
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical source path? -> A: /opt/data/workspace/hermes-context/ per A1 (kb digests, host-side Hermes context mount)"
  - "Q2: sync direction & writeback? -> A: host->workspace one-way; nothing writes back to host mount (A2)"
  - "Q3: systemd scope? -> A: user-level systemctl --user, no root; script must also work standalone if systemd absent (A3)"
  - "Q4: rsync missing? -> A: detect and fall back to cp -a (or tar pipe); sync CONTENTS of src into dst, no nesting (A4)"
  - "Q5: stale file handling? -> A: exact mirror, stale files DELETED; rsync --delete; cp fallback reconciles identically (A5)"
  - "Q6: dry-run log writes? -> A: --dry-run performs ZERO writes incl. log files even if HERMES_CONTEXT_LOG points inside DST; dry-run leaves DST byte-identical (A6)"
  - "Q7: fallback deletion depth? -> A: recursive convergence, stale subtrees deleted at every depth; README states this correctly (A7)"
  - "Q8: log & install placement? -> A: log ALWAYS outside DST (~/.cache default, no carve-outs); install paths outside mirrored tree (~/.local/bin or /workspace/hdcs/bin); sync never deletes its own entrypoints (A8)"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff:
  state: S_0 + Delta -> S_1
  report: [+done, -resolved, +open, +validation]
constraints:
  - "∀ real run -> DST end state == SRC end state, recursive, byte-faithful (A5/A7; no_resurrect: accumulate-only fallback, top-level-only deletion)"
  - "dry-run -> zero writes ∀ targets; mechanical gate = full-tree byte-identity of DST pre/post (A6; no_resurrect: probe-file-only dry-run check)"
  - "log path ∉ DST ∀ modes, no carve-outs, no post-mirror rewrite (A8; no_resurrect: log-inside-DST)"
  - "install paths ∉ mirrored tree; sync never deletes own entrypoints (A8; no_resurrect: artifact/ inside DST)"
  - "one-way host->workspace; no writeback to SRC (A2)"
  - "user units only, no root (MUST_KEEP)"
  - "idempotent: run^n == run^(n-1)"
paths:
  - /workspace/hermes-context/
  - /opt/data/workspace/hermes-context/
  - "<artifact_dir>/sync-hermes-context.sh"
  - "<artifact_dir>/hermes-context.service"
  - "<artifact_dir>/hermes-context.timer"
  - "<artifact_dir>/README.md"
  - "~/.config/systemd/user/hermes-context.service"
  - "~/.config/systemd/user/hermes-context.timer"
  - "~/.local/bin/sync-hermes-context.sh"
  - "~/.cache/hermes-context/sync.log"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
