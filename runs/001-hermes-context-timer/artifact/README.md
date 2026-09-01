# hermes-context sync

One-way mirror of the hermes-context register from the host mount into the
workspace. The source path is /opt/data/workspace/hermes-context/ and is
treated as read-only w.r.t. sync; nothing ever writes back to the host mount.

The destination default is /workspace/hermes-context/. The sync is an exact
recursive mirror: contents, directory structure, and symlinks are mirrored;
stale entries and stale subtrees are deleted at any depth so the destination
end state always equals the source end state. Metadata such as timestamps and
hardlinks is deliberately not compared or preserved (see KNOWN_LIMITATIONS).

## Install (user-level only, no root)

