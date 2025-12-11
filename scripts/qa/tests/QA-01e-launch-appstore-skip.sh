#!/bin/bash
# QA-01e: App Store Build - Skip Permissions
#
# Purpose: Validates App Store startup when user skips permission prompts
#
# Validates:
# - Permission prompts can be skipped
# - App doesn't crash
# - Graceful empty state shown
# - Startup completes
#
# Prerequisites:
# - App Store build available
# - Terminal has Accessibility permission
# - No existing database/bookmarks (will be removed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-01e"
TEST_NAME="App Store Build - Skip Permissions"

# ─────────────────────────────────────────────────────────────────────────────
# Test Implementation
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_subheader "Checking Prerequisites"

  assert_command_exists "sqlite3"
  assert_command_exists "osascript"

  if [ ! -d "$APPSTORE_APP_PATH" ]; then
    log_error "App Store build not found: $APPSTORE_APP_PATH"
    log_error "Build with: bash scripts/xc.sh --dist=appstore Debug build"
    exit 1
  fi

  log_info "Ensure Terminal has Accessibility permission for UI automation"
  log_success "Prerequisites met"
}

setup_test() {
  log_subheader "Setup"

  # Kill app if running
  kill_app_if_running

  # Full reset of App Store app state (DB, prefs, bookmarks, caches)
  # This ensures we get a true clean install experience with onboarding
  reset_appstore_state

  # Override DB_PATH for App Store sandbox location (for assertions)
  DB_PATH="$(get_appstore_db_path)"
  log_info "DB_PATH set to: $DB_PATH"

  # Start log capture
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"
  start_log_capture "$LOGDIR"

  log_success "Clean state prepared"
}

run_test_steps() {
  log_subheader "Test Execution"

  log_info "Launching App Store build and skipping permissions..."

  # Launch app
  if ! launch_appstore_app; then
    log_error "Failed to launch app"
    TEST_FAILED=1
    return 1
  fi

  # Wait for onboarding wizard
  sleep 3

  # Skip permission prompts via UI automation
  log_info "Skipping permission prompts..."

  # Try to skip first permission
  if skip_folder_permission "\[ONBOARD\]" 10; then
    log_success "First permission skipped"
  else
    log_info "First permission prompt not detected or already skipped"
  fi

  # Try to skip second permission (may not appear)
  sleep 2
  skip_folder_permission "\[ONBOARD\]" 5 || true

  # Try to continue/skip onboarding
  sleep 2
  click_button_retry "Continue" 3 || \
    click_button_retry "Skip" 3 || \
    click_button_retry "Later" 3 || \
    true

  # Wait for app to settle
  sleep 5

  # Check if app completed startup
  if ! app_is_running; then
    log_error "App crashed after skipping permissions"
    TEST_FAILED=1
    return 1
  fi

  log_success "App launched with skipped permissions"
}

validate_results() {
  log_subheader "Validation"

  # App should be running (most important check)
  assert_app_running "Contextify"

  # Database should exist (even with no permissions)
  assert_db_exists "Database created"

  # Should show empty state or limited functionality
  soft_assert_log_contains "empty\|EMPTY\|no.*permission\|NO.*ACCESS" "Empty state or no-access state logged"

  # Startup should have completed without crash
  soft_assert_log_contains "\[ORCH-STARTUP\]" "Orchestrator startup attempted"

  # No fatal errors
  local fatal_count
  fatal_count=$(log_count "FATAL\|CRASH\|abort")

  if [ "$fatal_count" -eq 0 ]; then
    log_success "✓ No fatal errors"
  else
    log_error "Fatal errors detected in logs"
    TEST_FAILED=1
  fi
}

cleanup_and_report() {
  log_subheader "Cleanup"

  # Kill app
  kill_app_if_running

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
  cleanup_and_report
}

main "$@"
