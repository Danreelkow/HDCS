build brief → B1
state: s0 := {SRC=/opt/data/workspace/hermes-context/; DST=/workspace/hermes-context/ pre-existing (INDEX.md, agents/, config/); LOG=~/.cache/hermes-context/sync.log; units=systemd --user; rsync-first w/ cp -a fallback; exact mirror w/ delete; dry-run zero writes; entrypoints/LOG never inside DST; no root}.
Δ := 
1. write sync-hermes-context.sh: shebang bash, set -euo pipefail, SRC/DST/LOG via env defaults (SRC default literal "/opt/data/workspace/hermes-context/", DST default "/workspace/hermes-context/", LOG default "$HOME/.cache/hermes-context/sync.log"); parse --dry-run; trap cleanup.
   expected: script parses; --dry-run path returns before any mkdir/touch/echo-to-log; normal path logs exactly one summary line.
2. mirror logic: if command -v rsync → `rsync -a --delete "$SRC"/ "$DST"/` (trailing slash: contents, no nest); else fallback: reconcile recursively — copy missing/changed files (cp -a), remove stale files/dirs in DST not in SRC (find-based, all depths).
   expected: both paths converge DST == SRC recursively byte-identical, stale deleted; SRC never nested under DST.
3. dry-run: enumerate actions to stdout only; zero writes incl. no log dir creation, no log append; DST unchanged.
   expected: `--dry-run` run leaves DST byte-identical and no LOG file/dir.
4. write hermes-context.service: [Service] Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh.
   expected: unit references user path, no root/system paths.
5. write hermes-context.timer: [Timer] OnCalendar=*-*-* 00/6:00:00, Persistent=true, Unit=hermes-context.service.
   expected: 6h schedule, user unit.
6. write README.md: states exact mirror semantics (recursive, stale deleted, all depths), rsync-first + cp fallback, --dry-run zero writes, install steps via systemctl --user, no root.
   expected: README claims match implementation incl. A5/A6/A7/A8.
7. verify: bash -n script; shellcheck if available (non-fatal); grep MUST_KEEP string in script.
   expected: bash -n exit 0; MUST_KEEP line present.
accept:
 - all four files exist in artifact dir; bash -n passes
 - script default SRC literal is "/opt/data/workspace/hermes-context/" (grep-verifiable)
 - rsync branch uses -a --delete with trailing slashes; fallback deletes stale entries recursively
 - --dry-run executes with zero writes (no LOG path touched, DST mtime/content unchanged)
 - no string "/workspace/hermes-context/" used as log or bin target in script/units (A8)
 - units are user units (no root, no [Install] requiring root); timer OnCalendar 6h
 - re-run of script (no changes in SRC) yields no spurious DST Δ and one log line
constraints: [MUST_KEEP SRC default verbatim; A2 one-way; A5 byte-identical convergence both paths; A6 dry-run zero writes incl. logs; A8 LOG/entrypoints never in DST; I7 idempotent; I9 one summary line per real run; no root anywhere; script standalone-capable without systemd]
deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]