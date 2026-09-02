# hdcs-runs-rotation

Rotate stale files out of a runs directory into an archive directory.
Pure bash + coreutils (`find`, `cmp`, `realpath`, `cksum`, `mv`, `sort`, `awk`).
No logrotate, no root required.

## Files

- `hdcs-runs-rotation.conf` — config, exactly five keys:
  `RUNS_DIR`, `ARCHIVE_DIR`, `AGE_DAYS`, `PATTERN`, `KEEP`.
- `rotate-hdcs-runs.sh` — dry-run planner (default) and `--apply` writer.
- `verify-rotation.sh` — read-only state verifier.

## Usage

    ./rotate-hdcs-runs.sh            # dry-run: prints planned moves, writes nothing
    ./rotate-hdcs-runs.sh --apply    # performs the rotation
    ./verify-rotation.sh             # exit 0 iff state is consistent

### Dry-run

Prints each planned move as `<src> -> <dst>` and creates nothing — no
`ARCHIVE_DIR`, no state files. Exit 0.

### Apply

- Validates paths (A4) before any write.
- `mkdir -p` on `ARCHIVE_DIR`.
- Finds files matching `PATTERN` with age ≥ `AGE_DAYS` under `RUNS_DIR`.
  Selection is exact: a file is stale iff its mtime is at or before
  `now − AGE_DAYS days`. GNU `find`'s rounded `-mtime +N` predicate would
  skip files whose age falls inside the N-day bucket, so it is NOT used;
  both scripts select with `! -newermt "$AGE_DAYS days ago"` instead,
  which matches every file with age ≥ AGE_DAYS inclusive of the threshold.
- Moves each to `ARCHIVE_DIR/<name>.<n>` (`.1`, incremented to `.2`, `.3`, …
  if the destination already exists).
- Byte-losslessness is verified with `cmp` against a snapshot; a failed
  verification leaves the source in place and exits ≥1.
- KEEP pruning: after moves, the oldest archived matching entries beyond
  `KEEP` are deleted. `KEEP >= 0` prunes; `KEEP < 0` = unlimited (no pruning).
- A second consecutive `--apply` with nothing stale is zero-action: exit 0,
  no moves, no new state.

## Environment overrides

`HDCS_RUNS_DIR` and `HDCS_ARCHIVE_DIR` override the corresponding conf values.
A variable that is set but empty is refused (A4). All path law refusals —
equal paths, containment in either direction, degenerate (`''`, `.`, `/`),
set-but-empty — exit ≥1 with a message citing `A4`, before any write.

## Exit codes

- `rotate-hdcs-runs.sh`: `0` success or zero-action; `≥1` any refusal/failure.
- `verify-rotation.sh`: `0` consistent (conf parses, no stale match under
  RUNS_DIR, archive listing consistent); `2` malformed conf; `≥1` otherwise.
  Verify never writes.

## KNOWN_LIMITATIONS

- Exotic filenames: names containing newlines, or beginning/ending with
  whitespace, are not handled specially; the tooling may misreport them.
  This is a documented limitation, not a tool failure (A7).
- Races: a file created or modified concurrently between the stale scan and
  the move may be rotated or skipped inconsistently; no locking is performed.
  Documented limitation (A7).
- Only regular files are rotated; symlinks, fifos, and other non-regular
  entries are ignored.
