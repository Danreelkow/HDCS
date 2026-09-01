# hermes-context sync

One-way exact mirror of the hermes context directory into the workspace,
suitable for standalone runs or a systemd **user** timer (no root).

- `SRC` = `$HERMES_CONTEXT_SRC` (default `/opt/data/workspace/hermes-context/`)
- `DST` = `$HERMES_CONTEXT_DST` (default `/workspace/hermes-context/`)
- `LOG` = `$HERMES_CONTEXT_LOG` (default `~/.cache/hermes-context/sync.log`)

## Semantics

- **One-way** (`A2`): data flows SRC → DST only. Nothing is ever written back
  to the host mount.
- **Contents** (`A4`): the *contents* of SRC are synced into DST (trailing-slash
  rsync semantics). SRC is never nested inside DST.
- **Exact mirror / stale deletion** (`A5`, `A7`): DST ends up identical to SRC.
  Files and **entire stale subtrees at every depth** are deleted on each run.
  There is no accumulate-only mode — anything in DST that is not in SRC is
  removed. **Do not keep anything in DST that you also do not keep in SRC.**
- **Dry-run purity** (`A6`): `--dry-run` performs ZERO writes anywhere — no DST
  changes and **no log writes**. DST is byte-identical after a dry-run.
- **Equivalence class** (`A9`): mirror equality = file contents (`cmp`),
  recursive directory structure, and symlink targets. Timestamps, permissions
  metadata, hardlinks, and xattrs are deliberately excluded.

## Usage (standalone)

    ~/.local/bin/sync-hermes-context.sh              # real run
    ~/.local/bin/sync-hermes-context.sh --dry-run    # zero-write preview

Environment overrides:

    HERMES_CONTEXT_SRC=/path/src HERMES_CONTEXT_DST=/path/dst \
        ~/.local/bin/sync-hermes-context.sh

The script uses `rsync -a --delete` when available; otherwise a fallback
(`rm` stale + `cp -a` / tar-pipe reconcile) converges DST to SRC with
identical mirror semantics, including recursive stale-subtree removal.

## Install (systemd user units)

    install -m 0755 sync-hermes-context.sh ~/.local/bin/
    mkdir -p ~/.config/systemd/user/
    install -m 0644 hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

The timer fires every 6 hours (`OnCalendar=*-*-* 0/6:00:00`, `Persistent=true`)
and runs the script via `hermes-context.service` (`Type=oneshot`, user-level,
`WantedBy=default.target`). No root required.

## Placement guarantees (`A8`)

- The LOG lives at `~/.cache/hermes-context/sync.log` — **outside** DST. The
  script validates LOG placement **before** any sync or deletion occurs, so a
  misconfigured LOG inside DST is refused (exit 5) and can never be deleted.
- Entrypoints (the script, unit files) live in `~/.local/bin` /
  `~/.config/systemd/user/` — **outside** the mirrored tree. The sync never
  deletes its own entrypoints.

## Exit codes

| code | meaning                                            |
|------|----------------------------------------------------|
| 0    | success (verify passed)                            |
| 2    | bad usage                                          |
| 3    | SRC missing / not a directory                      |
| 4    | nesting violation (DST inside SRC or vice versa)   |
| 5    | LOG configured inside DST (checked pre-sync)       |
| 6    | self-verify mismatch (never warn-exit-0)           |
| 7    | sync step failure (rsync/fallback error)           |

Verify mismatch always prints a report (diff of structure / contents /
symlink targets) and exits nonzero.

## Logging

Each non-dry-run run appends **exactly one** line to LOG — including runs that
fail the sync step (`result=SYNC_FAIL`, exit 7) or self-verify
(`result=VERIFY_FAIL`, exit 6). Only pre-flight refusals (bad usage, missing
SRC, nesting violation, LOG-inside-DST) exit before the logging block and
therefore write no line:

    2026-09-01T12:00:00+0000 mode=rsync dry_run=0 result=OK

Dry-run appends zero lines.

## KNOWN_LIMITATIONS

Recorded per `A10`, non-blocking:

- **Newline-in-filename corpora**: exotic/adversarial; the verify list-based
  comparison and fallback copy may misbehave on filenames containing newlines.
  Repro noted; not exercised in normal operation.
- **DST pointed at the LOG directory**: refused pre-sync with exit 5, so the
  log is never deleted. Other degenerate DST choices (e.g. DST = `/`) are not
  guarded — user is expected to supply a sane DST.
