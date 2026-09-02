# hdcs rotation triad

Rotates stale `*.txt` files (age >= 14 days) from the hdcs runs directory into
an archive directory, preserving relative subpaths and file contents.

## Files

- `hdcs-runs-rotation.conf` — exactly five KEY=VALUE lines:
  `RUNS_DIR=/workspace/hdcs/runs`, `ARCHIVE_DIR=/workspace/.hdcs-rotate/archive`,
  `AGE_DAYS=14`, `PATTERN=*.txt`, `KEEP=50`. Unknown keys are refused.
- `rotate-hdcs-runs.sh` — the rotator.
- `verify-rotation.sh` — the verifier.

## Usage

Dry-run (default; zero writes, A1):

    ./rotate-hdcs-runs.sh

Apply (sole writing mode):

    ./rotate-hdcs-runs.sh --apply

Verify:

    ./verify-rotation.sh

## Environment overrides

`HDCS_RUNS_DIR` and `HDCS_ARCHIVE_DIR` override the conf values. A set-but-empty
variable is a refusal (A4). Path law: equal, mutually containing, or degenerate
(`''`, `.`, `/`) paths are refused citing A4, with zero writes.

## Behavior

- Dry-run lists would-be moves and creates nothing.
- Apply moves only files with mtime >= AGE_DAYS; each file is copied to the
  archive, byte-compared (`cmp`) against the source, and only then removed from
  the source (A5 lossless). Name collisions get a `.1`, `.2`, ... suffix.
- After each apply, the rotator writes a cksum manifest
  (`.hdcs-rotation-manifest`) inside the archive listing every archived file.
- A second `--apply` finds zero candidates and is a no-op; the archive (and its
  manifest) remain cksum-identical (A5 idempotence).
- Verify exits 0 iff the conf parses with exactly 5 keys, no pending rotation
  exists under RUNS_DIR, the archive directory exists with at least one archived
  file within KEEP, and the archive's cksum listing matches the stored manifest
  (A6). Otherwise it exits nonzero with a reason line.

## Known limitations (A7)

Exotic filenames and concurrent writes during `--apply` are known limitations,
not failures.
