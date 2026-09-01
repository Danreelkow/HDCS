build brief for B1
state: s0 := {SRC=/opt/data/workspace/hermes-context/ (env HERMES_CONTEXT_SRC override), DST=/workspace/hermes-context/ (env HERMES_CONTEXT_DST override); one-way host->workspace; exact mirror class = contents+dirs+symlinks recursive, stale deleted; primary rsync -a --delete, fallback cp -a/tar-pipe full reconcile; guards A11/A12 realpath pre-flight; order stage->verify->reconcile; --dry-run zero writes incl. logs; log ~/.cache/hermes-context/sync.log; user units 6h OnCalendar; artifact_dir ./hermes-context-freshness/}
Δ := 
1. write sync-hermes-context.sh:
   1a. parse --dry-run flag; resolve SRC/DST via realpath; guard: reject nonzero, no writes, iff realpath(SRC)==realpath(DST) | ancestor/descendant | DST resolves inside SRC. Expected: guard block ~15 lines, exits 2 on violation before any write.
   1b. dry-run path: rsync -a --delete --dry-run -v SRC/ DST/ (or fallback: diff -r listing only); print planned actions to stdout only; no log file created. Expected: zero filesystem writes, exit 0.
   1c. real run rsync path: rsync -a --delete SRC/ DST/ (trailing slash, no nesting). Expected: DST mirrors SRC recursively.
   1d. fallback path (rsync absent): stage to mktemp -d outside DST; cp -a SRC/. STAGE/ (or tar -C SRC -cf - . | tar -C STAGE -xf -); verify stage vs SRC via diff -r (A9 class); only then reconcile: delete DST subtrees not in SRC (find-based, all depths), rsync-less copy stage->DST, remove stale; rm -rf stage only after verify. Expected: end state == SRC; verify fail => exit nonzero, DST untouched.
   1e. verify step (both paths): diff -r SRC DST (or stage) recursive; symlink targets compared; mismatch => nonzero exit, message to stderr. Expected: exit 0 iff A9-class mirror holds.
   1f. logging: one-line summary appended to ~/.cache/hermes-context/sync.log (mkdir -p ~/.cache/hermes-context); skipped entirely in dry-run; log path never under DST. Expected: single line per real run: timestamp + mode + status.
   1g. idempotent: second run with no changes => no-op writes, exit 0.
2. write hermes-context.service: [Service] Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh. Expected: user unit, no root, no %S writes into DST.
3. write hermes-context.timer: [Timer] OnCalendar=*-*-* 0/6:00:00, Persistent=true, Unit=hermes-context.service. Expected: 6h cadence.
4. write README.md: usage (--dry-run, manual run, install commands: cp to ~/.local/bin, units to ~/.config/systemd/user/, systemctl --user enable --now hermes-context.timer), mirror semantics (contents+structure+symlinks; metadata excluded), guards, KNOWN_LIMITATIONS section (newline-in-filename fallback diff edge; hostile symlink/log-dir combos), "verified" wording only for content-compared copies (A13 law). Expected: must_keep trio stated verbatim.
5. shellcheck -s bash all .sh; bash -n syntax check. Expected: clean.
accept:
- ./hermes-context-freshness/ contains exactly: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md
- bash -n sync-hermes-context.sh exits 0; shellcheck exits 0 (or only A10-class informational)
- grep confirms: trailing-slash rsync SRC/ DST/ (no DST/SRC nesting); --delete present; --dry-run present; realpath guard present pre-flight
- dry-run test: run with --dry-run; find DST -newer marker file created pre-run => no changes; no sync.log created/modified
- real-run test: create file in SRC, run, file exists in DST; delete file in SRC, run, file absent in DST; nested dir mirrored recursively; symlink target preserved
- guard test: HERMES_CONTEXT_DST=$SRC run => nonzero exit, DST/SRC untouched
- fallback test: PATH without rsync, repeat mirror test => identical end state, stale subtree deleted at depth≥2
- verify-fail test: corrupt staged copy => nonzero exit, DST byte-identical
- grep README: contains verbatim "source path is /opt/data/workspace/hermes-context/", "dry-run mode that performs no writes", "systemd user units, no root required"
- grep units: OnCalendar 6h cadence; no root/User= directives; ExecStart under %h
- log path check: grep confirms log target ~/.cache/hermes-context/, no DST-path log writes
constraints:
- writes only to artifact_dir during build; never write SRC or DST during build/testing except via explicit test runs of the script itself
- A12 guard before any destructive op, both sync paths
- A13: no DST touch before content-verify passes; verify fail => nonzero, DST untouched
- A8: log ∈ ~/.cache, install ∈ ~/.local/bin, never in DST
- A9: verify enforces contents+structure+symlinks recursive; mismatch never warn-and-exit-0
- A11: rm -rf of DST content only after verified stage exists
- no root anywhere; units are user units
- script standalone-capable without systemd
deliverable: [./hermes-context-freshness/sync-hermes-context.sh, ./hermes-context-freshness/hermes-context.service, ./hermes-context-freshness/hermes-context.timer, ./hermes-context-freshness/README.md]