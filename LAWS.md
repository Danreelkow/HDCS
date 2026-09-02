# HDCS Register Laws — canon (travel with every packet)

Approved operator laws. Per-task registers (answers.md) instantiate these; new tasks
inherit them unless the operator rules otherwise in the task register.

## A8 — non-attesting verifier (2026-09-02, Danreelkow)
A verifier's verdict must be derived by re-reading the artifact tree itself; state the
same toolchain wrote earlier may index but never attest. AND recorded notes must be
cross-checked against the tree on every run: re-derive the facts from disk, compare
with the notes — any drift between notes and disk is itself a failure. Recorded state
names paths to re-check and must agree with what the re-check finds.
Refusal wording: `fail "A8: verdict attested by self-written state, not artifact re-read"`
or `fail "A8: recorded notes drifted from artifact re-read"`.
Change-detection (operator, 2026-09-02): the verifier first fingerprints the tree on
disk (cksum/mtime) and compares against recorded state. Fingerprints match -> record
verified-no-change and skip the deep re-check. Anything differs (or no record) -> full
re-derive + notes cross-check. The match decision itself comes from disk evidence, never
from the notes asserting it.
Gate-testable: no — pure register law, S4-enforced (LOCK3-proven non-catchable class,
12 recurrences). First loop-authored law (self-upgrade cycle, 2026-09-02).

## A4 — canary-discriminating fixtures (2026-09-02, Danreelkow)
Every proposed fixture lock MUST be canary-discriminating: the fixture is valid only if it
FAILS on a defect-injected variant of the artifact and PASSES on the compliant artifact
(∀ fixture F: F(compliant) ∧ ¬F(mutant)). Scope: governs LOCK rejections where the fixture
passes the canary and cannot catch the defect class it claims to lock (wall, not gate).
Satisfying form: before submitting a lock, mutate the artifact along the finding class
(e.g., unscope the git query for A1, encode failure count in exit for A3) and show the
fixture verdict flips; a lock that passes both is rejected as non-testable, and the class
routes to S4 review instead. Extends A1/A3 by governing lock admissibility, not behavior.
Refusal wording: `fail "A4: fixture lock not canary-discriminating — passes mutant, cannot gate this defect class"`.
Gate-testable: yes — run the proposed lock against the artifact and one defect-injected
variant per the cited A-number; lock admissible iff verdicts differ.
