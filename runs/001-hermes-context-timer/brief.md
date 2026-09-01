state:
  s0 := hdcs/1 validated, open=[], no artifacts exist yet; SRC/DST defaults per A17.
  Δ:
Δ1 sync-hermes-context.sh:
  1a defaults: SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}", DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}", both realpath'd. exp: unset env → deployed defaults; env override works (A17).
  1b A18 guard: component-test (IFS=/, never string-prefix) SRC/DST ∈ {"", "/", "."} → exit 2, stderr cites A18, zero writes. exp: guard runs before any mktemp/log/write.
  1c A12 guard: realpath(SRC)==realpath(DST) ∨ ancestor ∨ descendant ∨ DST symlink resolving into SRC → exit 2, cites A12. exp: refusal precedes any write.
  1d flag parse: --dry-run only; unknown arg → usage, exit 2. exp: no side effects on parse error.
  1e A20 stage: STAGE="$(mktemp -d "${TMPDIR:-/tmp}/hermes-sync.XXXXXX")" + EXIT-trap cleanup; pure string calc → validate → create. exp: stage exists only under /tmp|$TMPDIR; zero bookkeeping files in SRC/DST.
  1f copy: command -v rsync → `rsync -a --delete "$SRC"/ "$STAGE"/`; else A4 fallback `cp -a "$SRC"/. "$STAGE"/`. exp: both branches mirror {contents, dirs, symlinks} recursively (A9 class).
  1g A13 verify: compare SRC vs STAGE (diff -r, symlink-aware); mismatch → exit 3, cites A13, DST untouched, stage cleaned. exp: verify textually precedes every DST mutation.
  1h mutate: only post-verify — DST already == SRC → no-op exit 0; else DST symlink (not into SRC) unlinked per A18, then rm -rf DST (A11: verified copy exists) and mv STAGE→DST. exp: DST end state == SRC end state; rerun is no-op.
  1i dry-run (A6/A16): print plan (add/del list) only; zero writes incl. log; exit 0. exp: nonexistent DST still absent after dry-run.
  1j log: parent := ${XDG_CACHE_HOME:-$HOME/.cache}/hermes-sync; if resolved parent ==|under realpath(DST) by component-boundary → exit 2, cites A14/A15. exp: log outside DST ∀ env (A8).
Δ2 hermes-context.service: [Service] Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh. exp: no User=, no root.
Δ3 hermes-context.timer: OnCalendar=*-*-* 00/6:00:00, Persistent=true, [Install] WantedBy=timers.target. exp: 6h cadence, user-unit only (A3).
Δ4 README.md sections: install (~/.local/bin, ~/.config/systemd/user, daemon-reload, enable --now), dry-run test, source-change procedure, sync strategy (A7-correct: one-way host→workspace, exact mirror, stale subtrees deleted, never bidirectional), env override table, KNOWN_LIMITATIONS. exp: all 6 sections present.
Δ5 checks: bash -n → 0; shellcheck if installed (absent = non-fatal).
Δ6 fixture self-test (mktemp sandbox, outside deliverables):
  6a dry-run, DST absent → exit 0, DST uncreated. 6b live → diff -r SRC DST empty; planted extra DST file removed on rerun. 6c symlink in SRC → same target at DST. 6d rsync masked via PATH shim → cp path: diff -r empty. 6e refusals (SRC==DST, DST=/, DST=".", DST ancestor of SRC, log-parent inside DST) → each nonzero, cites A-number, fixture hashes unchanged.
accept:
  1. exactly 4 deliverable files exist; bash -n exit 0.
  2. grep: script cites A12, A13, A14/A15, A18; verify step precedes all DST-mutating commands; dry-run code path contains no write ops.
  3. timer OnCalendar = 6h cadence + Persistent=true; both units usable via systemctl --user; no root.
  4. Δ6a–6e observed outputs match stated expectations exactly.
  5. README contains all Δ4 sections incl. explicit "stale subtrees deleted" wording.
constraints:
  - A19: refusals cite an A-number; path-law closed set {A12, A14/A15, A18}
  - A11/A13: stage → verify → mutate; never rm -rf DST before verified copy exists
  - A20: stage via string-calc→validate→create; no bookkeeping in mirrored trees
  - A4/A5: cp fallback reconciles identically to rsync --delete; both paths converge
  - A9: verify {contents, dirs, symlinks}, nonzero on mismatch; metadata excluded
  - A6/A16: dry-run zero writes incl. log; A10: exotic env combos → KNOWN_LIMITATIONS, not FAIL
  - A17: deployed defaults fixed; env override is contract; no root anywhere
deliverable:
  - sync-hermes-context.sh
  - hermes-context.service
  - hermes-context.timer
  - README.md