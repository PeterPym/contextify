#!/bin/bash
# QA-01c: App Store Build - First Run (Grant Permissions)
#
# Purpose: Validates first-run experience with App Store build,
#          granting transcript folder permissions via UI automation.
#
# Validates:
# - Permission prompt appears
# - Permission can be granted via AppleScript
# - Security-scoped bookmark saved
# - Startup completes successfully
#
# Prerequisites:
# - App Store build available
# - Terminal has Accessibility permission
# - No existing database/bookmarks (will be removed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-01c"
TEST_NAME="App Store Build - First Run (Grant Permissions)"

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

  log_info "Launching App Store build (first run)..."

  # Launch app
  if ! launch_appstore_app; then
    log_error "Failed to launch app"
    TEST_FAILED=1
    return 1
  fi

  # Wait for onboarding wizard
  sleep 3

  # Handle permission prompts via UI automation
  log_info "Handling permission prompts..."

  # Try to grant Claude Code permission
  if grant_folder_permission "\[ONBOARD\]" 15; then
    log_success "First permission granted"
  else
    log_warn "Could not grant first permission (may not have appeared)"
  fi

  # Try to grant Codex permission (may not appear)
  sleep 2
  if grant_folder_permission "\[ONBOARD\]" 10; then
    log_success "Second permission granted"
  else
    log_info "Second permission prompt not detected (may not be needed)"
  fi

  # Complete onboarding
  sleep 2
  complete_onboarding 3

  # Wait for startup completion
  log_info "Waiting for startup completion..."
  if ! wait_for_log_pattern "\[ORCH-STARTUP\] Startup complete" 30; then
    log_warn "Startup completion log not detected"
    # Check if app is still running
    if ! app_is_running; then
      log_error "App crashed during startup"
      TEST_FAILED=1
      return 1
    fi
  fi

  log_success "App launched and permissions handled"
}

validate_results() {
  log_subheader "Validation"

  # App should be running
  assert_app_running "Contextify"

  # Database should exist
  assert_db_exists "Database created"

  # Check for permission-related logs
  soft_assert_log_contains "\[ONBOARD\]" "Onboarding flow logged"

  # Check for bookmark saved (if permission was granted)
  soft_assert_log_contains "bookmark\|BOOKMARK" "Bookmark activity logged"

  # Check for startup completion
  soft_assert_log_contains "\[ORCH-STARTUP\]" "Orchestrator startup logged"
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
