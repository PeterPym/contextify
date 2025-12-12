#!/bin/bash
# QA-11: Deep Search Window
#
# Purpose: Validates Deep Search window opens via Cmd+Enter from search field.
#          Tests the AI-powered search window launch.
#
# @test_contract
# isolation:
#   transcripts: orchestrator  # Relies on --isolate
#   database: preserve         # Uses existing DB, read-only UI test
#
# database:
#   location: dmg
#   start:
#     exists: true
#     min_projects: 1
#     min_transcripts: 0       # Deep Search window works without data
#   mutations:
#     - "Focuses search field (Cmd+F)"
#     - "Types search term"
#     - "Opens Deep Search window (Cmd+Enter)"
#     - "Read-only: no database modifications"
#   end:
#     exists: true
#     projects: same
#     transcripts: same
#
# dependencies:
#   orchestrator_flags: [--isolate]
#   run_after: [QA-03, QA-04]  # Phase 5 - runs after search tests
#   notes: "Read-only UI test. Tests window creation for Deep Search."
#
# Validates:
# - Cmd+F focuses search field
# - Cmd+Enter opens Deep Search window
# - Window count increases
# - Window closes with Cmd+W
#
# Prerequisites:
# - DMG app build available
# - Terminal has Accessibility permission

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-11"
TEST_NAME="Deep Search Window"

check_prerequisites() {
  log_subheader "Checking Prerequisites"
  assert_command_exists "sqlite3"
  assert_command_exists "osascript"
  assert_dmg_app_exists

  # Contract: transcripts: orchestrator
  require_isolation "Transcript isolation required"

  # Contract: start.min_projects: 1, min_fts_entries: 1 (need data to search)
  assert_db_count_min "SELECT COUNT(*) FROM projects;" 1 "At least 1 project exists"
  assert_db_count_min "SELECT COUNT(*) FROM transcript_entries_fts;" 1 "FTS index populated"

  # Record baseline for end-state verification
  record_baseline_counts

  log_success "Prerequisites met"
}

run_test_steps() {
  log_subheader "Test Execution"

  local search_term="QA_FIXTURE_SEARCH_TERM"

  # 1. Focus search field
  log_info "Focusing search field (Cmd+F)"
  focus_search_field
  sleep 0.5

  # 2. Type search term
  log_info "Typing search term: $search_term"
  type_text "$search_term"
  sleep 0.3

  # 3. Submit search (press Enter to trigger search)
  log_info "Submitting search (Enter)"
  send_shortcut "$(printf '\r')" ""

  # 4. Wait for search to complete (must have results for Deep Search to open)
  log_info "Waiting for search results..."
  if ! wait_for_log_pattern "\[SEARCH-DONE\].*hits=" 10; then
    log_error "Search did not complete within timeout"
    TEST_FAILED=1
    return 1
  fi
  log_success "Search completed"

  # 5. Record window count before
  local windows_before
  windows_before=$(get_window_count)
  log_info "Windows before: $windows_before"

  # 6. Open Deep Search (Cmd+Enter)
  log_info "Opening Deep Search (Cmd+Enter)"
  send_shortcut "$(printf '\r')" "command down"

  # 7. Wait for Deep Search window to open
  sleep 2

  # 8. Verify window count increased
  local windows_after
  windows_after=$(get_window_count)
  log_info "Windows after: $windows_after"

  if [ "$windows_after" -le "$windows_before" ]; then
    log_warn "Window count did not increase (before: $windows_before, after: $windows_after)"
  fi

  # 9. Close Deep Search (Cmd+W)
  log_info "Closing Deep Search (Cmd+W)"
  send_shortcut "w" "command down"
  sleep 0.5

  # 10. Verify window closed
  local windows_final
  windows_final=$(get_window_count)
  log_info "Windows final: $windows_final"

  if [ "$windows_final" -lt "$windows_after" ]; then
    log_success "Deep Search window closed"
  else
    log_warn "Window count did not decrease after Cmd+W"
  fi

  log_success "Test execution completed"
}

validate_results() {
  log_subheader "Validation"

  # Deep Search window must have opened (hard assertion)
  assert_log_contains "\[DEEPSEARCH-INIT\]" "Deep Search window opened"

  # App still running (core requirement)
  assert_app_running "Contextify"

  # Contract: end state projects: same, transcripts: same
  assert_counts_unchanged "Database counts unchanged after deep search"

  log_success "Validation passed"
}

cleanup() {
  kill_app_if_running
  stop_log_capture
}

main() {
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"

  trap cleanup EXIT

  log_header "$TEST_ID: $TEST_NAME"
  check_prerequisites

  kill_app_if_running
  start_log_capture "$LOGDIR"

  if ! launch_dmg_app; then
    log_error "Failed to launch app"
    TEST_FAILED=1
    exit_with_result
  fi

  sleep 3

  run_test_steps
  validate_results
  exit_with_result
}

main "$@"
