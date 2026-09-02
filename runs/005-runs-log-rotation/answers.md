A1: Dry-run is the default and is zero-write: it may not create ARCHIVE_DIR, the
    archive, or any state file. --apply is the only writing mode.
A2: Pure bash + coreutils (find, cmp, realpath, cksum). logrotate does not exist
    on this host; invoking it is a defect. No root anywhere.
A4: Path law mirrors run 001: refuse RUNS_DIR == ARCHIVE_DIR, containment in
    either direction, degenerate paths ('', '.', '/'); refusals cite A-numbers
    and perform zero writes. Env HDCS_RUNS_DIR / HDCS_ARCHIVE_DIR override the
    conf; set-but-empty refuses.
A5: Idempotence: rotation is move-once (age threshold); a second --apply must be
    a zero-action no-op leaving ARCHIVE_DIR byte-identical. Archived bytes must
    equal originals (cmp), file names preserved with a rotation suffix.
A6: verify-rotation.sh: exit 0 only when (a) conf parses, (b) no file matching
    PATTERN is older than AGE_DAYS still under RUNS_DIR, (c) every archived file
    exists and is listed consistently; nonzero otherwise.
A7: Exotic filenames / concurrent writes during apply are KNOWN_LIMITATIONS, not FAIL.

OPERATOR RULING (2026-09-02, Danreelkow): A6 extends — verify-rotation.sh must run
against a STRICTLY READ-ONLY artifact dir (rotated tree included): it reads, never
writes. Any scratch/state/output it needs goes to a fresh temp dir (mktemp -d),
never the artifact dir, never RUNS_DIR/ARCHIVE_DIR. A verifier grades; it does not
edit. Non-destructive by construction.

CONF FORMAT (S4 finding, accepted): hdcs-runs-rotation.conf may contain blank lines
and comments (#). verify-rotation.sh counts KEY=VALUE lines and ignores blanks/
comments — a trailing blank line is NOT a parse failure. The conf artifact itself
must still ship as exactly the 5 KEY=VALUE lines (no stray blanks).

CONF TOLERANCE SEMANTICS (operator, precise): "conf parses" means — exactly the 5
KEY=VALUE lines are present; blank lines and #-comment lines are IGNORED; any other
non-empty, non-comment line (garbage, duplicate keys, malformed KEY=VALUE) is a PARSE
FAILURE and verify exits nonzero. Tolerant of whitespace, strict about content.
