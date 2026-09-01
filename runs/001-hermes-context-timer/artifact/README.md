# hermes-context sync

One-way mirror of the hermes-context tree from the host mount into the
workspace. Source defaults to `/opt/data/workspace/hermes-context/`,
destination to `/workspace/hermes-context/`.

Mirror class: file contents + recursive directory structure + symlinks.
File metadata (timestamps, ownership, hardlinks) is NOT mirrored. The
destination end state always equals the source end state: stale entries
are deleted recursively at every depth, and file<->dir / symlink type
changes are reconciled.

## Install

