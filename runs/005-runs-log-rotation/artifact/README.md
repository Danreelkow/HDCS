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

Both scripts honor env overrides `HDCS_RUNS_DIR` / `HDCS_ARCHIVE_DIR` (also
`HDCS_AGE_DAYS` / `HDCS_PATTERN` / `HDCS_KEEP`). Unset vars fall back to the conf
defaults; a var that is **set but empty** is refused (A4). The effective `PATTERN`
override governs the stale scan in both scripts **and** the archive orphan check in
`verify-rotation.sh` — it is never ignored in favor of a hardcoded glob.

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
- **Idempotence:** a second `--apply` on an already-rotated tree moves nothing and
  prunes nothing — byte-identical no-op.

## Verify semantics

`verify-rotation.sh` is strictly read-only and accumulates every check into a
flag counter (A7) — the exit status of every `grep` and every `find` scan is
accumulated too, never suppressed by a bare pipeline status or `2>/dev/null`.
The conf check is a strict line-by-line parse: every line must be one of exactly
the 5 `KEY=verbatim` lines; any malformed line (garbage, unknown key, wrong
value, duplicate key, wrong line count) is a parse failure. Checks: conf parses
with exactly the 5 keys and verbatim values; no stale file remains under
`RUNS_DIR`; archive listing is intact (names preserved with rotation suffixes
matched against the effective `PATTERN`, no orphans); a fresh `PATTERN` match
present in `RUNS_DIR` does **not** fail. Exit 0 ⇔ all checks pass. Path-law
violations are reported as refusals citing `A4`.

## Path law (A4)

Degenerate paths (`''`, `.`, `/` — checked before and after `realpath`
canonicalization), identity (`RUNS_DIR == ARCHIVE_DIR`), and containment in
either direction are refused with an explicit `REFUSE (A4)` before any write.

## KNOWN_LIMITATIONS

- Exotic filenames (newlines in names, control characters) are handled via
  NUL-delimited `find` where possible; archive prune ranking tolerates spaces
  but not newlines in names → listed here, not a FAIL.
- Concurrent writers appending to `RUNS_DIR` during `--apply` may produce a
  `cmp` mismatch on a live file; the source is then kept and a warning emitted
  (lossless is preferred over partial rotation) → KNOWN_LIMITATIONS, not FAIL.
- Equal-mtime prune ties resolve deterministically per run (sequence tie-break).
