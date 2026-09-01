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
