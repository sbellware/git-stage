#!/usr/bin/env bash
# test-amend.sh — tests for the --amend switch

source "$(dirname "$0")/test-helper.sh"

echo "$(bold 'Testing: --amend')"
echo

setup_repo

# ── Setup: make an initial commit to amend ────────────────────────────────────
echo "foo" > file-a.txt
git add file-a.txt
git commit -q -m "Original message"

# ── Test 1: amend changes the commit message ──────────────────────────────────
bash "$GIT_STAGE" --amend "Amended message" > /dev/null
result=$(git log -1 --pretty=format:'%s')
assert "amend updates the commit message" "$result" "Amended message"

# ── Test 2: amend does not create a new commit ────────────────────────────────
count=$(git log --oneline | wc -l | tr -d ' ')
assert "amend does not create an extra commit" "$count" "2"

# ── Test 3: amend with staged file includes it in the commit ──────────────────
echo "bar" > file-b.txt
git add file-b.txt
bash "$GIT_STAGE" --amend "Amended with file-b" > /dev/null
result=$(git show --name-only --pretty=format:'' HEAD | tr -d ' \n')
if [[ "$result" == *"file-b.txt"* ]]; then
  pass "amend includes newly staged file in the commit"
else
  fail "amend should include newly staged file (got: '$result')"
fi

# ── Test 4: commit count remains the same after amend with file ───────────────
count=$(git log --oneline | wc -l | tr -d ' ')
assert "amend with file does not create an extra commit" "$count" "2"

teardown_repo
summary
