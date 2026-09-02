# hdcs-runs-rotation

Rotate stale files out of a runs directory into an archive directory, with a
dry-run default, lossless idempotent apply, and an honest verifier.

## Usage

    ./rotate-hdcs-runs.sh           # dry-run (default): prints would-move actions, zero writes
    ./rotate-hdcs-runs.sh --dry-run # same, explicit
    ./rotate-hdcs-runs.sh --apply   # perform the moves
    ./verify-rotation.sh            # A6 verifier

Configuration is read from `hdcs-runs-rotation.conf` (RUNS_DIR, ARCHIVE_DIR,
PATTERN, AGE_DAYS). Environment variables `HDCS_RUNS_DIR`, `HDCS_ARCHIVE_DIR`,
`HDCS_PATTERN`, `HDCS_AGE_DAYS` override the conf values.
Install location: alongside this README (scripts resolve the conf relative to
their own directory), e.g. `/workspace/.hdcs-rotate/`.

## A1 — dry-run zero-write

Default mode (no arguments) and `--dry-run` perform NO writes: no archive
directory is created, no file in RUNS_DIR is touched, modified, or moved.

## A2 — toolchain

bash + coreutils only. No root required. No logrotate anywhere.

## A4 — path-law refusals

Identity (RUNS_DIR == ARCHIVE_DIR), containment (either inside the other), and
degenerate paths ('', '/', '.', or RUNS_DIR nonexistent/not a directory) are
refused with an A4-citing stderr message, exit 2, and zero writes.

## A5 — lossless idempotence

Each candidate is moved once to a mirrored relative path under ARCHIVE_DIR;
if the destination exists, a name-preserving suffix (`.1`, `.2`, …) is added.
The original is confirmed gone after the move. A second `--apply` finds no
remaining candidates and is a no-op (exit 0, archive unchanged).

## A6 — verifier criteria

`verify-rotation.sh` exits 0 if and only if: the conf parses, no pending
rotation exists (no RUNS_DIR file matches PATTERN older than AGE_DAYS), and
the archive is consistent (exists only if moves were made; no archived path
still pending in RUNS_DIR; ARCHIVE_DIR outside RUNS_DIR). It exits nonzero on
pending rotation or any inconsistency.

## KNOWN_LIMITATIONS (A7)

Exotic filenames (newlines, control characters, extremely long names) and
concurrent modification races during apply are not exhaustively handled; the
verifier reports them as limitations rather than FAILs where detection is
unreliable. Symlinked entries inside RUNS_DIR are not followed (only regular
files are candidates).
