# hermes-context-freshness

One-way mirror of the hermes context source tree into the workspace copy.
Source (`HERMES_CONTEXT_SRC`, default `/opt/data/workspace/hermes-context/`) is
never written to; destination (`HERMES_CONTEXT_DST`, default
`/workspace/hermes-context/`) is made an exact recursive mirror of the source.

## Install

1. Copy the script outside the mirrored tree:
   ```
   mkdir -p ~/.local/bin
   cp sync-hermes-context.sh ~/.local/bin/
   chmod +x ~/.local/bin/sync-hermes-context.sh
   ```
2. Install the systemd **user** units (no root required):
   ```
   mkdir -p ~/.config/systemd/user
   cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now hermes-context.timer
   ```
3. Alternative to `~/.local/bin`: run the script directly from the artifact
   directory (`/workspace/hdcs/artifacts/hermes-context-freshness/sync-hermes-context.sh`)
   via cron or an installer; the unit's `ExecStart` fallback is that absolute path.

## Source changes

Any change under the source tree is auto-mirrored within 6 hours by the timer.
To sync immediately, run the script manually:
`~/.local/bin/sync-hermes-context.sh`

## Dry-run test

Preview planned changes with zero writes (no files, no staging, no logs):
