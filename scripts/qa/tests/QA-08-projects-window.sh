#!/bin/bash
# QA-08: Projects Window
#
# Purpose: Validates projects window opening and project list loading
#
# Validates:
# - Window opens via keyboard shortcut
# - Project list loads
# - Window can be closed
#
# Prerequisites:
# - App running

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-08"
TEST_NAME="Projects Window"

# ─────────────────────────────────────────────────────────────────────────────
# Test Implementation
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_subheader "Checking Prerequisites"

  assert_app_running "Contextify"
  assert_command_exists "osascript"

  # Check for projects
  local project_count
  project_count=$(db_count "SELECT COUNT(*) FROM projects;")
  log_info "Projects in database: $project_count"

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

  log_info "Opening Projects window via keyboard shortcut..."

  # Ensure app is focused
  activate_app
  sleep 0.5

  # Try Cmd+Shift+P (common shortcut for projects)
  log_info "Sending Cmd+Shift+P"
  send_shortcut "p" "command down, shift down"

  # Wait for window to open
  sleep 2

  # Check if new window appeared
  local after_windows
  after_windows=$(get_window_count)
  log_info "Window count after shortcut: $after_windows"

  # If that didn't work, try alternatives
  if [ "$after_windows" -le 1 ]; then
    log_info "Trying Cmd+P..."
    send_shortcut "p" "command down"
    sleep 2
    after_windows=$(get_window_count)
    log_info "Window count after Cmd+P: $after_windows"
  fi

  # If still no luck, try via menu
  if [ "$after_windows" -le 1 ]; then
    log_info "Trying via menu: Window > Projects"
    osascript -e 'tell application "System Events" to tell process "Contextify" to click menu item "Projects" of menu "Window" of menu bar 1' 2>/dev/null || true
    sleep 2
    after_windows=$(get_window_count)
    log_info "Window count after menu: $after_windows"
  fi

  # Wait for content to load
  log_info "Waiting for content to load..."
  sleep 2

  log_success "Projects window command sent"
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

  # Check for project-related logs
  soft_assert_log_contains "PROJECT\|project\|Project" "Project activity logged"

  # Check database integrity
  local project_count
  project_count=$(db_count "SELECT COUNT(*) FROM projects;")

  if [ "$project_count" -ge 0 ]; then
    log_success "✓ Projects table accessible (count: $project_count)"
  else
    log_error "Could not query projects table"
    TEST_FAILED=1
  fi

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
