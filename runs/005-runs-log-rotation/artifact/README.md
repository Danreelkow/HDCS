# hdcs runs rotation

Rotates stale log files out of `RUNS_DIR` into `ARCHIVE_DIR`, preserving relative
paths, and prunes the archive to a bounded size. Pure `bash` + coreutils (`find`,
`cmp`, `realpath`, `cksum`); no root, no logrotate. All `find`/`stat` usage is
POSIX-portable (no `find -printf`), so the toolchain also works under BusyBox.

## Files

| file | role |
|---|---|
| `hdcs-runs-rotation.conf` | operator-fixed configuration, exactly 5 keys, no comments |
| `rotate-hdcs-runs.sh` | rotation tool — **dry-run by default**; `--apply` is the sole writing mode |
| `verify-rotation.sh` | zero-write checker; exit 0 iff the rotated state is healthy |

## Usage

```sh
./rotate-hdcs-runs.sh          # dry-run: prints planned moves/prunes, performs ZERO writes
./rotate-hdcs-runs.sh --apply  # sole writing mode: move stale files, prune archive
./verify-rotation.sh           # exit 0 <=> healthy state; writes nothing
```

Both scripts honor env overrides `HDCS_RUNS_DIR` / `HDCS_ARCHIVE_DIR` **only** —
these are the sole supported environment overrides. Unset vars fall back to the
conf defaults; a var that is **set but empty** is refused (A4). `AGE_DAYS`,
`PATTERN`, and `KEEP` are operator-fixed conf values and are never overridden by
the environment.

## Configuration (`hdcs-runs-rotation.conf`)

| key | value | meaning |
|---|---|---|
| `RUNS_DIR` | `/workspace/hdcs/runs` | source tree of run logs |
| `ARCHIVE_DIR` | `/workspace/.hdcs-rotate/archive` | destination tree (`RUNS_DIR/<rel>` → `ARCHIVE_DIR/<rel>`) |
| `AGE_DAYS` | `14` | staleness boundary in days |
| `PATTERN` | `*.txt` | `find -name` pattern selecting files |
| `KEEP` | `50` | newest files kept in `ARCHIVE_DIR`; older ones pruned (`KEEP=0` prunes the entire archive) |

## Stale boundary

A file is **stale** iff `floor((now − mtime) / 86400) >= AGE_DAYS`, computed with
explicit epoch arithmetic (never bare `find -mtime +N`). A file with age exactly
`AGE_DAYS − 1 day 23h` is **not** moved; a file aged exactly `AGE_DAYS` days
**is** moved. Boundary files are rotated like any other stale file.

## Apply semantics

- `mkdir -p ARCHIVE_DIR`, then each stale file is copied to
  `ARCHIVE_DIR/<relative path under RUNS_DIR>`; on a name collision a rotation
  suffix `.1`, `.2`, … is appended. The copy is `cmp`-verified byte-identical to
  the source **before** the source is removed (lossless, move-once).
- Pruning touches `ARCHIVE_DIR` **only** — `RUNS_DIR` is never pruned. Prune
  candidates are ranked newest-first by mtime (deterministic tie-break) and
  trimmed to `KEEP` entries; `KEEP=0` prunes every archived file (the bound is
  never skipped).
- **Idempotence (A5):** a second `--apply` on an already-rotated tree moves nothing
  and prunes nothing — byte-identical no-op.

## Verify semantics

`verify-rotation.sh` is strictly read-only: its only writes go to a `mktemp -d`
scratch dir **outside** the artifact dir, `RUNS_DIR`, and `ARCHIVE_DIR`
(component-overlap tested; a `TMPDIR` falling inside any protected tree is
rejected and `/tmp` is used instead), removed on exit; stderr goes only to the
caller's stderr (A6). Every check uses the mandatory flag accumulator —
`STALE_FOUND=0` is set inside the find/while loop and tested **after** the loop;
the conf parse, archive listing, and every `cksum`/`cmp` status are accumulated
via `note_fail`, never a bare `[ cond ] && exit 1`:

- conf parses: KEY=VALUE lines counted with blanks/`#` comments ignored; the shipped
  conf must contain exactly 5 keys with verbatim values.
- stale scan: no stale file may remain under `RUNS_DIR` (a fresh PATTERN match is
  normal and does **not** fail).
- archive intact ("newest KEEP present ∧ matches recorded listing"): a listing of
  every archived file (**mtime**, cksum, size, path) is recorded into the scratch
  dir **first**; a second, independent pass re-cksums, re-sizes, and re-stat-mtimes
  each file and compares per-entry against the recorded values — a file whose
  bytes/size/mtime changed between the two passes, or an entry that appeared or
  vanished, is a failure. The newest-KEEP condition is then established by:
  - **count bound:** the archived file count must not exceed `KEEP`; and
  - **rotation-suffix family order:** for every archived `base.N`, the family's
    newest copy (`base`, or `base.(N−1)` for intermediate suffixes) must be present
    with mtime ≥ `base.N`'s — i.e. the newest generation of every archived stream
    survives the prune. An arbitrarily old subset masquerading as the archive
    (missing the newest copy of a family, or a suffix newer than its un-numbered
    base) fails verification.
  Names must match the effective `PATTERN` + rotation suffix (no orphans).
- an absent `ARCHIVE_DIR` with no stale pending is healthy (exit 0).

Path-law violations are reported as refusals citing `A4`.

## Path law (A4)

Degenerate paths (`''`, `.`, `/` — checked before and after `realpath`
canonicalization), identity (`RUNS_DIR == ARCHIVE_DIR`), and containment in
either direction are refused with an explicit `REFUSE (A4)` before any write.

## KNOWN_LIMITATIONS

- Exotic filenames (newlines in names, control characters) are handled via
  NUL-delimited `find` where possible; archive prune ranking tolerates spaces
  but not newlines in names → listed here, not a FAIL (A7).
- Concurrent writers appending to `RUNS_DIR` during `--apply` may produce a
  `cmp` mismatch on a live file; the source is then kept and a warning emitted
  (lossless is preferred over partial rotation) → KNOWN_LIMITATIONS, not FAIL (A7).
- Equal-mtime prune ties resolve deterministically per run (sequence tie-break).
- The verify archive-intact check detects byte/size/mtime mutation between its
  two passes, count-bound violations, and missing/newest-copy violations within
  rotation-suffix families; files pruned in earlier runs are no longer present,
  so verify cannot prove that no *pruned* file was newer than a *kept* one
  outside family structure (no persistent state is kept — verify is zero-write).
