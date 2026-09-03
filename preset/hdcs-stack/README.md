# hdcs-stack agent preset — source of record

The LIVE preset lives at `$DSH_HOME/.agent-presets/hdcs-stack/` (outside
/workspace, outside any repo). This directory is its version-controlled
backup: after editing the live preset, copy the three files back here and
push. After a DSH-home reset, restore by copying the other way.

- `agent.cordis.yml` — composition: persona (five-stage doctrine + mode
  selector + kernel-runtime operator + REASONING VISIBILITY), preset-local
  `hdcs-reasoning` row (relative path — travels with the preset), shell /
  fs / skills / goals / planning / compaction / delegation.
- `plugins/hdcs-reasoning.mjs` — static tool row registering `hdcs_reasoning`
  for every agent on the preset (open parameters, output {schema, render},
  single-typed schema properties — same guard laws as the dynamic runner).
- `preset.yml` — display metadata.

Reasoning visibility, operator 2026-09-03: in HDCS mode the agent's visible
interleaved thinking is written in hcdl (the register reasons at the thinking
spot), and loop-status reports call `hdcs_reasoning` so the run's register /
brief / gate / judge verdict render as a card in the conversation flow.
Validate edits with `agentPresets.standingKeyFor('hdcs-stack')` (mount check,
no session needed).
