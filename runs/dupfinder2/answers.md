Operator non-negotiables:
- "build a duplicate-file finder in /workspace/dupfinder2/ — scanner module, CLI entry, and a README, three separate files"
- "Scanner walks a directory, hashes files, groups duplicates; CLI takes a path, prints groups with sizes; README documents usage."
- "Run the complete loop: S2 packet, S3 builders via subagent_worker, S4 gate via subagent_gpt ... S5 debrief."

Rulings: Python + standard library; recursive directory walk; SHA-256 hashing; duplicate groups only; CLI output includes size and paths.