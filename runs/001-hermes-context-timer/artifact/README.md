# hermes-context freshness sync

One-way freshness mirror of the hermes context from the host into the workspace
(direction is host -> workspace, never the reverse).

## Paths and environment

- `HERMES_CONTEXT_SRC` — source tree. Default: `/opt/data/workspace/hermes-context/`
- `HERMES_CONTEXT_DST` — destination tree. Default: `/workspace/hermes-context/`
- `HERMES_CONTEXT_LOG_DIR` — log directory (always OUTSIDE the DST tree). Default: `$HOME/.cache/hermes-context`

All three are namespaced env overrides. An explicitly **empty** value (`VAR=""`)
is refused with an A18 refusal — it never silently falls back to the default.
Trailing slashes on env values are canonicalized once at startup; all internal
mutations use the canonical paths.

Trailing-slash and default forms both work; the sync contents of SRC land
directly in DST (no extra nesting level).

## Usage

