# hermes-context sync

Mirrors the hermes context tree from SRC to DST so that the DST end state
always equals the SRC end state, recursively (A5). Runs standalone or under
a systemd --user timer (no root anywhere).

## Paths and env override contract (A17)

Defaults (deployed paths):
- SRC = `/opt/data/workspace/hermes-context/`
- DST = `/workspace/hermes-context/`

Override at invocation (gate contract):
- `HERMES_CONTEXT_SRC` — required override for the source
- `HERMES_CONTEXT_DST` — required override for the destination

When set, these env vars are the authoritative paths; otherwise the defaults
above are used.

## Usage

    ~/.local/bin/sync-hermes-context.sh            # real sync
    ~/.local/bin/sync-hermes-context.sh --dry-run  # dry-run

## dry-run semantics (A6)

`--dry-run` prints the plan (what would be transferred/deleted) to stdout and
performs zero write operations: no files created or modified, no log entry
written, and if DST does not exist it still does not exist after the run.

## Real-run ordering (A13)

1. **stage** — content is staged into a temp directory on the DST filesystem
   (`rsync -a --delete`, with a `cp -a` fallback).
2. **verify** — recursive content comparison of stage vs SRC (structure,
   file contents, and symlink targets). On any mismatch the script exits
   nonzero, the stage is discarded, and DST is untouched.
3. **touch DST** — only after verify passes, DST contents are replaced so the
   end state matches SRC (including deletions and file<->dir type swaps).

## Guards (A18)

The script refuses, before any write: empty paths, `/`, `.`; unresolvable
SRC; `realpath(SRC) == realpath(DST)`; ancestor/descendant pairs; and a
component boundary not owned by the invoking user. The component boundary of
DST is the deepest **existing** component of the DST path: a DST that does
not yet exist is allowed when its nearest existing ancestor (e.g. an existing
`/workspace/hermes-context`) is owned by the invoking user; if that nearest
existing ancestor is foreign-owned, the run is refused. This fixes the
previous over-strict "DST parent owned" check, which wrongly refused when the
immediate parent (`/workspace`) was root-owned but the component root itself
was user-owned.

## Logs

Real runs log to `~/.cache/hermes-context/sync.log` (outside the mirrored
tree). An alternate log via `HERMES_CTX_LOG` is refused if it points inside
DST.

## Install (systemd --user)

    install -Dm755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh
    mkdir -p ~/.config/systemd/user
    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

The service unit runs `ExecStart=%h/.local/bin/sync-hermes-context.sh`
(oneshot); the timer fires on a 6-hour cadence with `Persistent=true`.
The script is standalone-identical: it runs the same way without systemd.

## KNOWN_LIMITATIONS

- Environment algebra beyond the A14 guard (combinations of
  `HERMES_CONTEXT_SRC`/`HERMES_CONTEXT_DST`/`HERMES_CTX_LOG` beyond the
  guarded cases) is unverified. Open, non-blocking (A10).
