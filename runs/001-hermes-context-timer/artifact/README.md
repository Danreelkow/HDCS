# hermes-context sync

Mirrors the contents of `/opt/data/workspace/hermes-context/` (read-only host
mount) into `/workspace/hermes-context/` (user workspace). Stale files and
subtrees in the destination are deleted at every depth so DST always equals
SRC (contents + recursive structure + symlinks, including dangling symlinks;
metadata/timestamps are not compared).

## Standalone use

    ~/.local/bin/sync-hermes-context.sh

Override paths via environment or flags:

    HERMES_CONTEXT_SRC=/path/src HERMES_CONTEXT_DST=/path/dst \
      ~/.local/bin/sync-hermes-context.sh
    ~/.local/bin/sync-hermes-context.sh --src=/path/src --dst=/path/dst

## Dry-run

    ~/.local/bin/sync-hermes-context.sh --dry-run

Prints planned actions only. Performs ZERO writes of any kind — no staging
directory, no log entry, no change to the destination.

## Install entrypoint

    install -m 0755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh

## Enable the timer (systemd user units)

    mkdir -p ~/.config/systemd/user
    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

The timer fires every 6 hours (`OnCalendar=*-*-* 00/6:00:00`, `Persistent=true`)
and runs `%h/.local/bin/sync-hermes-context.sh` (Type=oneshot).

## Log

Sync activity is appended to `~/.cache/hermes-context/sync.log` (outside the
mirrored tree). Logging is skipped entirely in dry-run mode.

## Safety

- Source and destination identity/ancestor/symlink-into-source conflicts are
  refused before any destructive operation.
- The destination is never touched until a staged copy has been verified
  against the source (content compare); verification failure exits nonzero.
- The script refuses to run if the destination boundary-contains its own
  concrete owned paths (log parent, entrypoint dir) or if the staging base
  (TMPDIR included) resolves inside SRC or DST — refused before any staging
  directory is created, so the refusal performs zero writes.

## KNOWN_LIMITATIONS

- Filenames containing newline characters are outside the verified corpus;
  behavior with such names is unspecified.
- Exotic environment combinations beyond the concrete-path guard (e.g.
  unusual TMPDIR layouts, symlinked cache/entrypoint parents resolving in
  unexpected places) are not exhaustively guarded; such combos are recorded
  here as known limitations and are non-blocking.
