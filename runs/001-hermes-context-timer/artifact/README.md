# hermes-context sync

One-way mirror of `/opt/data/workspace/hermes-context/` to
`/workspace/hermes-context/` (SRC -> DST, never write-back). rsync-based,
with a `cp -a` fallback transport that converges to the same end state.
Stale entries on the destination are deleted every run (exact mirror).

## Files

- `sync-hermes-context.sh` — the sync script (standalone-capable)
- `hermes-context.service` — user service unit (Type=oneshot)
- `hermes-context.timer` — user timer unit (6h cadence)

## Environment variables (contract — all overridable, defaults are production values)

| Variable | Default | Meaning |
|---|---|---|
| `HERMES_CONTEXT_SRC` | `/opt/data/workspace/hermes-context/` | source directory |
| `HERMES_CONTEXT_DST` | `/workspace/hermes-context/` | destination directory |
| `HERMES_CTX_LOG` | `~/.cache/hermes-context/sync.log` | one-line summary log |

The script works with no environment set: it applies the production defaults
above (A17). Any variable may be overridden per-invocation; the systemd service
unit sets `HERMES_CONTEXT_SRC` and `HERMES_CONTEXT_DST` explicitly via
`Environment=` so normal-operation syncs need no extra configuration.

Guards (exit code 2, nothing executed): SRC nonexistent; DST exists but is not
a directory; identity or ancestry between SRC and DST (either direction);
log path resolving inside DST or SRC; no admissible staging base outside
DST/SRC.

## Dry-run

    bash sync-hermes-context.sh --dry-run

or with explicit overrides:

    HERMES_CONTEXT_SRC=/opt/data/workspace/hermes-context/ \
    HERMES_CONTEXT_DST=/workspace/hermes-context/ \
    bash sync-hermes-context.sh --dry-run

(or `DRY_RUN=1`). A dry-run writes **nothing**: no DST creation, no log line,
no temp residue (A6/A16). With rsync it prints the itemized plan; without
rsync it prints the fallback plan to stdout only.

## Real run (order: stage -> verify -> touch-DST)

The mirror is built in a private staging directory under `TMPDIR`
(never inside DST or SRC — if `TMPDIR`/`/tmp` resolves into an owned path,
the parent of DST is used as a last-resort base); it is verified against SRC
(`diff -rq --no-dereference`) **before** the destination is touched. If
verification fails, the script aborts with exit 1 and DST is left untouched —
source survival > freshness.

## Install

    cp sync-hermes-context.sh ~/.local/bin/
    chmod +x ~/.local/bin/sync-hermes-context.sh
    mkdir -p ~/.config/systemd/user/
    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

The service runs `%h/.local/bin/sync-hermes-context.sh` (i.e.
`/home/<you>/.local/bin/sync-hermes-context.sh`).

## Standalone invocation

    ~/.local/bin/sync-hermes-context.sh

or with explicit overrides:

    HERMES_CONTEXT_SRC=/opt/data/workspace/hermes-context/ \
    HERMES_CONTEXT_DST=/workspace/hermes-context/ \
    ~/.local/bin/sync-hermes-context.sh

## KNOWN_LIMITATIONS

- Mirror class is contents + structure + symlinks only. File metadata,
  timestamps, ownership, permissions fidelity and hardlinks are NOT
  preserved as a guarantee (A7/A10). Fallback transport cannot be verified
  for metadata; only the rsync path is authoritative.
- `cp -a` fallback prunes stale entries via a `diff -rq` listing; names
  containing newlines are unsupported in that path.
- Dry-run without rsync prints an approximate plan (no rsync itemize).
