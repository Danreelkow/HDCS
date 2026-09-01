# hermes-context sync

Mirrors the host-mounted context tree into the workspace: contents, recursive
directory structure, and symlinks (MIRROR class). Metadata such as timestamps
and hardlinks is explicitly out of scope. Stale entries in the destination are
deleted at every depth, so the destination always converges to an exact
recursive mirror of the source.

## Install

1. Copy the script outside the mirrored tree (A8):

       install -m 0755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh

2. Copy the user units:

       install -m 0644 hermes-context.service hermes-context.timer ~/.config/systemd/user/

3. Enable:

       systemctl --user daemon-reload
       systemctl --user enable --now hermes-context.timer

The service runs `ExecStart=%h/.local/bin/sync-hermes-context.sh` (oneshot,
user-level, no root). The timer fires every 6 hours
(`OnCalendar=*-*-* 00/6:00:00`, `Persistent=true`).

The script is standalone: it runs fine from cron or by hand without systemd.

## Paths and overrides (A17)

Defaults: SRC `/opt/data/workspace/hermes-context/`, DST
`/workspace/hermes-context/`. Override via environment — this is the mandated
contract mechanism:

    HERMES_CONTEXT_SRC=/path/to/src HERMES_CONTEXT_DST=/path/to/dst \
      ~/.local/bin/sync-hermes-context.sh

## Dry-run test (A6/A16)

    HERMES_CONTEXT_SRC=... HERMES_CONTEXT_DST=... \
      ~/.local/bin/sync-hermes-context.sh --dry-run

Prints the plan to stdout only: no files or directories are created anywhere,
nothing is logged, and a nonexistent DST stays nonexistent. Check afterwards
that DST is untouched (byte-identical) or still absent.

`--verify` compares an existing DST against SRC and exits nonzero on any
mismatch (it fails if DST does not exist).

## Sync strategy

- Primary: `rsync -a --delete` of the source contents into a script-owned
  staging directory.
- Fallback (no rsync): tar-pipe copy plus a prunelist reconciliation that
  deletes stale entries recursively at all depths.
- BOTH paths converge identically: the staged copy is content-verified against
  SRC (files, directories, symlink targets — recursive) BEFORE the destination
  is touched; only a verified copy replaces DST (`rm -rf DST`, then move the
  staged tree). A verification failure exits nonzero and leaves DST untouched.
- Guards run before any write and refuse (nonzero, citing the law number):
  degenerate paths (A18), SRC==DST or ancestor/descendant relationships
  resolved via realpath (A12), and owned paths (log dir, staging, entrypoint
  dir) colliding with SRC/DST boundaries (A14/A15). A DST symlink resolving
  outside SRC is accepted and replaced by the real tree (A18); a DST resolving
  into SRC is refused (A12).

Logs are appended to `~/.cache/hermes-context/sync.log` on real runs only and
never live inside the mirrored tree (A8).

## KNOWN_LIMITATIONS

- Exotic filenames (newlines/control characters) are not guaranteed to round-
  trip through the verification walk (A21); rsync itself copies them fine.
- Adversarial environment-variable combinations beyond the A14 guard (e.g.
  pointing auxiliary tool env vars at protected paths) are out of scope.
