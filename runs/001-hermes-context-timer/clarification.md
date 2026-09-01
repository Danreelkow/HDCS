# Clarification needed — 001-hermes-context-timer

## Gate output (after repair round)
```
GATE FAIL: real run exited nonzero: find: unrecognized: -printf
BusyBox v1.37.0 (2026-01-10 15:38:28 UTC) multi-call binary.

Usage: find [-HL] [PATH]... [OPTIONS] [ACTIONS]

Search for files and perform actions on them.
First failed action stops processing of current file.
Defaults: PATH is current directory, action is '-print'

	-L,-follow	Follow symlinks
	-H		...on command line only
	-xdev		Don't descend directories on other filesystems
	-maxdepth N	Descend at most N levels. -maxdepth 0 applies
			actions to command line arguments only
	-mindepth N	Don't act on first N levels
	-depth		Act on directory *after* traversing it

Actions:
	( ACTIONS )	Group actions for -o / -a
	! ACT		Invert ACT's success/failure
	ACT1 [-a] ACT2	If ACT1 fails, stop, else do ACT2
	ACT1 -o ACT2	If ACT1 succeeds, stop, else do ACT2
			Note: -a has higher priority than -o
	-name PATTERN	Match file name (w/o directory name) to PATTERN
	-iname PATTERN	Case insensitive -name
	-path PATTERN	Match path to PATTERN
	-ipath PATTERN	Case insensitive -path
	-regex PATTERN	Match path to regex PATTERN
	-type X		File type is X (one of: f,d,l,b,c,s,p)
	-executable	File is executable
	-perm MASK	At least one mask bit (+MASK), all bits (-MASK),
			or exactly MASK bits are set in file's mode
	-mtime DAYS	mtime is greater than (+N), less than (-N),
			or exactly N days in the past
	-atime DAYS	atime +N/-N/N days in the past
	-ctime DAYS	ctime +N/-N/N days in the past
	-mmin MINS	mtime is greater than (+N), less than (-N),
			or exactly N minutes in the past
	-newer FILE	mtime is more recent than FILE's
	-inum N		File has inode number N
	-user NAME/ID	File is owned by given user
	-group NAME/ID	File is owned by given group
	-size N[bck]	File size is N (c:bytes,k:kbytes,b:512 bytes(def.))
			+/-N: file size is bigger/smaller than N
	-links N	Number of links is greater than (+N), less than (-N),
			or exactly N
	-empty		Match empty file/directory
	-prune		If current file is directory, don't descend into it
If none of the following actions is specified, -print is assumed
	-print		Print file name
	-print0		Print file name, NUL terminated
	-exec CMD ARG ;	Run CMD with all instances of {} replaced by
			file name. Fails if CMD exits with nonzero
	-exec CMD ARG + Run CMD with {} replaced by list of file names
	-ok CMD ARG ;   Prompt and run CMD with {} replaced
	-delete		Delete current file/directory. Turns on -depth option
	-quit		Exit
sync-hermes-context.sh: line 107: cd: /tmp/hdcs-gate-dst/.hc-stage.9936: No such file or directory
find: unrecognized: -printf
BusyBox v1.37.0 (2026-01-10 15:38:28 UTC) multi-call binary.

Usage: find [-HL] [PATH]... [OPTIONS] [ACTIONS]

Search for files and perform actions on them.
First failed action stops processing of current file.
Defaults: PATH is current directory, action is '-print'

	-L,-follow	Follow symlinks
	-H		...on command line only
	-xdev		Don't descend directories on other filesystems
	-maxdepth N	Descend at most N levels. -maxdepth 0 applies
			actions to command line arguments only
	-mindepth N	Don't act on first N levels
	-depth		Act on directory *after* traversing it

Actions:
	( ACTIONS )	Group actions for -o / -a
	! ACT		Invert ACT's success/failure
	ACT1 [-a] ACT2	If ACT1 fails, stop, else do ACT2
	ACT1 -o ACT2	If ACT1 succeeds, stop, else do ACT2
			Note: -a has higher priority than -o
	-name PATTERN	Match file name (w/o directory name) to PATTERN
	-iname PATTERN	Case insensitive -name
	-path PATTERN	Match path to PATTERN
	-ipath PATTERN	Case insensitive -path
	-regex PATTERN	Match path to regex PATTERN
	-type X		File type is X (one of: f,d,l,b,c,s,p)
	-executable	File is executable
	-perm MASK	At least one mask bit (+MASK), all bits (-MASK),
			or exactly MASK bits are set in file's mode
	-mtime DAYS	mtime is greater than (+N), less than (-N),
			or exactly N days in the past
	-atime DAYS	atime +N/-N/N days in the past
	-ctime DAYS	ctime +N/-N/N days in the past
	-mmin MINS	mtime is greater than (+N), less than (-N),
			or exactly N minutes in the past
	-newer FILE	mtime is more recent than FILE's
	-inum N		File has inode number N
	-user NAME/ID	File is owned by given user
	-group NAME/ID	File is owned by given group
	-size N[bck]	File size is N (c:bytes,k:kbytes,b:512 bytes(def.))
			+/-N: file size is bigger/smaller than N
	-links N	Number of links is greater than (+N), less than (-N),
			or exactly N
	-empty		Match empty file/directory
	-prune		If current file is directory, don't descend into it
If none of the following actions is specified, -print is assumed
	-print		Print file name
	-print0		Print file name, NUL terminated
	-exec CMD ARG ;	Run CMD with all instances of {} replaced by
			file name. Fails if CMD exits with nonzero
	-exec CMD ARG + Run CMD with {} replaced by list of file names
	-ok CMD ARG ;   Prompt and run CMD with {} replaced
	-delete		Delete current file/directory. Turns on -depth option
	-quit		Exit
cp: cannot stat '/tmp/hdcs-gate-dst/.hc-stage.9936/.': No such file or directory

```

## Open questions recorded by S1
(none recorded)

## Packet
```yaml
reg: {domain: cs-devops-shell-scripting, canon: rsync flags, systemd user units (.service/.timer, systemctl --user), shell guards (realpath, exit codes), idempotent mirror semantics}
intent: >
  Build artifact dir containing sync-hermes-context.sh (rsync -> A9 exact mirror SRC->DST,
  cp/tar fallback with identical A9 semantics incl. recursive stale deletion, --dry-run
  with zero writes, idempotent, one-line real-run log to path outside DST, SRC==DST and
  A12 realpath-identity guards, A11/A13 stage->verify->touch-DST order), hermes-context.service
  + hermes-context.timer (systemd USER, 6h, no root; script standalone-capable per A3),
  README.md (install, source change, --dry-run test, correct A7 sync-strategy section).
must_keep:
  - source path is /opt/data/workspace/hermes-context/
  - dry-run mode that performs no writes
  - systemd user units, no root required
resolved:
  - "Q1: canonical SRC/DST? -> A: SRC=/opt/data/workspace/hermes-context/, DST=/workspace/hermes-context/ (exists: INDEX.md, agents/, config/) [A1]"
  - "Q2: direction? -> A: one-way host->workspace; no writes to SRC [A2]"
  - "Q3: root? -> A: systemd user units; script works standalone without systemd [A3]"
  - "Q4: rsync absent? -> A: cp -a/tar-pipe fallback, identical A9 semantics, src/->dst contents, no nesting [A4]"
  - "Q5: stale files? -> A: exact mirror, stale deleted both paths, recursive [A5,A7]"
  - "Q6: dry-run log? -> A: zero writes incl. logs; DST byte-identical [A6]"
  - "Q7: log/install placement? -> A: log outside DST always (~/.cache default); installs outside mirrored tree [A8]"
  - "Q8: mirror equivalence class? -> A: contents+structure+symlinks only; verify fail=nonzero [A9]"
  - "Q9: severity bar? -> A: normal-op FAILs block; exotic -> KNOWN_LIMITATIONS [A10]"
  - "Q10: destructive guard? -> A: SRC==DST guard; stage->verify( A13 content-compare)->touch DST [A11,A12,A13]"
workflow: {phases: [plan, scoped-build, verify, deliver], builders: dynamic, verifier: decorrelated, gate: READY|NOT_READY, max_fix_cycles: 2}
handoff: {state: S_0 + Delta -> S_1, report: [+done, -resolved, +open, +validation]}
constraints:
  - no_resurrect: MUST_KEEP items verbatim in must_keep and enforced in build
  - both sync paths converge to identical A9 end state; rsync --delete iff available
  - --dry-run: zero writes any target, incl. log path inside DST
  - log path always outside DST; install paths outside mirrored tree
  - guards (A11,A12) run before any destructive op, both paths, clean nonzero exit no writes
  - order=law: stage -> content-verify -> touch DST; staging verify fail -> nonzero
  - verify failures exit nonzero, never warn-and-exit-0
paths:
  - artifact dir: /workspace/hdcs/artifacts/hermes-context-freshness/
  - sync-hermes-context.sh, README.md (artifact dir)
  - hermes-context.service, hermes-context.timer (artifact dir; installed to ~/.config/systemd/user/)
  - script install: ~/.local/bin/sync-hermes-context.sh (outside DST per A8)
  - log default: ~/.cache/hermes-context/sync.log (outside DST per A8)
budgets: {tokens: estimate, lines: 60, fix_cycles: 2, questions: 2}
```
