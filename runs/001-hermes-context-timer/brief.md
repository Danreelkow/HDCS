build brief → B1
state: s0 := dst=/workspace/hermes-context/ exists (INDEX.md, agents/, config/); src=/opt/data/workspace/hermes-context/ (host mount, read-only for us); no sync artifacts yet; systemd user units go in ~/.config/systemd/user/; no root available.
Δ := 
1. Write /workspace/hermes-context/sync-hermes-context.sh:
   - shebang #!/usr/bin/env bash; set -u -o pipefail
   - SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"; DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
   - DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
   - validate SRC is a directory; else log error, exit 1
   - mkdir -p DST (skip in dry-run)
   - if command -v rsync: base cmd = rsync -a --delete "SRC/" "DST/" (trailing slashes => contents sync, no nesting); dry-run adds --dry-run
   - elif cp available: dry-run => list files that would change (find SRC -newer marker or diff -rq SRC DST, read-only); else rm -rf DST contents (except script? no — script lives in /workspace/hermes-context/, not inside DST... DST IS /workspace/hermes-context/ — wait, DST holds INDEX.md etc. and script is sibling at /workspace/hermes-context/sync-hermes-context.sh which IS inside DST. cp fallback must NOT delete the script/units/README: use cp -a "SRC/." "DST/" without --delete semantics, or exclude script+units+README from deletion) — resolved: cp fallback = cp -a "SRC/." "DST/" (no delete; idempotent overwrite); tar pipe fallback = tar -C "$SRC" -cf - . | tar -C "$DST" -xf -
   - both fallbacks: dry-run => perform read-only comparison (diff -rq SRC DST) and report would-transfer count, zero writes
   - count transferred/skipped (rsync: parse --stats or use -i; fallback: diff -rq counts)
   - exactly one summary line to stdout+log: "mode=<sync|dry-run> tool=<rsync|cp|tar> dir=host->workspace transferred=N skipped=M status=<ok|error>"
   - any tool failure => nonzero exit, error to stderr, summary line with status=error
   - chmod +x script
   expected: executable script at /workspace/hermes-context/sync-hermes-context.sh; `bash -n` passes; `--dry-run` run exits 0, prints one summary line, DST mtimes/contents unchanged (checksum before/after identical)
2. Write /workspace/hermes-context/hermes-context.service:
   - [Unit] Description=Hermes context sync host->workspace
   - [Service] Type=oneshot; ExecStart=%h/workspace/hermes-context/sync-hermes-context.sh
   expected: valid ini; `systemd-analyze verify` (if available) passes or no systemd present => syntax check only
3. Write /workspace/hermes-context/hermes-context.timer:
   - [Unit] Description=Run hermes-context sync every 6h
   - [Timer] OnCalendar=*-*-* 00/6:00:00; Persistent=true; Unit=hermes-context.service
   - [Install] WantedBy=timers.target
   expected: valid ini; OnCalendar parses (systemd-analyze calendar '*-*-* 00/6:00:00' => valid, 6h cadence)
4. Write /workspace/hermes-context/README.md:
   - purpose, one-way direction, src/dst defaults + env overrides, --dry-run usage, standalone usage, install: cp units to ~/.config/systemd/user/ && systemctl --user daemon-reload && systemctl --user enable --now hermes-context.timer
   expected: README exists, mentions all four commands above verbatim
accept:
  - [ ] /workspace/hermes-context/sync-hermes-context.sh exists, executable (test -x), bash -n clean
  - [ ] script --dry-run: exit 0, exactly one summary line on stdout, zero writes to DST (stat/checksum of DST tree identical pre/post)
  - [ ] script real run: exit 0, one summary line, DST contents match SRC contents (diff -rq SRC DST empty), no /workspace/hermes-context/hermes-context/ nested dir (test ! -d)
  - [ ] second real run: exit 0, transferred=0 (idempotent)
  - [ ] script with HERMES_CONTEXT_SRC=/nonexistent: exit != 0, status=error line
  - [ ] hermes-context.service: Type=oneshot, ExecStart points to script path
  - [ ] hermes-context.timer: OnCalendar every 6h, Persistent=true, Unit=hermes-context.service
  - [ ] no line in any file invokes sudo/root/systemctl without --user
  - [ ] README.md documents dry-run, standalone run, and user-unit install steps
constraints: ["no_root: ~/.config/systemd/user/ + systemctl --user only", "one_way: never write to HERMES_CONTEXT_SRC", "dry_run: zero mutations of DST", "contents_sync: SRC/ -> DST/, never DST/hermes-context/", "fallback: rsync ? rsync : cp -a | tar pipe; both fail => nonzero exit + error line", "logging: exactly one summary line per run", "cp fallback must not delete script/units/README living inside DST (no --delete in fallback)"]
deliverable: ["/workspace/hermes-context/sync-hermes-context.sh", "/workspace/hermes-context/hermes-context.service", "/workspace/hermes-context/hermes-context.timer", "/workspace/hermes-context/README.md"]