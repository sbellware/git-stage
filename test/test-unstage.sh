#!/usr/bin/env bash
# test-unstage.sh — tests for the --unstage switch

source "$(dirname "$0")/test-helper.sh"

echo "$(bold 'Testing: --unstage')"
echo

setup_repo

# ── Test 1: unstage a staged new file ────────────────────────────────────────
echo "foo" > file-a.txt
git add file-a.txt
bash "$GIT_STAGE" --unstage file-a.txt > /dev/null
assert_not_staged "unstages a newly added file" "file-a.txt"

# ── Test 2: unstage a staged modification ────────────────────────────────────
git add file-a.txt
git commit -q -m "Add file-a"
echo "bar" >> file-a.txt
git add file-a.txt
bash "$GIT_STAGE" --unstage file-a.txt > /dev/null
assert_not_staged "unstages a staged modification" "file-a.txt"

# ── Test 3: unstaging leaves worktree changes intact ─────────────────────────
result=$(git status --porcelain -- file-a.txt | cut -c2)
assert "worktree changes remain after unstaging" "$result" "M"

teardown_repo
summary
