state: s0 := canon=cs-programming (rsync --delete/--dry-run, systemctl --user + OnCalendar, POSIX sh, cp -a/tar pipe, exit codes); SRC=/opt/data/workspace/hermes-context/ DST=/workspace/hermes-context/ LOG=~/.cache/hermes-context/sync.log; invariants A2,A4(contents/fallback),A5(mirror+delete),A6(dry-run zero writes),A7(recursive stale delete),A8(LOG∉DST, entrypoints∉tree),A9(verify contents+dirs+symlinks, mismatch→nonzero),A10; timer=systemctl --user, 6h; script standalone-capable. Δ := 1) write sync-hermes-context.sh: POSIX sh, set -eu; args: --dry-run only; env-overridable SRC/DST/LOG; mkdir -p LOG dir; choose rsync if command -v rsync else fallback.
   expected: script accepts --dry-run, exit 0 on success, nonzero on verify mismatch or missing SRC.
2) rsync path: rsync -a --delete --dry-run(optional, implies -n) "$SRC" "$DST" (trailing-slash semantics = contents of SRC into DST); no -H/-A/-X (metadata excluded per A9).
   expected: DST == mirror of SRC contents incl. --delete; no nesting.
3) fallback path: rm -rf DST.contents then cp -a "$SRC"/. "$DST"/ (or tar -C SRC -cf - . | tar -C DST -xf -), so stale files/subtrees at every depth are removed (A5/A7); identical semantics both paths.
   expected: fallback converges DST to SRC, stale recursive removal.
4) logging: on non-dry-run runs append one line to LOG: timestamp, mode(rsync|fallback), dry-run?, result. In --dry-run: skip ALL writes incl. LOG (A6).
   expected: normal run appends exactly one LOG line; dry-run appends zero lines, DST byte-identical.
5) self-verify (A9): recursively compare {file contents (cmp), dir structure, symlink targets} SRC vs DST; on mismatch print diff and exit nonzero — never warn-exit-0. Skip verification in --dry-run.
   expected: mismatch → exit≠0; match → exit 0.
6) write hermes-context.service: Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh, User-level only (no root), [Install] WantedBy=default.target.
   expected: unit valid for systemctl --user.
7) write hermes-context.timer: [Timer] OnCalendar=*-*-* 0/6:00:00, Persistent=true, Unit=hermes-context.service.
   expected: 6h cadence via OnCalendar, user timer.
8) write README.md: usage (standalone run, --dry-run), install paths (~/.local/bin, ~/.config/systemd/user/), systemctl --user enable --now hermes-context.timer, one-way semantics, exact-mirror/delete-stale warning, dry-run purity, LOG location, KNOWN_LIMITATIONS (newline-in-filename corpora, DST=LOG misconfig), verify exit-code contract.
   expected: README states recursive stale deletion and that LOG/install paths are outside the mirrored tree.
9) deliver files to /workspace/hdcs/bin/ (script) + unit/README files as listed; do NOT place deliverables inside SRC or DST.
   expected: four files exist outside both SRC and DST.
accept:
  - sync-hermes-context.sh: `--dry-run` run over live SRC/DST leaves DST byte-identical and creates/appends zero files anywhere (incl. LOG); exit 0.
  - normal run (rsync present): after adding a stale file to DST, run sync → stale file gone, DST contents≡SRC, one LOG line appended, exit 0.
  - fallback run (rsync absent via PATH shim or forced mode): stale nested subtree removed at depth≥2, DST≡SRC, exit 0.
  - corrupt a file in DST → verify exits nonzero with mismatch report.
  - symlink in SRC → same symlink (same target) present in DST.
  - units: `systemd-analyze verify` passes; timer OnCalendar yields 6h cadence; no root required.
  - LOG path ∉ DST; deliverables ∉ SRC ∧ ∉ DST.
constraints: [A2 one-way no writeback; A5 --delete both paths, no accumulate-only; A6 dry-run zero writes incl. logs; A7 recursive stale deletion, README states it; A8 LOG/entrypoints outside mirrored tree; A9 verify contents+structure+symlinks, mismatch→nonzero, never warn-exit-0; A10 exotic triggers → README KNOWN_LIMITATIONS, non-blocking; POSIX sh only, no root, metadata/timestamps excluded from equivalence class]
deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]