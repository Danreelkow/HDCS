#!/usr/bin/env bash
# Read-only backup protocol health checker.
set -u

START_DIR=${1:-/workspace}
TMP_ROOT=${BACKUP_DOCTOR_TMP_ROOT:-/tmp}
AGENTS_ROOT=${DSH_HOME:-${START_DIR}}
if [[ ! -d $START_DIR ]]; then
  printf 'FAIL starting directory: %s does not exist\n' "$START_DIR"
  exit 1
fi
START_DIR=$(cd -- "$START_DIR" 2>/dev/null && pwd -P) || {
  printf 'FAIL starting directory: cannot enter %s\n' "$1"
  exit 1
}

failures=0
check() {
  local name=$1 reason=$2
  if [[ $reason == PASS:* ]]; then
    printf 'PASS %s: %s\n' "$name" "${reason#PASS: }"
  else
    printf 'FAIL %s: %s\n' "$name" "$reason"
    failures=1
  fi
}

repo_path() {
  case $1 in
    dsh-src) printf '%s/dsh-src' "$START_DIR" ;;
    hdcs) printf '%s/hdcs' "$START_DIR" ;;
    umbrella) printf '%s' "$START_DIR" ;;
    export) printf '%s/hdcs-export' "$TMP_ROOT" ;;
  esac
}

run_bounded() { timeout --signal=KILL 5s "$@"; }
is_repo() { run_bounded git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }
has_remote() { run_bounded git -C "$1" remote 2>/dev/null | grep -Fxq -- "$2"; }

DSH_SRC=$(repo_path dsh-src)
if [[ ! -d $DSH_SRC ]]; then
  check 'dsh-src exists' "missing directory $DSH_SRC"
else
  check 'dsh-src exists' 'PASS: directory exists'
  if ! is_repo "$DSH_SRC"; then
    check 'dsh-src is a git repository' 'not a git repository'
    check 'dsh-src is not shallow' 'cannot inspect shallow state: not a git repository'
    check 'dsh-src has github remote' 'cannot inspect remotes: not a git repository'
  else
    check 'dsh-src is a git repository' 'PASS: git metadata found'
    if run_bounded git -C "$DSH_SRC" rev-parse --is-shallow-repository 2>/dev/null | grep -Fxq false; then
      check 'dsh-src is not shallow' 'PASS: full clone'
    else
      check 'dsh-src is not shallow' 'shallow clone or unable to determine clone depth'
    fi
    if has_remote "$DSH_SRC" github; then check 'dsh-src has github remote' 'PASS: remote github exists'; else check 'dsh-src has github remote' 'remote github is missing'; fi
  fi
fi

HDCS=$(repo_path hdcs)
if [[ ! -d $HDCS ]]; then
  check 'hdcs clean' "not a git repository: $HDCS"
else
  # A1: resolve the enclosing repository directly — never via is_repo's git-dir
  # up-walk, and never via an unscoped status at $HDCS. The verdict derives
  # ONLY from `git -C <enclosing_toplevel> status --porcelain -- "$HDCS"`:
  # parent-repo dirt outside the audited subtree is invisible here (A1_mirror),
  # while genuine uncommitted changes inside the subtree still fail (A1_neg).
  toplevel=$(run_bounded git -C "$HDCS" rev-parse --show-toplevel 2>/dev/null) || toplevel=''
  if [[ -z $toplevel ]]; then
    check 'hdcs clean' "not a git repository: $HDCS — A1: git query unscoped — parent-repo state is not subtree state"
  elif [[ -n $(run_bounded git -C "$toplevel" status --porcelain -- "$HDCS" 2>/dev/null) ]]; then
    check 'hdcs clean' 'uncommitted changes detected'
  else
    check 'hdcs clean' 'PASS: working tree clean'
  fi
fi

EXPORT=$(repo_path export)
if ! is_repo "$EXPORT"; then
  check 'hdcs-export repository' "not a git repository: $EXPORT"
elif has_remote "$EXPORT" origin; then
  check 'hdcs-export repository' 'PASS: git repository with origin remote'
else
  check 'hdcs-export repository' 'origin remote is missing'
fi

if ! is_repo "$START_DIR"; then
  check 'umbrella remotes' 'starting directory is not a git repository'
elif [[ -n $(run_bounded git -C "$START_DIR" remote 2>/dev/null) ]]; then
  check 'umbrella remotes' 'remote configured; none is allowed'
else
  check 'umbrella remotes' 'PASS: no remotes configured'
fi

secret_pattern='(AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|(^|[^A-Za-z])(api[_-]?key|secret|token)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_+/=-]{16,})'
secret_failures=0
for repo in "$DSH_SRC" "$HDCS" "$EXPORT" "$START_DIR"; do
  [[ -d $repo ]] || continue
  is_repo "$repo" || continue
  staged=$(run_bounded git -C "$repo" diff --cached --name-only --diff-filter=ACMR 2>/dev/null) || staged=''
  while IFS= read -r file; do
    [[ -n $file ]] || continue
    if run_bounded git -C "$repo" show ":$file" 2>/dev/null | LC_ALL=C grep -Eiq -- "$secret_pattern"; then
      secret_failures=$((secret_failures + 1))
    fi
  done <<< "$staged"
done
if (( secret_failures == 0 )); then
  check 'staged secrets' 'PASS: no staged API-key or private-key pattern found'
else
  reason="$secret_failures staged files contain a secret-like pattern"
  check 'staged secrets' "$reason"
fi

agents=$AGENTS_ROOT/AGENTS.md
if [[ -f $agents ]] && run_bounded grep -Fq 'GitHub backup protocol' "$agents"; then
  check 'AGENTS.md protocol mention' 'PASS: phrase found'
elif [[ -f $agents ]]; then
  check 'AGENTS.md protocol mention' 'phrase GitHub backup protocol is missing'
else
  check 'AGENTS.md protocol mention' "missing file $agents"
fi

# A3: exit 0 iff all checks PASS, exit 1 iff any check FAIL — never a count.
exit "$failures"
