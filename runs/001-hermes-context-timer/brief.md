build brief for B1 (hcdl register)

state: s0 := artifact dir {sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md}; SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/; log=~/.cache/hermes-context-sync.log (outside DST, always); systemd USER units (systemctl --user, no root), timer OnCalendar every 6h; rsync --delete primary, cp -a fallback with recursive delete-reconciliation; --dry-run = zero writes incl. logs, gated by DST byte-identity; guards per A11/A12; self-verify per A9 (contents+structure+symlinks only, FAIL nonzero); standalone-capable without systemd.

Δ :=
1. Write sync-hermes-context.sh (bash, set -euo pipefail):
   1a. Arg parse: --dry-run flag only; SRC/DST from env HERMES_CONTEXT_SRC/HERMES_CONTEXT_DST, defaults per defs.
   expected: `bash -n` clean.
   1b. Identity guards BEFORE any destructive op, both paths: realpath(SRC)==realpath(DST) -> clean nonzero exit, zero writes; DST realpath is ancestor of SRC realpath or resolves through symlink into SRC -> same refusal. SRC missing -> nonzero, no writes.
   expected: equality/ancestor/symlink-into-SRC tests all exit nonzero, log and DST untouched.
   1c. --dry-run mode: rsync -rlptgoD --dry-run --delete when rsync present; else print planned copy/delete list via `find`-based diff, no writes. All logging suppressed (no log file creation/appends). Exit 0.
   expected: snapshot DST (find | sort + cksum of contents incl. symlinks) before and after dry-run — byte-identical; no log file exists or modified.
   1d. Live sync, rsync path: `rsync -rlptgoD --delete SRC/ DST/`; log appended to ~/.cache (mkdir -p log dir if needed — log dir must not be inside DST; if inside DST, abort nonzero per A8).
   expected: mirror converges; log line appended outside DST.
   1e. Live sync, cp fallback (rsync absent): copy SRC -> DST via cp -a of contents (src/ -> dst/, no nesting); then delete-reconciliation: walk DST recursively, remove any file/symlink absent in SRC and any empty/unmatched dir at EVERY depth (implements A7, converges to rsync --delete end state). Never rm -rf DST wholesale before copy succeeded (A11).
   expected: with seed corpus, end state == rsync --delete end state (compare via diff -r + symlink listing).
   1f. Self-verify after live sync (A9): recursive compare DST vs SRC on {file contents (byte), dir structure, symlink targets/existence}; ignore timestamps/metadata/hardlink topology. Mismatch -> print diff, exit nonzero (never warn-and-exit-0).
   expected: seeded content/dir/symlink mutations each cause nonzero exit; clean mirror exits 0.
2. Write hermes-context.service (Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh or chosen install path; User-level, no root).
   expected: `systemd-analyze verify` clean (or no-error for user unit).
3. Write hermes-context.timer (OnCalendar=*-*-* 00/12:00:00 equivalent: every 6h, e.g. OnCalendar=00/6:00:00; WantedBy=timers.target; Persistent=false).
   expected: `systemd-analyze verify` clean.
4. Write README.md documenting: SRC/DST defaults + env override; --dry-run zero-write semantics (A6 gate wording); rsync vs cp fallback with recursive delete (A5/A7); log placement outside DST (A8); install paths outside mirrored tree; mirror class limits (A9: no timestamps/metadata/hardlinks); KNOWN_LIMITATIONS section: newline-in-filename corpora, DST-under-log-dir misconfig (repro notes, non-blocking, per A10); sync-strategy section states recursive stale-subtree deletion at every depth.
   expected: README contains sections matching A5/A6/A7/A8/A9/A10 claims verbatim in substance.

accept:
- [ ] `bash -n sync-hermes-context.sh` passes.
- [ ] Dry-run: byte-identical DST snapshot (contents incl. symlinks, structure) before/after; zero log writes.
- [ ] SRC==DST, ancestor, and symlink-into-SRC guards each exit nonzero pre-destructive; both sync paths guarded.
- [ ] Live sync end state == rsync --delete end state on both rsync-present and fallback paths (seeded corpus with stale files/subdirs/symlink changes).
- [ ] Fallback deletes stale subtrees at depth ≥2.
- [ ] Self-verify FAILs nonzero on seeded content, structure, and symlink mismatches; passes on clean mirror.
- [ ] No log file inside DST in any mode; log default ~/.cache/hermes-context-sync.log.
- [ ] Units verify as USER units; no root anywhere; timer fires every 6h.
- [ ] Script runs standalone with systemctl absent.
- [ ] README documents A5–A10 incl. KNOWN_LIMITATIONS with repro notes.

constraints:
- log outside DST unconditionally (A8); abort if log dir inside DST.
- install paths outside mirrored tree; sync never deletes own entrypoints.
- no rm -rf DST before verified source copy exists (A11).
- path-identity guards before ANY destructive op, both paths (A12).
- dry-run = zero writes of any kind (A6).
- self-verify enforces exactly A9 class; FAIL nonzero, never warn-and-exit-0.
- one-way host->workspace; nothing writes back to SRC.

deliverable: [sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md]