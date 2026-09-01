# hermes-context sync

One-way mirror of the host hermes-context source into the workspace destination
(A2: host -> workspace only; the reverse direction is never performed).

## Paths and environment

| Role | Default | Override |
|------|---------|----------|
| SRC  | `/opt/data/workspace/hermes-context/` | `HERMES_CONTEXT_SRC` |
| DST  | `/workspace/hermes-context/` | `HERMES_CONTEXT_DST` |
| Log file | `$HOME/.cache/hermes-context/sync.log` | `HERMES_CONTEXT_LOG` |

SRC, DST, and HERMES_CONTEXT_LOG are required, namespaced variables. UNSET
variables fall back to the production defaults shown above (A23). Setting any
of them to the EMPTY string is a REFUSAL (A23) — the script never silently
falls back to defaults for an explicitly empty value. Trailing slashes on env
values are canonicalized once; all mutations go through the canonical paths.

## Usage

    sync-hermes-context.sh            # real run: exact mirror
    sync-hermes-context.sh --dry-run  # plan/diff print only
    sync-hermes-context.sh --verify   # check DST is an exact mirror; nonzero on mismatch

Env override examples:

    HERMES_CONTEXT_SRC=/opt/data/workspace/hermes-context/ \
    HERMES_CONTEXT_DST=/tmp/hdcs-gate-dst \
    sync-hermes-context.sh --dry-run

### --dry-run zero-write guarantee

Dry-run executes every guard, prints the plan or the current differences, and
performs ZERO writes of any kind: no log file, no stage directory, and if DST
does not exist it is NOT created (A6, A16). DST is byte-identical after a dry-run.

### --verify

Fails (nonzero) when DST is absent. Verification enforces exactly
MIRROR_CLASS = { file contents, recursive directory structure, symlinks } and
is lstat-based: it never dereferences symlinks (no -L/-aL anywhere in
verification), so a regular file carrying the target's bytes does NOT pass for
a SRC symlink. Verification does not check metadata, timestamps, or hardlinks
(A9).

## Sync semantics

- Primary engine: `rsync -a --delete`; fallback (rsync absent): `cp -a` plus
  explicit recursive stale-subtree deletion at every depth. Both strategies
  produce the same result: a recursive mirror with stale entries deleted (A5/A7).
- SRC CONTENTS are synced into DST (no `dst/src` nesting) (A4).
- The end state after a real run is an exact mirror: stale entries deleted,
  file<->dir type changes reconciled (remove then copy, converge), DST-internal
  symlinks replaced by the real entry — a user symlink outside DST is never
  touched. Reruns are idempotent (exit 0, 0 copied 0 deleted).
- Pipeline is stage -> content-verify -> touch DST (A11/A13/A20): the stage
  parent candidate is validated as a string AND guard-checked (realpath vs
  SRC/DST/owned paths) BEFORE anything is created under it, then `mktemp -d`
  instantiates the stage, the INSTANTIATED path is re-validated, SRC is copied
  into the stage, the stage is A9-compared against SRC, and only then is DST
  touched. No `rm -rf` of DST before a verified stage exists.

## Refusals (each exits nonzero citing its A-number only)

- A23: HERMES_CONTEXT_SRC or HERMES_CONTEXT_DST is set but empty — no fallback.
- A18: SRC or DST is `/`, empty, or `.` (component test).
- A12: DST == SRC, DST inside SRC, SRC inside DST, or DST's path resolves
  through a symlink into SRC (realpath-based, component boundaries, never
  string prefixes).
- A22: DST itself is a symlink (resolving anywhere) — the symlink is REFUSED,
  never replaced; the operator removes it manually and reruns. The refusal
  leaves the path untouched.
- A14/A15: DST collides (equal, containing, or contained — component-boundary
  aware, never string-prefix) with a concrete owned path: the instantiated
  stage directory, the log file's PARENT directory, or the entrypoint
  directory. Generic ancestors like /tmp are NOT owned; a DST under /tmp is an
  ordinary path and syncs normally.

## Logs and entrypoints (A8)

The log file (`$HOME/.cache/hermes-context/sync.log`, overridable via
`HERMES_CONTEXT_LOG`; one UTC line per real run) and the entrypoint
(`%h/.local/bin/sync-hermes-context.sh`) always live OUTSIDE the DST tree;
the sync never deletes its own entrypoints or logs.

## Installation (systemd user units)

Copy the script to `%h/.local/bin/sync-hermes-context.sh`, the units to
`~/.config/systemd/user/`, then:

    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer
    systemctl --user list-timers hermes-context.timer   # shows the scheduled run

The service runs `ExecStart=%h/.local/bin/sync-hermes-context.sh` (Type=oneshot);
the timer fires on `OnCalendar=*-*-* 00/6:00:00` with `Persistent=true` and is
installed under `default.target`. The script is also standalone-executable on
hosts without systemd (no root required).

## KNOWN_LIMITATIONS

1. Exotic filenames (newline/control characters) can break reporting and
   comparison paths — repro: a corpus containing `\n` in filenames.
2. Adversarial env combinations beyond the A14 owned-path guard are closed by
   citation of A14 and are not re-derived; combinations not on the closed
   path-law list {A12, A14/A15, A18, A22, A23} are out of scope (A19).
