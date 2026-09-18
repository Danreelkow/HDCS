operator non-negotiables (verbatim-faithful):
- Build /workspace/tempconv2/src/index.js.
- Zero-dependency node CLI.
- positional args `node src/index.js <value> <from> <to>`.
- converting between Celsius, Fahrenheit, Kelvin.
- accept C/F/K and full names, case-insensitive.
- reject below-absolute-zero and bad input with stderr + exit 1.
- Do NOT reuse or modify /workspace/tempconv.

precise rulings:
- below-absolute-zero := source value less than the source unit threshold; boundary values are valid.
- bad input := invalid arity, non-numeric/non-finite value, or unknown unit.
