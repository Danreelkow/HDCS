# RUNBOOK — sync-hermes-context.sh

This runbook documents the tool in `runs/001-hermes-context-timer/artifact/`:
`sync-hermes-context.sh`, `hermes-context.service`, `hermes-context.timer`, `README.md`.

Terms used here: an "A-number" is one of the tool's named refusal codes (e.g. A9), cited
when the script refuses to run and states why. No other register-specific jargon appears
in this document.

---

## 1. What the tool does

`sync-hermes-context.sh` performs a one-way mirror from the source directory
(`HERMES_CONTEXT_SRC`, default `/opt/data/workspace/hermes-context/`) to the destination
directory (`HERMES_CONTEXT_DST`, default `/workspace/hermes-context/`):

- recursive copy of the full tree,
- stale files that exist only in DST are removed,
- entry types and symlink targets are preserved exactly,
- after syncing, the script re-verifies the result and fails (exit nonzero) if DST is not
  an exact mirror of SRC.

It supports exactly two flags:

- `--dry-run` — prints the plan of what would be synced/removed; performs zero writes.
- `--verify` — exits 0 only if DST is currently an exact mirror of SRC; otherwise exits
  nonzero with citation A9 (mirror mismatch).

Any unknown flag exits with status 2.

Each real (non-dry-run, non-verify) run writes one log line under `~/.cache/hermes-context/`.

---

## 2. Test before installing (--dry-run)

You can preview a sync without installing anything. In these examples, the operator paths
`~/src/hermes-context` and `~/dst/hermes-context` are examples only — substitute your own.

```sh
HERMES_CONTEXT_SRC=~/src/hermes-context \
HERMES_CONTEXT_DST=~/dst/hermes-context \
  ./sync-hermes-context.sh --dry-run
```

Expected: a printed plan of copies/removals; nothing on disk changes.

Behavior of the environment variables:

- **Unset** — the production defaults are used: `HERMES_CONTEXT_SRC=/opt/data/workspace/hermes-context/`, `HERMES_CONTEXT_DST=/workspace/hermes-context/`.
- **Set but empty** — the script refuses with citation A23. Empty is not "default"; either unset the variable or give it a real value.

Refusal conditions checked before any write: degenerate paths (A18), same path /
ancestor–descendant / symlink-component overlap (A12), staging path conflicts (A14),
staging verify failure (A13). See the troubleshooting table for details.

---

## 3. Install

No directories are assumed to exist; create them and install with `install -D`:

```sh
mkdir -p ~/.local/bin ~/.config/systemd/user
install -D -m 755 sync-hermes-context.sh ~/.local/bin/sync-hermes-context.sh
install -D -m 644 hermes-context.service ~/.config/systemd/user/hermes-context.service
install -D -m 644 hermes-context.timer  ~/.config/systemd/user/hermes-context.timer
```

The installed script lives at `~/.local/bin/sync-hermes-context.sh`; the systemd user
units live at `~/.config/systemd/user/hermes-context.{service,timer}`.

---

## 4. Configure

Configuration is via environment variables read by the script:

- `HERMES_CONTEXT_SRC` — source directory (default `/opt/data/workspace/hermes-context/`)
- `HERMES_CONTEXT_DST` — destination directory (default `/workspace/hermes-context/`)
- `TMPDIR` — optional staging parent used by the script during real runs

If a variable is unset, the default above applies. If it is set but empty, the script
refuses (A23). Trailing slashes in the values are canonicalized by the script; either
form works.

The timer unit runs the script with the defaults; if you need different paths, override
the service unit's environment (e.g. a user-level drop-in setting the two variables), or
export them in your service environment file.

---

## 5. Schedule

The timer syncs every 6 hours. Enable it for your user:

```sh
systemctl --user daemon-reload
systemctl --user enable --now hermes-context.timer
```

Check status:

```sh
systemctl --user status hermes-context.timer
systemctl --user list-timers hermes-context.timer
```

Logs: each real run appends one line under `~/.cache/hermes-context/`.

---

## 6. Verify a sync

```sh
~/.local/bin/sync-hermes-context.sh --verify
```

- Exit 0: DST is an exact mirror of SRC (entry types, symlink targets, and file bytes).
- Exit nonzero with citation A9: mirror mismatch — run a real sync to repair:

```sh
~/.local/bin/sync-hermes-context.sh
```

---

## 7. Rollback

If a sync went wrong, restore the destination from the known-good configured source.
Set the two variables to the SAME values you configured in section 4 (the defaults are
shown here; substitute your overrides if you use any). The removal uses `find` so that
hidden (dot-prefixed) entries are removed too:

```sh
export HERMES_CONTEXT_SRC=/opt/data/workspace/hermes-context/
export HERMES_CONTEXT_DST=/workspace/hermes-context/

find "$HERMES_CONTEXT_DST" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
~/.local/bin/sync-hermes-context.sh
```

The script reads the exported `HERMES_CONTEXT_SRC`/`HERMES_CONTEXT_DST`, so it re-syncs
the configured destination from the configured known-good source. (If you did not export
them, unset variables fall back to the same defaults.)

Important: merely disabling the timer (`systemctl --user disable hermes-context.timer`)
is **not** a rollback — it stops future syncs but leaves the bad DST contents in place
(A6). Remove and re-sync DST as shown above.

---

## 8. Troubleshooting

The tool's refusal codes ("A-numbers") and what triggers them:

| Code | Condition | What to do |
|------|-----------|------------|
| A23 | An env variable (`HERMES_CONTEXT_SRC`, `HERMES_CONTEXT_DST`, `TMPDIR`) is set but empty. Unset variables fall back to the mandated defaults. | Either `unset VAR` or set a real value. |
| A18 | A degenerate path: SRC or DST is empty, `.`, or resolves to `/`. | Set SRC/DST to a real directory path. |
| A12 | SRC and DST are the same path, one is an ancestor/descendant of the other, or a symlink component makes them overlap. | Choose two disjoint directories (mind symlinked parents). |
| A13 | Staging verification failed before the sync; DST is untouched. | Inspect the error; ensure the staging area is writable and on the same filesystem expectations; retry. |
| A14 | Staging path conflict, including `TMPDIR` set but empty or a staging area overlapping SRC/DST or paths the tool owns. | Point `TMPDIR` at a neutral directory (e.g. unset it or use `/tmp`); do not set `TMPDIR` inside SRC or DST. |
| A9 | Mirror mismatch (from `--verify`, or post-sync re-verification failed). | Run a real sync to repair; if it recurs, check for concurrent writers to DST. |

Conditions with no code (described, not cited):

- **Unknown flag** — passing anything other than `--dry-run` or `--verify` exits with
  status 2 and a usage message.
- **Log/target path inside DST** — if a log or staging location would land inside DST,
  the script refuses rather than sync into its own output.

For anything else, run with `--dry-run` first and read the printed plan; it shows exactly
what the tool intends to do before any change.
