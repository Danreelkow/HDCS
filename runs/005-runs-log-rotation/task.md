Task: log/artifact rotation for HDCS run directories

/workspace/hdcs/runs/ accumulates per-run text artifacts (gate-out.txt, in.txt,
s*-out.txt, debrief-*.txt) forever. Deliver a self-contained rotation pair.
NO logrotate exists on this host; no root; plain bash + coreutils only.

Deliverable (all files in one artifact dir):
- hdcs-runs-rotation.conf — KEY=VALUE config: RUNS_DIR (default
  /workspace/hdcs/runs), ARCHIVE_DIR (default /workspace/.hdcs-rotate/archive),
  AGE_DAYS (default 14), PATTERN (default *.txt), KEEP (default 50)
- rotate-hdcs-runs.sh — default mode is DRY-RUN (lists planned moves, zero
  writes); --apply moves files matching PATTERN under RUNS_DIR older than
  AGE_DAYS into ARCHIVE_DIR preserving relative path; env HDCS_RUNS_DIR /
  HDCS_ARCHIVE_DIR override the config; refuses degenerate/overlapping paths
  (identity, containment either way) with a cited A-number; idempotent
- verify-rotation.sh — exits 0 only when the tree is consistent: config parses,
  no rotation pending, archive listing intact
- README.md — install, configure, test with a dry run, schedule

MUST_KEEP: default mode is dry-run that performs no writes
MUST_KEEP: no root required and no logrotate dependency
MUST_KEEP: archived originals land outside the runs directory
