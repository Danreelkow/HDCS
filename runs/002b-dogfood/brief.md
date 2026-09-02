# BUILD BRIEF → B1

state: s0 := packet READY; artifact tree at /workspace/hdcs/runs/001-hermes-context-timer/artifact/ (sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md); facts I1–I7 in context.hcdl; target file RUNBOOK.md does not yet exist; no open questions.

Δ :=

1. Read all four artifact files at /workspace/hdcs/runs/001-hermes-context-timer/artifact/ to confirm facts I1–I4 (flags, env vars, paths, timer period, log location).
   → expected: notes confirming --dry-run, --verify, exit 2 on other flags, HERMES_CONTEXT_SRC/DST defaults, 6h timer, ~/.cache/hermes-context/ log path.

2. Create /workspace/hdcs/runs/001-hermes-context-timer/RUNBOOK.md with exactly these 8 sections in order, each non-empty:
   1. **What this tool does** — one-way recursive rsync mirror SRC→DST, removes stale DST extras, preserves types+symlink targets, re-verifies after sync (I3).
   2. **Test before installing** — block starting with literal `cd /workspace/hdcs/runs/001-hermes-context-timer/artifact` then `./sync-hermes-context.sh --dry-run` (I3: plan only, zero writes).
   3. **Install** — `mkdir -p ~/.local/bin ~/.config/systemd/user` then `install -D` (or cp) of script and both units; no assumption dirs exist (mkdir_rule).
   4. **Configure** — document HERMES_CONTEXT_SRC and HERMES_CONTEXT_DST verbatim with defaults /opt/data/workspace/hermes-context/ → /workspace/hermes-context/; show `export` mechanism; any override lines marked `# example:` (A1_mk1, Q5).
   5. **Schedule** — `systemctl --user daemon-reload`, `systemctl --user enable --now hermes-context.timer`; state 6h period (I4).
   6. **Verify a sync** — `./sync-hermes-context.sh --verify` after cd line; exit 0 = exact mirror, nonzero = mismatch (I3).
   7. **Roll back a bad sync** — concrete: remove bad HERMES_CONTEXT_DST contents, re-sync from configured known-good HERMES_CONTEXT_SRC; state disabling timer alone is insufficient (I7).
   8. **Troubleshooting** — table/list of A-number meanings: A9 mirror-mismatch findings; A12 same/ancestor/descendant/symlink-component path conflict; A13 staging verification failed (DST untouched); A14 staging conflicts incl. set-but-empty TMPDIR; A18 degenerate paths (empty/'.'); A23 set-but-empty env var (unset falls back to prod defaults); other refusals described without citation (I5).
   → expected: RUNBOOK.md exists with 8 sections, exact order, all non-empty.

3. Self-check pass against constraints before handoff:
   - every instruction block begins with the literal cd line or uses absolute paths; only `# example:` lines exempt;
   - no tool flags beyond --dry-run/--verify anywhere; no --checksum/--delete/--itemize-changes taught;
   - no invented mechanisms (env files, canonicalization, invented refusal text);
   - no hcdl vocabulary (packet/seat/register) unexplained in body — prefer omit;
   - every claim traceable to I1–I7 or artifact; delete anything else.
   → expected: checklist all-pass; any failing claim deleted, not reworded.

accept:
1. /workspace/hdcs/runs/001-hermes-context-timer/RUNBOOK.md exists.
2. grep -c '^## ' RUNBOOK.md == 8, headings match mandated order/names.
3. Every fenced command block's first line is `cd /workspace/hdcs/runs/001-hermes-context-timer/artifact` or all commands use absolute paths; exception: lines starting `# example:`.
4. `grep -E -- '--(checksum|delete|itemize-changes)' RUNBOOK.md` returns no matches outside rsync-internal disclaimer context (or zero matches).
5. HERMES_CONTEXT_SRC and HERMES_CONTEXT_DST each appear with verbatim defaults.
6. Rollback section contains a concrete removal + re-sync action; phrase "disabling the timer" appears only as insufficient.
7. Troubleshooting section defines A9, A12, A13, A14, A18, A23 in plain English.
8. No occurrence of "packet", "seat", "hcdl" in body.

constraints:
- closed-world: every claim ∈ facts(I1–I7) ∨ artifact-verifiable; else DELETE.
- tool flags = --dry-run, --verify only; any other flag = usage error exit 2 (document as such, never teach).
- instruction blocks executable verbatim from arbitrary cwd.
- `# example:`-marked config lines exempt from executability; section must still show export mechanism.
- document refusals as delivered (A5); no idealized behavior.
- single deliverable file; no other files created or modified.

deliverable:
- /workspace/hdcs/runs/001-hermes-context-timer/RUNBOOK.md