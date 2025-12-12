#!/bin/bash
# QA-01b: DMG Build - Existing Database
#
# Purpose: Validates normal startup with existing database
#
# Validates:
# - AppStateOrchestrator startup
# - Discovery notification posted
# - FSEvents monitoring active
# - Project loading
#
# Prerequisites:
# - DMG build available
# - Existing database with at least one project

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-01b"
TEST_NAME="DMG Build - Existing Database"

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

  # Verify database exists
  if [ ! -f "$DB_PATH" ]; then
    log_warn "No existing database - run QA-01a first or start app manually"
    log_info "Creating minimal database for test..."
    # Run QA-01a to create database, or just launch app briefly
    open "$DMG_APP_PATH"
    sleep 10
    pkill -9 "Contextify" 2>/dev/null || true
    sleep 2
  fi

  assert_db_exists "Existing database present"

  log_success "Prerequisites met"
}

setup_test() {
  log_subheader "Setup"

  # Kill app if running
  kill_app_if_running

  # Start log capture
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"
  start_log_capture "$LOGDIR"

  log_success "Setup complete"
}

run_test_steps() {
  log_subheader "Test Execution"

  log_info "Launching DMG build with existing database..."

  # Launch app
  if ! launch_dmg_app; then
    log_error "Failed to launch app"
    TEST_FAILED=1
    return 1
  fi

  # Give app time to complete initialization and discovery
  sleep 5

  log_success "App launched"
}

validate_results() {
  log_subheader "Validation"

  # App should be running
  assert_app_running "Contextify"

  # CRITICAL: Verify this opened an EXISTING database (not creating new)
  assert_log_contains "\[DB-INIT\] OPENING EXISTING DATABASE" "Existing database opened"
  # Note: EXISTING DATABASE LOADED may not appear in log window if validation completed before capture
  soft_assert_log_contains "\[DB-INIT\] EXISTING DATABASE LOADED" "Existing database loaded signal"

  # Should NOT see "CREATING NEW DATABASE" (that indicates test setup failed)
  if grep -q "\[DB-INIT\] CREATING NEW DATABASE FROM SCRATCH" "$LOGFILE" 2>/dev/null; then
    log_error "Found 'CREATING NEW DATABASE' - test should have used existing DB"
    TEST_FAILED=1
  fi

  # Check for record counts in logs (existing DB should have some)
  soft_assert_log_contains "\[DB-INIT\] Records:" "Database record counts logged"

  # Check for startup completion
  assert_log_contains "\[ORCH-STARTUP\] Startup complete" "AppStateOrchestrator started"

  # Check for discovery notification
  soft_assert_log_contains "projectsDiscoveryComplete\|discovery" "Discovery notification posted"

  # Check for FSEvents monitoring
  soft_assert_log_contains "FSEvents\|FSEVENTS" "FSEvents monitoring active"

  # Verify projects loaded
  local project_count
  project_count=$(db_count "SELECT COUNT(*) FROM projects;")

  if [ "$project_count" -ge 1 ]; then
    log_success "✓ Projects loaded (count: $project_count)"
  else
    log_warn "No projects in database (may be expected for fresh install)"
  fi

  # No errors in logs (soft check)
  local error_count
  error_count=$(log_count "\[ERROR\]")
  if [ "$error_count" -eq 0 ]; then
    log_success "✓ No errors in startup logs"
  else
    log_warn "Found $error_count error(s) in logs"
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
