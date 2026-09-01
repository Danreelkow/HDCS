# hermes-context sync

One-way mirror `SRC -> DST` of the hermes context tree. The source is never
modified; the destination is replaced only from a verified staging copy.

## Environment overrides

- `HERMES_CONTEXT_SRC` — source tree, default `/opt/data/workspace/hermes-context/`
- `HERMES_CONTEXT_DST` — destination tree, default `/workspace/hermes-context/`
- `HERMES_CONTEXT_LOG_DIR` — log dir, default `~/.cache/hermes-context/` (refused if it points inside SRC or DST)

## Install

Copy the entrypoint to either location (outside the mirrored tree):

    cp sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh && chmod +x ~/.local/bin/sync-hermes-context.sh

or use it in place at `/workspace/hdcs/bin/sync-hermes-context.sh`. The systemd
user units below expect the `/.local/bin/sync-hermes-context.sh` location; if
you keep the script in `/workspace/hdcs/bin/`, adjust `ExecStart=` accordingly.

Enable the timer (6h cadence, persistent):

    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

The service unit `ExecStart=%h/.local/bin/sync-hermes-context.sh` runs the
script as the normal user; no root directives.

## Standalone fallback (no systemd)

Invoke directly, optionally from cron:

    ~/.local/bin/sync-hermes-context.sh

Every real run appends one log line to `~/.cache/hermes-context/hermes-context.log`.

## Source-change note

Edit files under `HERMES_CONTEXT_SRC` only. The next timer tick (or the next
manual run) mirrors the new state to the destination. Stale subtrees are
deleted at all depths on the destination.

## Dry-run test procedure

    HERMES_CONTEXT_SRC=/tmp/src HERMES_CONTEXT_DST=/tmp/dst \
      ~/.local/bin/sync-hermes-context.sh --dry-run

The dry run prints the plan and performs zero writes anywhere — it never
creates the destination or the log dir.

## Guards

Refused (exit 2, zero writes): `SRC == DST`, either path an ancestor of the
other, the destination being a symlink resolving into the source, or a log
directory pointing inside SRC or DST.
