```markdown
# hermes-context sync

One-way mirror of the hermes context directory from host to workspace
(direction fixed: host -> workspace, A2).

## Paths and env override

- `HERMES_CONTEXT_SRC` — source directory (default `/opt/data/workspace/hermes-context/`)
- `HERMES_CONTEXT_DST` — destination directory (default `/workspace/hermes-context/`)
- `HERMES_CONTEXT_LOG_DIR` (or `LOG_DIR`) — log directory (default `~/.cache/hermes-context/`, always outside DST, A8)

Trailing slashes on env values are canonicalized once; all mutations go through
the canonical paths.

## Usage

    sync-hermes-context.sh            # real run: stage -> verify -> mirror to DST
    sync-hermes-context.sh --dry-run  # plan/diff print only
    sync-hermes-context.sh --verify   # exit 0 only on exact mirror

### --dry-run zero-write guarantee

Dry-run performs ALL guards, prints the plan (and a diff when DST exists), and
performs ZERO writes: no log file, no stage dir, and DST is NOT created if
absent (A6, A16).

### --verify

Fails (nonzero exit) when DST is absent or does not exactly mirror SRC.
Verification never dereferences symlinks: a regular file with a symlink
target's bytes does NOT pass for a SRC symlink (A9, lstat-based class).

## Sync semantics

- rsync `-a --delete` when available; otherwise a `cp -a` fallback that
  explicitly deletes stale files and stale subtrees at every depth (A4, A7).
- SRC CONTENTS are synced into DST — no extra nesting level.
- Exact mirror end state: stale entries deleted, file<->dir type changes
  reconciled (A5).
- MIRROR_CLASS scope: file contents, recursive directory structure, and
  symlinks. Timestamps and hardlink topology are NOT preserved or compared.
- Order is law: build stage -> content-verify stage vs SRC -> only then touch
  DST (A11, A13). The copy promoted to DST is content-compared; the README
  never calls any unverified copy "verified".
- Idempotent: rerunning on a mirrored DST makes no changes and exits 0.

## Refusals (each exits nonzero citing its A-number)

- Degenerate paths `/`, `""`, `.` for SRC or DST (A18). Explicitly EMPTY env
  values are refused, never silently defaulted (A18).
- SRC == DST, DST inside SRC, DST an ancestor of SRC, DST resolving through a
  symlink into SRC — realpath-based, pre-destruction (A12).
- DST (path-level) is a symlink: REFUSED, never replaced. The operator must
  remove the symlink manually (A22).
- DST equal to / containing / inside an OWNED concrete path: the script stage
  dir, the log file's PARENT directory, or the entrypoint directory —
  component-boundary-aware comparison, never a string prefix (A14, A15).
  Note: e.g. DST=/workspace/data/hermes-context-sibling is NOT refused.

## Logs

One line per real run is appended to `$HERMES_CONTEXT_LOG_DIR/sync.log`
(default `~/.cache/hermes-context/sync.log`), always outside the DST tree.
The sync never deletes its own entrypoints or logs (A8).

## systemd user units

- `hermes-context.service` — Type=oneshot, ExecStart at
  `%h/.local/bin/sync-hermes-context.sh` (i.e. `~/.local/bin/sync-hermes-context.sh`).
- `hermes-context.timer` — `OnCalendar=*-*-* 00/6:00:00`, Persistent=true.

Install:

    install -m 755 sync-hermes-context.sh ~/.local/bin/
    mkdir -p ~/.config/systemd/user
    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer
    systemctl --user list-timers hermes-context.timer

The script also runs standalone on hosts without systemd (A3).

## KNOWN_LIMITATIONS

- Exotic filenames: filenames containing newlines or other control characters
  break reporting/comparison. Repro: corpus containing a filename with `\n`.
  (+open)
- Adversarial env combinations beyond the A14 owned-path guard are out of
  scope; closed by citation of A14 — no re-derivation. (+open)
