build brief for B1 — RUNBOOK.md (run-001 hermes-context)

state:
s0 := artifact = {sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md} @ runs/001-hermes-context-timer/artifact/. Tool facts (closed world): tool_flags = {--dry-run, --verify}; any other token → usage error, exit 2. env = HERMES_CONTEXT_SRC := /opt/data/workspace/hermes-context/, HERMES_CONTEXT_DST := /workspace/hermes-context/; set-but-empty → A23; unset → prod defaults. Behavior: one-way mirror DST→SRC (recursive, removes stale DST extras, preserves types ∧ symlink targets); staging verify → A13 on fail (DST untouched); --dry-run zero writes; --verify exit 0 iff exact mirror else nonzero + A9. Citations allowed: A23, A18 (∅/'. '/'), A12 (path identity/ancestor/symlink component), A13, A14 (staging path conflict incl TMPDIR set-but-empty), A9. Install: mkdir -p / install -D required; bin → ~/.local/bin; units → ~/.config/systemd/user/; timer period 6h. Rollback = remove bad DST + re-sync from HERMES_CONTEXT_SRC (not reinstall, not timer-disable-only).

Δ:
1. Write RUNBOOK.md at runs/001-hermes-context-timer/ with sections exactly in order, each non-empty:
   1) "What this tool does" — one-way mirror of HERMES_CONTEXT_SRC → HERMES_CONTEXT_DST; flags --dry-run, --verify only; other flags refused (usage error, exit 2).
   2) "Test before installing (--dry-run)" — run ./sync-hermes-context.sh --dry-run from artifact dir; state zero writes; note SRC/DST paths as configured env or prod defaults.
   3) "Install" — install -D -m 755 artifact/sync-hermes-context.sh ~/.local/bin/; install -D -m 644 artifact/hermes-context.service ~/.config/systemd/user/; install -D -m 644 artifact/hermes-context.timer ~/.config/systemd/user/; mkdir -p "$HERMES_CONTEXT_DST" or /workspace/hermes-context/.
   4) "Configure" — export HERMES_CONTEXT_SRC=... HERMES_CONTEXT_DST=... before sync (example paths marked "example"); unset → prod defaults; set-but-empty → A23 refuse.
   5) "Schedule" — systemctl --user daemon-reload; systemctl --user enable --now hermes-context.timer; timer period 6h.
   6) "Verify a sync" — sync-hermes-context.sh --verify; exit 0 = exact mirror; nonzero + A9 message = mismatch.
   7) "Roll back a bad sync" — rm -rf "$HERMES_CONTEXT_DST" then re-run sync to restore from HERMES_CONTEXT_SRC (concrete restore; NOT reinstall or timer-disable).
   8) "Troubleshooting" — A13 (staging verify fail, DST untouched), A14 (staging path conflict incl TMPDIR set-but-empty), A9 (mirror mismatch), A18 (∅/'.'/'/' paths), A12 (symlink/path-identity component issues), A23 (set-but-empty env); any other condition described without an A-number.
   Expected output: RUNBOOK.md exists at runs/001-hermes-context-timer/, contains all 8 headers in order, non-empty bodies.
2. Self-check: verify every command in the runbook succeeds as-written against artifact paths; verify MUST_KEEP strings present and non-hollow; verify no flag/env/path outside facts block (A1/A4); no hcdl jargon unexplained (A3).
   Expected output: self-check pass note listing checks 1–5 all pass.

accept:
- RUNBOOK.md exists at runs/001-hermes-context-timer/RUNBOOK.md.
- 8 sections in mandated order [What this tool does, Test before installing (--dry-run), Install, Configure, Schedule, Verify a sync, Roll back a bad sync, Troubleshooting], each non-empty.
- HERMES_CONTEXT_SRC and HERMES_CONTEXT_DST named exactly (INV_MK1); pre-install --dry-run test present (INV_MK2); rollback = remove DST + re-sync from HERMES_CONTEXT_SRC (INV_MK3).
- Every command succeeds as-written against artifact paths; install uses mkdir -p / install -D; timer period 6h; units/bin in stated user paths.
- No tool claim outside closed world: only --dry-run/--verify; no rsync-internal flags taught; citations limited to A23/A18/A12/A13/A14/A9; example operator paths marked as examples.
- Refusals/edge cases documented as delivered (A5); hcdl terms explained or absent (A3).

constraints:
- closed-world tool claims only (A1, A4); no invented flags/env/paths/defaults.
- tool_flags = {--dry-run, --verify}; --checksum/--delete/--itemize-changes are rsync internals, not taught as tool flags.
- citation register closed: {A23, A18, A12, A13, A14, A9}; unknown conditions described without A-number.
- install section must not assume target dirs exist (mkdir -p / install -D).
- sections ordered, all non-empty; example paths clearly marked.
- rollback = remove/re-sync DST from HERMES_CONTEXT_SRC; ¬ reinstall; ¬ disable-only.
- run-001 refusals documented as-is (A5, no_resurrect).
- plain imperative English (A3); validation bar = A7/S4.

deliverable:
- runs/001-hermes-context-timer/RUNBOOK.md