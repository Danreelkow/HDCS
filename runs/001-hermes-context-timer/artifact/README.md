# hermes-context-sync

One-way mirror of the hermes context directory into the workspace:

- **SRC** (read-only, never written to): `/opt/data/workspace/hermes-context/`
- **DST** (written, mirrored exactly): `/workspace/hermes-context/`

The end state of DST always matches SRC, including deletions (mirror semantics).

## Configuration

Override via environment variables:

- `HERMES_CONTEXT_SRC` — source directory (default `/opt/data/workspace/hermes-context/`)
- `HERMES_CONTEXT_DST` — destination directory (default `/workspace/hermes-context/`)
- `HERMES_CONTEXT_LOG` — optional log file path (default empty = no logging)

## Usage

Standalone (no systemd, no rsync required):

    ./sync-hermes-context.sh

### Flags

- `--dry-run` — print the planned sync (itemized plan or rsync dry-run output) to
  stdout **only**. Zero writes to DST and zero writes to the log, even if
  `HERMES_CONTEXT_LOG` points inside DST. Never creates DST or the log file.
- `--log FILE` — override the log path for this invocation (real runs only).

## Sync strategy

1. **Primary**: `rsync -a --delete SRC/ DST/` (used when `rsync` is on PATH).
2. **Fallback**: if `rsync` is unavailable:
   - `mkdir -p DST`
   - `cp -a SRC/. DST/`
   - reconciliation pass: delete any top-level entry in DST absent from SRC.

Both paths produce an identical end state (verified: same
`find "$DST" -printf '%P %y\n' | sort` output when GNU find is available; the
script itself avoids GNU extensions and works with BusyBox find/coreutils).

## Logging

A single line (timestamp, mode, src, dst) is appended to the log file on real
runs only, and only if a log path is configured. Dry runs never touch the log.

## systemd user units

Install the script (then make executable):

    install -m 0755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh

(Or edit `hermes-context.service` to use an absolute path to the script.)

Copy `hermes-context.service` and `hermes-context.timer` to
`~/.config/systemd/user/`, then:

    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

The timer runs every 6 hours (`OnCalendar=*-*-* 00/6:00:00`) with
`Persistent=true` to catch missed runs. Units are user units — no root
required, no `User=` directive.

## Safety

- SRC is only ever read; nothing is ever written to `/opt/data/workspace/hermes-context/`.
- SRC is never nested inside DST (contents are synced, `SRC/.` → `DST/`).
- Stale files in DST are removed by both sync paths (mirror, not accumulate).
- The script uses no GNU-only constructs (`find -printf`, `date -I`), so it runs
  under BusyBox as well as GNU userland.
