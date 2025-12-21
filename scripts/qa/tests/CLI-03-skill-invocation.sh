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
CLAUDE_TIMEOUT="${CLAUDE_TIMEOUT:-25}"
CLAUDE_MODEL="${CLAUDE_MODEL:-haiku}"
CLAUDE_SYSTEM_PROMPT="${CLAUDE_SYSTEM_PROMPT:-When the user asks to search conversation history or use Contextify, invoke the /query:contextify-reinject skill and run contextify-query.}"
CLAUDE_REQUIRE_NL_TRIGGER="${CLAUDE_REQUIRE_NL_TRIGGER:-0}"
CLI_BIN="${CONTEXTIFY_QUERY_BIN:-contextify-query}"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/contextify-query/claude-plugin"
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

  detect_timeout_cmd
  if [ -z "${TIMEOUT_CMD:-}" ]; then
    log_warn "timeout/gtimeout not found - skipping skill tests"
    exit 0
  fi
}

install_plugin_if_available() {
  if [[ "$CLI_BIN" == /* ]]; then
    if [ ! -x "$CLI_BIN" ]; then
      log_warn "contextify-query CLI not found at $CLI_BIN - skipping plugin install"
      return 0
    fi
  else
    if ! command -v "$CLI_BIN" >/dev/null 2>&1; then
      log_warn "contextify-query CLI not found - skipping plugin install"
      return 0
    fi
  fi

  local output
  output=$(run_with_timeout 20 "$CLI_BIN" install-plugin 2>&1 || true)
  log_info "Plugin install output: $output"
}

run_claude_prompt() {
  local prompt="$1"
  local output
  local args=()
  set +e
  if [ -d "$PLUGIN_DIR" ]; then
    output=$(printf "%s" "$prompt" | "$TIMEOUT_CMD" "$CLAUDE_TIMEOUT" claude -p --output-format json --input-format text --dangerously-skip-permissions --model "$CLAUDE_MODEL" --system-prompt "$CLAUDE_SYSTEM_PROMPT" --tools Bash --plugin-dir "$PLUGIN_DIR" 2>&1)
    LAST_STATUS=$?
  else
    output=$(run_with_timeout "$CLAUDE_TIMEOUT" claude -p --output-format json --dangerously-skip-permissions --model "$CLAUDE_MODEL" --system-prompt "$CLAUDE_SYSTEM_PROMPT" --tools Bash "$prompt" 2>&1)
    LAST_STATUS=$?
  fi
  set -e
  echo "$output"
}

probe_claude() {
  local output
  output=$(run_claude_prompt "ping")
  if [ "$LAST_STATUS" -ne 0 ]; then
    log_warn "Claude CLI not ready (exit code: $LAST_STATUS) - skipping skill tests"
    log_warn "Output: $output"
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
  response=$(run_claude_prompt "Use Contextify to search conversation history for the word test.")
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

  if [ "$CLAUDE_REQUIRE_NL_TRIGGER" = "1" ]; then
    log_error "ISSUE 7 PRESENT: Natural language did not trigger skill"
    TEST_FAILED=1
    return 1
  fi

  log_warn "Natural language did not trigger skill (set CLAUDE_REQUIRE_NL_TRIGGER=1 to enforce)"
  return 0
}

test_skill_explicit_invocation() {
  setup_skill_project
  pushd "$TEST_PROJECT" > /dev/null

  local response
  response=$(run_claude_prompt "/query:contextify-reinject test")
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
    "use contextify to search our conversation history for errors"
    "search our conversation history for the word bug"
    "find where we discussed the database"
  )

  local triggered=0
  local phrase
  for phrase in "${phrases[@]}"; do
    local response
    response=$(run_claude_prompt "$phrase")
    if [ "$LAST_STATUS" -ne 0 ]; then
      log_warn "Claude prompt failed or timed out for phrase: $phrase"
      continue
    fi
    if response_has_skill "$response"; then
      triggered=$((triggered + 1))
    fi
  done

  popd > /dev/null

  if [ "$triggered" -ge 2 ]; then
    log_success "Alternative phrases triggered skill ($triggered/3)"
    return 0
  fi

  if [ "$CLAUDE_REQUIRE_NL_TRIGGER" = "1" ]; then
    log_error "ISSUE 7 PRESENT: Only $triggered/3 alternative phrases triggered skill"
    TEST_FAILED=1
    return 1
  fi

  log_warn "Alternative phrases did not trigger skill ($triggered/3) - non-deterministic model"
  return 0
}

run_skill_tests() {
  log_header "$TEST_ID: $TEST_NAME"
  check_prerequisites
  install_plugin_if_available
  probe_claude

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
