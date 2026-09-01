# hermes-context sync

One-way mirror of the hermes-context tree from the host into the workspace:

    SRC: /opt/data/workspace/hermes-context/   (override: HERMES_CONTEXT_SRC)
    DST: /workspace/hermes-context/            (override: HERMES_CONTEXT_DST)

Direction is always host -> workspace (A2). There is no writeback path.

## Install

Script must be installed **outside** the mirrored tree (A8) — either location works:

    install -m 755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh
    # or: install -m 755 sync-hermes-context.sh /workspace/hdcs/bin/

Units (systemctl --user only; no root anywhere, A3):

    mkdir -p ~/.config/systemd/user/
    install -m 644 hermes-context.service ~/.config/systemd/user/
    install -m 644 hermes-context.timer  ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer

The timer fires every 6 hours (`OnCalendar=*-*-* 0/6:00:00`, `Persistent=true`).

## Standalone usage

The script is standalone-capable (cron / any caller invokes it directly):

    ~/.local/bin/sync-hermes-context.sh

Environment overrides:

    HERMES_CONTEXT_SRC   source dir   (default /opt/data/workspace/hermes-context/)
    HERMES_CONTEXT_DST   dest dir     (default /workspace/hermes-context/)
    HERMES_CONTEXT_LOG   summary log  (default ~/.cache/hermes-context-sync.log)

## Dry-run

    ~/.local/bin/sync-hermes-context.sh --dry-run

Reports what would be mirrored or deleted. Performs **zero** writes of any
kind (A6): no destination changes, no directories created, no log file.

## Behavior notes

Both sync paths follow the same order (A11/A13): copy SRC to a staging dir
**outside DST**, verify the staged copy against SRC, and only then reconcile
into DST and re-verify the end state. DST is never modified before a verified
copy of SRC exists elsewhere, and SRC is never touched.

- rsync path: SRC is staged with `rsync -a SRC/ stage/`, verified, then
  applied with `rsync -a --delete stage/ DST/` (trailing slash — contents are
  mirrored, not nested, A4).
- cp_path (no rsync): SRC is staged with `cp -a SRC/. stage/`, verified, then
  stale entries are deleted from DST (recursive subtree deletion, A7) and the
  verified stage is copied in.

End state is identical either way (A5/A7).

- Verification covers the mirror class (A9): file contents, recursive
  directory structure, and symlinks. A mismatch exits nonzero — never a
  silent warn-and-exit-0.
- Identity guards (A12): the run is refused with a clean nonzero exit and
  zero writes if SRC and DST resolve to the same path, one is an ancestor of
  the other, or DST is a symlink resolving into SRC.
- The run summary log is never placed inside the DST tree (A8) nor inside the
  SRC tree (A2 no-writeback).

## KNOWN_LIMITATIONS

Per A10 these are open, classified, non-blocking:

- Newline-in-filename corpora: path handling is NUL-delimited internally, but
  the diff output of a verify failure and some tooling does not round-trip
  such names cleanly.
- Hostile environment where DST is also the log directory: the script refuses
  log paths inside DST (A8) — and inside SRC (A2) — so in such an environment
  the run summary is dropped if the default log dir is unwritable; redirect
  HERMES_CONTEXT_LOG outside both SRC and DST.
- Entry types outside the mirror class (sockets, fifos, devices) fail
  verification loudly rather than being mirrored.
- Non-GNU userlands (find without -print0/-z sort) are unsupported.
