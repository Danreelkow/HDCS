# hermes-context sync

One-way sync of `/opt/data/workspace/hermes-context/` → `/workspace/hermes-context/`.

## Files

- `sync-hermes-context.sh` — POSIX sh sync script (rsync primary, `cp -a` fallback)
- `hermes-context.service` — user systemd oneshot unit
- `hermes-context.timer` — user systemd timer, every 6 hours

## Install (user-level systemd)

