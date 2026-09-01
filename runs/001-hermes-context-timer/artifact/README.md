# hermes-context mirror

Standing user-level one-way mirror: `SRC` → `DST`, every 6 hours.

- `SRC` (default `/opt/data/workspace/hermes-context/`) is read-only source; never written.
- `DST` (default `/workspace/hermes-context/`) is exact mirror: contents + structure + symlinks, recursive. Metadata/timestamps/hardlinks are not preserved.
- Stale files/subtrees in `DST` are deleted at any depth (true mirror, no accumulate-only behavior). An empty source yields an empty `DST`.
- Post-sync self-verification: any mismatch → nonzero exit with diff report (never warn-and-exit-0).
- Portable: works with BusyBox `find`/`ls` (no GNU `-printf` dependency).

## Install (systemd user units)

