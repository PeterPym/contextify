#!/bin/bash
# CLI-03: Skill invocation tests
#
# Purpose: Validate Claude CLI skill triggering for contextify-query.
#
# @test_contract
# isolation:
#   transcripts: none
#   database: preserve
#
# database:
#   location: default
#   start:
#     exists: true
#   mutations:
#     - "Creates temporary project at /tmp/contextify-skill-test"
#   end:
#     exists: true
#
# dependencies:
#   cli_tools: [claude]
#   notes: "Skill tests require Claude CLI; skipped if unavailable."

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="CLI-03"
TEST_NAME="Skill Invocation"

TEST_PROJECT="${TEST_PROJECT:-/tmp/contextify-skill-test}"
LAST_STATUS=0

run_command() {
  local output
  set +e
  output=$("$@" 2>&1)
  LAST_STATUS=$?
  set -e
  echo "$output"
}

check_prerequisites() {
  if ! command -v claude >/dev/null 2>&1; then
    log_warn "Claude CLI not found - skipping skill tests"
    exit 0
  fi
}

setup_skill_project() {
  create_test_project "$TEST_PROJECT"
}

response_has_skill() {
  echo "$1" | grep -qiE "contextify-query|contextify-reinject|query:contextify-reinject|Skill"
}

test_skill_trigger_claude() {
  setup_skill_project
  pushd "$TEST_PROJECT" > /dev/null

  local response
  response=$(run_command claude -p --output-format json --dangerously-skip-permissions \
    "Use contextify to search our conversation history for the word 'test'")
  local status=$LAST_STATUS
  popd > /dev/null

  if [ "$status" -ne 0 ]; then
    log_error "ISSUE 7 PRESENT: Claude command failed (exit code: $status)"
    TEST_FAILED=1
    return 1
  fi

  if response_has_skill "$response"; then
    log_success "Skill trigger succeeded for natural language prompt"
    return 0
  fi

  log_error "ISSUE 7 PRESENT: Natural language did not trigger skill"
  TEST_FAILED=1
  return 1
}

test_skill_explicit_invocation() {
  setup_skill_project
  pushd "$TEST_PROJECT" > /dev/null

  local response
  response=$(run_command claude -p --output-format json --dangerously-skip-permissions \
    "/query:contextify-reinject test")
  local status=$LAST_STATUS
  popd > /dev/null

  if [ "$status" -ne 0 ]; then
    log_error "Explicit skill invocation failed (exit code: $status)"
    TEST_FAILED=1
    return 1
  fi

  if response_has_skill "$response"; then
    log_success "Explicit skill invocation works"
    return 0
  fi

  log_warn "Explicit skill invocation produced no skill signal"
  return 0
}

test_skill_alternative_phrases() {
  setup_skill_project
  pushd "$TEST_PROJECT" > /dev/null

  local phrases=(
    "search our conversation history for errors"
    "look through past sessions for the word bug"
    "find where we discussed the database"
  )

  local triggered=0
  local phrase
  for phrase in "${phrases[@]}"; do
    local response
    response=$(run_command claude -p --output-format json --dangerously-skip-permissions "$phrase")
    if response_has_skill "$response"; then
      triggered=$((triggered + 1))
    fi
  done

  popd > /dev/null

  if [ "$triggered" -ge 2 ]; then
    log_success "Alternative phrases triggered skill ($triggered/3)"
    return 0
  fi

  log_error "ISSUE 7 PRESENT: Only $triggered/3 alternative phrases triggered skill"
  TEST_FAILED=1
  return 1
}

run_skill_tests() {
  log_header "$TEST_ID: $TEST_NAME"
  check_prerequisites

  test_skill_trigger_claude || true
  test_skill_explicit_invocation || true
  test_skill_alternative_phrases || true

  exit_with_result
}

main() {
  run_skill_tests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
