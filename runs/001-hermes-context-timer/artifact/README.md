# hermes-context sync

One-way mirror of the hermes context from the host source directory into the
workspace destination (`A2`: host -> workspace only, never a writeback).

## Install

1. Copy the script to `~/.local/bin/sync-hermes-context.sh` and make it
   executable (`chmod +x ~/.local/bin/sync-hermes-context.sh`).
2. Copy `hermes-context.service` and `hermes-context.timer` to
   `~/.config/systemd/user/`.
3. `systemctl --user daemon-reload`
4. `systemctl --user enable --now hermes-context.timer`

The timer fires on `OnCalendar=*-*-* 00/6:00:00` (every 6 hours, `Persistent=true`)
and starts `hermes-context.service`, which runs the sync script as a oneshot
(`ExecStart=%h/.local/bin/sync-hermes-context.sh` — `%h` expands to your home
directory, i.e. the same `~/.local/bin/sync-hermes-context.sh` path above).

## Environment overrides

Both endpoints are parameterized; unset variables fall back to the mandated
production paths, and a set-but-empty value is refused (A23).

