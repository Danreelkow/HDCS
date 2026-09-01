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
