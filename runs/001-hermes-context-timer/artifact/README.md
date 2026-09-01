# sync-hermes-context

One-way contents-sync `SRC -> DST` (never writes back to SRC). Mirror class:
contents, structure, symlinks. Deletions in SRC propagate to DST. Order is
stage -> verify (content-compare) -> touch DST, so a failed verify never
touches DST. Primary transport is rsync; if rsync is absent the script falls
back to a tar pipe (same end state).

## Files
- `sync-hermes-context.sh` — the sync engine (standalone executable)
- `hermes-context.service` — systemd --user oneshot unit
- `hermes-context.timer` — systemd --user timer, fires every 6 hours

## Install (user units only, no root)
1. `install -Dm755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh`
2. `install -Dm644 hermes-context.service hermes-context.timer -t ~/.config/systemd/user/`
3. Edit `Environment=` lines in `hermes-context.service` if needed, then:
   - `systemctl --user daemon-reload`
   - `systemctl --user enable --now hermes-context.timer`
   - `systemctl --user list-timers hermes-context.timer` to confirm

Standalone exec (no systemd): the script has built-in defaults
(`SRC=/opt/data/workspace/hermes-context/`, `DST=/workspace/hermes-context/`),
so `~/.local/bin/sync-hermes-context.sh` works as-is; both paths are
env-overridable (see below).

## Change the source/destination
Env vars `HERMES_CONTEXT_SRC` and `HERMES_CONTEXT_DST` override the s0
defaults, both under systemd (edit the unit's `Environment=` lines) and
standalone. Log path defaults to `~/.cache/sync-hermes-context.log` and may be
moved via `HERMES_CTX_LOG` — it is refused if it points inside DST.

## Dry-run test procedure
`HERMES_CONTEXT_SRC=... HERMES_CONTEXT_DST=... sync-hermes-context.sh --dry-run`
prints a one-line plan and performs zero writes — no DST changes, no log file
created. A missing DST is a valid dry-run input: it reports a full-population
plan and exits 0 without creating anything. Confirm with checksums or
`diff -r --no-dereference SRC DST` before and after; they must be
byte-identical.

## Guards
- SRC == DST (literal or by realpath) aborts before any destructive op.
- DST at or under a protected path (`/`, `/etc`, `/usr`, `/bin`, `/sbin`,
  `/var`, `/boot`, `/dev`, `/proc`, `/sys`; override via `HERMES_CTX_PROTECTED`)
  aborts. Comparison is boundary-aware (path components, not string prefixes).

## KNOWN_LIMITATIONS
- Exotic env combos only: e.g. very old diffutils lacking `--no-dereference`
  falls back to plain `diff -r`; filesystems without symlink support cannot
  honor the symlink part of the mirror class; DST on a read-only mount fails
  at the touch phase (by design, nonzero exit).
