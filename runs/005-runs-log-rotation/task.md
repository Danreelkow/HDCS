Task: log/artifact rotation for HDCS run directories

/workspace/hdcs/runs/ accumulates per-run text artifacts (gate-out.txt, in.txt,
s*-out.txt, debrief-*.txt) forever. Deliver a self-contained rotation pair.
NO logrotate exists on this host; no root; plain bash + coreutils only.

Deliverable (all files in one artifact dir):
- hdcs-runs-rotation.conf — KEY=VALUE config (no comment lines): RUNS_DIR
  (default /workspace/hdcs/runs), ARCHIVE_DIR (default
  /workspace/.hdcs-rotate/archive), AGE_DAYS (default 14), PATTERN (default
  *.txt), KEEP (default 50)
- rotate-hdcs-runs.sh — default mode is DRY-RUN (lists planned moves, zero
  writes); --apply moves files matching PATTERN under RUNS_DIR older than
  AGE_DAYS into ARCHIVE_DIR preserving relative path, then prunes ARCHIVE_DIR
  to the newest KEEP archived files (oldest removed first); dry-run prunes
  nothing; env HDCS_RUNS_DIR / HDCS_ARCHIVE_DIR override the config; refuses
  degenerate/overlapping paths (identity, containment either way) with a
  cited A-number; idempotent. Stale means floor(age in days) >= AGE_DAYS: a
  file aged exactly AGE_DAYS rotates; note GNU find's bare `-mtime +N`
  excludes ages in the [N, N+1) day band, so implement the boundary
  explicitly
- verify-rotation.sh — exits 0 only when the tree is consistent: config
  parses, no rotation pending, archive listing intact (intact = the newest
  KEEP archived files are present and match their recorded listing).
  "Pending" means a STALE file (age >= AGE_DAYS); a fresh file matching
  PATTERN is normal and must NOT fail verify. Implement the stale scan as a
  flag accumulator (STALE_FOUND=0, set inside the find/while loop, tested
  after it) — a bare `[ cond ] && exit 1` pipeline reports false pending via
  bash subshell status when the last file is fresh
- README.md — install, configure, test with a dry run, schedule

MUST_KEEP: default mode is dry-run that performs no writes
MUST_KEEP: no root required and no logrotate dependency
MUST_KEEP: archived originals land outside the runs directory
MUST_KEEP: the config defines exactly the five keys RUNS_DIR, ARCHIVE_DIR, AGE_DAYS, PATTERN, KEEP
MUST_KEEP: the conf values are exactly RUNS_DIR=/workspace/hdcs/runs, ARCHIVE_DIR=/workspace/.hdcs-rotate/archive, AGE_DAYS=14, PATTERN=*.txt, KEEP=50 (builders never invent conf values)
