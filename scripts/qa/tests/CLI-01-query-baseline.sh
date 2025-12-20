#!/bin/bash
# CLI-01: contextify-query baseline regression tests
#
# Purpose: Validate expected working behavior for contextify-query.
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
#     min_transcripts: 1
#   mutations:
#     - "None (read-only CLI queries)"
#   end:
#     exists: true
#     transcripts: unchanged
#
# dependencies:
#   cli_tools: [contextify-query, jq]
#   notes: "Requires a populated database."

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="CLI-01"
TEST_NAME="Query Baseline"
CLI_BIN="${CONTEXTIFY_QUERY_BIN:-contextify-query}"

CLI_SEARCH_TERM="${CLI_SEARCH_TERM:-}"
CLI_DAYS="${CLI_DAYS:-365}"
CLI_LIMIT="${CLI_LIMIT:-5}"

LAST_STATUS=0

run_command() {
  local output
  set +e
  output=$("$@" 2>&1)
  LAST_STATUS=$?
  set -e
  echo "$output"
}

require_ok_status() {
  local desc="$1"
  if [ "$LAST_STATUS" -ne 0 ]; then
    log_error "ASSERTION FAILED: $desc (exit code: $LAST_STATUS)"
    TEST_FAILED=1
    return 1
  fi
  return 0
}

json_length() {
  echo "$1" | jq '.data | length' 2>/dev/null || echo "-1"
}

collect_terms() {
  local activity
  set +e
  activity=$("$CLI_BIN" activity --days "$CLI_DAYS" --limit 5 --json 2>/dev/null)
  set -e

  if [ -z "$activity" ]; then
    return 0
  fi

  echo "$activity" | jq -r '.data[].content // empty' 2>/dev/null | \
    tr -cs '[:alnum:]' '\n' | \
    awk 'length($0) >= 4 { print tolower($0) }' | \
    head -n 10
}

resolve_search_term() {
  if [ -n "$CLI_SEARCH_TERM" ]; then
    echo "$CLI_SEARCH_TERM"
    return 0
  fi

  local term
  term=$(collect_terms | head -n 1)
  if [ -z "$term" ]; then
    term="contextify"
  fi
  echo "$term"
}

resolve_or_terms() {
  local terms
  terms=($(collect_terms | head -n 3))
  if [ "${#terms[@]}" -lt 3 ]; then
    terms=("contextify" "search" "history")
  fi
  echo "${terms[@]}"
}

check_prerequisites() {
  if [[ "$CLI_BIN" == /* ]]; then
    if [ ! -x "$CLI_BIN" ]; then
      log_error "ASSERTION FAILED: contextify-query CLI not found at $CLI_BIN"
      TEST_FAILED=1
      exit 1
    fi
    log_success "✓ contextify-query CLI available ($CLI_BIN)"
  else
    if ! assert_command_exists "$CLI_BIN" "contextify-query CLI available"; then
      exit 1
    fi
  fi
  if ! assert_command_exists "jq" "jq available"; then
    exit 1
  fi
}

test_basic_search() {
  local result
  local term
  term=$(resolve_search_term)
  result=$(run_command "$CLI_BIN" search "$term" --days "$CLI_DAYS" --limit "$CLI_LIMIT" --json)
  if ! require_ok_status "Basic search command succeeds"; then
    return 1
  fi

  local count
  count=$(json_length "$result")
  if ! assert_greater_than "$count" 0 "Basic search returns results"; then
    return 1
  fi
}

test_status_command() {
  local result
  result=$(run_command "$CLI_BIN" status --json)
  if ! require_ok_status "Status command succeeds"; then
    return 1
  fi

  if ! assert_contains "$result" '"type"' "Status returns JSON"; then
    return 1
  fi

  local db_path
  db_path=$(echo "$result" | jq -r '.data.databasePath // empty' 2>/dev/null || echo "")
  if ! assert_not_empty "$db_path" "Status includes database path"; then
    return 1
  fi
}

test_projects_command() {
  local result
  result=$(run_command "$CLI_BIN" projects --json)
  if ! require_ok_status "Projects command succeeds"; then
    return 1
  fi
  if ! assert_contains "$result" '"type"' "Projects returns JSON"; then
    return 1
  fi
}

test_transcripts_command() {
  local result
  result=$(run_command "$CLI_BIN" transcripts --project . --limit 5 --json)
  if ! require_ok_status "Transcripts command succeeds"; then
    return 1
  fi
  if ! assert_contains "$result" '"type"' "Transcripts returns JSON"; then
    return 1
  fi
}

test_context_command() {
  local search
  local term
  term=$(resolve_search_term)
  search=$(run_command "$CLI_BIN" search "$term" --days "$CLI_DAYS" --limit 1 --json)
  if ! require_ok_status "Context search succeeds"; then
    return 1
  fi

  local entry_id
  entry_id=$(echo "$search" | jq -r '.data[0].id // empty' 2>/dev/null || echo "")
  if [ -z "$entry_id" ]; then
    log_warn "No entries found for context test - skipping"
    return 0
  fi

  local result
  result=$(run_command "$CLI_BIN" context "$entry_id" --before 2 --after 2 --json)
  if ! require_ok_status "Context command succeeds"; then
    return 1
  fi

  if ! echo "$result" | jq -e '.data | has("anchor")' >/dev/null 2>&1; then
    log_error "ASSERTION FAILED: Context output includes anchor"
    TEST_FAILED=1
    return 1
  fi
  log_success "Context output includes anchor"
}

test_fts5_or_two_terms() {
  local result
  local terms
  terms=($(resolve_or_terms))
  result=$(run_command "$CLI_BIN" search "${terms[0]} OR ${terms[1]}" --days "$CLI_DAYS" --limit "$CLI_LIMIT" --json)
  if ! require_ok_status "FTS5 OR with two terms succeeds"; then
    return 1
  fi

  local count
  count=$(json_length "$result")
  if ! assert_greater_than "$count" 0 "FTS5 OR with two terms returns results"; then
    return 1
  fi
}

test_fts5_or_three_terms() {
  local result
  local terms
  terms=($(resolve_or_terms))
  result=$(run_command "$CLI_BIN" search "${terms[0]} OR ${terms[1]} OR ${terms[2]}" --days "$CLI_DAYS" --limit "$CLI_LIMIT" --json)
  if ! require_ok_status "FTS5 OR with three terms succeeds"; then
    return 1
  fi

  local count
  count=$(json_length "$result")
  if ! assert_greater_than "$count" 0 "FTS5 OR with three terms returns results"; then
    return 1
  fi
}

test_limit_parameter() {
  local result
  local term
  term=$(resolve_search_term)
  result=$(run_command "$CLI_BIN" search "$term" --days "$CLI_DAYS" --limit 3 --json)
  if ! require_ok_status "Search with limit succeeds"; then
    return 1
  fi

  local count
  count=$(json_length "$result")
  if ! assert_less_than "$count" 4 "Limit 3 returns <= 3 results"; then
    return 1
  fi
}

test_days_parameter() {
  local result
  local term
  term=$(resolve_search_term)
  result=$(run_command "$CLI_BIN" search "$term" --days 1 --limit "$CLI_LIMIT" --json)
  if ! require_ok_status "Search with days parameter succeeds"; then
    return 1
  fi

  if ! echo "$result" | jq -e '.type == "search"' >/dev/null 2>&1; then
    log_error "ASSERTION FAILED: Days parameter returns search response"
    TEST_FAILED=1
    return 1
  fi
  log_success "Days parameter returns search response"
}

test_json_output_valid() {
  local result
  local term
  term=$(resolve_search_term)
  result=$(run_command "$CLI_BIN" search "$term" --days "$CLI_DAYS" --limit "$CLI_LIMIT" --json)
  if ! require_ok_status "JSON output command succeeds"; then
    return 1
  fi

  if ! echo "$result" | jq . >/dev/null 2>&1; then
    log_error "ASSERTION FAILED: JSON output is valid"
    TEST_FAILED=1
    return 1
  fi
  log_success "JSON output is valid"
}

run_baseline_tests() {
  log_header "$TEST_ID: $TEST_NAME"
  check_prerequisites

  test_basic_search || true
  test_status_command || true
  test_projects_command || true
  test_transcripts_command || true
  test_context_command || true
  test_fts5_or_two_terms || true
  test_fts5_or_three_terms || true
  test_limit_parameter || true
  test_days_parameter || true
  test_json_output_valid || true

  exit_with_result
}

main() {
  run_baseline_tests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
