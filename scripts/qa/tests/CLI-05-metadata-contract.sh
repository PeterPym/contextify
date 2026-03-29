#!/bin/bash
# CLI-05: Metadata contract tests (ct-796)
#
# Purpose: Verify JSON metadata shape and CLI error semantics.
# Specifically:
#   - search --json returns databaseSummary (not scopeSummary) with correct fields
#   - status --json returns newestEntryTimestamp
#   - unknown bare project name returns dbProjectNotFound (not filesystem fallback)
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

TEST_ID="CLI-05"
TEST_NAME="Metadata Contract"
CLI_BIN="${CONTEXTIFY_QUERY_BIN:-contextify-query}"

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

check_prerequisites() {
  if [[ "$CLI_BIN" == /* ]]; then
    if [ ! -x "$CLI_BIN" ]; then
      log_error "ASSERTION FAILED: contextify-query CLI not found at $CLI_BIN"
      TEST_FAILED=1
      exit 1
    fi
    log_success "contextify-query CLI available ($CLI_BIN)"
  else
    if ! assert_command_exists "$CLI_BIN" "contextify-query CLI available"; then
      exit 1
    fi
  fi
  if ! assert_command_exists "jq" "jq available"; then
    exit 1
  fi
}

# ct-796 R1: search --json metadata contains databaseSummary, not scopeSummary
test_search_metadata_uses_databaseSummary() {
  local result
  result=$(run_command "$CLI_BIN" search "test" --days 365 --limit 1 --json)
  if ! require_ok_status "Search command succeeds"; then
    return 1
  fi

  # Must have databaseSummary
  local has_db_summary
  has_db_summary=$(echo "$result" | jq 'has("metadata") and (.metadata | has("databaseSummary"))' 2>/dev/null || echo "false")
  if [ "$has_db_summary" != "true" ]; then
    log_error "ASSERTION FAILED: metadata.databaseSummary must be present"
    TEST_FAILED=1
    return 1
  fi
  log_success "metadata.databaseSummary is present"

  # Must NOT have scopeSummary
  local has_scope_summary
  has_scope_summary=$(echo "$result" | jq '.metadata | has("scopeSummary")' 2>/dev/null || echo "true")
  if [ "$has_scope_summary" = "true" ]; then
    log_error "ASSERTION FAILED: metadata.scopeSummary must NOT be present (renamed to databaseSummary)"
    TEST_FAILED=1
    return 1
  fi
  log_success "metadata.scopeSummary is absent (correctly renamed)"
}

# ct-796 R1: databaseSummary contains required fields
test_databaseSummary_has_required_fields() {
  local result
  result=$(run_command "$CLI_BIN" search "test" --days 365 --limit 1 --json)
  if ! require_ok_status "Search command succeeds"; then
    return 1
  fi

  local summary
  summary=$(echo "$result" | jq '.metadata.databaseSummary' 2>/dev/null)

  for field in entryCount projectCount deviceCount; do
    local val
    val=$(echo "$summary" | jq ".$field // empty" 2>/dev/null)
    if [ -z "$val" ] || [ "$val" = "null" ]; then
      log_error "ASSERTION FAILED: databaseSummary.$field must be present"
      TEST_FAILED=1
      return 1
    fi
  done
  log_success "databaseSummary contains entryCount, projectCount, deviceCount"

  # Verify they are numbers >= 0
  local entry_count
  entry_count=$(echo "$summary" | jq '.entryCount' 2>/dev/null)
  if ! assert_greater_than "$entry_count" -1 "databaseSummary.entryCount is a non-negative number"; then
    return 1
  fi
}

# ct-796: status --json includes newestEntryTimestamp
test_status_includes_newestEntryTimestamp() {
  local result
  result=$(run_command "$CLI_BIN" status --json)
  if ! require_ok_status "Status command succeeds"; then
    return 1
  fi

  local has_ts
  has_ts=$(echo "$result" | jq '.data | has("newestEntryTimestamp")' 2>/dev/null || echo "false")
  if [ "$has_ts" != "true" ]; then
    log_error "ASSERTION FAILED: status.data.newestEntryTimestamp must be present"
    TEST_FAILED=1
    return 1
  fi
  log_success "status includes newestEntryTimestamp"

  local ts
  ts=$(echo "$result" | jq '.data.newestEntryTimestamp' 2>/dev/null)
  if ! assert_greater_than "$ts" 0 "newestEntryTimestamp is a positive timestamp"; then
    return 1
  fi
}

# ct-796 R3: unknown bare project name returns dbProjectNotFound error
test_unknown_project_returns_not_found_error() {
  local result
  local exit_code

  # Capture both output and exit code without triggering set -e
  set +e
  result=$("$CLI_BIN" search "test" --project "zzz-nonexistent-project-12345" --json 2>&1)
  exit_code=$?
  set -e

  # Should fail with exit code 2 (dbNotFound)
  if [ "$exit_code" -eq 0 ]; then
    log_error "ASSERTION FAILED: Unknown project name should fail (got exit 0)"
    TEST_FAILED=1
    return 1
  fi
  log_success "Unknown project name returns non-zero exit code ($exit_code)"

  # Should return dbProjectNotFound error code
  local code
  code=$(echo "$result" | jq -r '.code // empty' 2>/dev/null)
  if [ "$code" != "dbProjectNotFound" ]; then
    log_error "ASSERTION FAILED: Expected error code 'dbProjectNotFound', got '$code'"
    TEST_FAILED=1
    return 1
  fi
  log_success "Error code is dbProjectNotFound (not filesystem fallback)"

  # Should include hint
  local hint
  hint=$(echo "$result" | jq -r '.hint // empty' 2>/dev/null)
  if [ -z "$hint" ]; then
    log_error "ASSERTION FAILED: Error should include a hint"
    TEST_FAILED=1
    return 1
  fi
  log_success "Error includes contextual hint: $hint"
}

run_contract_tests() {
  log_header "$TEST_ID: $TEST_NAME"
  check_prerequisites

  test_search_metadata_uses_databaseSummary || true
  test_databaseSummary_has_required_fields || true
  test_status_includes_newestEntryTimestamp || true
  test_unknown_project_returns_not_found_error || true

  exit_with_result
}

main() {
  run_contract_tests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
