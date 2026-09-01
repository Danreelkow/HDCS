state: s0 := artifact dir /workspace/hermes-context/ absent; SRC=/opt/data/workspace/hermes-context/ exists (A1); DST=/workspace/hermes-context/ (A1); logs default to ~/.cache/hermes-context/ (outside DST, A8); units target ~/.config/systemd/user/; script standalone-capable (A3); sync one-way host->workspace (A2); rsync primary w/ cp -a fallback (A4); guards per closed law list {A12, A14/A15, A18} (A19); stage->verify->touch order is law (A11, A13, A20, A22).

Δ :=
1. Create /workspace/hermes-context/.
   → expected: dir exists.
2. Write sync-hermes-context.sh, executable, standalone + systemd-invokable:
   a. Parse --dry-run; dry-run => perform ALL guards, print plan/diff only, ZERO writes incl. no log file, no stage dir, must NOT create DST if absent (A6, A16).
   b. Env: SRC=${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}, DST=${HERMES_CONTEXT_DST:-/workspace/hermes-context/}, LOG_DIR=${HERMES_CONTEXT_LOG_DIR:-$HOME/.cache/hermes-context} (A17).
   c. Guards, each refusal exits nonzero citing its A-number (A19): empty/"."/"/" via component test (A18); realpath(SRC)==realpath(DST), ancestor/descendant, or DST symlink resolving into SRC — checked on both paths, pre-destruction (A12); DST path-level symlink -> REFUSE, never replace (A22); realpath(DST) ==/inside/contains OWNED_PATH (script stage dir, LOG_DIR, entrypoint dir) via component-boundary-aware comparison, never string prefix (A14, A15).
   d. Stage path: compute as pure string under validated parent, validate, THEN create via mktemp -d under that parent + re-validate instantiated path; TMPDIR failure -> script-owned fallback stage (A20, A22).
   e. Sync SRC CONTENTS into stage (no nesting): rsync -a --delete if present, else cp -a + explicit recursive stale-subtree deletion at every depth (A4, A5, A7).
   f. Content-compare stage vs SRC on MIRROR_CLASS exactly {file contents, recursive structure, symlinks}; mismatch -> nonzero exit, never warn-exit-0 (A9, A13, A21).
   g. Only after VERIFIED stage: real run mkdir -p DST if absent, then atomically promote stage content to DST achieving exact mirror incl. stale deletion; log one line to LOG_DIR (outside DST); dry-run reaches no step beyond (f) print (A6, A8, A11, A13, A16).
   h. Idempotent: rerun on mirrored DST -> no changes, exit 0.
   → expected: executable script; guard refusals print A-number; dry-run on nonexistent DST leaves DST nonexistent; real run produces exact mirror.
3. Write hermes-context.service (user unit): ExecStart=entrypoint script path, Type=oneshot.
   → expected: valid user unit, no root.
4. Write hermes-context.timer: OnCalendar=6h Persist=true; WantedBy=timers.target.
   → expected: valid user timer.
5. Write README.md: documents SRC/DST defaults + env override, --dry-run zero-write guarantee, cp -a fallback deletes stale subtrees at every depth, MIRROR_CLASS scope (not timestamps/hardlinks), DST-symlink refusal (operator removes manually), KNOWN_LIMITATIONS entries (newline/control-char filenames; adversarial env combos closed by A14 citation).
   → expected: README states fallback deletion correctly; never calls unverified copy "verified" (A13); KNOWN_LIMITATIONS present.
6. Install entrypoint copy to ~/.config/systemd/user/ units target and verify: systemctl --user daemon-reload; systemctl --user enable --now hermes-context.timer.
   → expected: timer active; `systemctl --user list-timers hermes-context.timer` shows scheduled run.

accept:
- [ ] sync-hermes-context.sh executable, runs standalone; bash -n clean.
- [ ] Guards: SRC=DST, DST inside SRC, DST="/" / "" / ".", DST symlink (path-level and into-SRC), DST==LOG_DIR — each exits nonzero citing A12/A14/A15/A18/A22 respectively; DST=/workspace/data/hermes-context-sibling NOT refused (A15 calibration).
- [ ] Dry-run: on absent DST leaves DST absent; on existing DST leaves DST byte-identical; creates no log, no stage dir (A6, A16).
- [ ] Real run with rsync present: DST end state == SRC on MIRROR_CLASS; stale files/subtrees at all depths deleted; rsync absent: cp -a fallback achieves same (A4, A5, A7).
- [ ] Verification: mismatch corpus -> nonzero exit; matching corpus -> exit 0 (A9).
- [ ] Stage pipeline: no mktemp-before-validate (A20); no DST destruction before VERIFIED stage exists (A11, A13).
- [ ] Log line written to LOG_DIR, outside DST; sync never deletes entrypoints/logs (A8).
- [ ] Idempotent: second run no changes, exit 0.
- [ ] hermes-context.service/.timer installable via systemctl --user; timer enabled and scheduled.
- [ ] README: fallback deletion documented, MIRROR_CLASS scope, dry-run zero-write, KNOWN_LIMITATIONS (2 entries), no "verified" mislabel (A13, A21).

constraints:
- "refusals must cite an A-number (A19); no refusal outside closed law list {A12, A14/A15, A18}"
- "dry-run purity: zero writes of any kind incl. logs and stage dirs (A6)"
- "stage->content-verify->touch-DST order on every destructive path (A11, A13)"
- "MIRROR_CLASS only: no timestamps/hardlink preservation requirements (A9)"
- "entrypoints + logs outside DST tree (A8)"
- "line budget per file: script <= ~250 lines; total brief artifacts = 4 files"
- "DST symlink refused, never replaced (A22)"

deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]