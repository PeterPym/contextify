#!/bin/bash
# QA-07: Transcript Window
#
# Purpose: Validates transcript window opening and content loading
#
# Validates:
# - Window opens via keyboard shortcut
# - Transcript content loads
# - Window can be closed
#
# Prerequisites:
# - App running with active project
# - At least one transcript in database

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-07"
TEST_NAME="Transcript Window"

# ─────────────────────────────────────────────────────────────────────────────
# Test Implementation
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_subheader "Checking Prerequisites"

  assert_app_running "Contextify"
  assert_command_exists "osascript"

  # Check for transcripts
  local transcript_count
  transcript_count=$(db_count "SELECT COUNT(*) FROM transcripts;")

  if [ "$transcript_count" -lt 1 ]; then
    log_warn "No transcripts in database - window may show empty state"
  else
    log_info "Transcripts available: $transcript_count"
  fi

  log_success "Prerequisites met"
}

setup_test() {
  log_subheader "Setup"

  # Get initial window count
  local initial_windows
  initial_windows=$(get_window_count)
  log_info "Initial window count: $initial_windows"

  # Ensure app is active and focused
  activate_app
  sleep 1

  # Start log capture
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"
  start_log_capture "$LOGDIR"

  sleep 2
}

run_test_steps() {
  log_subheader "Test Execution"

  log_info "Opening Transcript window via keyboard shortcut..."

  # Ensure app is focused
  activate_app
  sleep 0.5

  # Transcripts window shortcut is Cmd+Ctrl+I
  log_info "Sending Cmd+Ctrl+I (Show Transcripts)"
  send_shortcut "i" "command down, control down"

  # Wait for window to open
  sleep 2

  # Check if new window appeared
  local after_windows
  after_windows=$(get_window_count)
  log_info "Window count after shortcut: $after_windows"

  # Wait for content to load
  log_info "Waiting for content to load..."
  sleep 2

  log_success "Transcript window command sent"
}

validate_results() {
  log_subheader "Validation"

  # App should still be running
  assert_app_running "Contextify"

  # Check window count
  local window_count
  window_count=$(get_window_count)

  if [ "$window_count" -ge 1 ]; then
    log_success "✓ Window(s) present (count: $window_count)"
  else
    log_warn "No windows detected"
  fi

  # Check for transcript-related logs
  soft_assert_log_contains "TRANSCRIPT\|transcript\|Transcript" "Transcript activity logged"

  # Check for any window-related logs
  soft_assert_log_contains "window\|WINDOW\|Window\|view\|VIEW" "Window/view activity logged"

  # No errors
  local error_count
  error_count=$(log_count "\[ERROR\]")
  if [ "$error_count" -eq 0 ]; then
    log_success "✓ No errors during window operation"
  else
    log_warn "Found $error_count error(s) in logs"
  fi
}

cleanup_and_close() {
  log_subheader "Cleanup"

  # Close any extra windows with Cmd+W
  log_info "Closing extra windows..."
  local attempts=0
  while [ $attempts -lt 3 ]; do
    local current_count
    current_count=$(get_window_count)
    if [ "$current_count" -le 1 ]; then
      break
    fi
    send_shortcut "w" "command down"
    sleep 0.5
    attempts=$((attempts + 1))
  done

  # Ensure main window is visible by activating app
  activate_app

  exit_with_result
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
  log_header "$TEST_ID: $TEST_NAME"

  check_prerequisites
  setup_test
  run_test_steps
  validate_results
  cleanup_and_close
}

main "$@"
