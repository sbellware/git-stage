#!/usr/bin/env bash
# run-tests.sh — runs all git-stage test scripts and summarises results

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export GIT_STAGE="${GIT_STAGE:-$(cd "$SCRIPT_DIR/.." && pwd)/git-stage.sh}"

bold()  { printf '\033[1m%s\033[0m'  "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }
dim()   { printf '\033[2m%s\033[0m'  "$*"; }

if [[ ! -f "$GIT_STAGE" ]]; then
  echo "$(red 'Error:') git-stage.sh not found at: $GIT_STAGE" >&2
  echo "Set the GIT_STAGE environment variable to the correct path." >&2
  exit 1
fi

echo
echo "$(bold 'git-stage test suite')"
echo "$(dim "Script: $GIT_STAGE")"
echo

TESTS=(
  "$SCRIPT_DIR/test-stage.sh"
  "$SCRIPT_DIR/test-unstage.sh"
  "$SCRIPT_DIR/test-commit.sh"
  "$SCRIPT_DIR/test-amend.sh"
  "$SCRIPT_DIR/test-revert.sh"
  "$SCRIPT_DIR/test-delete.sh"
)

TOTAL_PASS=0
TOTAL_FAIL=0

for test in "${TESTS[@]}"; do
  if [[ ! -f "$test" ]]; then
    echo "$(red 'Missing test script:') $test"
    continue
  fi

  chmod +x "$test"
  output=$(bash "$test" 2>&1)
  exit_code=$?

  echo "$output"

  # Extract pass/fail counts from the summary line
  passed=$(echo "$output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || echo 0)
  failed=$(echo "$output" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo 0)
  TOTAL_PASS=$(( TOTAL_PASS + passed ))
  TOTAL_FAIL=$(( TOTAL_FAIL + failed ))
done

echo "$(bold '══════════════════════════════════')"
echo "$(bold 'Total:') $(( TOTAL_PASS + TOTAL_FAIL )) tests — $(green "$TOTAL_PASS passed"), $(red "$TOTAL_FAIL failed")"
echo

[[ $TOTAL_FAIL -eq 0 ]]
