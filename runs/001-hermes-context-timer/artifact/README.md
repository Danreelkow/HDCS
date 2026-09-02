# hermes-context sync

One-way (A2) host -> workspace mirror of the hermes context. The destination is
brought to an exact recursive mirror of the source (contents + structure +
symlinks; not metadata/timestamps/hardlinks — A9 class). No writeback ever
happens from workspace to host.

## Install

