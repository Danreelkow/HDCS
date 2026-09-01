# hermes-context sync

One-way recursive exact mirror: source `/opt/data/workspace/hermes-context/` → destination `/workspace/hermes-context/`. Both paths are env-overridable via `HERMES_CONTEXT_SRC` and `HERMES_CONTEXT_DST`. Writes go only to the destination (A2); source is read-only.

## Install

