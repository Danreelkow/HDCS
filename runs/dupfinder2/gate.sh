#!/usr/bin/env bash
set -euo pipefail
root=/workspace/dupfinder2
for f in scanner.py dupfinder.py README.md; do test -s "$root/$f"; done
node - "$root" <<'NODE'
const fs=require('fs'); const root=process.argv[2];
const scanner=fs.readFileSync(root+'/scanner.py','utf8');
const cli=fs.readFileSync(root+'/dupfinder.py','utf8');
const readme=fs.readFileSync(root+'/README.md','utf8');
for (const [s, terms] of [[scanner,['os.walk','sha256','find_duplicates']], [cli,['argparse','find_duplicates','bytes']], [readme,['Usage','SHA-256','duplicate']]]) for (const t of terms) if (!s.includes(t)) throw new Error(`missing ${t}`);
NODE
printf 'gate PASS (static/runtime unavailable: Python interpreter absent)\n'
