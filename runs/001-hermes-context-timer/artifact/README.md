# hermes-context sync

One-way host->workspace mirror of the HERMES context directory (contents +
recursive directory structure + symlinks; no metadata/timestamps/hardlinks —
the MIRROR class). Stale entries in DST are deleted at every depth so DST
always converges to exactly SRC's end state.

## Install

1. Copy the script **outside the mirrored tree** (A8):

       install -m 755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh

2. Copy the user units:

       mkdir -p ~/.config/systemd/user
       cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
       systemctl --user daemon-reload
       systemctl --user enable --now hermes-context.timer

   The service runs `ExecStart=%h/.local/bin/sync-hermes-context.sh` (`%h`
   expands to your home directory). Standalone/cron usage works without
   systemd — just run the script directly; it appends to
   `~/.cache/hermes-context/sync.log` (log file is never inside DST).

## Source/destination override (A17)

Env overrides are the mandated contract mechanism:

    HERMES_CONTEXT_SRC=/other/src HERMES_CONTEXT_DST=/other/dst \
      ~/.local/bin/sync-hermes-context.sh

Deployed defaults: SRC=`/opt/data/workspace/hermes-context/`,
DST=`/workspace/hermes-context/`. Every reference renames together.

## Dry-run test procedure (A6/A16)

    ~/.local/bin/sync-hermes-context.sh --dry-run

Emits a plan to stdout only. Verify DST is byte-identical afterward, and if
DST did not exist it still does not exist — zero writes anywhere, including
no log write and no stage directory. Exit 0.

## Verify mode

    ~/.local/bin/sync-hermes-context.sh --verify

Exits nonzero with `FAIL` if DST is absent (or still a symlink); exits 0
with `OK` only when DST is an exact recursive mirror of SRC. Any mismatch
is a nonzero failure, never a warn-exit-0.

## Sync strategy

- **Primary:** `rsync -a --delete` of SRC contents into a staging directory
  (never nested: contents of SRC go into stage, `src/` -> `dst`).
- **Fallback (no rsync):** `cp -a` of SRC contents into a freshly created
  stage directory (`cp -a "$SRC/." "$STAGE/"`). Because the stage is fresh,
  the `cp -a` copy is already the exact recursive tree; **stale entries are
  deleted at all depths** when DST is replaced by the verified stage tree at
  install time (A7).

Both paths converge identically to an exact recursive mirror. The staged
copy is content-verified against SRC (files, recursive dirs, symlink targets)
**before** DST is touched; a verification failure exits nonzero with DST
untouched. Only a content-compared, verified copy is ever installed —
"verified" here means exactly that content comparison, nothing more.

## DST symlink refusal (A22)

If DST itself is a symlink (pointing anywhere outside SRC), the script
**refuses with A22 and exits nonzero — it never replaces a user-placed
symlink**. Remove the symlink manually, then rerun. (A DST symlink that
resolves *into* SRC is refused with A12.) The outside link target is never
touched in any case.

## Guards (refusals cite A-numbers, exit nonzero, zero writes)

Refuses: SRC==DST by realpath; ancestor/descendant in either direction;
DST symlink resolving into SRC (A12); DST path-level symlink (A22);
degenerate paths (`/`, empty, `.`) via component tests (A18); owned paths
(log dir, log file, stage, entrypoint) colliding with the DST boundary —
inside DST, DST inside them, or equal to DST — via component-boundary-aware
realpath comparison (A14, A15). Every owned path is resolved with `realpath`
— through any existing symlinks, e.g. a symlinked `XDG_CACHE_HOME` or a
pre-existing `sync.log` symlink — before comparison, so a resolved target
inside the mirror tree is refused, not the raw string. The stage is created
with `mktemp -d` under an already-validated parent and the **instantiated**
path is re-validated before use (A15/A20/A22). Any log-related environment
variable (e.g. `HERMES_CTX_LOG`, `LOG_DIR`) that resolves (through symlinks)
inside the mirror tree is refused with zero writes. Source survival outranks
freshness: DST is only replaced after a verified copy exists elsewhere.

## KNOWN_LIMITATIONS

- Exotic filenames (newlines/control characters) (A21) — the tooling copies
  them, but losslessness is scoped to normal filenames. Repro: corpus with
  `\n` in filenames.
- Adversarial environment-variable combinations beyond the A14 guard
  (closed by citation of A14; no re-derivation).

## Files

- `sync-hermes-context.sh` — the sync tool (standalone)
- `hermes-context.service` — systemd user oneshot unit
- `hermes-context.timer` — systemd user timer, fires every 6 hours,
  `Persistent=true`, `WantedBy=timers.target`
