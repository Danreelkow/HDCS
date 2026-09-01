state: s0 := SRC=/opt/data/workspace/hermes-context/ exists (A1); DST=/workspace/hermes-context/ one-way target (A2, ¬write-back); scheduler=systemctl --user timer OnUnitActiveSec=6h (A3); transport=rsync primary, cp -a/tar-pipe fallback, src/ -> dst trailing-slash semantics (A4); mirror class=contents+structure+symlinks, stale deleted, ∀depth convergence (A5/A7/A9); dry-run = zero writes ∀ target incl. logs (A6/A16); order=stage→verify→touch-DST (A13); guards A11/A12/A18 precede ∀ destructive op; owned paths concrete, parent ∉ DST, TMPDIR fallback (A8/A14/A15); env parameterization = contract, defaults production (A17); open: ∅.

Δ := [
 1. mkdir -p /workspace/hdcs/hermes-sync/; write sync-hermes-context.sh:
    a. env-parameterized: SRC, DST, LOG (default ~/.cache/hermes-context/sync.log), DRY_RUN=0; `set -euo pipefail`.
    b. Guards first (A12/A18): realpath both paths; refuse if identical, ancestry (either contains other), SRC nonexistent, DST nonexistent-or-not-dir. Exit 2 on refusal.
    c. DRY_RUN=1 branch: rsync -rlptgoD --delete --dry-run SRC DST; fallback path: compute plan to stdout only; write NOTHING (no log, no mktemp residue, no DST touch) (A6/A16).
    d. Live path (A13): mktemp -d under owned parent outside DST (fallback TMPDIR); stage=rsync -a --delete SRC "$TMP/stage/" ; if rsync absent → cp -a SRC/. "$TMP/stage/" then prune stale via diff -rq listing, rm extras; verify: diff -rq --no-dereference SRC stage (or find-based compare of contents/structure/symlinks) → nonzero ⇒ abort, exit 1, DST untouched (A11 source survival > freshness); only then touch-DST: rsync -a --delete "$TMP/stage/" DST (fallback: rm -rf DST/* + cp -a stage/. DST/).
    e. Emit one-line summary to LOG (timestamp, transport, exit status, counts). Dry-run writes no log line.
    f. Idempotent: second live run yields zero changes.
 2. Write hermes-context.service: [Service] Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh.
 3. Write hermes-context.timer: [Timer] OnUnitActiveSec=6h, OnBootSec=10min, Persistent=true, [Install] WantedBy=timers.target.
 4. Write README.md: usage, env vars, dry-run, install steps (cp script ~/.local/bin/, cp units ~/.config/systemd/user/, systemctl --user daemon-reload, enable --now timer), standalone invocation, KNOWN_LIMITATIONS (no metadata/timestamps/hardlink fidelity per A7/A10).
 5. Verify: bash -n all scripts; DRY_RUN=1 run → assert DST nonexistent-or-byte-identical, no log written, no temp residue; live run → diff -rq SRC DST empty; run twice → second run reports 0 changes; both transports exercised (rsync present + PATH-restricted rsync-absent simulation); A12 test: DST=SRC/ and SRC=DST/ each exit 2.
]

accept:
- /workspace/hdcs/hermes-sync/ contains sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md.
- sync-hermes-context.sh: `bash -n` clean; honors env SRC/DST/LOG/DRY_RUN with production defaults (A17).
- DRY_RUN=1: zero writes — DST unchanged/nonexistent, no log entry, no temp dirs; exit 0.
- Live run: `diff -rq /opt/data/workspace/hermes-context/ /workspace/hermes-context/` empty, incl. symlinks; stale entries deleted; ∀depth (A9).
- Second consecutive run: no changes (idempotent).
- cp -a fallback path converges to same end state (A9/A9-convergence).
- Guards: realpath identity or ancestry (either direction) ⇒ exit 2, no destructive op executed.
- Verify step failure aborts before DST mutation; SRC never written (A2/A11).
- Units: OnUnitActiveSec=6h, user units, no root; script runs standalone.

constraints: [A2 no write-back; A5 exact mirror ∀ run; A6/A16 dry-run zero-write ∀ target incl. logs; A7 no metadata/timestamps/hardlink fidelity required; A11 source survival > freshness; A12 refuse identity/ancestry paths; A13 stage→verify→touch-DST; A14/A15 concrete owned paths outside DST, TMPDIR fallback; A18 guards precede ∀ destructive op; A17 env parameterization = contract, defaults = production values; no root required]
deliverable: [/workspace/hdcs/hermes-sync/sync-hermes-context.sh, /workspace/hdcs/hermes-sync/hermes-context.service, /workspace/hdcs/hermes-sync/hermes-context.timer, /workspace/hdcs/hermes-sync/README.md]