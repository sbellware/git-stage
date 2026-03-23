#!/usr/bin/env bash
# test-stage.sh — tests for the --stage switch

source "$(dirname "$0")/test-helper.sh"

echo "$(bold 'Testing: --stage')"
echo

setup_repo

# ── Test 1: stage a new file ─────────────────────────────────────────────────
echo "foo" > file-a.txt
bash "$GIT_STAGE" --stage file-a.txt > /dev/null
assert_staged "stages a new untracked file" "file-a.txt"

# ── Test 2: stage a modified tracked file ────────────────────────────────────
git add file-a.txt
git commit -q -m "Add file-a"
echo "bar" >> file-a.txt
bash "$GIT_STAGE" --stage file-a.txt > /dev/null
assert_staged "stages a modified tracked file" "file-a.txt"

# ── Test 3: stage multiple files ─────────────────────────────────────────────
echo "baz" > file-b.txt
echo "qux" > file-c.txt
bash "$GIT_STAGE" --stage file-b.txt > /dev/null
bash "$GIT_STAGE" --stage file-c.txt > /dev/null
assert_staged "stages first of multiple files" "file-b.txt"
assert_staged "stages second of multiple files" "file-c.txt"

# ── Test 4: staging a file that doesn't exist exits non-zero ─────────────────
bash "$GIT_STAGE" --stage nonexistent.txt > /dev/null 2>&1
result=$?
if [[ $result -ne 0 ]]; then
  pass "exits non-zero when file does not exist"
else
  fail "should exit non-zero when file does not exist"
fi

teardown_repo
summary
