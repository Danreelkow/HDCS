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

### Conf grammar (L_conf)

The shipped conf contains exactly 5 `KEY=VALUE` lines. Both scripts parse it
with the same strict grammar: blank lines and lines beginning with `#` are
ignored; **any other non-empty, non-comment line is a parse failure** (nonzero
exit in `rotate-hdcs-runs.sh`, a recorded failure in `verify-rotation.sh`);
each of the 5 keys must appear **exactly once** (a missing key or a duplicate
key is a parse failure); a total count other than 5 is a parse failure. A parse
failure never performs any write.

## Stale boundary

A file is **stale** iff `floor((now − mtime) / 86400) >= AGE_DAYS`, computed with
explicit epoch arithmetic (never bare `find -mtime +N`). A file with age exactly
`AGE_DAYS − 1 day 23h` is **not** moved; a file aged exactly `AGE_DAYS` days
**is** moved. Boundary files are rotated like any other stale file.

## Scratch discipline (zero-write guarantee, A1/A6)

Both scripts create their scratch directory via `mktemp -d` at a base that is
**verified — with a path-component test, never a string prefix — to lie OUTSIDE
`RUNS_DIR` and `ARCHIVE_DIR`** (verify also excludes the artifact dir). The check
runs twice: once on the candidate **base** (`TMPDIR`, else `/tmp`) and again on the
**instantiated** `mktemp` result — a base outside the trees does not by itself
guarantee the concrete created path is. A `TMPDIR` pointing into either protected
tree is therefore rejected and `/tmp` is used instead; if no safe base exists,
the script refuses (verify records the failure through the accumulator; rotate
exits nonzero with `REFUSE (A4)`). No scratch byte is ever written inside
`RUNS_DIR`, `ARCHIVE_DIR`, or the artifact tree, in any mode.

## Traversal discipline (find status is never discarded; pipeline masking banned)

Every `find` in both scripts writes its listing to a scratch file so that
`find`'s **exit status** is captured and its stderr is inspected:

- `rotate-hdcs-runs.sh`: a failed or error-reporting `RUNS_DIR` traversal is a
  hard refusal (zero writes) — a skipped stale file must never silently violate
  the rotation law. `prune_select`'s exit status is **always tested explicitly**:
  its output is redirected to a scratch file and iterated from there — never
  consumed through a pipeline whose last stage (`while …`) would mask a traversal
  failure with exit 0. A failed `ARCHIVE_DIR` traversal aborts the prune (and the
  dry-run plan) with a nonzero exit; refusing to prune from a partial listing is
  the lossless choice. A file that cannot be `stat`ed during prune selection is
  likewise a hard refusal, not a warning-skip.
- `verify-rotation.sh`: a failed or error-reporting traversal of `RUNS_DIR`
  (stale scan or fresh scan) or of `ARCHIVE_DIR` (integrity scan) is recorded
  through the `note_fail` accumulator — an unreadable subdirectory makes the
  scan **incomplete**, and an incomplete scan can never yield exit 0. The same
  holds for every per-file `stat` inside any scan (stale scan AND fresh scan):
  a failed stat is recorded via `note_fail` — never silently ignored. This
  closes the "protected subdirectory hides stale files / archive entries" hole.

## Apply semantics

- `mkdir -p ARCHIVE_DIR`, then each stale file is copied to
  `ARCHIVE_DIR/<relative path under RUNS_DIR>`; on a name collision a rotation
  suffix `.1`, `.2`, … is appended. The copy is `cmp`-verified byte-identical to
  the source **before** the source is removed (lossless, move-once).
- **Failure discipline (apply):** EVERY step in the writing path is
  status-checked — parent-directory `mkdir`, `cp`, the `cmp` verification, the
  source `rm -f`, and each prune `rm -f`. Any failure is reported to stderr,
  accumulated in `APPLY_FAIL`, and the run exits **nonzero**. `--apply` never
  reports success while a stale file remained unrotated, a copy was not verified,
  a source removal failed, or a prune removal failed.
- Pruning touches `ARCHIVE_DIR` **only** — `RUNS_DIR` is never pruned. Prune
  candidates are ranked newest-first by mtime (deterministic tie-break) and
  trimmed to `KEEP` entries; `KEEP=0` prunes every archived file (the bound is
  never skipped).
- **Idempotence (A5):** a second `--apply` on an already-rotated tree moves nothing
  and prunes nothing — byte-identical no-op.

## Verify semantics

`verify-rotation.sh` is strictly read-only: its only writes go to a `mktemp -d`
scratch dir **outside** the artifact dir, `RUNS_DIR`, and `ARCHIVE_DIR`
(component-tested on both the base and the instantiated path; a `TMPDIR` falling
inside any protected tree is rejected and `/tmp` is used instead), removed on
exit; stderr goes only to the caller's stderr (A6). Even the scratch-creation
failure is reported through the accumulator pattern (no direct early exit
bypasses it). Every check uses the mandatory flag accumulator — `STALE_FOUND=0`
is set inside the find/while loop and tested **after** the loop; the conf parse,
archive listing, every `cksum`/`cmp` status, and every `find` traversal status
are accumulated via `note_fail`, never a bare `[ cond ] && exit 1`. All
archive-listing work (recording, per-entry re-verification, orphan detection,
checksum collection) runs in the **main shell** — never inside a
command-substitution subshell — so every `note_fail`/flag update persists to the
final exit code:

- conf parses: strict L_conf grammar (see above) — KEY=VALUE lines counted with
  blanks/`#` comments ignored, malformed lines rejected, each of the 5 keys
  required exactly once with verbatim values.
- stale scan: no stale file may remain under `RUNS_DIR` (a fresh PATTERN match is
  normal and does **not** fail). The scan's `find` exit status and stderr are
  captured into the scratch dir; a nonzero status or any stderr output means the
  scan was incomplete and is recorded as a failure — an unreadable subdirectory
  cannot hide stale files behind an exit 0.
- archive intact — **recorded listing + per-entry live verification**: the
  archive is scanned once (with `find` status captured — a failed traversal fails
  the integrity check outright) and a listing of every archived file
  (`mtime cksum size relpath`, ranked newest-first) is recorded into the scratch
  dir. Then **every recorded entry is verified individually against the live
  filesystem**: the file at `ARCHIVE_DIR/<relpath>` must still exist (a deleted
  archived original fails) and its freshly computed `cksum`/size/mtime must
  equal the recorded values (a mutated or replaced file fails per entry). A
  recorded entry that vanished, or a file whose bytes/size/mtime changed since
  recording, is detected **per entry** — not merely as a whole-set diff. Orphan
  names and unreadable/unchecksumable files fail in the same main-shell loop.
- **archive-name law (strict rotation suffix):** an archive file name is legal
  iff it matches `PATTERN` exactly, OR matches `PATTERN` followed by a `.` plus
  **one or more digits and nothing else**. The suffix is validated strictly by
  stripping a `\.[0-9]+$` tail and re-testing the stripped base against
  `PATTERN` — so `run.txt.1` is legal, but `run.txt.1garbage` (a digit followed
  by trailing characters) is an **orphan** and fails verification. The lax
  glob form `PATTERN.[0-9]*` is deliberately avoided: in a `case` glob,
  `[0-9]*` means "one digit followed by anything", which would wrongly accept
  such garbage-suffixed names.
- newest KEEP present: the archived count must not exceed `KEEP` — a count above
  `KEEP` means the retained set is not the newest-`KEEP` window (older-than-KEEP
  files were retained) and is a failure. When the count is `<= KEEP` and every
  recorded entry exists and matches live, the full retained (newest-`KEEP`) set
  is present and byte-identical — the two L_verify conditions (newest KEEP
  present AND matches the recorded listing) both hold. The apply-side prune
  retains exactly the newest `KEEP` entries and removes the rest, so a
  conforming archive never exceeds `KEEP`.
- an absent `ARCHIVE_DIR` with no stale pending is healthy (exit 0).

Path-law violations are reported as refusals citing `A4`.

### Exit status law (accumulator capping)

The verification exit status is **never** the raw accumulator value. Shell exit
statuses are taken modulo 256, so a failure count that is a multiple of 256
(e.g. exactly 256 stale files detected in the stale-scan loop) would wrap to 0
and a failing verification would exit 0 — violating the "exit 0 iff" contract.
Instead: `FLAGS -eq 0` → exit 0; any `FLAGS -ne 0` → a **fixed nonzero status**
(exit 1), with the true failure count printed to stderr (`verify: N failure(s)
recorded`). The accumulator still counts every distinct failure for reporting;
only the process exit status is capped to {0, 1}.

## Path law (A4)

Degenerate paths are refused with an explicit `REFUSE (A4)` before any write,
**both on the original string and after `realpath -m` canonicalization**:
`''`, `.`, `/` literally, and any value that canonicalizes to the current
directory (`./`, `foo/..`, trailing-slash cwd forms) or to `/` (`/tmp/../..`).
The post-canonicalization test compares against the **canonicalized current
directory** (`realpath -m '.'`), because `realpath -m` never returns the literal
string `.` — comparing against `'.'` would silently accept `./` and `foo/..`.
Identity (`RUNS_DIR == ARCHIVE_DIR`) and containment in either direction are
likewise refused.

## KNOWN_LIMITATIONS

- Exotic filenames (newlines in names, control characters) are handled via
  NUL-delimited `find` where possible; archive prune ranking tolerates spaces
  but not newlines in names → listed here, not a FAIL (A7).
- Concurrent writers appending to `RUNS_DIR` during `--apply` may produce a
  `cmp` mismatch on a live file; the source is then kept, the failure is
  accumulated, and the run exits **nonzero** (lossless is preferred over partial
  rotation) → KNOWN_LIMITATIONS, not FAIL (A7).
- Equal-mtime prune ties resolve deterministically per run (path tie-break).
- Verify keeps no persistent state across runs (zero-write): its recorded
  listing is taken at verification time, so a deletion/mutation is detected only
  from the moment of recording onward (the per-entry live re-verification closes
  the within-run window); a pruned-then-deleted file from a run before the
  checker ever ran leaves no trace to verify against.
