# hermes-context sync

One-way mirror (`A2`): copies `HERMES_CONTEXT_SRC` into `HERMES_CONTEXT_DST`
(host -> workspace only; never writes back). End state is a recursive mirror of
contents, directory structure, and symlinks (`A5`/`A9` class — metadata,
timestamps, and hardlinks are not preserved).

## Install

1. Script: copy `sync-hermes-context.sh` to `~/.local/bin/sync-hermes-context.sh`
   and `chmod +x ~/.local/bin/sync-hermes-context.sh`.
   (This matches the service unit's `ExecStart=%h/.local/bin/sync-hermes-context.sh`.)
2. Units: copy `hermes-context.service` and `hermes-context.timer` to
   `~/.config/systemd/user/`.
3. Reload and enable:

       systemctl --user daemon-reload
       systemctl --user enable --now hermes-context.timer

The timer runs the service every 6 hours (`OnCalendar=*-*-* 00/6:00:00`,
`Persistent=true` so missed runs are caught up). Both units install with
`WantedBy=default.target`. systemd is optional — the script is a standalone
executable and needs no root.

## Environment override

The script reads namespaced env vars; unset variables fall back to the
mandated production defaults; set-but-empty refuses (`A23`).

    # production defaults:
    #   HERMES_CONTEXT_SRC=/opt/data/workspace/hermes-context
    #   HERMES_CONTEXT_DST=/workspace/hermes-context

    # override example:
    HERMES_CONTEXT_SRC=/home/me/src \
    HERMES_CONTEXT_DST=/home/me/dst \
    ~/.local/bin/sync-hermes-context.sh

Trailing slashes are canonicalized once; all mutations go through canonical
paths.

## Dry-run test procedure

    ~/.local/bin/sync-hermes-context.sh --dry-run

Prints a plan (`rsync -an --delete --itemize-changes`) and a
`dry-run: sync=N delete=M` summary. Zero writes of any kind — no files, no
stage dir, no log line, and an absent DST stays absent (`A6`/`A16`).

## Verify

    ~/.local/bin/sync-hermes-context.sh --verify

Fails (nonzero) when DST is absent or is not an exact mirror; symlink targets
are compared by `lstat`, never dereferenced — a regular file holding a
symlink's target bytes fails verification.

## Sync strategy

- Primary: `rsync -a --delete` (exact recursive mirror).
- Fallback (rsync unavailable): `cp -a` plus a recursive reconcile that
  deletes stale subtrees, copies differing files, converts file<->dir type
  changes, and converges symlink targets. Both paths produce the same end
  state: DST ≡ SRC recursively.

Refusals cite A-numbers only: `A12` (SRC/DST identity, ancestor/descendant,
realpath-based), `A14`/`A15` (collision with owned concrete paths: the
instantiated stage dir, the log file's parent `~/.cache/hermes-context`, the
entrypoint dir `~/.local/bin`), `A18` (degenerate paths `/`, ``, `.`),
`A22` (DST itself is a symlink — refused, never replaced), `A23`
(set-but-empty env override).

Each successful real run appends one line to
`~/.cache/hermes-context/sync.log`; the log and the entrypoint live outside
DST and are never touched by sync (`A8`).

## KNOWN_LIMITATIONS

- Exotic filenames (newlines/control characters) — not handled (+open, `A21`).
- Adversarial environment combinations beyond the `A14` owned-path guard —
  treated as open, not FAIL (`A10`/`A14`).
