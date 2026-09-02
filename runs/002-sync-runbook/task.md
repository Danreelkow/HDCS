Task: operator runbook for the run-001 hermes-context sync tool

Run 001 delivered a working sync artifact (runs/001-hermes-context-timer/artifact/):
sync-hermes-context.sh plus systemd user units. New operators have nothing that
explains how to live with it. Write that document.

Deliverable (single file): RUNBOOK.md — a runbook for a NEW operator with zero
prior context. Required sections, in order: What this tool does; Install;
Configure (change the source); Test before installing (--dry-run); Schedule
(systemd user timer); Verify a sync; Roll back a bad sync; Troubleshooting
(refusals and what their A-number citations mean).

System facts you must represent accurately (they are the accuracy bar):
env vars HERMES_CONTEXT_SRC / HERMES_CONTEXT_DST override the deployed defaults
(/opt/data/workspace/hermes-context/ -> /workspace/hermes-context/); --dry-run
performs zero writes; --verify exits nonzero on mirror mismatch; real runs log
one line to ~/.cache/hermes-context/; install path ~/.local/bin; units in
~/.config/systemd/user/; timer fires every 6 hours; refusals exit nonzero and
cite an A-number.

MUST_KEEP: documents HERMES_CONTEXT_SRC and HERMES_CONTEXT_DST exactly
MUST_KEEP: includes a --dry-run test the operator can run before installing
MUST_KEEP: states the documented rollback for a bad sync
