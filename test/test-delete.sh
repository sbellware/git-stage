#!/usr/bin/env bash
# test-delete.sh — tests for the --delete switch

source "$(dirname "$0")/test-helper.sh"

echo "$(bold 'Testing: --delete')"
echo

setup_repo

# ── Test 1: delete removes an untracked file ──────────────────────────────────
echo "foo" > untracked.txt
bash "$GIT_STAGE" --delete untracked.txt > /dev/null
assert_file_not_exists "delete removes an untracked file" "untracked.txt"

# ── Test 2: delete removes an untracked directory ────────────────────────────
mkdir -p untracked-dir
echo "foo" > untracked-dir/file.txt
bash "$GIT_STAGE" --delete untracked-dir > /dev/null
assert_file_not_exists "delete removes an untracked directory" "untracked-dir"

# ── Test 3: delete on a nonexistent file exits non-zero ──────────────────────
bash "$GIT_STAGE" --delete nonexistent.txt > /dev/null 2>&1
result=$?
if [[ $result -ne 0 ]]; then
  pass "exits non-zero when file does not exist"
else
  fail "should exit non-zero when file does not exist"
fi

# ── Test 4: delete does not affect tracked files ─────────────────────────────
echo "tracked" > tracked.txt
git add tracked.txt
git commit -q -m "Add tracked.txt"
echo "foo" > untracked2.txt
bash "$GIT_STAGE" --delete untracked2.txt > /dev/null
assert_file_exists "delete does not remove tracked file" "tracked.txt"

teardown_repo
summary
