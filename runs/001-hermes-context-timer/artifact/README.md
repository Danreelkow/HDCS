# hermes-context sync

One-way mirror (host -> workspace) of the hermes context: exact replica,
stale subtrees deleted, never bidirectional (A2/A9).

## Install

    cp sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh
    chmod +x ~/.local/bin/sync-hermes-context.sh
    mkdir -p ~/.config/systemd/user
    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

Standalone execution (no root required, A3):

    ~/.local/bin/sync-hermes-context.sh

Check the timer:

    systemctl --user list-timers hermes-context.timer

## Env override (A17)

All paths are env-parameterized; deployed defaults are the production values.

| Variable | Default |
|---|---|
| `SRC_DIR` | `/opt/data/workspace/hermes-context/` |
| `DST_DIR` | `/workspace/hermes-context` |
| `LOG_DIR` | `~/.cache/hermes-context` |

Example:

    SRC_DIR=/other/src DST_DIR=/other/dst ~/.local/bin/sync-hermes-context.sh

## Dry-run example

    ~/.local/bin/sync-hermes-context.sh --dry-run

Prints would-create / would-update / would-delete, performs zero writes,
and never creates DST even if absent (A6/A16). No log lines are appended
in dry-run mode.

## Verify

    ~/.local/bin/sync-hermes-context.sh --verify

Recursively compares DST against SRC (file contents, directory structure,
symlink presence + targets, stale files). Exit 0 on mirror; nonzero with
the mismatched paths listed otherwise.

## Logs

Real runs append a timestamped summary to:

    ~/.cache/hermes-context/sync.log

LOG_DIR always lives outside DST (A14/A15); dry-run writes nothing.

## Refusals (A19 closed list)

- Root execution → refused (A12).
- DST same as / inside SRC (or vice versa) → refused (A18).
- SRC missing or not a directory; LOG_DIR or entrypoint inside DST → refused (A14/A15).

All refusal paths write nothing.

## Sync strategy

Primary: `rsync -a --delete SRC/ DST/`. Fallback (no rsync): stage via
`mktemp -d` under LOG_DIR, `cp -a` SRC into it, content-verify the stage
against SRC (A13), then swap into DST after deleting stale content — the
end state converges identically to the rsync branch (A5), recursively,
symlinks preserved.
