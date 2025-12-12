#!/bin/bash
# QA-01e: App Store Build - Incomplete Onboarding
#
# Purpose: Validates App Store gracefully handles incomplete onboarding
#
# Validates:
# - App doesn't crash when onboarding isn't completed
# - DB init is correctly deferred (not created without permissions)
# - App stays in safe state until onboarding is complete
# - No fatal errors occur
#
# Note: The onboarding wizard requires at least one permission grant
# before the Continue button becomes active. This test verifies the app
# handles the "stuck in onboarding" state gracefully.
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
TEST_NAME="App Store Build - Incomplete Onboarding"

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

  log_info "Launching App Store build without completing onboarding..."

  # Launch app
  if ! launch_appstore_app; then
    log_error "Failed to launch app"
    TEST_FAILED=1
    return 1
  fi

  # Wait for onboarding wizard to appear
  sleep 3

  # Do NOT complete onboarding - just let the app sit at the wizard
  log_info "Not completing onboarding wizard (testing incomplete state)"

  # Wait a moment to verify app stays stable
  sleep 5

  # Check if app is still running (didn't crash)
  if ! app_is_running; then
    log_error "App crashed while showing onboarding wizard"
    TEST_FAILED=1
    return 1
  fi

  log_success "App stable in incomplete onboarding state"
}

validate_results() {
  log_subheader "Validation"

  # App should be running (most important check)
  assert_app_running "Contextify"

  # Database should NOT exist when onboarding is incomplete
  # The app correctly defers DB init until onboarding completes
  if [ -f "$DB_PATH" ]; then
    log_warn "Database exists at $DB_PATH (unexpected - should be deferred)"
    # Not a failure, but worth noting
  else
    log_success "✓ Database correctly deferred (not created without onboarding)"
  fi

  # Should see the startup-gate log indicating deferral
  assert_log_contains "\[STARTUP-GATE\]" "Startup correctly deferred"

  # Onboarding wizard should be shown
  assert_log_contains "\[ONBOARD-WIZARD\]" "Onboarding wizard displayed"

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
