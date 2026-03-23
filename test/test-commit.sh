#!/usr/bin/env bash
# test-commit.sh — tests for the --commit switch

source "$(dirname "$0")/test-helper.sh"

echo "$(bold 'Testing: --commit')"
echo

setup_repo

# ── Test 1: commit a staged file ─────────────────────────────────────────────
echo "foo" > file-a.txt
git add file-a.txt
bash "$GIT_STAGE" --commit "Add file-a" > /dev/null
assert_committed "commits a staged file" "file-a.txt"

# ── Test 2: commit message is recorded correctly ──────────────────────────────
result=$(git log -1 --pretty=format:'%s')
assert "commit message is recorded correctly" "$result" "Add file-a"

# ── Test 3: commit with nothing staged exits non-zero ────────────────────────
bash "$GIT_STAGE" --commit "Empty commit" > /dev/null 2>&1
result=$?
if [[ $result -ne 0 ]]; then
  pass "exits non-zero when nothing is staged"
else
  fail "should exit non-zero when nothing is staged"
fi

# ── Test 4: multiple files committed together ─────────────────────────────────
echo "bar" > file-b.txt
echo "baz" > file-c.txt
git add file-b.txt file-c.txt
bash "$GIT_STAGE" --commit "Add file-b and file-c" > /dev/null
assert_committed "commits first of multiple staged files" "file-b.txt"
assert_committed "commits second of multiple staged files" "file-c.txt"

teardown_repo
summary
