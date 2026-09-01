# hermes-context sync

One-way mirror of the hermes context from host to workspace (A7): exact
replica, stale subtrees deleted, never bidirectional.

## Install

    cp sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh
    chmod +x ~/.local/bin/sync-hermes-context.sh
    mkdir -p ~/.config/systemd/user
    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

The script refuses to run if its own directory (`%h/.local/bin`, i.e. the
entrypoint directory) lies inside the destination — placement guard A14/A15.

## Dry-run test

    ~/.local/bin/sync-hermes-context.sh --dry-run

Prints the plan only; performs zero writes, including logs, and never
creates the destination (A6/A16).

## Source-change procedure

1. Edit the context under the source directory.
2. Run the script with `--dry-run` and inspect the plan.
3. Run it live; verify with `diff -r` if desired.
4. Check the log at `${XDG_CACHE_HOME:-$HOME/.cache}/hermes-sync/hermes-sync.log`.

## Sync strategy

One-way host -> workspace. The destination end state always equals the
source end state (A5): file contents, directory structure, and symlinks,
recursively. Stale subtrees deleted on the destination — `rsync --delete`
semantics, with a `cp -a` fallback that reconciles identically (A4).
Metadata, timestamps, and hardlinks are excluded from verification (A9).
Never configure bidirectional syncing.

## Env override

| Variable | Default | Notes |
|---|---|---|
| `HERMES_CONTEXT_SRC` | `/opt/data/workspace/hermes-context/` | required contract; deployed default when unset (A17) |
| `HERMES_CONTEXT_DST` | `/workspace/hermes-context/` | required contract; deployed default when unset (A17) |
| `TMPDIR` | `/tmp` | staging area location (A20); stage refused if it lands inside DST (A14/A15) |
| `XDG_CACHE_HOME` | `$HOME/.cache` | log parent; refused if inside DST (A14/A15) |

## KNOWN_LIMITATIONS

- Exotic environment combinations (e.g. relative `TMPDIR`, unwritable
  cache parent) fall back to a non-fatal degraded log write or refusal;
  residual adversarial cases are logged here rather than as gate FAILs
  (A10).
- Hardlink structure and file metadata/timestamps are not mirrored (A9).
- If neither `rsync` nor a writable stage location exists, the run fails
  before touching DST (A11/A13).
- A `DST` path whose *parent* chain contains symlinks is compared via
  `realpath -m`; only the final DST component symlink is guaranteed to be
  replaced in place (A18).
