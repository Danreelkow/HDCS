# hermes-context sync

One-way exact-mirror sync of the hermes context tree from the host to the
workspace. The source path is /opt/data/workspace/hermes-context/ and the
destination is /workspace/hermes-context/. Direction is strictly host ->
workspace; nothing is ever written back to the source.

## Install

1. Copy the script to a bin directory outside the mirrored tree. The primary
   install location is `~/.local/bin/` (this is what the provided unit file
   expects):

       cp sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh
       chmod +x ~/.local/bin/sync-hermes-context.sh

   Alternatively, `/workspace/hdcs/bin` is acceptable — but if you install
   there, edit `ExecStart` in `hermes-context.service` to point at
   `/workspace/hdcs/bin/sync-hermes-context.sh` before installing the units.
   In all cases the script must not live inside the mirrored tree.

2. Install the systemd user units, no root required:

       mkdir -p ~/.config/systemd/user/
       cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
       systemctl --user daemon-reload
       systemctl --user enable --now hermes-context.timer

The timer fires every 6 hours (`OnCalendar=0 */6:00:00`, `Persistent=true`).

## Source changes

After editing files under the source tree, the next timer tick picks them up
automatically, or run the script manually:

    ~/.local/bin/sync-hermes-context.sh

## Dry-run test

Before any real run, test with the dry-run mode that performs no writes of
any kind — no staging directory, no destination change (DST is byte-identical
before and after), and no log file is created:

    ~/.local/bin/sync-hermes-context.sh --dry-run

## Sync strategy

The end state is an **exact mirror** of the source: recursive, with stale
files and subtrees deleted on every run — never accumulate-only. This holds
for both sync paths:

- **Primary:** `rsync -a --delete SRC/ stage/` into a fresh staging directory.
- **Fallback (rsync absent):** `tar -cf - . | tar -xf -` into a fresh staging
  directory. Because staging starts empty, stale entries cannot survive, so
  the fallback yields the identical mirror end state including stale deletion.

Ordering guarantees:

1. **Stage** — source is copied to a temp staging dir (`mktemp` under
   `$TMPDIR`/`/tmp`).
2. **Verify** — the staged tree is compared against the source recursively:
   byte-compare of file contents, symlink targets, and directory structure.
   Metadata and timestamps are ignored. Any mismatch aborts with a nonzero
   exit and the destination is left untouched.
3. **Apply** — only after verification succeeds are the destination's
   contents replaced with the staged mirror.

"Verified" only means the staging copy was content-compared against the
source. It is never a claim about an unverified copy.

## Safety guards

- **Identity guard:** the script refuses (clean nonzero exit, zero writes) if
  source and destination resolve to the same path, are in an
  ancestor/descendant relation, or the destination path traverses a symlink
  resolving into the source.
- **Destructive ordering:** no deletion at the destination happens before a
  verified copy of the source exists in staging. Source survival always
  outranks mirror freshness.
- **Logs and entrypoints** live outside the mirrored tree (default log:
  `~/.cache/hermes-context/log`, override with `HERMES_CTX_LOG`); the sync
  never touches or deletes them.

## Exit codes

- `0` — success, or clean dry-run.
- `2` — usage error (unknown flag).
- `1` — guard refusal, staging/verify failure, or post-apply mirror mismatch
  (mismatch is never a warn-and-exit-0).
