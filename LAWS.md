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
Gate-testable: no — pure register law, S4-enforced (LOCK3-proven non-catchable class,
12 recurrences). First loop-authored law (self-upgrade cycle, 2026-09-02).
