# tempconv2 CLI

intent: Build `/workspace/tempconv2/src/index.js`, a zero-dependency Node.js CLI converting Celsius|Fahrenheit|Kelvin.
artifacts: `/workspace/tempconv2/src/index.js`
acceptance:
- positional invocation exactly `node src/index.js <value> <from> <to>`
- source/destination accept C/F/K and Celsius/Fahrenheit/Kelvin, case-insensitive
- valid conversion prints numeric result to stdout and exits 0
- bad arity, non-finite/non-numeric value, unknown unit, or below-absolute-zero source prints stderr and exits 1
- no dependency imports; `/workspace/tempconv` remains untouched

A-laws:
- A1: Preserve exact positional interface.
- A2: Zero dependencies; only Node built-ins if needed.
- A3: Enforce source absolute-zero thresholds: C >= -273.15, F >= -459.67, K >= 0.
- A4: Isolate all writes to `/workspace/tempconv2`; never reuse or modify `/workspace/tempconv`.
