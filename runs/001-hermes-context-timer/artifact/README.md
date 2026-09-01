# hermes-context sync

Mirrors the hermes context source tree into the destination directory.

## Paths

- Script: `sync-hermes-context.sh` (install to `~/.local/bin/sync-hermes-context.sh`)
- Source (read-only, never written): `/opt/data/workspace/hermes-context/`
- Destination: `/workspace/hermes-context/`
- Log: `${HERMES_CONTEXT_DST}/.sync-hermes-context.log` if set, else `~/.cache/hermes-context-sync.log`

## Environment variables

- `HERMES_CONTEXT_SRC` — source directory (default `/opt/data/workspace/hermes-context/`)
- `HERMES_CONTEXT_DST` — destination directory (default `/workspace/hermes-context/`)
- `HERMES_CONTEXT_LOG` — log file path (overridable; default `~/.cache/hermes-context-sync.log`)

## Behavior

- **Primary mode**: `rsync -a --delete "${SRC}/" "${DST}/"` — src contents map directly into dst with no nesting.
- **Fallback mode** (rsync absent): tar-pipe (or `cp -a`) copy, then find-based recursive deletion of dst entries absent from src, at every depth. Converges byte-identically.
- **Dry-run purity**: `sync-hermes-context.sh --dry-run` performs zero writes — no DST changes, no log lines. It only computes and compares (rsync `--dry-run`, or compute-and-compare in fallback).
- **Logging**: exactly one summary line (timestamp, mode, status) per real run. Dry-runs append nothing.
- **Standalone**: exits 0 on success without systemd.

## Install (user units, no root)

