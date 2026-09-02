# HDCS runs rotation

`rotate-hdcs-runs.sh` rotates matching files from the runs tree into the
archive tree while preserving each file's relative path.

## Configuration

The fixed production configuration is in `hdcs-runs-rotation.conf`:

- `RUNS_DIR=/workspace/hdcs/runs`
- `ARCHIVE_DIR=/workspace/.hdcs-rotate/archive`
- `AGE_DAYS=14`
- `PATTERN=*.txt`
- `KEEP=50`

The directory settings can be overridden for a single invocation with
`HDCS_RUNS_DIR` and `HDCS_ARCHIVE_DIR`. An unset override uses the configured
production value; a set-but-empty override is rejected. Overlapping, equal,
empty, dot, and root paths are rejected with an A4 diagnostic.

## Usage

The default invocation is a dry run and only lists files that would be
rotated:

```sh
HDCS_RUNS_DIR=/workspace/hdcs/runs \
HDCS_ARCHIVE_DIR=/workspace/.hdcs-rotate/archive \
./rotate-hdcs-runs.sh
```

No archive directory or state file is created during a dry run. To perform the
rotation, use:

```sh
./rotate-hdcs-runs.sh --apply
```

Apply mode copies each stale file to its archived relative path, compares the
archived bytes with the original before removing the original, and writes an
archive checksum listing. Repeating apply is idempotent. If an archive path
already exists with different bytes, a numeric suffix is used. The archive is
pruned to the newest `KEEP` archived files.

A file is stale when:

```text
floor(age_days) >= AGE_DAYS
```

Thus a file exactly 14 complete days old is stale with the supplied
configuration, while a file only 13 complete days old is not.

Verification is read-only:

```sh
./verify-rotation.sh
```

It fails if a stale matching file remains in the runs directory, if the archive
checksum listing is absent or does not match its files, if an archive file is
missing from the recorded listing, or if the archive has no recorded entries.

## KNOWN_LIMITATIONS (A7)

Exotic filenames containing newline or pipe characters are not supported by the
human-readable checksum manifest format. Concurrent writes while rotation or
verification is running are also outside the consistency guarantee.
