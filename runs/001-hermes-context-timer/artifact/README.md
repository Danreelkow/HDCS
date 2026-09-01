# hermes-context sync

One-way mirror of the hermes context from the host into the workspace (A2/A9):
the destination end state always converges to the source end state — contents,
directory structure, and symlinks — with stale destination files deleted.

## Files

- `~/.local/bin/sync-hermes-context.sh` — the sync script (standalone exec or systemd user unit, A3)
- `~/.config/systemd/user/hermes-context.service` — oneshot service unit
- `~/.config/systemd/user/hermes-context.timer` — 6h timer

## Standalone usage

    ~/.local/bin/sync-hermes-context.sh            # real run (rsync --delete, cp/tar fallback)
    ~/.local/bin/sync-hermes-context.sh --dry-run  # read-only diff report, zero writes (A6/A16)
    ~/.local/bin/sync-hermes-context.sh --verify   # recursive SRC vs DST comparison; nonzero on mismatch

## systemd user units (A3, no root)

    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer
    systemctl --user list-timers hermes-context.timer

The service runs `%h/.local/bin/sync-hermes-context.sh` (Type=oneshot).

## Environment overrides (A17)

All paths are env-parameterized; the deployed values below are the production defaults:

- `SRC_DIR` (or `HERMES_CONTEXT_SRC`) — default `/opt/data/workspace/hermes-context/`
- `DST_DIR` (or `HERMES_CONTEXT_DST`) — default `/workspace/hermes-context`
- `LOG_DIR` (or `HERMES_CTX_LOG`) — default `~/.cache/hermes-context/`

All paths are canonicalized with `realpath` before guards run, so symlinked
ancestors cannot spoof a source/destination relationship. Guards run before
any write; on refusal nothing is created or modified.

## Staging (A13)

Every real run (rsync primary and cp/tar fallback alike) first copies SRC into
a staging tree, content-verifies the staging against SRC, and only then
mutates DST. A failed staging verification leaves DST untouched.

## Dry-run example

    ~/.local/bin/sync-hermes-context.sh --dry-run
    # prints would-create / would-update / would-delete; never creates or touches DST (A6/A16)

## Logging

Real runs append a timestamped summary to `~/.cache/hermes-context/sync.log`
(override with `LOG_DIR` or `HERMES_CTX_LOG`). Dry-run mode writes no log
lines. A log directory that resolves inside DST is refused (A8) with a
nonzero exit and zero writes.

## Refusals (A19/A20 — closed list, zero writes on refusal path)

- Running as root → refused, cites A12
- Missing/non-directory source → refused, cites A14/A15
- Destination equal to or inside source (realpath-resolved) → refused, cites A18
- Log directory resolving inside DST → refused, cites A8
