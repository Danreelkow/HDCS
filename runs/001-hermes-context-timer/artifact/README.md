# hermes-context sync

## Purpose

Keeps the hermes context directory in the workspace (`/workspace/hermes-context/`)
in sync with the read-only host mount (`/opt/data/workspace/hermes-context/`).
Sync is **one-way**: host → workspace. The source is never written to.

## Defaults and overrides

- Source: `/opt/data/workspace/hermes-context/` (override: `HERMES_CONTEXT_SRC`)
- Destination: `/workspace/hermes-context/` (override: `HERMES_CONTEXT_DST`)
- Log file: `/tmp/hermes-context-sync.log` (override: `HERMES_CONTEXT_LOG`)

Tool selection: `rsync` if available, otherwise `cp -a`, otherwise a `tar` pipe.
Fallbacks never delete files (the script, units, and README live inside the
destination and are protected).

## Dry-run

Preview changes without writing anything:

    /workspace/hermes-context/sync-hermes-context.sh --dry-run

## Standalone usage

Run a real sync once:

    /workspace/hermes-context/sync-hermes-context.sh

Each run prints exactly one summary line:
`mode=<sync|dry-run> tool=<rsync|cp|tar> dir=host->workspace transferred=N skipped=M status=<ok|error>`

## Install as systemd user units (no root required)

    cp /workspace/hermes-context/hermes-context.service /workspace/hermes-context/hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

The timer fires every 6 hours (`OnCalendar=*-*-* 00/6:00:00`) and is
`Persistent=true`, so a missed run (e.g. machine off) runs at next boot.
