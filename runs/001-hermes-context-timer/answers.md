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
