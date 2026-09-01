# hermes-context freshness sync

One-way exact mirror of the hermes context directory from the host mount into
the workspace. The source path is /opt/data/workspace/hermes-context/ and the
destination is /workspace/hermes-context/. Both are overridable via the
environment variables `HERMES_CONTEXT_SRC` and `HERMES_CONTEXT_DST`.

## What it does

- Exact mirror: file contents, directory structure (recursive), and symlinks
  (by target) are replicated. Stale files and subtrees in DST are deleted at
  any depth. Metadata, timestamps, and hardlink identity are NOT part of the
  mirror class and are not guaranteed.
- Order law: every real run first stages SRC into a temp directory outside
  DST, verifies the stage, and only then reconciles DST. If verification
  fails, DST is left byte-identical and the script exits nonzero.
- Primary path: `rsync -a --delete SRC/ STAGE/` for staging (trailing slash —
  contents of SRC land in the stage, never nested), then the verified stage
  is copied into DST with stale entries deleted at all depths.
- Fallback path (rsync absent): `cp -a SRC/. STAGE/` (or tar-pipe), verify
  the stage against SRC, then full reconcile of DST (stale subtrees deleted
  at all depths).
- Verify step: recursive content-compare (`diff -r`) plus explicit symlink
  target comparison. A copy is called "verified" only after this
  content-comparison passes. A verify failure exits nonzero and leaves DST
  untouched — never warn-and-exit-0.
- Guards: before any write, SRC and DST are resolved with `realpath(1)`.
  The run is rejected (exit 2, no writes) if they are equal, if either is an
  ancestor of the other, or if DST resolves inside SRC. The script never
  deletes its own entrypoints and never writes its log inside DST.

## Dry-run

There is a dry-run mode that performs no writes: pass `--dry-run`. Planned
actions are printed to stdout only; no log file is created or modified and
DST stays byte-identical.

## Usage

    # preview (zero writes)
    ~/.local/bin/sync-hermes-context.sh --dry-run

    # real run
    ~/.local/bin/sync-hermes-context.sh

    # overrides
    HERMES_CONTEXT_SRC=/path/src HERMES_CONTEXT_DST=/path/dst \
      ~/.local/bin/sync-hermes-context.sh

## Install (systemd user units, no root required)

    mkdir -p ~/.local/bin ~/.config/systemd/user
    cp sync-hermes-context.sh ~/.local/bin/
    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

The service unit runs `ExecStart=%h/.local/bin/sync-hermes-context.sh` as a
oneshot; the timer fires every 6 hours (`OnCalendar=*-*-* 00/6:00:00`,
`Persistent=true`). The script is standalone-capable and runs fine without
systemd.

## Logging

One line per real run (timestamp, mode, status) is appended to
`~/.cache/hermes-context/sync.log`. Dry-run never logs. The log path is
never under DST.

## KNOWN_LIMITATIONS

- Newline-in-filename corpora: the fallback verify/diff path can mis-report
  on filenames containing newlines (diff -r listing edge). Repro notes only.
- Hostile environment combos where DST resolves through a symlink into the
  log directory (or similar symlink/log-dir interactions) are not fully
  enumerated; repro notes only. The realpath guard covers direct
  ancestor/descendant/identity cases.
- Mirror class excludes metadata/timestamps/hardlinks by design.
