state: s0 := SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/; laws A1–A19 certified no-ambiguity; artifact dir hermes-context-sync/ pending. Δ := B1 builds:
1. Create hermes-context-sync/sync-hermes-context.sh (bash, set -euo pipefail):
   - Parse --dry-run flag; all guards run before any write.
   - Guards (each refusal exits nonzero printing cited A-number):
     a. SRC/DST empty, ".", "/" by component test → refuse A18.
     b. realpath(SRC)==realpath(DST), ancestor/descendant, DST symlink resolving into SRC → refuse A12.
     c. realpath(DST) vs owned set {stage mktemp -d dir, resolved log parent, entrypoint dir}: refuse equal/⊂/⊃ by component-boundary comparison → refuse A14/A15.
     d. SRC==DST pre-mutation → refuse A11.
     e. DST symlink resolving outside SRC → refuse A18; DST symlink resolving inside tree (post-guards) → replace with real dir.
   - Resolve rsync: if command -v rsync → plan `rsync -rl --delete --dry-run` / real `rsync -rl --delete`; else fallback cp: stage=$(mktemp -d), `cp -a SRC/. stage/`, then swap. Both paths converge to identical A9-class end state (contents+structure+symlinks, recursive, stale deleted).
   - Order law: stage → content-verify staging vs SRC per A9 levels 1–3 (recursive cmp of contents, structure, symlink targets; mismatch → exit nonzero, never warn-exit-0) → only then mutate DST: mkdir -p DST, atomically replace tree, delete stale subtrees. No rm -rf DST before verified copy exists (A11,A13).
   - --dry-run purity: zero writes — no log file, no mktemp, no DST mkdir, no DST touch; dry-run leaves DST byte-identical/nonexistent (A6,A16).
   - Log: real runs append to ${HERMES_CONTEXT_LOG:-$HOME/.cache/hermes-context/sync.log}; parent mkdir -p (real runs only); log ∉ DST always (A8).
   - Standalone-capable: runs under cron/manual identically (no systemctl dependency in script).
   Expected output: executable script, `bash -n` clean, `shellcheck` no errors (warnings acceptable, listed).
2. Create hermes-context.service: [Unit] Description; [Service] Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh (or /workspace/hdcs/bin path), user-level only, no root.
   Expected output: ExecStart points outside DST, no User=/sudo directives.
3. Create hermes-context.timer: [Timer] OnCalendar=*-*-* 00/6:00:00 (every 6h), Persistent=true; [Install] WantedBy=timers.target.
   Expected output: systemctl --user compatible unit syntax.
4. Create README.md: install steps (cp script to ~/.local/bin, systemctl --user daemon-reload/enable --now timer), standalone usage `sync-hermes-context.sh` / `--dry-run`, env vars HERMES_CONTEXT_SRC/DST/LOG with deployed production defaults, guard behavior summary citing A11/A12/A14/A15/A18.
   Expected output: README documents dry-run purity + log∉DST.

accept:
1. All four files exist in hermes-context-sync/; `bash -n sync-hermes-context.sh` exits 0.
2. `sync-hermes-context.sh --dry-run` with DST absent → exit 0, DST still nonexistent, no log file created, no temp dirs left in ${TMPDIR}.
3. `sync-hermes-context.sh` (rsync present): DST == SRC per A9 levels 1–3 (recursive diff of contents/structure/symlinks passes; no timestamps/hardlink requirement).
4. Delete a stale subtree from SRC, rerun → subtree absent in DST after both rsync and cp-fallback paths (fallback forced via PATH without rsync).
5. Real run creates/uses log outside DST; `find DST -name '*.log'` empty.
6. SRC==DST invocation exits nonzero with "A11"; DST=/opt/data/workspace (ancestor of SRC) exits nonzero with "A12"; DST="" exits nonzero with "A18"; DST=/tmp exits nonzero with "A14".
7. Script + units contain no root/sudo; timer OnCalendar encodes 6h.

constraints:
- One-way SRC→DST only; no write-back to SRC (A2).
- No rm -rf DST before verified staged copy exists (A11,A13).
- Verify enforces exactly A9 levels 1–3; mismatch = nonzero exit, never warn-exit-0.
- Dry-run: zero writes of any kind, incl. log and DST creation (A6,A16).
- Refusals must cite A-numbers; guard set closed (A19) — do not invent scope (e.g., ownership requirements).
- No banned defects: accumulate-only fallback, probe-only dry-run gate, metadata-in-scope verify, over-broad parent-wall refusals, DST-must-pre-exist.

deliverable: [hermes-context-sync/sync-hermes-context.sh, hermes-context-sync/hermes-context.service, hermes-context-sync/hermes-context.timer, hermes-context-sync/README.md]