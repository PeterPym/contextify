#!/bin/bash
# QA-01d: App Store Build - Existing Bookmarks
#
# Purpose: Validates App Store startup with existing security-scoped bookmarks
#
# Validates:
# - No permission prompt shown
# - Existing bookmarks resolved
# - Startup completes successfully
#
# Prerequisites:
# - App Store build available
# - Existing bookmarks from previous grant (run QA-01c first)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-01d"
TEST_NAME="App Store Build - Existing Bookmarks"

# ─────────────────────────────────────────────────────────────────────────────
# Test Implementation
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_subheader "Checking Prerequisites"

  assert_command_exists "sqlite3"

  if [ ! -d "$APPSTORE_APP_PATH" ]; then
    log_error "App Store build not found: $APPSTORE_APP_PATH"
    log_error "Build with: bash scripts/xc.sh --dist=appstore Debug build"
    exit 1
  fi

  # Set DB_PATH to App Store sandbox location for all assertions
  DB_PATH="$(get_appstore_db_path)"
  log_info "DB_PATH set to: $DB_PATH"

  # Check for existing database (suggests previous run)
  if [ ! -f "$DB_PATH" ]; then
    log_warn "No existing database - bookmarks may not exist"
    log_info "Run QA-01c first to grant permissions and create bookmarks"
  fi

  log_success "Prerequisites met"
}

setup_test() {
  log_subheader "Setup"

  # Kill app if running
  kill_app_if_running

  # DO NOT clear UserDefaults or reset state - we want to keep bookmarks

  # Start log capture
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"
  start_log_capture "$LOGDIR"

  log_success "Setup complete (preserving bookmarks)"
}

run_test_steps() {
  log_subheader "Test Execution"

  log_info "Launching App Store build with existing bookmarks..."

  # Launch app
  if ! launch_appstore_app; then
    log_error "Failed to launch app"
    TEST_FAILED=1
    return 1
  fi

  # Wait for startup - should be fast with existing bookmarks
  log_info "Waiting for startup (should skip onboarding)..."

  if ! wait_for_log_pattern "\[ORCH-STARTUP\] Startup complete" 30; then
    log_warn "Startup completion log not detected"
    # Check if app is still running
    if ! app_is_running; then
      log_error "App crashed during startup"
      TEST_FAILED=1
      return 1
    fi
  fi

  # Give app time to settle
  sleep 3

  log_success "App launched"
}

validate_results() {
  log_subheader "Validation"

  # App should be running
  assert_app_running "Contextify"

  # Should NOT show permission prompt (check for onboarding wizard being skipped)
  local onboard_count
  onboard_count=$(log_count "\[ONBOARD-PERMISSION\]")

  if [ "$onboard_count" -eq 0 ]; then
    log_success "✓ No permission prompt shown (bookmarks used)"
  else
    log_warn "Permission prompt detected ($onboard_count times) - bookmarks may not be set"
  fi

  # Check for bookmark resolution
  soft_assert_log_contains "bookmark\|BOOKMARK\|resolved" "Bookmark resolution logged"

  # Check for startup completion
  soft_assert_log_contains "\[ORCH-STARTUP\]" "Orchestrator startup logged"

  # Verify projects loaded
  local project_count
  project_count=$(db_count "SELECT COUNT(*) FROM projects;")

  if [ "$project_count" -ge 1 ]; then
    log_success "✓ Projects loaded (count: $project_count)"
  else
    log_info "No projects discovered (may be expected if no transcripts exist)"
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
