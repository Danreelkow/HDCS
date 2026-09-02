Task: operator runbook for the run-001 hermes-context sync tool

Run 001 delivered a working sync artifact (runs/001-hermes-context-timer/artifact/):
sync-hermes-context.sh plus systemd user units. New operators have nothing that
explains how to live with it. Write that document.

Deliverable (single file): RUNBOOK.md — a runbook for a NEW operator with zero
prior context. Required sections, in order: What this tool does; Test before
installing (--dry-run); Install; Configure (change the source); Schedule
(systemd user timer); Verify a sync; Roll back a bad sync; Troubleshooting
(refusals and what their A-number citations mean).

System facts you must represent accurately (they are the accuracy bar):
env vars HERMES_CONTEXT_SRC / HERMES_CONTEXT_DST override the deployed defaults
(/opt/data/workspace/hermes-context/ -> /workspace/hermes-context/); --dry-run
performs zero writes; --verify exits nonzero on mirror mismatch; real runs log
one line to ~/.cache/hermes-context/; install path ~/.local/bin; units in
~/.config/systemd/user/; timer fires every 6 hours; refusals exit nonzero and
cite an A-number.

Artifact register (the run-001 artifact directory contains exactly these four
files; all of them are in-scope to teach: sync-hermes-context.sh,
hermes-context.service, hermes-context.timer, README.md). Install instructions
must not assume the target directories already exist (teach the mkdir -p or
install -D step). The rollback section must give a concrete data-restore action
for a bad sync (remove or re-sync HERMES_CONTEXT_DST from a known-good source),
not merely disabling the timer.

CLI and citation register (closed world):
- The tool's own flags are exactly --dry-run and --verify. The strings
  --checksum / --delete / --itemize-changes in the source are rsync's internal
  invocation flags, not user-facing tool flags; do not teach them.
- Refusal A-number register (cite only these, only where true): A8 set-but-empty
  env var; A9 source/destination identity, ancestry, or symlink traversal; A10
  degenerate paths; A14 log-path conflict; A14c staging overlap; A22 destination
  is a symlink; A23 production default paths. If a refusal's citation is not in
  this register, describe the refusal condition without a citation.
- Known-good source means the configured HERMES_CONTEXT_SRC: after removing a
  bad HERMES_CONTEXT_DST, re-syncing from it is the documented restore.

Example rule: illustrative example paths for the OPERATOR's own files (e.g. a
source directory under the home directory) are allowed when clearly marked as
examples. Claims about the TOOL are still closed-world: no env var, flag,
default, or behavior beyond this facts block may be asserted as the tool's.

MUST_KEEP: documents HERMES_CONTEXT_SRC and HERMES_CONTEXT_DST exactly
MUST_KEEP: includes a --dry-run test the operator can run before installing
MUST_KEEP: states the documented rollback for a bad sync
