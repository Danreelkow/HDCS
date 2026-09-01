# hermes-context sync

One-way mirror of the host mount `/opt/data/workspace/hermes-context/` into the
workspace at `/workspace/hermes-context/` (contents + recursive directory
structure + symlinks; no metadata/timestamps/hardlinks). Stale entries are
deleted at every depth so DST end state always equals SRC end state.

## Install

