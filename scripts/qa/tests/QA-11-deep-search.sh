#!/bin/bash
# QA-11: Deep Search Window
#
# Validates Deep Search window opens via Cmd+Enter from search field.
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

  # 3. Record window count before
  local windows_before
  windows_before=$(get_window_count)
  log_info "Windows before: $windows_before"

  # 4. Open Deep Search (Cmd+Enter)
  log_info "Opening Deep Search (Cmd+Enter)"
  send_shortcut "$(printf '\r')" "command down"

  # 5. Wait for Deep Search window
  if ! wait_for_log_pattern "\[DEEPSEARCH-INIT\]" 10; then
    log_error "Deep Search window did not open within 10s"
    TEST_FAILED=1
    return 1
  fi

  sleep 1  # Let window fully render

  # 6. Verify window count increased
  local windows_after
  windows_after=$(get_window_count)
  log_info "Windows after: $windows_after"

  if [ "$windows_after" -le "$windows_before" ]; then
    log_warn "Window count did not increase (before: $windows_before, after: $windows_after)"
  fi

  # 7. Close Deep Search (Cmd+W)
  log_info "Closing Deep Search (Cmd+W)"
  send_shortcut "w" "command down"
  sleep 0.5

  # 8. Verify window closed
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

  # Deep Search initialized
  assert_log_contains "\[DEEPSEARCH-INIT\]" "Deep Search window opened"

  # App still running
  assert_app_running "Contextify"

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
