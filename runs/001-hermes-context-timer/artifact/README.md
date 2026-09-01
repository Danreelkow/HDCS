# hermes-context sync

One-way host -> workspace mirror of the hermes context tree (A2): contents,
recursive directory structure, and symlinks — no metadata/timestamps/hardlinks
(MIRROR class). Stale entries in the destination are deleted at every depth
(A5/A7).

## Paths

- SRC default: `/opt/data/workspace/hermes-context/`
- DST default: `/workspace/hermes-context/`
- Override via env (A17, mandated contract mechanism):
  - `HERMES_CONTEXT_SRC=/custom/src sync-hermes-context.sh`
  - `HERMES_CONTEXT_DST=/custom/dst sync-hermes-context.sh`

Log file: `~/.cache/hermes-context/sync.log` (always outside DST, A8).

## Install

1. Copy the script outside the mirrored tree:
   `install -m 0755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh`
2. Copy the units:
   `mkdir -p ~/.config/systemd/user`
   `cp hermes-context.service hermes-context.timer ~/.config/systemd/user/`
3. Enable:
   `systemctl --user daemon-reload`
   `systemctl --user enable --now hermes-context.timer`
4. Check: `systemctl --user list-timers hermes-context.timer`

The service runs `ExecStart=%h/.local/bin/sync-hermes-context.sh` as a user
unit (no root). The script also runs standalone under cron without systemd (A3).

## Dry-run test (A6/A16)

`sync-hermes-context.sh --dry-run`

Emits the plan to stdout only: no files or directories are created anywhere,
no log write, DST byte-identical afterwards (a nonexistent DST stays
nonexistent). After dry-run, confirm: `test ! -e "$HERMES_CONTEXT_DST"` if it
did not exist before.

There is also a read-only check of an existing mirror:
`sync-hermes-context.sh --verify` — exits nonzero if DST is absent or differs
from SRC (A9 class).

## Sync strategy

- Primary: `rsync -a --delete SRC/ stage/` — contents of SRC into a
  script-owned staging directory (never nested, never inside DST/SRC).
- Fallback (no rsync): `tar -C SRC -cf - . | tar -C stage -xf -` followed by a
  recursive reconcile that deletes stale entries at all depths (A7).
- BOTH paths converge identically: the staged copy is content-verified
  against SRC (files, dirs, symlink targets, recursive; A9). Only after the
  verified copy exists is DST replaced (A11/A13). Verification failure exits
  nonzero and leaves DST untouched.
- Guards run before any write and refuse (nonzero, citing the A-number):
  degenerate paths (A18), SRC==DST / ancestor / descendant / DST inside SRC by
  realpath (A12), log/stage/entrypoint colliding with SRC or DST boundaries
  (A14/A15). Source survival outranks freshness (A11).
- A DST that is itself a symlink is permitted when its symlink-resolved target
  passes all guards (A12/A14/A15/A18); the sync then REPLACES the symlink with
  a real directory tree. A DST symlink resolving into SRC (directly or via a
  symlinked ancestor) is refused under A12.

## KNOWN_LIMITATIONS

- Exotic filenames (newline/control characters) are out of scope for the
  losslessness guarantee (A21); rsync itself copies them fine.
- Adversarial environment-variable combinations beyond the A14 guard
  (log/stage/entrypoint vs SRC/DST boundary checks) are open.
