Task: hermes-context freshness timer

Keep /workspace/hermes-context/ fresh from its canonical host-mount source. The workspace
needs a standing sync so local analysis always reads current Hermes context.

Deliverable (all files in one artifact dir):
- sync-hermes-context.sh — rsync-based sync; source path from HERMES_CONTEXT_SRC env var
  with a sensible default at the top of the script; destination likewise via
  HERMES_CONTEXT_DST (default /workspace/hermes-context); must support --dry-run (no
  writes); must be idempotent; must log a one-line summary per run
- hermes-context.service + hermes-context.timer — systemd USER units (no root), timer
  runs every 6 hours
- README.md — how to install, how to change the source, how to test with --dry-run

MUST_KEEP: source path is /opt/data/workspace/hermes-context/
MUST_KEEP: dry-run mode that performs no writes
MUST_KEEP: systemd user units, no root required
