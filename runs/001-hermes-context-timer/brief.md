build brief -> B1
state: s0 := validated hdcs/1 packet; artifact dir hermes-context-sync/ does not yet exist. Canonical facts: SRC=/opt/data/workspace/hermes-context/; DST=/workspace/hermes-context/ (contains INDEX.md, agents/, config/); one-way mirror host->workspace; rsync primary (rsync -a --delete), fallback cp -a + delete-reconciliation pass; identical end state either path; --dry-run => zero writes to DST and to log (even if HERMES_CONTEXT_LOG resides inside DST); systemd --user units (OnCalendar every 6h, WantedBy=default.target); script standalone-runnable without systemd and without rsync; never nest SRC inside DST; never write to SRC.
Δ := 
1. mkdir -p hermes-context-sync → output: directory hermes-context-sync/ exists.
2. Write hermes-context-sync/sync-hermes-context.sh → output: bash script with: set -euo pipefail; defaults SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/ overridable via HERMES_CONTEXT_SRC/HERMES_CONTEXT_DST; flags --dry-run and --log FILE (default ${HERMES_CONTEXT_LOG:-}, empty = no log); detect rsync via command -v; DRY_RUN branch: if rsync present, run `rsync -a --delete --dry-run "$SRC"/ "$DST"/` printing the itemized plan to stdout only, else print planned actions (files to copy, entries to delete) computed read-only; return before any mkdir/log/write; REAL_RUN branch: mkdir -p "$DST"; if rsync: `rsync -a --delete "$SRC"/ "$DST"/`; else `mkdir -p "$DST"` + `cp -a "$SRC"/. "$DST"/` + reconciliation pass: iterate `find "$SRC" -mindepth 1 -maxdepth 1 -printf '%f\n'`, delete any entry in DST not present in SRC (use find on DST top level, rm -rf -- path); write log line (timestamp, mode, path) only in real-run, appending to log file only if log path non-empty; exit 0. → output: executable script (chmod +x), `bash -n` passes.
3. Write hermes-context-sync/hermes-context.service → output: [Unit] Description=Hermes context mirror; [Service] Type=oneshot; ExecStart=%h/.local/bin/sync-hermes-context.sh (note in README to install script there or use absolute path); no User= directive (user unit).
4. Write hermes-context-sync/hermes-context.timer → output: [Unit] Description=Run hermes context sync every 6h; [Timer] OnCalendar=*-*-* 00/6:00:00; Persistent=true; [Install] WantedBy=default.target.
5. Write hermes-context-sync/README.md → output: documents purpose, SRC/DST env vars, --dry-run semantics (zero writes incl. log), fallback behavior, standalone usage, `systemctl --user daemon-reload; systemctl --user enable --now hermes-context.timer`, no root required.
6. Self-check (verify before handoff): run `bash hermes-context-sync/sync-hermes-context.sh --dry-run` against a temp fixture dir (populate via HERMES_CONTEXT_SRC/HERMES_CONTEXT_DST overrides) twice with a stale file in DST → output: stale file still present after both dry-runs; no log file created.
7. Convergence check: in temp fixture, real-run with rsync, snapshot `find dst -printf '%P %y\n' | sort`; reset dst, real-run with PATH stripped of rsync → output: both snapshots identical (rsync path ≡ fallback path end state).

accept:
- hermes-context-sync/ contains exactly: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md.
- `bash -n sync-hermes-context.sh` exits 0; script is executable.
- grep confirms: `--delete` present in rsync invocation; `OnCalendar=` present with 6h cadence; `WantedBy=default.target` in timer; no `User=` root directive in either unit.
- test: real-run with rsync vs real-run with rsync unavailable produce identical `find "$DST" -printf '%P %y\n' | sort` output.
- test: `--dry-run` leaves DST byte-identical (`diff -r` before/after empty) and creates/modifies no log file, even when HERMES_CONTEXT_LOG points inside DST.
- test: file present in DST but absent in SRC is deleted by both real-run paths.
- test: DST listing never contains top-level entry named after SRC basename (no nesting).
- script runs successfully when invoked directly with no systemd and no rsync on PATH.

constraints:
- one-way: no writes to /opt/data/workspace/hermes-context/ ever (only reads).
- --dry-run => zero writes to any fs target including log; dry-run output to stdout only.
- user units only; WantedBy=default.target; no root.
- sync contents of SRC into DST (SRC/. → DST/), never nest SRC dir itself inside DST.
- fallback must reconcile deletions to match rsync --delete; no accumulate-only mode.
- single artifact dir; no resurrection of stray files elsewhere.
- logging only on real runs.

deliverable: [hermes-context-sync/sync-hermes-context.sh, hermes-context-sync/hermes-context.service, hermes-context-sync/hermes-context.timer, hermes-context-sync/README.md]