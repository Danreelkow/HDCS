# hermes-context sync

One-way mirror of the canonical source tree into the workspace:
`/opt/data/workspace/hermes-context/` -> `/workspace/hermes-context/`

The source path is **parameterized**: the script reads the required, namespaced
env var `HERMES_CONTEXT_SRC` (never a bare `SRC`/`DST` name). It exits nonzero
if the variable is unset. The systemd unit supplies it via `Environment=`.

## must_keep

1. Source path: `/opt/data/workspace/hermes-context/` (canonical, never written to).
2. Dry-run zero-writes: `--dry-run` performs no writes at all, including no log
   file creation; DST is byte-identical before and after.
3. User-level systemd, no root: install as user units via
   `systemctl --user`; the script and units require no root privileges.

## Files

- `sync-hermes-context.sh` — the sync entrypoint. Install to `~/.local/bin/`
  (outside the mirrored tree, so sync never deletes its own entrypoint).
- `hermes-context.service` — user unit; `ExecStart=%h/.local/bin/sync-hermes-context.sh`,
  with `Environment=HERMES_CONTEXT_SRC=/opt/data/workspace/hermes-context/`.
- `hermes-context.timer` — user unit; runs every 6 hours (`OnCalendar=*-*-* 0/6:00:00`,
  `Persistent=true`).

## Install

