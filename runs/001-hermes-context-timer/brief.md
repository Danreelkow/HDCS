**BUILD BRIEF → B1** | reg: cs-devops-shell-systemd | s0+Δ → S1 | report: +done / -resolved / +open / +validation
```
state: s0 := {
  SRC := /opt/data/workspace/hermes-context/ ; read-only ∀ run [A2]
  DST := /workspace/hermes-context/ ; exists (INDEX.md, agents/, config/) [A1]
  rsync availability unknown -> detect (command -v), else FB = tar-pipe + recursive delete-reconcile [A4]
  mirror := one-way host->workspace, recursive, stale deleted; ∀{RS,FB} end state == SRC end state [A5_mirror]
  units := user-scoped systemctl --user, no root; script standalone-capable [A3]; cadence 6h [A7]
  DR := zero writes ∀ target incl. logs; gate = DST byte-identical pre/post [A6]
  env := HERMES_CONTEXT_SRC | HERMES_CONTEXT_DST | HERMES_CONTEXT_LOG ; defaults = canonical paths
}
Δ := [
  1. mkdir -p ./artifact (= <artifact_dir>); author sync-hermes-context.sh (#!/usr/bin/env bash; set -euo pipefail).
     expected: file exists; bash -n -> 0
  2. defaults first: SRC=${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/};
     DST=${HERMES_CONTEXT_DST:-/workspace/hermes-context/};
     LOG=${HERMES_CONTEXT_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/sync-hermes-context.log} (default OUTSIDE DST so exact-mirror [A5] holds).
     expected: all 3 var names + 2 canonical path literals verbatim in file
  3. parse --dry-run: print plan (add/update/delete lists + counts) to stdout ONLY; exit 0 before ANY write syscall; log untouched.
     expected: accept-b gate passes
  4. real run: mkdir -p DST; if command -v rsync -> RS: rsync -a --delete "${SRC%/}/" "${DST%/}/" (trailing slash = contents, ¬nesting);
     if LOG resolves inside DST add --exclude=<relpath>.
     expected: literal "rsync -a --delete" present; accept-c/d gates pass
  5. FB (rsync absent): (cd "${SRC%/}" && tar -cf - .) | tar -xf - -C "${DST%/}"; then bottom-up reconcile ∀ depth:
     rm every DST path (files, then emptied dirs) absent in SRC; skip LOG path if inside DST.
     expected: accept-c gate passes with identical end state as RS
  6. summary: ONE appended line per real run only -> "$LOG": "<utc-ts> mode=RS|FB copied=N deleted=N status=OK|FAIL"; DR writes no log line.
     expected: accept-f gate passes
  7. author hermes-context.service: [Unit] Description; [Service] Type=oneshot; ExecStart=<abs artifact_dir>/sync-hermes-context.sh.
     expected: accept-g verify clean
  8. author hermes-context.timer: [Timer] OnCalendar=*-*-* 00/6:00:00; Persistent=true; Unit=hermes-context.service;
     [Install] WantedBy=timers.target.
     expected: verify clean; both canon identifiers present
  9. chmod +x script; author README.md covering: install (cp units -> ~/.config/systemd/user/, systemctl --user daemon-reload,
     systemctl --user enable --now hermes-context.timer), standalone run, --dry-run test, env vars, mirror semantics (--delete / FB reconcile).
     expected: 5 topics present; exec bit set
]
accept: [
  a. bash -n ./artifact/sync-hermes-context.sh == 0
  b. [A6] sha256-tree(DST ∪ LOG-path) byte-identical pre/post `./artifact/sync-hermes-context.sh --dry-run` (run once with LOG ∈ DST too); exit 0; stdout non-empty
  c. [A5] RS==FB: plant stale file + nested stale subtree (≥2 levels) in DST -> RS removes both, diff -r DST SRC empty; restore; force FB (PATH w/o rsync) -> byte-identical end state incl. subtree deletion
  d. [A4] ¬nesting: top-level(DST) == top-level(SRC); no DST/src/
  e. [A2] sha256-tree(SRC) byte-identical pre/post every test invocation (RS, FB, DR)
  f. idempotency: two consecutive real runs -> log gains exactly 1 line each; diff(DST) pre/post run-2 empty
  g. [A3] systemd-analyze --user verify hermes-context.service hermes-context.timer -> 0; units contain no User=/root
  h. env: scratch SRC/DST pair via HERMES_CONTEXT_* -> mirror semantics hold; HERMES_CONTEXT_LOG honored on real run, untouched on DR
]
constraints: [
  ∀ run ¬writes(SRC) — log never located in SRC [A2]
  DR -> zero writes ∀ target incl. logs; byte-identity gate [A6]
  ∀ path ∈ {RS,FB}: DST end state == SRC end state, recursive, stale deleted [A5_mirror]
  no_root_required; units user-scoped [MUST_KEEP]; SRC verbatim /opt/data/workspace/hermes-context/ [MUST_KEEP]
  rsync absent -> FB with identical semantics [A4]; script idempotent; one-line summary log per real run only
  canon ids: rsync, tar, OnCalendar, WantedBy=timers.target, HERMES_CONTEXT_SRC|DST|LOG
]
deliverable: [./artifact/sync-hermes-context.sh, ./artifact/hermes-context.service, ./artifact/hermes-context.timer, ./artifact/README.md]
```