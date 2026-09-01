# hermes-context-sync

Mirror `SRC` → `DST` recursively (contents, structure, symlinks), verified, idempotent.

## Files

- `sync-hermes-context.sh` — main script
- `hermes-context.service` — systemd user service (Type=oneshot)
- `hermes-context.timer` — 6-hour timer (`OnCalendar=*-*-* 00/6:00:00`, Persistent)

## Usage (standalone)

`SRC` and `DST` are **required environment variables** (the source is fully
parameterized; nothing is hardcoded-only):

    SRC=/opt/data/workspace/hermes-context DST=/workspace/hermes-context \
      bash sync-hermes-context.sh --dry-run   # zero writes (incl. LOG)
    SRC=/opt/data/workspace/hermes-context DST=/workspace/hermes-context \
      bash sync-hermes-context.sh             # real run, verifies after sync

Install to `~/.local/bin/sync-hermes-context.sh` (or `/workspace/hdcs/bin/`).

## Usage (systemd --user)

    mkdir -p ~/.config/systemd/user
    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    # if installed to /workspace/hdcs/bin instead of ~/.local/bin, edit ExecStart accordingly
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer
    systemctl --user start hermes-context.service   # run once now

No root required; default `--user` scope. SRC/DST/LOG are set via `Environment=`
in the unit; override with a drop-in (`systemctl --user edit hermes-context.service`)
or `EnvironmentFile=` if your paths differ.

## Environment variables

| Var       | Default                                | Notes                              |
|-----------|----------------------------------------|------------------------------------|
| `SRC`     | *(required — no default)*              | source tree                        |
| `DST`     | *(required — no default)*              | destination tree                   |
| `LOG`     | `~/.cache/hermes-context-sync.log`     | forced outside DST (A8)            |
| `ART_DIR` | `~/.cache/hermes-context-sync-artifacts` | artifact directory               |

## Dry-run semantics (A6)

`--dry-run` computes the sync plan only. With rsync present it invokes
`rsync -aN --delete --dry-run`; on the fallback path it computes the plan via
NUL-delimited traversal diff. **No writes of any kind, including LOG.** The DST
tree is byte-identical before and after a dry-run.

## Sync & convergence

- Primary: `rsync -a --delete`.
- Fallback (rsync absent): NUL-delimited `find` piped through `cpio`/`tar`
  (with a NUL-safe per-entry `cp -a` last resort) into a staging directory,
  verified against SRC, then swapped into place — same end state at any
  nesting depth (A5/A7). `rm -rf` of DST is never performed before a verified
  copy exists elsewhere (A11).
- Self-verify (A9): recursive compare of contents (`cmp`), structure (file
  set), and symlink targets via NUL-delimited traversal. Mismatch → exit ≠ 0.
- Idempotent (A13): re-running with unchanged SRC performs no changes.

## Guards (A11/A12)

Realpath canonicalization runs before any write (including LOG). Rejected
with exit ≠ 0 and zero writes: `SRC == DST`, DST inside SRC, SRC inside DST,
DST symlink resolving into SRC.

## Exit codes

- `0` — success (or dry-run plan computed)
- `1` — verify failure / sync failure
- `2` — guard rejection

## Logging (A14)

Real runs append exactly one line to `LOG`. Dry-runs and guard rejections
write nothing.

## KNOWN_LIMITATIONS (non-blocking, A10)

- **Q16 — newline-in-filename / NUL-traversal scope:** traversal is
  NUL-delimited, so newlines in filenames are handled correctly. However,
  filenames containing NUL are impossible on POSIX filesystems; pathological
  filenames that defeat `cpio`/`tar` staging in the fallback path (e.g.
  extremely long paths or unusual file types on exotic filesystems) may cause
  the fallback to fail with exit ≠ 0 rather than mis-copy. Rsync path is
  unaffected.
- **Q17 — LOG ∈ DST real-run churn:** if `LOG` is explicitly placed inside
  DST, it is rewritten to the default `~/.cache` location at startup (A8), so
  no churn occurs within the mirrored tree. If a user re-points `LOG` into
  DST via env on every run, the log line itself would appear as a DST change
  on the *next* run only; this is user configuration, not a script defect.
