A1: The canonical source is /opt/data/workspace/hermes-context/ (recorded in kb digests as
    the host-side Hermes context mount). Destination is /workspace/hermes-context/ (exists,
    currently holds INDEX.md, agents/, config/).
A2: Sync direction is host -> workspace, one-way; nothing writes back to the host mount.
A3: Prefer a user-level systemd timer (systemctl --user); if the environment lacks systemd,
    the script itself must still work standalone (cron/installer can call it).
A4: The runtime may lack rsync entirely — the script must detect that and fall back to
    `cp -a` semantics (or tar pipe) so the timer works on minimal hosts. Also sync the
    CONTENTS of the source directory into the destination (src/ -> dst), never nesting
    the source dir inside the destination.

## A5 (2026-09-01, operator ruling on S4 verdict): mirror semantics
- Destination must be an EXACT mirror of source: stale files DELETED. The rsync path (--delete) is correct; the cp fallback path must reconcile identically — no accumulate-only mode. Both paths converge to identical end state.
- Rationale: fallback is a fallback, not a different feature. Divergent semantics between paths = defect (S4 catch, confirmed).

## A6 (2026-09-01, operator ruling on S4 verdict): dry-run purity
- --dry-run performs ZERO writes of ANY kind — including log files. If HERMES_CONTEXT_LOG points inside the destination, dry-run must not touch it. Logging happens only in real-run mode.
- Mechanical gate addition: dry-run must leave the destination byte-identical (not merely "no probe.txt").

## A7 (2026-09-01, operator ruling on S4 verdict #2): recursive convergence
- Confirmed: A5 means RECURSIVE convergence. Reconciliation in the cp fallback must delete stale SUBTREES at every depth (mirroring rsync --delete), not just top-level entries. DST must end byte-identical to SRC in both paths, nested paths included. README's sync-strategy section must state this correctly.

## A8 (2026-09-01, operator-delegated ruling on S4 verdict #5): placement law
- Confirmed both findings. The log lives OUTSIDE the destination ALWAYS (the ~/.cache default; never inside DST, no carve-outs, no post-mirror rewrite exceptions — A5 exact mirror means exact).
- Install paths live OUTSIDE the mirrored tree: ~/.local/bin (or /workspace/hdcs/bin), never artifact/ inside DST. A sync must never delete or move the installed service's own entrypoints.

## A9 (2026-09-01, operator ruling): equivalence class of "exact mirror"
- Mirror = levels 1-3 ONLY: file contents + directory structure (recursive, both sync paths) + symlinks. NOT included: file/root metadata, timestamps, hardlink topology.
- The self-verification must enforce exactly this class: verify contents+structure+symlinks recursively, and FAIL (nonzero exit) on any mismatch — never warn-and-exit-0.
- Judge scope: complaints about metadata/root-metadata/hardlinks are out-of-scope per this ruling.

## A10 (2026-09-01, operator ruling): S4 severity bar / stopping criteria
- FAIL only on defects reachable in NORMAL operation: default config, documented usage, plausible misconfiguration that loses or corrupts user data.
- Exotic/adversarial triggers (newline-in-filename corpora, hostile env combinations like pointing DST at the log dir) go to the packet's +open section as KNOWN_LIMITATIONS with repro notes — they do not block delivery.
- The judge still cites everything it finds; the bar classifies, it does not suppress.

## A11 (2026-09-01, operator-delegated): destructive-misconfig guard
- Confirmed A10-class FAIL. The script MUST guard SRC == DST (reject or clean no-op) and MUST NOT rm -rf the destination before establishing a verified copy of the source elsewhere. Source survival outranks mirror freshness.

## A12 (2026-09-01, operator-delegated): path-identity guard (A11 in spirit)
- Guard the IDENTITY of the trees, not string equality: compare realpath (symlinks resolved) of SRC and DST; refuse (clean nonzero exit, no writes) when realpath(SRC) == realpath(DST), or when either realpath is an ancestor/descendant of the other, or when DST is (or resolves through) a symlink into SRC. Applies to both sync paths before ANY destructive operation.

## A13 (2026-09-01, operator-delegated): "verified copy" definition (A11/A12 completion)
- "Verified" means CONTENT-COMPARED: the staging copy counts as verified only after its contents+structure+symlinks (A9 class) are compared against SRC and match — a non-emptiness check is not verification.
- NO destructive operation on DST (deletion, reconciliation, rename-over) until a verified copy of SRC exists. Order is law: stage -> verify -> only then touch DST.
- Self-verification inside the script must enforce this (exit nonzero if staging verification fails) and the README must not call an unverified copy "verified".

## A14 (2026-09-01, operator-delegated): protected-path class closes the env-interaction theme
- GENERALIZED guard (replaces per-var whack-a-mole): the script computes its own internal paths (log dir, staging dir, entrypoint dir) and REFUSES (clean nonzero, no writes) if HERMES_CONTEXT_DST realpath equals or contains any of them, or if the resolved staging location equals/is-inside DST or SRC (TMPDIR included — force a script-owned stage dir if TMPDIR fails the check).
- This closes the entire "env var X pointed at Y" class. FURTHERMORE: adversarial env combinations beyond this guard are KNOWN_LIMITATIONS (+open), NOT FAIL — the judge must cite A14 and stop re-deriving this class through new doors. Judgment returns to intent-vs-law, not env algebra.

## A15 (2026-09-01, operator-delegated): A14 precision — concrete paths, not parents (gate-not-wall calibration)
- "Owned path" = the CONCRETE instantiated path: the actual stage dir the script creates (e.g. its mktemp -d result), the resolved log FILE's parent dir, the resolved entrypoint dir. Never a generic ancestor like TMPDIR or /tmp itself.
- Comparison rule: refuse only when realpath(DST) == owned, or owned is inside DST, or DST is inside owned — using path-boundary-aware comparison (split on components or trailing-slash boundary), never bare string-prefix matching.
- Run 017's refusal of /tmp/hdcs-gate-dst was a WALL (over-broad A14 implementation), not a gate — this ruling is the calibration.

## A16 (2026-09-01, operator-delegated): DST lifecycle (run 019 wall calibration)
- DST may not exist before a run. The script MUST create it (mkdir -p) on real runs; dry-run MUST NOT create it. "DST must pre-exist" is not law — the fixture lifecycle deliberately runs dry-run against an absent DST.
- Gate probe strengthened: dry-run must leave DST nonexistent (not merely probe-free).

## A17 (2026-09-01, operator-delegated): parameterization vs deployed defaults (judge calibration)
- The packet's fixed paths (e.g. /opt/data/workspace/hermes-context/) are the DEPLOYED configuration — the values the unit/timer passes at install time. They are NOT a prohibition on env parameterization: HERMES_CONTEXT_SRC/DST env override is the mandated mechanism (gate contract), and the deployed paths are simply its production values.
- Judges: never read a deployed default as a scope restriction. The S4 verdict that called env override "inventing scope" was WRONG and caused a contract regression in the repair. Contract (gate.sh) and A-law outrank verdicts.

## A18 (2026-09-01, operator-delegated): degenerate-path refusals (root safety)
- Refuse (clean nonzero, no writes) when HERMES_CONTEXT_DST or SRC is "/" , empty, or "." — always, before any destructive op. The component-boundary guards must handle these as special cases first (the "$RD/"-pattern form misses DST=/ : test components, not slash-suffixed strings).
- DST symlink resolving outside SRC: refuse (A12) — after A12+placement guards pass, DST must END as a real directory tree identical to SRC (A5/A9); if the old DST was a symlink, it is replaced by the real tree (symlink removed, not retained).

## A19 (2026-09-01, operator-delegated): no invented scope — ownership edition
- There is NO ownership requirement on DST, SRC, or their ancestors. The operator may sync anywhere they hold write permission (including /tmp leaves under a root-owned parent — sticky-bit dirs exist for exactly this). The OS is the ownership gate; the script adds none.
- The complete path-law list is closed: A12 identity, A14/A15 protected internal paths (concrete), A18 degenerate paths. Anything beyond these = invented scope = wall behavior. Refusals must cite one of these A-numbers; a refusal citing nothing is itself a defect.

## A20 (2026-09-01, operator-delegated): staging order + script-namespace reservation (closes run 025 findings)
- STAGE BEFORE CHECK is legal in ONE form only: resolve the stage path with a PURE string computation (no mktemp, no mkdir, no write); validate the computed path against SRC/DST/owned; only then create it. mktemp-then-refuse violates C4 (refusal paths perform zero writes).
- Reserved script namespace: '.prunelist', 'staging', '.hc-stage*' and similar working names are RESERVED when used by the script. If SRC itself contains a file/dir with a reserved name, the script RENAMES ITS WORKING FILE (e.g. '.hc-prunelist' -> use mktemp file instead of fixed name) rather than touching the mirror file. Mirror files are never overwritten by script bookkeeping.

## A21 (2026-09-01, operator-delegated): exotic filenames = KNOWN_LIMITATIONS
- Filenames containing newlines/control characters are legal but exotic; a mirror that copies them correctly (rsync does) but reports/comparison-breaks on them is +open KNOWN_LIMITATIONS, NOT FAIL. Gate does not fixture them. A9-class losslessness applies to normal filenames.
- Scope notes (no new law, enforcement reminders): A13 order (stage->content-verify->touch DST) applies to the PRIMARY destructive path (rsync), not just the fallback; LOG_DIR is "the log dir" in A14's guard scope — covered, implement it.

## A22 (2026-09-01, operator-delegated): A18 disambiguation — refuse, never replace
- A18's two sentences contradicted each other (refuse vs accept-and-replace). RESOLVED: DST whose realpath resolves to a symlink (any target outside SRC) is REFUSED with an A-number. Sync never replaces or destroys a user-placed symlink at the DST path level; the operator removes it manually first. The earlier "replaced by the real tree" clause is VOID; the run 021 finding's "reconcile OR refuse" option resolves to refuse.
- Stage TOCTOU (run 036 finding 2): create the stage with mktemp -d under an already-validated parent, then re-validate the instantiated path (A15 concrete-path rule closes the construct-string-then-mkdir gap).

## A23 (2026-09-01, operator-delegated): A20/ledger-14 disambiguation + default semantics
- Stage ordering (resolves A20 vs ledger-14 conflict): (1) compute candidate parent paths as PURE strings (no writes); (2) validate parent not inside DST/SRC/owned; (3) mktemp -d under the validated parent — this atomic create is NOT a "write before refusal" (C4 forbids writes into protected trees; a validated-parent mktemp writes nothing protected); (4) re-validate the instantiated stage path (realpath, symlink-swap check). "mktemp-then-refuse" remains forbidden ONLY when the mktemp target's parent is unvalidated/protected.
- Defaults (fixes run 043 overcorrection of 8b): UNSET variable -> the MANDATED production default (SRC=/opt/data/workspace/hermes-context, DST=/workspace/hermes-context — A17: deployed defaults are the production values); SET-BUT-EMPTY -> refuse (A18). `${VAR-default}` pattern with an explicit [ -z ] refusal for the empty case. The default value itself must be the real paths, never a placeholder word.
