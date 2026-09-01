# hermes-context sync

One-way mirror of the hermes context from the host mount into the workspace
(A1/A2): the destination end state always converges to the source end state —
contents, recursive directory structure, and symlinks — with stale destination
entries deleted at every depth (A5/A7).

## Files

- `~/.local/bin/sync-hermes-context.sh` — the sync script (standalone exec or systemd user unit, A3/A8)
- `~/.config/systemd/user/hermes-context.service` — oneshot service unit
- `~/.config/systemd/user/hermes-context.timer` — 6h timer (`OnCalendar=00/6:00:00`, `Persistent=true`)

## Standalone usage

    ~/.local/bin/sync-hermes-context.sh            # real run
    ~/.local/bin/sync-hermes-context.sh --dry-run  # zero-write plan (A6/A16)
    ~/.local/bin/sync-hermes-context.sh --verify   # recursive SRC vs DST check, nonzero on mismatch

## Install (systemd user units — no root, A3)

    cp sync-hermes-context.sh ~/.local/bin/ && chmod +x ~/.local/bin/sync-hermes-context.sh
    cp hermes-context.service hermes-context.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer
    systemctl --user list-timers hermes-context.timer

The service runs `%h/.local/bin/sync-hermes-context.sh` (Type=oneshot); the
script and log live outside the mirrored tree (A8), so the sync can never
delete its own entrypoints.

## Environment overrides (A17)

All paths are env-parameterized; the deployed values are production defaults,
not scope limits:

- `HERMES_CONTEXT_SRC` — default `/opt/data/workspace/hermes-context/`
- `HERMES_CONTEXT_DST` — default `/workspace/hermes-context`
- `HERMES_CTX_LOG` — default `~/.cache/hermes-context/` (log FILE: `sync.log`)

All paths are canonicalized with `realpath` before guards run. Guards run
before ANY write; every refusal cites an A-number and exits nonzero with zero
writes (A19/A20).

## Sync strategy (A5/A7/A13)

- Primary: `rsync -a --delete SRC/ stage/` — contents of SRC into a staging
  tree, never nested.
- Fallback (no rsync): `tar -C SRC -cf - . | tar -C stage -xf -` (or `cp -a`),
  then a recursive reconcile with a mktemp prunelist in a reserved namespace
  (`.hc-stage.*`, A20) that deletes stale / type-mismatched DST entries at ALL
  depths.
- BOTH paths converge to the exact same end state: a recursive mirror of
  contents + directory structure + symlinks, stale entries deleted at any
  depth (A5/A7).
- Order is always: stage → content-verify stage against SRC (files, dirs,
  symlink targets) → only then touch DST (A13/A11). A verification failure
  exits nonzero and leaves DST untouched; no unverified copy is ever treated
  as verified.
- If DST was a symlink passing the guards, it is replaced with a real tree
  (A18).

## Dry-run test procedure (A6/A16)

    ~/.local/bin/sync-hermes-context.sh --dry-run

Prints `would-create / would-delete / would-update` to stdout only. Verify
zero side effects: DST is byte-identical afterwards, and if DST did not exist
before, it still does not exist (no dir, log, or temp file created anywhere).

## Refusals (nonzero exit, zero writes, A-number cited)

- Degenerate SRC/DST (`""`, `.`, `..`, `/`, or resolving to `/`) → A18
- SRC/DST equal, ancestor, descendant, or DST inside SRC (realpath) → A12
- Log directory or script entrypoint dir colliding with the SRC or DST
  boundary (component-split compare of concrete instantiated paths) → A14/A15
- Missing/non-directory source → A1

Staging (`mktemp -d` under the validated log dir, created only after all
guards) is content-verified before DST is touched (A13/A20); the staging
verification failure path exits nonzero with DST untouched (A9).

## KNOWN_LIMITATIONS

- Exotic filenames (newlines/control characters) are not guaranteed
  lossless through the portable `find`/`sed`-based comparison walk (A21).
- Adversarial environment combinations beyond the A14/A15 owned-path guard
  (e.g. env overrides pointing staging/log at attacker-chosen paths) are not
  exhaustively guarded (A14).
