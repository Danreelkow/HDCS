```
state: s0 := backup-doctor.sh at artifact root with defect: 'hdcs clean' branch executes
  unscoped `git -C "$HDCS" status --porcelain`; combined with is_repo's up-walk via
  rev-parse, a non-repo hdcs/ inside a repo parent misattributes parent dirt; a truly
  committed subtree inside a dirty parent (FIXTURE A) wrongly FAILs. All other checks,
  CLI contract (positional START_DIR arg, BACKUP_DOCTOR_TMP_ROOT, DSH_HOME), read-only
  discipline, exit semantics (0 all-PASS / 1 any-FAIL) are correct and byte-frozen.
Δ := 
  step 1: In the `HDCS=$(repo_path hdcs)` block ONLY, replace the elif/else status
    clause with subtree-scoped logic. Resolve the enclosing repo WITHOUT is_repo's
    git-dir walk:
      toplevel=$(run_bounded git -C "$HDCS" rev-parse --show-toplevel 2>/dev/null) || toplevel=''
    Branches:
      a) [[ ! -d $HDCS ]] || [[ -z $toplevel ]] ->
         check 'hdcs clean' "not a git repository: $HDCS"
      b) [[ -n $(run_bounded git -C "$toplevel" status --porcelain -- "$HDCS" 2>/dev/null) ]] ->
         check 'hdcs clean' 'uncommitted changes detected'
      c) else -> check 'hdcs clean' 'PASS: working tree clean'
    expected output: exactly one branch per run; branch b query is
      git -C <enclosing_toplevel> status --porcelain -- "$HDCS"  (A1 shape).
  step 2: Touch nothing else — no edits to: dsh-src block, hdcs-export block, umbrella
    remotes block, staged-secrets loop, AGENTS.md check, check(), run_bounded, is_repo,
    has_remote, repo_path, header, set -u, final `exit "$failures"`.
    expected output: diff vs source is confined to the hdcs clean block.
  step 3: Confirm final `exit "$failures"` retained — check() increments failures on
    FAIL, so overall exit is 0 iff all PASS, 1 iff any FAIL (never a count).
    expected output: last executable line is `exit "$failures"`.
accept:
  1. FIXTURE A: tree = committed dsh-src repo + committed hdcs repo/ OR hdcs subdir fully
     committed, parent repo with dirt OUTSIDE hdcs/ -> line `PASS hdcs clean:` present;
     overall exit status 0.
  2. FIXTURE B: uncommitted modification on a tracked file inside hdcs/ ->
     line `FAIL hdcs clean: uncommitted changes detected` present; overall exit status 1.
  3. NO-REPO: hdcs/ inside no repository at all -> `FAIL hdcs clean: not a git repository: <path>`;
     exit 1 (this branch is the only hdcs-clean failure mode; no other refusal text needed).
  4. grep of artifact: every git status invocation touching hdcs is
     `git -C "$toplevel" status --porcelain -- "$HDCS"`; zero occurrences of an
     unscoped hdcs status (git -C "$HDCS" status --porcelain with no -- pathspec).
  5. All other check names byte-identical to source: 'dsh-src exists', 'dsh-src is a git
     repository', 'dsh-src is not shallow', 'dsh-src has github remote', 'hdcs clean',
     'hdcs-export repository', 'umbrella remotes', 'staged secrets',
     'AGENTS.md protocol mention'.
  6. All git invocations wrapped in run_bounded; script performs no writes (read-only);
     `exit "$failures"` is final line.
constraints:
  - A1: hdcs verdict derives only from `git -C <enclosing_repo> status --porcelain -- <subtree>`; no parent-walk status
  - A1-refusal: no enclosing repo -> "A1: git query unscoped — parent-repo state is not subtree state" semantics preserved via not-a-repo branch; no crash, exit 1
  - A2: CLI byte-compatible (positional root arg, BACKUP_DOCTOR_TMP_ROOT, DSH_HOME); no_resurrect(a2-contract); read-only; bounded subprocesses
  - A3: exit 0 iff all PASS, exit 1 iff any FAIL; never a failure count other than 0/1 at exit
deliverable:
  - backup-doctor.sh
```