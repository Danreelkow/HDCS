build brief → B1
state: s0 := { target: /workspace/tempconv2/src/index.js absent-or-stale; deps: none allowed; interface: `node src/index.js <value> <from> <to>` exact; units: {C,F,K,celsius,fahrenheit,kelvin} case-insensitive; thresholds: C:-273.15, F:-459.67, K:0, boundary valid; reject: stderr + exit 1; success: numeric stdout + exit 0; isolation: writes ∈ /workspace/tempconv2/** only }.
Δ := 
1. mkdir -p /workspace/tempconv2/src → expected: directory exists.
2. Write /workspace/tempconv2/src/index.js implementing:
   - arity check: process.argv.length === 5, else stderr "usage: node src/index.js <value> <from> <to>" + process.exit(1).
   - value := Number(process.argv[2]); Number.isFinite(value) else stderr + exit 1.
   - normalize unit via toUpperCase(): map C→C, F→F, K→K, CELSIUS→C, FAHRENHEIT→F, KELVIN→K; else stderr "unknown unit" + exit 1.
   - absolute-zero check: value ≥ threshold(fromUnit) with thresholds {C:-273.15, F:-459.67, K:0}; strictly less → stderr + exit 1.
   - convert to target unit: C↔F: F=C*9/5+32; C↔K: K=C+273.15; F↔K via C intermediate.
   - success: console.log(result) (numeric) + process.exit(0).
   → expected: file exists, zero import statements, exact positional handling.
3. Smoke tests (run from /workspace/tempconv2):
   - `node src/index.js 100 C F` → stdout `212`, exit 0.
   - `node src/index.js 0 celsius kelvin` → stdout `273.15`, exit 0.
   - `node src/index.js 32 fahrenheit K` → stdout `273.15`, exit 0.
   - `node src/index.js -273.15 C K` → stdout `0`, exit 0 (boundary valid).
   - `node src/index.js -300 C F` → stderr non-empty, exit 1.
   - `node src/index.js -460 F K` → stderr non-empty, exit 1.
   - `node src/index.js -1 K C` → stderr non-empty, exit 1.
   - `node src/index.js abc C F` → stderr non-empty, exit 1.
   - `node src/index.js 1 C` → stderr non-empty, exit 1 (bad arity).
   - `node src/index.js 1 C X` → stderr non-empty, exit 1 (unknown unit).
   → expected: all 10 checks pass exactly as stated.
accept:
- /workspace/tempconv2/src/index.js exists and runs under `node src/index.js <value> <from> <to>`.
- grep -cE "require\(|import " src/index.js → 0.
- All 10 smoke tests above produce the stated stdout/stderr/exit codes.
- `node src/index.js -273.15 C K` exits 0; `node src/index.js -273.150001 C K` exits 1.
- No file outside /workspace/tempconv2/** modified (git status / mtime check clean elsewhere).
constraints: [A1 exact positional arity 3 args; A2 zero deps, Node built-ins only (may use none); A3 thresholds C≥-273.15 F≥-459.67 K≥0, boundary valid; A4 all writes ∈ /workspace/tempconv2/**, /workspace/tempconv untouched; ≤60 lines source].
deliverable: [/workspace/tempconv2/src/index.js].