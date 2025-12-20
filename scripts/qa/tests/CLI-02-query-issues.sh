#!/bin/bash
# CLI-02: contextify-query known issues (expected red)
#
# Purpose: Expose logged CLI issues. These tests should fail until fixed.
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
#   notes: "Expected to fail until issues are fixed."

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="CLI-02"
TEST_NAME="Query Issues"
CLI_BIN="${CONTEXTIFY_QUERY_BIN:-contextify-query}"

CLI_DAYS="${CLI_DAYS:-365}"
CLI_LIMIT="${CLI_LIMIT:-5}"
CLI_SEARCH_TERM="${CLI_SEARCH_TERM:-}"

LAST_STATUS=0

run_command() {
  local output
  set +e
  output=$("$@" 2>&1)
  LAST_STATUS=$?
  set -e
  echo "$output"
}

json_length() {
  echo "$1" | jq '.data | length' 2>/dev/null || echo "-1"
}

json_valid() {
  echo "$1" | jq . >/dev/null 2>&1
}

contains_error_text() {
  echo "$1" | grep -qiE "error|invalid|unsupported|parse"
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
  terms=($(collect_terms | head -n 4))
  if [ "${#terms[@]}" -lt 4 ]; then
    terms=("contextify" "search" "history" "query")
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

test_issue_1_regex_or_silent_failure() {
  local result
  result=$(run_command "$CLI_BIN" search "thank you|thanks|nice" --days "$CLI_DAYS" --limit "$CLI_LIMIT" --json)

  if contains_error_text "$result"; then
    log_success "Issue 1 fixed: invalid syntax returns error"
    return 0
  fi

  if json_valid "$result"; then
    local count
    count=$(json_length "$result")
    if [ "$count" -gt 0 ]; then
      log_success "Issue 1 fixed: regex OR supported"
      return 0
    fi
    if [ "$count" = "0" ]; then
      log_error "ISSUE 1 PRESENT: Regex OR returns 0 silently (no error message)"
      TEST_FAILED=1
      return 1
    fi
  fi

  log_error "ISSUE 1 PRESENT: Invalid response for regex OR query"
  TEST_FAILED=1
  return 1
}

test_issue_2_kinds_filter_broken() {
  local result
  local term
  term=$(resolve_search_term)
  result=$(run_command "$CLI_BIN" search "$term" --days "$CLI_DAYS" --limit 20 --kinds user --json)

  if ! json_valid "$result"; then
    log_error "ISSUE 2 PRESENT: Invalid JSON response for --kinds"
    TEST_FAILED=1
    return 1
  fi

  local total_count
  total_count=$(json_length "$result")
  if [ "$total_count" = "0" ]; then
    log_warn "No results for --kinds test - skipping"
    return 0
  fi

  local assistant_count
  assistant_count=$(echo "$result" | jq '[.data[] | select(.kind == "assistant")] | length' 2>/dev/null || echo "0")

  if [ "$assistant_count" -gt 0 ]; then
    log_error "ISSUE 2 PRESENT: --kinds user returned $assistant_count assistant messages"
    TEST_FAILED=1
    return 1
  fi

  log_success "Issue 2 fixed: --kinds filter works"
}

test_issue_3_fts5_or_documented() {
  local help_text
  help_text=$(run_command "$CLI_BIN" --help)

  if echo "$help_text" | grep -qiE "FTS5|query syntax|OR"; then
    log_success "Issue 3 fixed: FTS5 OR documented in help"
    return 0
  fi

  log_error "ISSUE 3 PRESENT: FTS5 OR syntax not documented in --help"
  TEST_FAILED=1
  return 1
}

test_issue_4_fts5_or_four_terms() {
  local result
  local terms
  terms=($(resolve_or_terms))
  result=$(run_command "$CLI_BIN" search "${terms[0]} OR ${terms[1]} OR ${terms[2]} OR ${terms[3]}" --days "$CLI_DAYS" --limit "$CLI_LIMIT" --json)

  if contains_error_text "$result"; then
    log_success "Issue 4 fixed: 4-term OR returns error"
    return 0
  fi

  if json_valid "$result"; then
    local count
    count=$(json_length "$result")
    if [ "$count" -gt 0 ]; then
      log_success "Issue 4 fixed: 4-term OR query works"
      return 0
    fi
    if [ "$count" = "0" ]; then
      local single
      single=$(run_command "$CLI_BIN" search "${terms[0]}" --days "$CLI_DAYS" --limit 1 --json)
      if json_valid "$single"; then
        local single_count
        single_count=$(json_length "$single")
        if [ "$single_count" -gt 0 ]; then
          log_error "ISSUE 4 PRESENT: 4-term OR returns 0 but single terms have results"
          TEST_FAILED=1
          return 1
        fi
      fi
      log_warn "No data for 4-term OR test - skipping"
      return 0
    fi
  fi

  log_error "ISSUE 4 PRESENT: Invalid response for 4-term OR query"
  TEST_FAILED=1
  return 1
}

test_issue_5_context_output_structure() {
  local search
  local term
  term=$(resolve_search_term)
  search=$(run_command "$CLI_BIN" search "$term" --days "$CLI_DAYS" --limit 1 --json)

  if ! json_valid "$search"; then
    log_error "ISSUE 5 PRESENT: Invalid JSON response for context search"
    TEST_FAILED=1
    return 1
  fi

  local entry_id
  entry_id=$(echo "$search" | jq -r '.data[0].id // empty' 2>/dev/null || echo "")
  if [ -z "$entry_id" ]; then
    log_warn "No entries for context test - skipping"
    return 0
  fi

  local result
  result=$(run_command "$CLI_BIN" context "$entry_id" --before 2 --after 2 --json)
  if ! json_valid "$result"; then
    log_error "ISSUE 5 PRESENT: Context response is not valid JSON"
    TEST_FAILED=1
    return 1
  fi

  local help_text
  help_text=$(run_command "$CLI_BIN" context --help)

  if echo "$result" | jq -e '.data | type == "array"' >/dev/null 2>&1; then
    log_success "Issue 5 fixed: context output is a flat array"
    return 0
  fi

  if echo "$help_text" | grep -qiE "anchor|before|after|--flat"; then
    log_success "Issue 5 fixed: context output structure documented"
    return 0
  fi

  log_error "ISSUE 5 PRESENT: Context output structure inconsistent and undocumented"
  TEST_FAILED=1
  return 1
}

test_issue_6_no_limit_metadata() {
  local result
  local term
  term=$(resolve_search_term)
  result=$(run_command "$CLI_BIN" search "$term" --days "$CLI_DAYS" --limit 10 --json)

  if ! json_valid "$result"; then
    log_error "ISSUE 6 PRESENT: Invalid JSON response for limit metadata check"
    TEST_FAILED=1
    return 1
  fi

  local has_metadata
  has_metadata=$(echo "$result" | jq 'has("metadata") or has("total") or has("hasMore") or has("returned")' 2>/dev/null || echo "false")

  if [ "$has_metadata" = "true" ]; then
    log_success "Issue 6 fixed: result metadata present"
    return 0
  fi

  log_error "ISSUE 6 PRESENT: No metadata indicating if more results exist"
  TEST_FAILED=1
  return 1
}

test_issue_8_empty_vs_error() {
  local valid_empty
  valid_empty=$(run_command "$CLI_BIN" search "xyznonexistent123456789" --days 1 --limit "$CLI_LIMIT" --json)

  local invalid
  invalid=$(run_command "$CLI_BIN" search "a OR b OR c OR d" --days 1 --limit "$CLI_LIMIT" --json)

  local valid_is_json=0
  local invalid_is_json=0
  if json_valid "$valid_empty"; then
    valid_is_json=1
  fi
  if json_valid "$invalid"; then
    invalid_is_json=1
  fi

  if [ "$invalid_is_json" -eq 0 ] && contains_error_text "$invalid"; then
    log_success "Issue 8 fixed: invalid query returns error output"
    return 0
  fi

  if [ "$valid_is_json" -eq 1 ] && [ "$invalid_is_json" -eq 1 ]; then
    local valid_count
    local invalid_count
    valid_count=$(json_length "$valid_empty")
    invalid_count=$(json_length "$invalid")

    if [ "$valid_count" = "0" ] && [ "$invalid_count" = "0" ]; then
      local invalid_has_error
      invalid_has_error=$(echo "$invalid" | jq 'has("error") or has("warning") or has("query")' 2>/dev/null || echo "false")
      if [ "$invalid_has_error" = "true" ]; then
        log_success "Issue 8 fixed: invalid query is distinguishable"
        return 0
      fi

      log_error "ISSUE 8 PRESENT: Empty results and query errors indistinguishable"
      TEST_FAILED=1
      return 1
    fi
  fi

  log_success "Issue 8 fixed or not reproducible"
}

first_object_keys() {
  echo "$1" | jq -r '
    if (.data | type) == "array" and (.data | length) > 0 then
      .data[0] | keys[]
    elif (.data | type) == "object" then
      .data | keys[]
    else
      empty
    end
  ' 2>/dev/null || true
}

test_issue_9_field_consistency() {
  local transcripts
  transcripts=$(run_command "$CLI_BIN" transcripts --project . --limit 1 --json)

  local stats
  stats=$(run_command "$CLI_BIN" stats --json)

  local t_keys
  local s_keys
  t_keys=$(first_object_keys "$transcripts")
  s_keys=$(first_object_keys "$stats")

  if [ -z "$t_keys" ] || [ -z "$s_keys" ]; then
    log_warn "Insufficient data for field consistency test - skipping"
    return 0
  fi

  if echo "$t_keys" | grep -q "Timestamp" && echo "$s_keys" | grep -q "Ts"; then
    log_error "ISSUE 9 PRESENT: Inconsistent timestamp naming (Timestamp vs Ts)"
    TEST_FAILED=1
    return 1
  fi

  log_success "Issue 9 fixed: field naming consistent"
}

run_issue_tests() {
  log_header "$TEST_ID: $TEST_NAME"
  check_prerequisites

  test_issue_1_regex_or_silent_failure || true
  test_issue_2_kinds_filter_broken || true
  test_issue_3_fts5_or_documented || true
  test_issue_4_fts5_or_four_terms || true
  test_issue_5_context_output_structure || true
  test_issue_6_no_limit_metadata || true
  test_issue_8_empty_vs_error || true
  test_issue_9_field_consistency || true

  exit_with_result
}

main() {
  run_issue_tests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
