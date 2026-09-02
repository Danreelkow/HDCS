# hermes-context

One-way mirror of a host-side context directory into the workspace
(`host -> workspace` only, never writeback). Runs as a systemd **user**
unit every 6 hours, or standalone from the shell. No root required.

## Install

1. Copy the script to `~/.local/bin/sync-hermes-context.sh` and make it
   executable (`chmod +x ~/.local/bin/sync-hermes-context.sh`).
2. Copy `hermes-context.service` and `hermes-context.timer` to
   `~/.config/systemd/user/`.
3. `systemctl --user daemon-reload && systemctl --user enable --now hermes-context.timer`

The service runs `~/.local/bin/sync-hermes-context.sh` (Type=oneshot),
triggered by the timer (`OnCalendar=*-*-* 00/6:00:00`, `Persistent=true`,
`Unit=hermes-context.service`, installed under `default.target`).

## Configuration (env overrides)

- `HERMES_CONTEXT_SRC` — source directory. Unset → production default
  `/opt/data/workspace/hermes-context`. Set-but-empty → refused (A23).
- `HERMES_CONTEXT_DST` — destination directory. Unset → production default
  `/workspace/hermes-context`. Set-but-empty → refused (A23).
- `HERMES_CTX_LOG` — log file path (one line per real run). Default
  `~/.cache/hermes-context/sync.log`. Its parent directory is an owned
  path and must live outside DST (A14: DST inside it is refused).

Example:

    HERMES_CONTEXT_SRC=/home/me/ctx HERMES_CONTEXT_DST=/tmp/ctx-dst \
      ~/.local/bin/sync-hermes-context.sh

Trailing slashes on env values are canonicalized once; all mutations go
through the canonical paths.

## Test without writing anything

    ~/.local/bin/sync-hermes-context.sh --dry-run

`--dry-run` prints `dry-run: sync=N delete=M` (plus the itemized rsync
plan when rsync is available) and performs **zero** writes: no stage
dir, no log line, no DST creation — an absent DST stays absent.

Check an existing destination against the source (read-only, A9-class:
contents + structure + symlink targets, never dereferencing symlinks):

    ~/.local/bin/sync-hermes-context.sh --verify

Exits nonzero on any mismatch, including a regular file standing in for
a source symlink, and when DST is absent.

## Sync strategy

- **Primary:** `rsync -a --delete SRC/ DST/` (recursive mirror; stale
  subtrees deleted; file↔dir type changes reconciled; symlinks copied
  as symlinks).
- **Fallback (rsync unavailable):** `cp -a` plus a recursive reconcile
  pass that deletes stale entries, replaces type mismatches, and
  compares symlink *targets* (same type alone is not equality).
- Both paths converge to the same end state: DST ≡ SRC recursively.
  Order is always: guards → stage → content-verify → touch DST → final
  self-verify (mismatch ⇒ exit nonzero, never warn-and-exit-0).

## Refusals

Guards cite only: A12 (identity/ancestor/descendant/symlink-into-SRC),
A14/A15 (overlap with owned concrete paths: instantiated stage dir, log
file's parent, entrypoint dir), A18 (degenerate `/`, ``, `.`), A22 (DST
itself resolves to a user-placed symlink — refused, never replaced),
A23 (set-but-empty env values). Ancestor-path refusals are realpath-based,
never lexical prefixes.

## KNOWN_LIMITATIONS

- A21: exotic filenames containing newlines or control characters are
  not handled (KNOWN_LIMITATIONS, open).
- Adversarial env combinations beyond the A14 owned-path guard
  (KNOWN_LIMITATIONS, open).
