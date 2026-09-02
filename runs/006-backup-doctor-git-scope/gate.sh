#!/usr/bin/env bash
# Gate 006: git-scope repair. Proves parent-walk dirt cannot fail a subtree check (A),
# and genuine subtree dirt still fails (B). Fixture discipline: mktemp scratch, bounded runs.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ART="$HERE/artifact"
fail(){ echo "GATE FAIL: $*"; exit 1; }
[ -f "$ART/backup-doctor.sh" ] || fail "artifact missing backup-doctor.sh"
bash -n "$ART/backup-doctor.sh" || fail "backup-doctor.sh fails bash -n"

mkfix(){ # $1 dirty_subtree 0|1
  local d; d="$(mktemp -d)" || fail "mktemp"
  git -C "$d" init -q root
  git -C "$d/root" config user.email t@t.local
  git -C "$d/root" config user.name t
  mkdir -p "$d/root/hdcs"
  echo base > "$d/root/hdcs/f.txt"
  echo base > "$d/root/sibling.txt"
  git -C "$d/root" add hdcs sibling.txt
  git -C "$d/root" commit -qm init
  echo dirt >> "$d/root/sibling.txt"   # the trap: dirty OUTSIDE the audited subtree
  [ "$1" = 1 ] && echo dirt >> "$d/root/hdcs/f.txt"
  git -C "$d/root" init -q dsh-src
  git -C "$d/root/dsh-src" remote add github git@github.com:x/y.git
  mkdir -p "$d/exp"
  git -C "$d/exp" init -q hdcs-export
  git -C "$d/exp/hdcs-export" remote add origin git@github.com:x/e.git
  mkdir -p "$d/home"
  echo "GitHub backup protocol" > "$d/home/AGENTS.md"
  echo "$d"
}

DOC="$ART/backup-doctor.sh"

A="$(mkfix 0)"
outA="$(DSH_HOME="$A/home" BACKUP_DOCTOR_TMP_ROOT="$A/exp" timeout 25 bash "$DOC" "$A/root" 2>&1)"; rcA=$?
grep -q 'FAIL hdcs clean' <<<"$outA" && fail "FIXTURE A: false positive — parent-repo dirt outside the audited subtree failed the subtree check (the exact live defect)"
[ "$rcA" -eq 0 ] || fail "FIXTURE A: expected exit 0 on all-healthy fixture, got $rcA (output: $(echo "$outA" | grep FAIL | head -2))"

B="$(mkfix 1)"
outB="$(DSH_HOME="$B/home" BACKUP_DOCTOR_TMP_ROOT="$B/export" timeout 25 bash "$DOC" "$B/root" 2>&1)"; rcB=$?
grep -q 'FAIL hdcs clean' <<<"$outB" || fail "FIXTURE B: doctor missed a genuine uncommitted change INSIDE the audited subtree (wall, not gate)"
[ "$rcB" -eq 1 ] || fail "FIXTURE B: expected exit 1, got $rcB"

echo "GATE PASS"
exit 0
