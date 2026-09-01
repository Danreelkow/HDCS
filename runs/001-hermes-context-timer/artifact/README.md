# hermes-context sync

Standing one-way sync (A2) of the host canonical mount into the workspace:
exact recursive mirror — file contents + directory structure (recursive) +
symlinks; NOT metadata/timestamps/hardlinks.
mirror := A9 class: file contents + directory structure (recursive) + symlinks; NOT metadata/timestamps/hardlinks

SRC := /opt/data/workspace/hermes-context/  (host canonical mount, MUST_KEEP; fixed, not overridable)
DST := /workspace/hermes-context/  (override with `HERMES_CONTEXT_DST`)

## Install (no root)

Install to ~/.local/bin/ (outside the mirrored tree, A8):

    install -m 0755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh
    mkdir -p ~/.config/systemd/user
    install hermes-context.service hermes-context.timer ~/.config/systemd/user/

The service runs ExecStart=%h/.local/bin/sync-hermes-context.sh — the unit path
`%h/.local/bin/sync-hermes-context.sh` must exist; keep script and unit in step.

Enable the user timer (systemctl --user, no root):

    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer
    systemctl --user list-timers hermes-context.timer

## Dry-run test (A6/A16)

`--dry-run` prints the plan and performs ZERO writes — no log entry, and DST is
never created (it stays byte-identical or nonexistent):

    ~/.local/bin/sync-hermes-context.sh --dry-run

Then do a real run and check the log (one line per real run only):

    ~/.local/bin/sync-hermes-context.sh
    cat ~/.cache/hermes-context/sync.log

## Semantics

Primary path: `rsync -a --delete` (contents sync, src/ -> dst, no nesting), so
stale subtrees are deleted at every depth and file<->dir type changes reconcile.
cp_path := fallback when rsync absent; tar-pipe or cp -a + recursive reconcile; semantics MUST equal rsync_path
The fallback (tar-pipe from a fresh staging dir, verified, then `cp -a`) reaches
the identical end state; run with `PATH` stripped of rsync to test parity.

Safety ordering (A11): stage -> content-verify vs SRC -> only then touch DST.
The script never deletes DST before a verified (content-compared, A13) staging
copy exists, never writes to SRC, and refuses cleanly (nonzero exit, no writes)
on: SRC==DST via realpath, ancestor/descendant relation, DST resolving through a
symlink into SRC, or DST conflicting with owned concrete paths (stage dir,
resolved log parent dir, entrypoint dir) in EITHER direction — DST inside an
owned path, or an owned path inside DST — via component-split comparison, not
string prefix (A12/A14/A15). In particular, a log dir inside DST would violate
A8 (post-sync log write would modify the mirrored tree) and is refused.

## KNOWN_LIMITATIONS

Cited per A10, non-blocking (exotic triggers, not reachable in normal op):
- A14/A15: adversarial env combos beyond the guard — e.g. `TMPDIR` set to a
  path that is itself a symlink racing to point inside DST between the mktemp
  and the realpath check; a DST intermediate component replaced by a symlink
  into SRC after `realpath -m` but before the copy. Repro notes: run the script
  with a hostile inotify/timer that swaps symlinks mid-run; the realpath-based
  guards check at decision time only. Plausible mitigations (open-tree fds) are
  out of scope here.
- Log path is fixed to `~/.cache/hermes-context/sync.log`; a `HOME` pointing
  inside the mirrored tree would be refused by the owned-path guard, not
  relocated.
- Fallback path requires GNU `tar` and `cp -a` (preserves symlinks; metadata
  parity is not required by A9).
