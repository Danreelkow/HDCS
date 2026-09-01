# hermes-context sync

One-way mirror of the host-side Hermes context into the workspace.

- **Direction (A2):** host -> workspace only, every run. There is no writeback to `HERMES_CONTEXT_SRC` (`/opt/data/workspace/hermes-context/`). The script only ever writes under `HERMES_CONTEXT_DST` (`/workspace/hermes-context/`).
- **Primary path (A5):** `rsync -a --delete SRC DST` — DST ends up byte-identical to SRC, recursive, on every real run.
- **Fallback (A4/A7):** if rsync is unavailable, the script purges DST with recursive `rm -rf` of all contents (stale subtrees deleted at every depth, mirroring `rsync --delete`), then copies faithfully with `cp -a SRC/. DST/`. Because DST is fully emptied before copying, the resulting tree is rebuilt entirely from SRC content, so both paths converge to a byte-identical end state under the mechanical gate (full-tree checksum compare, not link counts). Note: `cp -a` preserves hard-link relationships that `rsync -a` (without `-H`) does not; this affects only link topology, never file content, so the byte-compare gate converges. The fallback is never accumulate-only.
- **Dry run (A6):** `sync-hermes-context.sh --dry-run` runs `rsync -a --delete --dry-run` and performs **zero writes anywhere** — no log file, no mkdir, no touch, no redirections. If rsync is not installed, the dry-run fallback computes read-only full-tree checksum (md5) manifests of **both SRC and DST** and diffs them, reporting exactly what a real run would change; it performs no filesystem writes and still exits 0. DST is byte-identical before and after a dry run.
- **Mechanical gate:** dry-run purity is verified by a full-tree checksum compare of DST pre/post (not a probe file):

  ```sh
  find "$DST" -type f -print0 | sort -z | xargs -0 md5sum > /tmp/pre
  sync-hermes-context.sh --dry-run
  find "$DST" -type f -print0 | sort -z | xargs -0 md5sum > /tmp/post
  diff /tmp/pre /tmp/post   # must be empty (I1)
  ```

  After a real run, `diff -r SRC DST` must be clean (I2), and run1 vs run2 checksums must match (I4). The real `cp -a` fallback performs this full-tree checksum compare itself and logs the result.
- **Placement (A8):** the log defaults to `~/.cache/hermes-context/sync.log` (override via `HERMES_CONTEXT_LOG`), always outside DST in all modes, created only in real mode. Install locations are `~/.local/bin` (or `/workspace/hdcs/bin`), never inside the mirrored tree. The sync never deletes or moves its own entrypoints, and no artifact (script, unit, README, log) is ever copied into DST.
- **Standalone (A3):** the script runs fine without systemd; the units are `systemctl --user` only, no root required.
- **Idempotence (I4):** running the script N times yields the same DST state as one run.

## Environment

| Variable | Default |
|---|---|
| `HERMES_CONTEXT_SRC` | `/opt/data/workspace/hermes-context/` |
| `HERMES_CONTEXT_DST` | `/workspace/hermes-context/` |
| `HERMES_CONTEXT_LOG` | `$HOME/.cache/hermes-context/sync.log` |

If `HERMES_CONTEXT_LOG` is set to a path inside DST, the script refuses to run (exit 1, no writes).

## Install

