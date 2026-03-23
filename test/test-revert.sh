#!/usr/bin/env bash
# test-revert.sh — tests for the --revert switch

source "$(dirname "$0")/test-helper.sh"

echo "$(bold 'Testing: --revert')"
echo

setup_repo

# ── Setup: commit a file then modify it ──────────────────────────────────────
echo "original content" > file-a.txt
git add file-a.txt
git commit -q -m "Add file-a"

# ── Test 1: revert restores file to last committed state ──────────────────────
echo "modified content" > file-a.txt
bash "$GIT_STAGE" --revert file-a.txt > /dev/null
result=$(cat file-a.txt)
assert "revert restores file to committed content" "$result" "original content"

# ── Test 2: reverted file has no worktree changes ─────────────────────────────
xy=$(git status --porcelain -- file-a.txt)
assert "reverted file shows no worktree changes" "$xy" ""

# ── Test 3: revert does not affect staged changes ─────────────────────────────
echo "staged content" > file-b.txt
git add file-b.txt
echo "modified content" > file-a.txt
bash "$GIT_STAGE" --revert file-a.txt > /dev/null
assert_staged "revert does not affect other staged files" "file-b.txt"

# ── Test 4: revert on a file with no changes exits non-zero ──────────────────
bash "$GIT_STAGE" --revert file-a.txt > /dev/null 2>&1
result=$?
if [[ $result -ne 0 ]]; then
  pass "exits non-zero when file has no changes to revert"
else
  fail "should exit non-zero when file has no changes to revert"
fi

teardown_repo
summary
