# hermes-context sync

Mirror-syncs the host-side Hermes context mount into the workspace, one-way
(host -> workspace; nothing is ever written back to the host mount).

## Files

- `sync-hermes-context.sh` — the sync script (standalone-capable)
- `hermes-context.service` — user-level oneshot service
- `hermes-context.timer` — user-level timer, 6h cadence

Install location assumed below: `~/.local/bin/sync-hermes-context.sh` (this is
the exact path the service unit's `ExecStart=%h/.local/bin/sync-hermes-context.sh`
points at; adjust both together if you install elsewhere).

## Sync strategy

Mirror semantics per the MIRROR class {file contents, recursive directory
structure, symlink targets}; file/root metadata, timestamps and hardlink
topology are not mirrored.

- Recursive: DST ends byte-identical to SRC including all nested paths (any
  depth).
- Stale subtrees in DST are pruned at any depth (rsync `--delete` in both the
  stage and reconcile passes; the cp fallback implements equivalent recursive
  pruning).
- Both sync paths (rsync and cp fallback) converge to the identical end state;
  repeated runs are idempotent (byte-identical after every run).
- Contents sync: SRC's *contents* are synced into DST; the source directory is
  never nested inside the destination.

Order of operations (PIPE law):

1. **Guards** — degenerate/identity/owned-path checks; zero writes before all
   guards pass. Generic ancestors (e.g. `/tmp`) are NOT treated as owned
   concrete paths; only the concrete `mktemp -d` staging result is checked
   (against both DST and SRC — a TMPDIR under SRC would contaminate the source).
2. **Stage** — copy SRC contents into a fresh script-owned temp stage dir.
3. **verify_stage** — content-compare (diff) stage vs SRC. Only after this does
   a *verified copy* exist; before this point the staged copy is never called
   verified.
4. **Reconcile** — only then is DST touched: a pre-existing DST symlink is
   replaced (never followed) if it resolves within SRC, refused outright if it
   resolves outside SRC; DST is ensured and the verified copy is copied over
   DST with stale-subtree pruning. DST is never destroyed before a verified
   copy exists elsewhere.
5. **verify_final** — diff DST vs SRC; any mismatch exits nonzero.
6. **Summary** to stdout; log file written only on real runs (never during
   `--dry-run`, never inside DST).

Any verification mismatch is a hard failure with nonzero exit — never
warn-and-exit-0.

## Configuration (env overrides)

| Variable | Default |
|---|---|
| `HERMES_CONTEXT_SRC` | `/opt/data/workspace/hermes-context/` |
| `HERMES_CONTEXT_DST` | `/workspace/hermes-context/` |
| `HERMES_CONTEXT_LOG` | `~/.cache/hermes-context/sync.log` |

The service unit pins the deployed defaults via `Environment=`; the same names
override them for manual/test runs (e.g. `HERMES_CONTEXT_LOG` for the log
path). The log file's parent must lie outside DST (the script refuses
otherwise, exit nonzero, zero writes).

## Dry-run test

    HERMES_CONTEXT_SRC=/tmp/src HERMES_CONTEXT_DST=/tmp/dst \
      ~/.local/bin/sync-hermes-context.sh --dry-run

`--dry-run` writes nothing at all: no log file, no stage dir, and DST is not
created (an absent DST stays absent; an existing DST stays byte-identical).
The summary goes to stdout. Note the dry-run guard only refuses when DST
collides with a *concrete owned path* (entrypoint dir, resolved log-file
parent, or the actual instantiated stage dir) — a generic ancestor like `/tmp`
is not owned and does not trigger refusal.

## User-unit install

    mkdir -p ~/.config/systemd/user ~/.local/bin
    cp sync-hermes-context.sh ~/.local/bin/
    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

No root is involved: both units are user units (`WantedBy=default.target`),
and the service carries no `User=` line.

## Standalone / cron fallback

The script is standalone-capable: when systemd is absent (or for installer/
cron setups), call it directly from crontab or any scheduler:

    0 */6 * * * /home/youruser/.local/bin/sync-hermes-context.sh >>/tmp/hctx-cron.log 2>&1

Guards and verification behave identically standalone.

## Guards (refusals — all exit nonzero with zero writes, citing the register)

- Degenerate paths (`/`, empty, `.`) — refused (A18).
- DST identical to SRC by realpath, or ancestor/descendant relation, or a DST
  symlink resolving into SRC — refused (A12).
- DST equal to / containing / inside any script-owned *concrete* path
  (entrypoint dir, the instantiated staging dir, resolved log-file parent), or
  an owned path inside DST — refused (A14/A15). The resolved staging path is
  likewise checked against both DST and SRC (A14/A15).
- A pre-existing DST symlink resolving outside SRC — refused (A18).
- Log file parent inside DST — refused (A8/A14).

## KNOWN_LIMITATIONS (non-blocking)

- KL1 [A10, A14]: adversarial environment combinations beyond the concrete
  owned-path guard (hostile vars colliding with targets outside the owned-path
  set) are not defended. Repro: set TMPDIR/log overrides pointing at colliding
  targets beyond the concrete owned-path set.
- KL2 [A10]: corpora containing newlines in filenames are not guaranteed
  (prune traversal in the cp fallback assumes newline-free names).
