# Clarification needed — 001-hermes-context-timer

S4 FAIL verdict (after feedback repair):

VERDICT: FAIL
EVIDENCE: The script does not implement the required realpath-based path guards. In `sync-hermes-context.sh` lines 16–22, `canon()` only strips trailing slashes; lines 33–36 reject nesting using lexical string prefixes. A destination symlink or symlinked ancestor resolving to `SRC` (or inside `SRC`) bypasses A18, despite the packet’s required `realpath` vocabulary and guard set.

EVIDENCE: A13 is not satisfied for the primary rsync path. In `sync-hermes-context.sh`, `sync_real()` lines 150–158 creates `DST` and then executes `rsync -a --delete` directly; staging and content verification occur only inside `sync_fallback()` lines 119–148. Thus the primary destructive path has no content-compared staging verification before DST destruction.

EVIDENCE: `LOG_DIR` is not enforced to remain outside `DST`. `sync-hermes-context.sh` line 11 accepts an arbitrary `LOG_DIR`, and `sync_real()` lines 162–164 creates and appends to it. Setting `LOG_DIR="$DST"` writes into the destination and violates A8/Q3; setting it inside `DST` also lets fallback staging occur inside the destination (`sync_fallback()` lines 122–124). README.md lines 38–42 incorrectly claim the override is “always outside DST.”

EVIDENCE: Verification and diff logic is not lossless for valid filenames containing newlines. `tree_list()` in `sync-hermes-context.sh` lines 48–52 serializes paths as newline-delimited records, and `tree_cmp()`, `list_mismatches()`, and `dry_run()` parse those records line-by-line. Such filenames are split into multiple records, so A9-class comparison and dry-run reporting can mismatch or misreport a tree that rsync copied correctly.

EVIDENCE: `--verify` incorrectly succeeds when `DST` does not exist but `SRC` is an existing empty directory. `tree_list()` suppresses the failed `cd` and returns an empty listing (lines 48–52), while `verify_cmd()` compares only listings (lines 98–107); both become empty and it reports “verify OK,” although the destination directory is absent and therefore not an exact mirror.

## Packet
```yaml
reg:
  domain: cs-programming
  canon: "rsync/systemd-user vocabulary: idempotent, --delete, --dry-run, realpath, mktemp -d, Type=oneshot, OnUnitActiveSec, systemctl --user"
intent: >
  build artifact dir := {sync-hermes-context.sh, hermes-context.service, hermes-context.timer, README.md}
  such that ∀ run -> DST := exact mirror of SRC (A9 class: contents+structure+symlinks, recursive, stale deleted),
  sync direction host->workspace one-way (A2), rsync primary with cp/tar fallback converging identically (A5),
  --dry-run -> zero writes ∀ kind (A6), systemd USER units timer 6h + standalone execution (A3),
  guards per A11/A12/A14/A15/A18/A19/A20, self-verification exits nonzero on A9-class mismatch (A9/A13).
must_keep:
  - "source path is /opt/data/workspace/hermes-context/"
  - "dry-run mode that performs no writes"
  - "systemd user units, no root required"
resolved:
  - "Q1: canonical SRC/DST values? -> A: A1; SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context (deployed defaults per A17; env override is the mechanism)"
  - "Q2: fallback semantics when rsync absent? -> A: A4+A5+A7; cp/tar reconcile with recursive stale deletion, identical end state to rsync --delete"
  - "Q3: logging location given dry-run purity? -> A: A6+A8; log outside DST always (e.g. ~/.cache default), logging only in real-run mode"
  - "Q4: DST absent lifecycle? -> A: A16; real run mkdir -p DST; dry-run leaves DST nonexistent"
  - "Q5: mirror equivalence class? -> A: A9; contents+structure+symlinks only; verify FAILs nonzero on mismatch"
  - "Q6: refusal authority list? -> A: A19 closed list (A12, A14/A15, A18); refusals cite A-numbers, zero writes on refusal path (C4/A20)"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: "S_0 + Delta -> S_1", report: ["+done", "-resolved", "+open", "+validation"]}
constraints:
  - "A5 mirror semantics, recursive convergence (A7)"
  - "A6 dry-run zero writes, byte-identical DST; A16 dry-run never creates DST"
  - "A9 verification class; A13 verified=content-compared staging before any DST destruction"
  - "A11/A12/A14/A15/A18/A20 guards; A19 closed path-law list; refusals cite A-numbers"
  - "A17 env parameterization mandated; deployed paths are production values"
  - "A3 systemd user units, standalone fallback; A10 severity bar"
paths:
  - "/workspace/hermes-context/"
  - "/opt/data/workspace/hermes-context/"
  - "~/.local/bin"
  - "~/.cache/hermes-context/"
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
