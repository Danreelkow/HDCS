# sync-hermes-context

One-way sync of the hermes context tree from the host mount into the workspace.
Source of truth is the host mount; the workspace copy is a mirror — stale entries
are deleted at any depth on every run.

## Paths (contract, env-overridable)

- Source: `HERMES_CONTEXT_SRC` (default `/opt/data/workspace/hermes-context/`)
- Destination: `HERMES_CONTEXT_DST` (default `/workspace/hermes-context/`)

Env override is the mandated parameterization mechanism; deployed defaults are
production values. Sync is strictly one-way (host -> workspace); nothing is ever
written back to the source.

## Install

1. Copy the script outside the mirrored tree:

   ```
   install -m 0755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh
   ```

2. Copy the user units:

   ```
   mkdir -p ~/.config/systemd/user
   cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now hermes-context.timer
   ```

The service runs `%h/.local/bin/sync-hermes-context.sh` as a oneshot unit; the
timer fires every 6 hours (`OnCalendar=*-*-* 00/6:00:00`, `Persistent=true`).
Check status with `systemctl --user status hermes-context.timer` and
`journalctl --user -u hermes-context.service`.

The script also runs standalone (cron, manual) with no systemd dependency.

## Dry-run test

