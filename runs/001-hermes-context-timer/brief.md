build brief → B1
state: s0 := artifact dir /workspace/hermes-context-artifact/ absent; src=/opt/data/workspace/hermes-context/, dst=/workspace/hermes-context/; user-level systemd; rsync primary, cp -a fallback.
Δ:
1. mkdir -p /workspace/hermes-context-artifact → dir exists.
2. Write sync-hermes-context.sh (POSIX sh, set -eu):
   - SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}", DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"
   - DRY=0; parse --dry-run → DRY=1
   - mkdir -p "$DST" (skip in dry-run)
   - if command -v rsync: rsync -a --delete ${DRY:+--dry-run} "$SRC"/ "$DST"/
   - else fallback: if DRY=1 → print "[dry-run] would copy $SRC/ -> $DST/ (cp -a fallback)", zero writes; else find "$SRC" -mindepth 1 -maxdepth 1 | while read f: rm -rf "$DST/$(basename "$f")" then cp -a "$f" "$DST"/ (delete-then-copy ≈ --delete)
   - one-line summary: echo "sync-hermes-context: src=$SRC dst=$DST mode=$([ $DRY = 1 ] && echo dry-run || echo run) tool=$TOOL files=$(count)"
   - chmod +x → expected: executable script, src/ contents → dst/ (no nesting), dry-run writes nothing.
3. Write hermes-context.service:
   [Unit] Description=Hermes context one-way sync
   [Service] Type=oneshot
   ExecStart=%h/workspace/hermes-context-artifact/sync-hermes-context.sh
   → expected: valid user unit, no User=, no root.
4. Write hermes-context.timer:
   [Unit] Description=Run hermes-context sync every 6h
   [Timer] OnCalendar=*-*-* 00/6:00:00
   Persistent=true
   [Install] WantedBy=timers.target
   → expected: valid user timer, 6h cadence.
5. Write README.md: install steps (cp units to ~/.config/systemd/user/, systemctl --user daemon-reload, systemctl --user enable --now hermes-context.timer), standalone usage, env vars, dry-run flag, fallback note → expected: doc covers all.
accept:
- test -x /workspace/hermes-context-artifact/sync-hermes-context.sh
- sh -n sync-hermes-context.sh exits 0
- DRY_RUN check: HERMES_CONTEXT_DST=/tmp/dst-test ./sync-hermes-context.sh --dry-run → /tmp/dst-test unchanged (no dir created if absent)
- run twice: ./sync-hermes-context.sh; ./sync-hermes-context.sh → second run output identical state; ls /workspace/hermes-context/ shows INDEX.md, agents/, config/ at top level, no hermes-context/ subdir
- grep -q 'User=' hermes-context.service → false
- grep -q 'OnCalendar=\*-\*-\* 00/6' hermes-context.timer → true
- grep -q -- '--delete' sync-hermes-context.sh → true
- grep -q 'command -v rsync' sync-hermes-context.sh → true
- all 4 files exist under /workspace/hermes-context-artifact/
constraints: [one-way host→workspace only; --dry-run zero writes in rsync AND fallback paths; idempotent convergence; user units only (no User=, no root); fallback via command -v rsync; sync src/ contents → dst, never dst/hermes-context/; POSIX sh only; ≤60 lines script]
deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]