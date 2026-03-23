#!/usr/bin/env bash
# test-helper.sh — shared utilities for git-stage test scripts

PASS=0
FAIL=0
GIT_STAGE="${GIT_STAGE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/git-stage.sh}"

green() { printf '\033[32m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }
bold()  { printf '\033[1m%s\033[0m'  "$*"; }
dim()   { printf '\033[2m%s\033[0m'  "$*"; }

pass() { (( PASS++ )); echo "  $(green '✓') $1"; }
fail() { (( FAIL++ )); echo "  $(red   '✗') $1"; }

assert() {
  local description="$1" result="$2" expected="$3"
  if [[ "$result" == "$expected" ]]; then
    pass "$description"
  else
    fail "$description (expected: '$expected', got: '$result')"
  fi
}

assert_file_exists() {
  local description="$1" file="$2"
  if [[ -e "$file" ]]; then
    pass "$description"
  else
    fail "$description (file not found: $file)"
  fi
}

assert_file_not_exists() {
  local description="$1" file="$2"
  if [[ ! -e "$file" ]]; then
    pass "$description"
  else
    fail "$description (file should not exist: $file)"
  fi
}

assert_staged() {
  local description="$1" file="$2"
  local xy
  xy=$(git status --porcelain -- "$file" 2>/dev/null | head -1)
  local x="${xy:0:1}"
  if [[ "$x" != " " && "$x" != "?" && -n "$x" ]]; then
    pass "$description"
  else
    fail "$description (file is not staged: $file, status: '$xy')"
  fi
}

assert_not_staged() {
  local description="$1" file="$2"
  local xy
  xy=$(git status --porcelain -- "$file" 2>/dev/null | head -1)
  local x="${xy:0:1}"
  if [[ "$x" == " " || "$x" == "?" || -z "$x" ]]; then
    pass "$description"
  else
    fail "$description (file should not be staged: $file, status: '$xy')"
  fi
}

assert_committed() {
  local description="$1" file="$2"
  local xy
  xy=$(git status --porcelain -- "$file" 2>/dev/null | head -1)
  if [[ -z "$xy" ]]; then
    pass "$description"
  else
    fail "$description (file has uncommitted changes: $file, status: '$xy')"
  fi
}

setup_repo() {
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR" || exit 1
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test User"
  # Create an initial commit so HEAD exists
  echo "initial" > .gitkeep
  git add .gitkeep
  git commit -q -m "Initial commit"
}

teardown_repo() {
  cd / || true
  rm -rf "$TMPDIR"
}

summary() {
  local total=$(( PASS + FAIL ))
  echo
  echo "$(bold "Results:") $total tests — $(green "$PASS passed") $(dim ',') $(red "$FAIL failed")"
  echo
  [[ $FAIL -eq 0 ]]
}
