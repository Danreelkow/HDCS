state: s0 := SRC=/opt/data/workspace/hermes-context/; DST=/workspace/hermes-context/; mirror_class A9; no artifacts built yet; open: [].
Δ :=
1. Create sync-hermes-context.sh (bash, set -euo pipefail):
   1a. Env contract (A17/A23): SRC_ENV/DST_ENV/LOG_ENV unset->defaults (/opt/data/workspace/hermes-context/ , /workspace/hermes-context/ , ~/.cache/hermes-context/); set-empty->exit nonzero citing A23. Expect: empty env value -> refuse exit !=0.
   1b. Path guards (A12/A18/A22): realpath both; refuse if SRC==DST, ancestor/descendant (component-boundary), degenerate ('', '.', '/'), or DST is symlink — every refusal message cites an A-number. Expect: 4 synthetic bad-input cases each exit nonzero with A-citation.
   1c. Log dir (A8): only at real run, mkdir -p outside DST; verify realpath not under DST. Expect: dry-run leaves zero new dirs anywhere.
   1d. --dry-run mode (A6/A16): rsync --delete --dry-run path only, no mkdir, no log file, no mktemp; DST nonexistent-if-absent preserved. Expect: on absent DST, dry-run exit 0 and test -e DST = false; strace/stat shows no writes under DST or SRC.
   1e. Real run (A11/A13/A20/A23): validate log parent as pure string -> mktemp -d under it -> re-validate stage dir; run rsync -a --delete SRC/ STAGE/ ; if rsync absent or fails, rm -rf STAGE, mktemp again, cp -a SRC/. STAGE/ (A4/A5); content-verify stage vs SRC per A9 (contents+structure+symlinks, recursive; diff -r --no-dereference or equivalent; verify exit nonzero on mismatch); on verify success, mkdir -p DST, rsync -a --delete STAGE/ DST/ (or cp -a fallback), then rm -rf STAGE. Sync never writes SRC (A2). Bookkeeping dirs use mktemp random names (A20). Expect: real run exit 0; post-state DST == SRC per A9; rsync and cp -a paths both tested and converge; corrupted-stage test exits nonzero before touching DST.
2. Create hermes-context.service: Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh (or /workspace/hdcs/bin), no root. Expect: systemd-analyze verify user-unit clean.
3. Create hermes-context.timer: OnCalendar=*-*-* 00/6:00:00, Persistent=true, Unit=hermes-context.service. Expect: systemd-analyze verify clean.
4. Create README.md: usage, standalone vs systemd --user install, --dry-run semantics, env override contract, KNOWN_LIMITATIONS (A10/A14/A21 exotic filenames, adversarial env combos). Expect: documents all four MUST_KEEPs verbatim.
accept:
- [ ] artifact dir contains exactly: sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md; script passes bash -n and shellcheck (or noted KNOWN_LIMITATIONS).
- [ ] dry-run: exit 0, zero writes (no DST creation if absent, no log file, no tmp dirs); DST absent stays absent.
- [ ] real run rsync path: DST end state == SRC end state (contents+structure+symlinks, recursive); stale DST-only file deleted; exit 0.
- [ ] real run cp -a fallback (rsync masked): same convergence; verify exit nonzero when a mismatch is injected.
- [ ] guards: SRC==DST, ancestor/descendant, '', '.', '/', DST-symlink each refused nonzero with A-number citation; SRC never modified (checksum SRC before/after run).
- [ ] env: unset->defaults used; set-empty->refused nonzero.
- [ ] units verify via systemd-analyze --user; no root required anywhere.
- [ ] README contains the three MUST_KEEP strings verbatim and a KNOWN_LIMITATIONS section.
constraints:
- MUST_KEEP verbatim: "source path is /opt/data/workspace/hermes-context/", "dry-run mode that performs no writes", "systemd user units, no root required".
- A2: never write to SRC. A8: log dir + install paths outside DST. A11/A13: stage -> content-verify -> touch DST on both sync paths. A19/A24: no invented ownership scope; refusals cite A-numbers only from the register. A20: no fixed bookkeeping names colliding with SRC contents. A10/A14/A21: beyond-guard cases -> KNOWN_LIMITATIONS, not FAIL.
deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]