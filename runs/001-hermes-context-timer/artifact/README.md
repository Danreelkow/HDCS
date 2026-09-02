# hermes-context sync

One-way (host -> workspace) mirror of the hermes context directory.
Primary backend is `rsync -a --delete`; when rsync is unavailable the script
falls back to `cp -a` plus a recursive reconcile (deletes stale subtrees,
copies missing/differing entries). Both backends produce the same recursive
mirror end state: contents + directory structure + symlinks (A9-class;
metadata/timestamps/hardlinks are not part of the equivalence class).

## Install

1. Copy `sync-hermes-context.sh` to `%h/.local/bin/sync-hermes-context.sh`
   and make it executable:

       install -m 755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh

2. Copy the units into the systemd user directory:

       mkdir -p ~/.config/systemd/user
       install -m 644 hermes-context.service ~/.config/systemd/user/
       install -m 644 hermes-context.timer  ~/.config/systemd/user/
       systemctl --user daemon-reload
       systemctl --user enable --now hermes-context.timer

The timer runs the service every 6 hours (`OnCalendar=*-*-* 00/6:00:00`,
`Persistent=true`), `WantedBy=default.target`. systemd is optional; the
script is standalone and needs no root.

## Configuration (environment overrides)

Unset variables fall back to the mandated production paths. A variable that
is set but empty is refused (A23).

    # production defaults
    HERMES_CONTEXT_SRC=/opt/data/workspace/hermes-context
    HERMES_CONTEXT_DST=/workspace/hermes-context

    # example override
    HERMES_CONTEXT_SRC=/tmp/hdcs-gate-src \
    HERMES_CONTEXT_DST=/tmp/hdcs-gate-dst \
      ~/.local/bin/sync-hermes-context.sh

Trailing slashes in the values are canonicalized once at startup; all
subsequent mutations go through the canonical paths.

## Test procedure (--dry-run)

    HERMES_CONTEXT_SRC=/path/src HERMES_CONTEXT_DST=/path/dst \
      ~/.local/bin/sync-hermes-context.sh --dry-run

`--dry-run` prints `dry-run: sync=N delete=M` (or an all-create plan when the
destination is absent) and performs zero writes of any kind — no stage
directory, no log line, and an absent destination stays absent.

    ~/.local/bin/sync-hermes-context.sh --verify

`--verify` exits nonzero if the destination is missing or is not an exact
A9-class mirror (symlinks are never dereferenced during verification).

## Sync strategy states

- **rsync primary** (rsync on PATH): `rsync -a --delete` from a verified
  staging directory to the destination; exact recursive mirror, idempotent.
- **cp fallback** (rsync absent): `cp -a` into the stage, prune stage entries
  absent from the source, then reconcile the destination (delete stale, copy
  missing/differing, replace symlinks and file<->dir type changes). Same
  recursive mirror end state.

Every real run: guards -> `mktemp -d` stage -> fill stage -> verify stage
against source -> only then touch the destination -> post-sync verify ->
one log line appended to `~/.cache/hermes-context/sync.log` -> stage removed.

Refusals (exit nonzero, citing the invariant): degenerate paths `/`/`''`/`.`
(A18); source/destination identity or nesting, including symlinked ancestors
resolving into the source (A12); destination is a user-placed symlink — it is
refused and left untouched, never replaced (A22); destination conflicting with
an owned path — instantiated staging directory, log-file parent, entrypoint
directory (A14/A15).

## KNOWN_LIMITATIONS

- A21: filenames containing newlines or other control characters are not
  guaranteed to round-trip through the cp-fallback reconcile path (exotic
  filenames — known limitation, open).
- Adversarial environment combinations beyond the A14/A15 owned-path guard
  are treated as known limitations (open), not normal-operation failures.

