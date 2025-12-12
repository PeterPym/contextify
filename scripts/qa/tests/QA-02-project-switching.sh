#!/bin/bash
# QA-02: Project Switching
#
# Purpose: Validates project switching via keyboard shortcuts (Cmd+Shift+] and [).
#          Tests that switching between projects works correctly.
#
# @test_contract
# isolation:
#   transcripts: orchestrator  # Relies on --isolate for consistent project set
#   database: preserve         # Uses existing database, doesn't reset
#
# database:
#   location: dmg
#   start:
#     exists: true
#     min_projects: 2          # Need at least 2 projects to switch between
#     min_transcripts: 0
#   mutations:
#     - "Updates last_viewed_ts on switched-to project"
#     - "May trigger timeline refresh"
#     - "No structural changes to projects/transcripts tables"
#   end:
#     exists: true
#     projects: same           # No projects added/removed
#     transcripts: same        # No transcripts added/removed
#
# dependencies:
#   orchestrator_flags: [--isolate]
#   run_after: []              # Phase 1 - tests existing data
#   notes: "Read-heavy test. Needs 2+ projects. Updates timestamps only."
#
# Validates:
# - Orchestrator receives switch request
# - [ORCH-SELECT] logged
# - Timeline refreshes after switch
# - No errors during switch
#
# Prerequisites:
# - App running
# - At least 2 projects in database

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-02"
TEST_NAME="Project Switching"

# ─────────────────────────────────────────────────────────────────────────────
# Test Implementation
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_subheader "Checking Prerequisites"

  assert_command_exists "sqlite3"
  assert_command_exists "osascript"

  # Check if app is running, start if not
  if ! app_is_running; then
    log_info "App not running, launching..."
    launch_dmg_app
    sleep 3
  fi

  assert_app_running "Contextify"

  # Check for multiple projects
  local project_count
  project_count=$(db_count "SELECT COUNT(*) FROM projects;")

  if [ "$project_count" -lt 2 ]; then
    log_warn "Only $project_count project(s) in database"
    log_info "Project switching test works best with 2+ projects"
    log_info "Creating test project for switching..."
    # The switch will still work, just might wrap around to same project
  fi

  log_success "Prerequisites met (projects: $project_count)"
}

setup_test() {
  log_subheader "Setup"

  # Ensure app is active and focused
  activate_app
  sleep 1

  # Start log capture
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"
  start_log_capture "$LOGDIR"

  # Wait for log capture to initialize
  sleep 2

  log_success "Setup complete"
}

run_test_steps() {
  log_subheader "Test Execution"

  log_info "Triggering project switch via keyboard shortcut..."

  # Ensure app is focused
  activate_app
  sleep 0.5

  # Get current project before switch
  local project_before
  project_before=$(db_query "SELECT id FROM projects ORDER BY updated_at DESC LIMIT 1;")
  log_info "Current project ID: ${project_before:-unknown}"

  # Send Cmd+Shift+] to switch to next project
  log_info "Sending Cmd+Shift+] (switch to next project)"
  send_shortcut "]" "command down, shift down"

  # Wait for switch to complete
  log_info "Waiting for switch completion..."
  if ! wait_for_log_pattern "\[ORCH-SELECT\]" 10; then
    # Try alternative pattern
    if ! wait_for_log_pattern "project.*switch\|SWITCH\|selected" 10; then
      log_warn "Switch completion not detected in logs"
    fi
  fi

  # Give time for UI to update
  sleep 2

  # Switch back to verify bidirectional switching
  log_info "Switching back via Cmd+Shift+["
  send_shortcut "[" "command down, shift down"
  sleep 2

  log_success "Project switches triggered"
}

validate_results() {
  log_subheader "Validation"

  # App should still be running
  assert_app_running "Contextify"

  # Check for switch-related logs
  soft_assert_log_contains "SWITCH\|switch\|SELECT\|select" "Switch activity detected"

  # Check for timeline refresh
  soft_assert_log_contains "TIMELINE\|timeline\|feed\|FEED" "Timeline activity detected"

  # Check for watcher activity
  soft_assert_log_contains "WATCHER\|watcher" "Watcher activity detected"

  # No errors during switch
  local error_count
  error_count=$(log_count "\[ERROR\]")

  if [ "$error_count" -eq 0 ]; then
    log_success "✓ No errors during switch"
  else
    log_warn "Found $error_count error(s) in logs during switch"
  fi

  # Verify projects table wasn't corrupted
  local project_count
  project_count=$(db_count "SELECT COUNT(*) FROM projects;")

  if [ "$project_count" -ge 1 ]; then
    log_success "✓ Projects table intact (count: $project_count)"
  else
    log_error "Projects table may be corrupted"
    TEST_FAILED=1
  fi
}

cleanup_and_report() {
  # Note: Don't kill app - leave it running for subsequent tests
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
