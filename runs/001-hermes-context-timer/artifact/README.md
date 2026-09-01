# hermes-context sync

One-way freshness sync of the hermes context tree: host -> workspace (A2).

## Paths

- Source: `HERMES_CONTEXT_SRC` (default `/opt/data/workspace/hermes-context/`)
- Destination: `HERMES_CONTEXT_DST` (default `/workspace/hermes-context/`)
- Log dir: `HERMES_CONTEXT_LOG_DIR` (default `~/.cache/hermes-context` — always outside DST, A8)

An explicitly **empty** env value is refused (it never falls back to the default).

## Usage

