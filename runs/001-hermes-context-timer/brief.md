build brief → B1
state: s0 := SRC=/opt/data/workspace/hermes-context/ (exists); DST=/workspace/hermes-context/ (exists, contains INDEX.md, agents/, config/); direction one-way SRC→DST; mirror class {contents, structure, symlinks}; rsync primary, cp -a/tar fallback; systemd --user timer every-6h + standalone exec; log default ~/.cache/sync-hermes-context.log (never in DST); guards A11/A12/A14/A15; order stage→verify(content-compare)→touch DST; --dry-run zero writes incl. logs.
Δ := 
1. Write sync-hermes-context.sh (bash, set -euo pipefail):
   1.1 env-overridable SRC/DST/LOG defaults per s0; expected output: script parses with `bash -n`.
   1.2 guards: [ "$SRC" = "$DST" ] abort; [ "$(realpath -e "$SRC")" = "$(realpath -e "$DST")" ] abort; protected-path check: for each owned concrete path P, abort if P == DST or DST is boundary-aware prefix of P (compare path components, not string prefix). Expected: guard tests exit nonzero with message on stderr.
   1.3 --dry-run flag: compute plan (rsync -ain --delete or fallback listing), print one-line summary, write nothing — no DST writes, no log file creation. Expected: post-run `find DST -newer marker` empty; no log file created.
   1.4 sync path A (rsync present): stage to `mktemp -d` sibling of DST → `rsync -a --delete --copy-links=no "$SRC"/ "$STAGE"/` (preserve symlinks as symlinks; no metadata beyond A9 class). Expected: STAGE populated.
   1.5 sync path B (no rsync): `rm -rf "$STAGE"/*` then `cd "$SRC" && tar cf - . | (cd "$STAGE" && tar xf -)`; deletions: after verify, replace DST contents wholesale (rm -rf DST/* + hidden) so deletions propagate. Expected: STAGE == SRC contents incl. symlinks.
   1.6 verify: content-compare STAGE vs SRC boundary-aware (diff -r --no-dereference or per-file cmp; symlinks compared by target). Mismatch → cleanup STAGE, exit nonzero. Expected: verified copy or nonzero exit.
   1.7 touch DST: rsync path → `rsync -a --delete "$STAGE"/ "$DST"/`; fallback path → `rm -rf "$DST"/* "$DST"/.[!.]* "$DST"/..?* 2>/dev/null; cp -a "$STAGE"/. "$DST"/`. Expected: DST end state == SRC end state (contents+structure+symlinks).
   1.8 log one-line summary (timestamp, path, counts) to LOG only on real runs; mkdir -p log dir; log path asserted ∉ DST. Expected: log line appended, outside DST.
   1.9 exit 0 on success; nonzero on any guard/verify failure.
2. Write hermes-context.service: [Unit] Description; [Service] Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh (or installed path), Environment overrides allowed. Expected: `systemd-analyze verify` clean.
3. Write hermes-context.timer: [Timer] OnCalendar=*-*-* 00/6:00:00, Persistent=true, Unit=hermes-context.service; [Install] WantedBy=timers.target. Expected: verify clean.
4. Write README.md: install steps (cp script to ~/.local/bin, units to ~/.config/systemd/user/, systemctl --user daemon-reload/enable --now timer), change-source (env SRC/DST override), dry-run test procedure, KNOWN_LIMITATIONS (exotic env combos only). Expected: doc covers all three.
accept:
- bash -n sync-hermes-context.sh passes; shellcheck no errors (warnings ok).
- `./sync-hermes-context.sh --dry-run` → exit 0, DST byte-identical (checksum before/after), no log file created.
- `./sync-hermes-context.sh` → exit 0; `diff -r --no-dereference SRC DST` empty; file deleted in SRC then rerun → absent in DST.
- SRC==DST invocation → nonzero, DST untouched.
- DST set to a protected owned path → nonzero, no writes.
- rsync removed from PATH → fallback path yields same end state (diff -r empty).
- verify-failure injection (corrupt STAGE) → nonzero exit, DST untouched.
- systemd-analyze verify passes both units; timer OnCalendar every-6h; no root required anywhere.
- log file located outside DST; install paths outside /workspace/hermes-context/.
- must_keep 3/3 verbatim present across deliverables.
constraints: [A2 one-way no writeback; A5/A7 exact mirror recursive deletions; A6 dry-run zero writes; A8 log/install ∉ DST; A9 mirror class only, verify mismatch → nonzero; A11/A12 identity guards abort pre-destructive; A13 stage→verify→touch; A14/A15 boundary-aware protected-path guard; user units only, no root; standalone exec without systemd; ≤60 lines per file not required but keep script compact]
deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]