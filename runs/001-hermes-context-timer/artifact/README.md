# hermes-context sync

One-way mirror of `/opt/data/workspace/hermes-context/` (SRC) into
`/workspace/hermes-context/` (DST). Never write to DST by any other
means — the syncer is the only permitted DST writer.

## Semantics

- **Exact mirror** (recursive, all depths): after a real run, DST
  end state is byte-identical to SRC end state.
- **Stale files deleted**: files and directories present in DST but
  absent in SRC are removed, at any depth.
- **No nesting**: SRC *contents* are mirrored into DST; SRC itself is
  never nested under DST.
- **rsync-first**: if `rsync` is available, `rsync -a --delete` with
  trailing slashes is used. Otherwise a pure-shell fallback (`cp -a`
  plus find-based reconciliation) converges to the same byte-identical
  result.
- **Idempotent**: re-running with unchanged SRC produces no spurious
  changes in DST.
- **Logging**: each real run appends exactly one summary line to
  `~/.cache/hermes-context/sync.log`. The log path is never inside DST,
  and the entrypoint script is never placed inside DST.

## Dry run

`sync-hermes-context.sh --dry-run` enumerates the actions it would
take (copies, deletions) to stdout only. It performs **zero writes**:
no log directory is created, no log is appended, and DST is left
byte-identical (mtime and content untouched).

## Install (user session, no root)

