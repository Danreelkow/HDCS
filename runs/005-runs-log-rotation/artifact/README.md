# hdcs-runs-rotation

Rotate stale files out of a runs directory into an archive directory.
Pure bash + coreutils (`find`, `stat`, `cmp`, `realpath`, `mv`, `sort`, `awk`).
No logrotate, no root required.

## Files

- `hdcs-runs-rotation.conf` — config, exactly five keys:
  `RUNS_DIR`, `ARCHIVE_DIR`, `AGE_DAYS`, `PATTERN`, `KEEP`.
- `rotate-hdcs-runs.sh` — dry-run planner (default) and `--apply` writer.
- `verify-rotation.sh` — read-only state verifier.

## Install

Copy the three files above into the same directory, e.g. `/usr/local/bin` or
`~/bin`, and make the scripts executable:

    cp hdcs-runs-rotation.conf rotate-hdcs-runs.sh verify-rotation.sh /destination/dir/
    chmod +x /destination/dir/rotate-hdcs-runs.sh /destination/dir/verify-rotation.sh

## Configure

Edit `hdcs-runs-rotation.conf` (five `KEY=value` lines, no comments):

    RUNS_DIR=/workspace/hdcs/runs
    ARCHIVE_DIR=/workspace/.hdcs-rotate/archive
    AGE_DAYS=14
    PATTERN=*.txt
    KEEP=50

Environment overrides `HDCS_RUNS_DIR` and `HDCS_ARCHIVE_DIR` take precedence
over the conf values. A variable that is set but empty is refused (A4). All
path law refusals — equal paths, containment in either direction, degenerate
(`''`, `.`, `/`), set-but-empty — exit ≥1 with a message citing `A4`, before
any write. `KEEP=0` is valid: the archive is pruned to zero entries on apply.

## Dry-run

Run with no arguments:

    ./rotate-hdcs-runs.sh

Prints each planned move as `<src> -> <dst>` and creates nothing — no
`ARCHIVE_DIR`, no state files. Exit 0. The dry-run plan applies the same
collision-suffix logic as `--apply`, so the reported destination is exactly
the one `--apply` would use.

## Scheduling

Example cron line (nightly apply at 03:00):

    0 3 * * * /path/to/rotate-hdcs-runs.sh --apply

## Apply behavior

- Validates paths (A4) before any write.
- `mkdir -p` on `ARCHIVE_DIR`.
- Finds files matching `PATTERN` under `RUNS_DIR` whose age, computed with
  explicit stat epoch math (`now_epoch - mtime_epoch >= AGE_DAYS * 86400`),
  is at or beyond `AGE_DAYS`. A file exactly `AGE_DAYS` old IS rotated.
  `find` is used only to enumerate candidate paths; the staleness threshold
  is decided per file from `stat -c %Y` against `date +%s`, never from any
  day-rounded time predicate, which can exclude threshold-age files.
- Mirrored relative paths (A5_mirror): each file `RUNS_DIR/<rel>` is archived
  to `ARCHIVE_DIR/<rel>` — the full recursive relative path is preserved, so
  `RUNS_DIR/001-old/gate-out.txt` lands at
  `ARCHIVE_DIR/001-old/gate-out.txt`, never flattened to a top-level name.
- On a name collision inside the mirrored directory, a numeric suffix is
  appended to the basename: `gate-out.txt.1`, `gate-out.txt.2`, …
- Byte-losslessness is verified with `cmp` against a snapshot; a failed
  verification leaves the source in place and exits ≥1.
- KEEP pruning: after moves, the oldest archived entries beyond `KEEP`
  (across the whole archive tree, newest kept) are deleted. This applies for
  every `KEEP` value including `KEEP=0` (archive emptied).
- A second consecutive `--apply` with nothing stale is zero-action: exit 0,
  no moves, no new state.

## Verify behavior

`verify-rotation.sh` exits 0 only when the conf parses, the stale scan
completes cleanly and finds nothing at or beyond `AGE_DAYS`, and the archive
directory exists with an intact recursive file listing. A scan that cannot
run (unreadable tree, failed `stat` on a candidate) is a verify FAILURE —
the verifier never reports OK on an incomplete scan.

Verify never writes: it creates no files in the artifact directory or the
watched tree. Its only scratch files are `mktemp` files in the system temp
directory (outside both), removed on exit; every check feeds a flag
accumulator, and `find`'s own exit status is captured directly (never masked
by a downstream pipeline stage).

## Exit codes

- `rotate-hdcs-runs.sh`: `0` success or zero-action; `≥1` any refusal/failure.
- `verify-rotation.sh`: `0` consistent (conf parses, no stale match under
  RUNS_DIR, archive listing intact); `2` malformed conf; `≥1` otherwise.
  Verify never writes.

## KNOWN_LIMITATIONS

- Exotic filenames: names containing newlines are handled via NUL-safe
  traversal for scanning, but tooling output may misrender them; names
  beginning/ending with whitespace may be misreported in messages.
  Documented limitation, not a tool failure (A7).
- Races: a file created or modified concurrently between the stale scan and
  the move may be rotated or skipped inconsistently; no locking is performed.
  Documented limitation (A7).
- Only regular files are rotated; symlinks, fifos, and other non-regular
  entries are ignored.
