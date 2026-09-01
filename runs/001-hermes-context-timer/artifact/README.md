# hermes-context freshness sync

One-way mirror of the hermes context from host to workspace (A2): `SRC -> DST`, never the reverse.

## Paths and environment (A17)

| Variable | Default |
|---|---|
| `HERMES_CONTEXT_SRC` | `/opt/data/workspace/hermes-context/` |
| `HERMES_CONTEXT_DST` | `/workspace/hermes-context/` |
| `HERMES_CONTEXT_LOG_DIR` | `~/.cache/hermes-context` (outside DST, A8) |

Trailing slashes on env values are canonicalized once internally; all mutations go through the canonical paths.

## Usage

    sync-hermes-context.sh            # real run: stage -> verify -> promote
    sync-hermes-context.sh --dry-run  # plan only
    sync-hermes-context.sh --verify   # check DST is an exact mirror; nonzero on mismatch or absent DST

### --dry-run zero-write guarantee (A6/A16)

Dry-run executes every guard, prints the plan, and performs **zero writes of any kind**: no log
file, no stage directory, and DST is **not created** if it does not exist.

## Sync semantics

- rsync primary (`rsync -a --delete`), `cp -a` fallback (A4). SRC **contents** are synced into
  DST (no nesting).
- End state is an exact mirror (A5): stale files and stale subtrees are deleted at **every
  depth** — including in the `cp -a` fallback, where the promote step clears DST before copying
  the verified stage (A7).
- File <-> directory type changes on either side are reconciled to the mirror end state. This
  includes a pre-existing regular **file** at DST (or inside the path being promoted into): the
  file is replaced by the required directory mirror once a verified stage exists (A11).
- MIRROR_CLASS scope (A9): file contents, recursive directory structure, and symlinks.
  Timestamps, hardlinks, and other metadata are **not** preserved or compared.
- Verification compares **file contents byte-for-byte** (rsync checksum mode, `-rLnc`), never
  size/mtime — same-size files with different bytes fail verification (A9/A13).
- Idempotent: rerunning against an already-mirrored DST makes no changes and exits 0.

## Safety guards (refusals exit nonzero and cite an A-number, A19)

- **A18** — degenerate paths refused: SRC or DST is `/`, empty, or `.`.
- **A12** — realpath-based identity guard: `realpath(SRC) == realpath(DST)`, either an
  ancestor/descendant of the other, or DST resolving through a symlink into SRC. Checked on
  both paths before any destruction; lexical prefix tests are never used.
- **A22** — DST is a symlink at the path level: **refused, never replaced**. The sync never
  destroys a user-placed symlink; the operator removes it manually, then reruns.
- **A14/A15** — owned paths (log dir, `HERMES_CTX_LOG`, script/entrypoint dir, stage dir):
  refused if DST equals, lies inside, or contains them — component-boundary-aware, never a
  string-prefix test. A sibling name such as `/workspace/data/hermes-context-sibling` is NOT
  refused.

## Stage pipeline (A11/A13/A20/A22)

The stage directory is created with `mktemp -d` under an already-validated parent, then the
instantiated path is re-validated. SRC contents are synced into the stage, the stage is
content-compared against SRC on MIRROR_CLASS, and only a **verified** stage is promoted to
DST. DST is never touched or destroyed before a verified stage exists. The word "verified" on
this page always means this content-compared stage — never an unverified copy.

## Logs (A8)

One line per real run is appended under `LOG_DIR` (default `~/.cache/hermes-context`), always
outside the DST tree. The log write is not suppressed: a successful real run always produces
its log line, and a log failure fails the run. Entrypoints and logs are never deleted by the
sync.

## systemd user installation (A3)

    install -Dm755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh
    install -Dm644 hermes-context.service hermes-context.timer -t ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now hermes-context.timer
    systemctl --user list-timers hermes-context.timer   # confirm scheduled run

The service runs `~/.local/bin/sync-hermes-context.sh` (Type=oneshot); the timer fires it
every 6 hours (`OnCalendar=*-*-* 00/6:00:00`, persistent). The script also runs standalone on
hosts without systemd.

## KNOWN_LIMITATIONS

1. **Exotic filenames** — filenames containing newlines or control characters can break
   reporting/comparison. Repro: corpus with `\n` in a filename.
2. **Adversarial env combinations beyond the A14 guard** — closed by citation of A14; no
   re-derivation is performed for combinations outside the closed law list
   {A12, A14/A15, A18}.
