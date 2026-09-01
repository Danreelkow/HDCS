# hermes-context-sync

One-way mirror of the Hermes context tree: `SRC -> DST` only, never write-back (A1/A2).

## Install (systemd user units)

    cp sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh
    chmod +x ~/.local/bin/sync-hermes-context.sh
    mkdir -p ~/.config/systemd/user
    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

The service runs `%h/.local/bin/sync-hermes-context.sh` (Type=oneshot, user-level only; no root, no sudo anywhere).

## Standalone usage (cron / manual — identical behavior, no systemctl dependency)

    ~/.local/bin/sync-hermes-context.sh            # real run: stage -> verify -> mutate DST
    ~/.local/bin/sync-hermes-context.sh --dry-run  # plan only, zero writes

## Environment variables (all optional; deployed defaults are the production values)

| Variable | Default | Meaning |
|---|---|---|
| `HERMES_CONTEXT_SRC` | `/opt/data/workspace/hermes-context/` | source tree (read-only to this script) |
| `HERMES_CONTEXT_DST` | `/workspace/hermes-context/` | destination tree (mirrored, stale subtrees deleted) |
| `HERMES_CONTEXT_LOG` | `$HOME/.cache/hermes-context/sync.log` | real-run log; always outside DST (A8) |

## Sync semantics

- rsync-based (`rsync -rl --delete`); if rsync is absent, a `cp -a` staged fallback converges to the same end state (A3/A5).
- End state = exact contents + structure + symlinks at every depth; stale subtrees deleted (A5/A7). Class is contents/structure/symlinks only — no timestamps, metadata, or hardlinks are in scope (A9 levels 1–3).
- Order law (A13): stage → recursive content-verify of staging against SRC → only then mutate DST. Verification failure exits nonzero; never warn-exit-0. No `rm -rf DST` before a verified copy exists (A11).
- Guard-before-mutation: all guards (A11/A12/A14/A15/A18) run before any write — no log parent creation, no mktemp stage, no DST touch happens before every collision check has passed.
- Type changes (file↔dir) and stale entries reconcile to the mirrored end state.

## Dry-run purity

`--dry-run` performs ZERO writes of any kind: no log file, no temp dirs, no DST creation, no DST touch (A6/A16). DST is left byte-identical or nonexistent.

## Log placement

Real runs append to `$HOME/.cache/hermes-context/sync.log` (overridable via `HERMES_CONTEXT_LOG`). The log never lives inside DST (A8); an override pointing into DST is refused before any directory is created.

## Guards (closed set; refusals exit nonzero citing the law)

- **A11**: `SRC == DST` refused; no destructive DST mutation before a verified copy exists.
- **A12**: `realpath(SRC) == realpath(DST)` or ancestor/descendant relation refused; DST symlinks resolving into SRC refused.
- **A14/A15**: DST colliding (equal / containing / contained-in, by component-boundary comparison) with any concrete owned path — stage mktemp dir, resolved log parent, entrypoint dir — refused.
- **A18**: SRC/DST empty, `.`, or `/` (component test) refused; DST symlink resolving outside SRC refused; dangling DST symlink refused with an explicit A18 citation (never an unhandled resolution failure).

DST itself is always created/kept as a real directory; inner DST symlinks are replaced by the mirrored real entries, never followed.
