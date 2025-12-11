#!/bin/bash
# QA-01a: DMG Build - First Run (No Database)
#
# Purpose: Validates first-run experience with DMG build
#
# Validates:
# - Database schema creation/migration
# - Startup completion
# - App running state
#
# Prerequisites:
# - DMG build available
# - No existing database (will be removed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-01a"
TEST_NAME="DMG Build - First Run (Clean Install)"

# ─────────────────────────────────────────────────────────────────────────────
# Test Implementation
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_subheader "Checking Prerequisites"

  assert_command_exists "sqlite3"

  if [ ! -d "$DMG_APP_PATH" ]; then
    log_error "DMG build not found: $DMG_APP_PATH"
    log_error "Build with: bash scripts/xc.sh build"
    exit 1
  fi

  log_success "Prerequisites met"
}

setup_test() {
  log_subheader "Setup"

  # Kill app if running
  kill_app_if_running

  # Remove existing database for clean test
  log_info "Removing existing database for clean install test..."
  rm -f "$DB_PATH"*

  # Clear UserDefaults
  clear_user_defaults

  # Start log capture
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"
  start_log_capture "$LOGDIR"

  log_success "Clean state prepared"
}

run_test_steps() {
  log_subheader "Test Execution"

  log_info "Launching DMG build (first run)..."

  # Launch app
  if ! launch_dmg_app; then
    log_error "Failed to launch app"
    TEST_FAILED=1
    return 1
  fi

  # Give app time to complete initialization
  sleep 3

  log_success "App launched"
}

validate_results() {
  log_subheader "Validation"

  # App should be running
  assert_app_running "Contextify"

  # Database should exist
  assert_db_exists "Database created"

  # Check for migration logs
  soft_assert_log_contains "\[DB" "Database initialization logged"

  # Check for startup completion
  assert_log_contains "\[ORCH-STARTUP\] Startup complete" "Startup completed"

  # Verify project count (may be 0 or more depending on existing transcripts)
  local project_count
  project_count=$(db_count "SELECT COUNT(*) FROM projects;")
  log_info "Projects discovered: $project_count"

  # Discovery should have run
  soft_assert_log_contains "discovery" "Discovery ran"
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
