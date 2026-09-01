state:
  s0 := packet validated. SRC=${HERMES_CONTEXT_SRC-default /opt/data/workspace/hermes-context/}, DST=${HERMES_CONTEXT_DST-default /workspace/hermes-context/} (A17/A23: unset→default, set-but-empty→refuse).
  A2 one-way host→workspace. A5 mirror: rsync -a --delete primary; rsync absent → cp -a + recursive reconcile (delete stale subtrees, copy diffs); end state DST≡SRC recursive.
  A9-class compare = contents+structure+symlinks (not metadata/timestamps/hardlinks); mismatch → exit nonzero, never warn-and-exit-0.
  A6/A16: --dry-run ⇒ zero writes ∀ kind incl. logs, no stage dir, absent DST stays absent, exit 0 with plan printed.
  A8: log ~/.cache/hermes-context/sync.log (real runs only, one line); entrypoint ~/.local/bin/sync-hermes-context.sh; both outside DST ⇒ never deleted by sync.
  A11/A13: guards → mktemp -d stage → re-validate → copy SRC→stage → A9-compare SRC vs stage → only then touch DST; no rm -rf before verified stage.
  Guards: A18 degenerate {"/","","."} component test; A12 realpath identity/ancestor/descendant; A22 DST symlink → refuse, never replace; A14/A15 owned={instantiated stage, log parent, entrypoint dir} concrete, component-boundary; refusals cite only A12|A14/A15|A18|A22|A23 (A19).
  A20: parent string-validated → mktemp -d → re-validate instantiated; reserved names via mktemp bookkeeping. A21 exotic filenames → KNOWN_LIMITATIONS. A10 FAIL only normal-operation defects. A3 standalone-executable, no root, systemd optional.
Δ:
  1. mkdir hermes-context/; write sync-hermes-context.sh (#/usr/bin/env bash, set -euo pipefail):
     (a) parse --dry-run; resolve SRC/DST per A23. expect: set-but-empty → exit≠0, stderr "A23".
     (b) guards A18→A12→A22→A14/A15 (log parent, entrypoint dir). expect: each refusal exit≠0 citing its A-number only.
     (c) dry-run branch: plan via `rsync -an --delete --itemize-changes SRC/ DST/` (DST absent ⇒ all-create) else read-only find-diff; print "dry-run: sync=N delete=M". expect: zero writes anywhere, exit 0.
     (d) stage: validate ${TMPDIR:-/tmp} as string → mktemp -d → realpath re-validate vs A14/A15 → `rsync -a --delete SRC/ stage/`; no rsync → `cp -a SRC/. stage/` + delete stage entries absent from SRC.
     (e) A13: A9-compare SRC vs stage (`diff -r --no-dereference` + symlink-target check); mismatch → rm stage, exit≠0, DST untouched.
     (f) touch DST: `rsync -a --delete stage/ DST/`; fallback: delete DST entries absent from stage, cp -a missing/differing; then A9-compare SRC vs DST, mismatch → exit≠0.
     (g) append one-line UTC summary to log (mkdir -p parent); rm -rf stage; exit 0. Real path only — dry-run never reaches (d)-(g).
     expect: bash -n → exit 0; chmod +x applied.
  2. write hermes-context.service: [Service] Type=oneshot, ExecStart=%h/.local/bin/sync-hermes-context.sh; [Install] WantedBy=default.target.
     expect: systemd-analyze verify hermes-context.service → exit 0.
  3. write hermes-context.timer: [Timer] OnCalendar=*-*-* 00/6:00:00, Persistent=true, Unit=hermes-context.service; [Install] WantedBy=default.target.
     expect: systemd-analyze verify hermes-context.timer → exit 0.
  4. write README.md: install (script→~/.local/bin; units→~/.config/systemd/user; systemctl --user daemon-reload && enable --now hermes-context.timer), env override examples, --dry-run test procedure, sync-strategy states (rsync primary / cp fallback, both = recursive mirror), KNOWN_LIMITATIONS section (A21 exotic filenames; adversarial env beyond A14).
     expect: contains strings HERMES_CONTEXT_SRC, HERMES_CONTEXT_DST, --dry-run, OnCalendar, default.target.
  5. smoke matrix (mktemp fixtures, env-overridden SRC/DST):
     (i) dry-run, absent DST → exit 0; DST still absent after.
     (ii) dry-run, existing DST → exit 0; tree-hash before==after.
     (iii) real run → exit 0; A9-compare SRC≡DST; exactly one log line; rerun → 0 copied 0 deleted, log grows by one line.
     (iv) SRC==DST → cites A12; DST symlink→elsewhere → cites A22; DST="." → cites A18; all exit≠0, DST unchanged.
     (v) PATH-shim hiding rsync, real run → exit 0, A9-compare passes.
     (vi) corrupt one DST file, rerun → exit 0, content restored, A9-compare passes.
     expect: all (i)-(vi) outcomes exactly as stated.
accept:
  - hermes-context/{sync-hermes-context.sh,hermes-context.service,hermes-context.timer,README.md} exist; script +x, bash -n 0; both units verify 0
  - smoke (i)-(vi) pass verbatim
  - every refusal stderr cites only A12|A14/A15|A18|A22|A23
  - --dry-run: no stage, no log, no DST write; absent DST stays absent
  - real run: A9-compare SRC≡DST, stale subtrees deleted, idempotent, one log line/run
  - script writes only to {stage, DST, log}; log+entrypoint outside DST
  - README KNOWN_LIMITATIONS section present
constraints: [A19 closed refusal law, no invented scope; A2 no writeback DST→SRC; A11 stage→verify→touch, no rm -rf DST pre-verify; A6/A16 dry-run zero-write incl. logs; A8 placement; A9-class mirror only; A20 stage ordering; A22 refuse-never-replace; A23 unset/empty semantics; bash+rsync+systemd-user canon, no root, no systemd required at runtime; A21 exotic → +open not FAIL]
deliverable: [hermes-context/sync-hermes-context.sh, hermes-context/hermes-context.service, hermes-context/hermes-context.timer, hermes-context/README.md]