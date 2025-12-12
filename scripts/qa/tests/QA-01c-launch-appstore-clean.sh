#!/bin/bash
# QA-01c: App Store Build - First Run (Grant Permissions)
#
# Purpose: Validates first-run onboarding experience with App Store build.
#          Tests permission grants via UI automation.
#
# @test_contract
# isolation:
#   transcripts: orchestrator  # Relies on --isolate for fixture transcripts
#   database: sandbox          # Uses App Store sandbox (inherently isolated)
#
# database:
#   location: appstore         # ~/Library/Containers/sh.contextify.Contextify/...
#   start:
#     exists: false            # Sandbox is reset before test
#     min_projects: 0
#     min_transcripts: 0
#   mutations:
#     - "User completes onboarding wizard"
#     - "Security-scoped bookmarks saved for transcript folders"
#     - "Database created after onboarding completes"
#     - "Initial discovery runs"
#   end:
#     exists: true
#     projects: 2-4            # From fixture transcripts
#     transcripts: 2-4         # From fixture transcripts
#
# dependencies:
#   orchestrator_flags: [--isolate]
#   run_after: []              # Phase 2 - destructive (resets sandbox)
#   notes: "Resets App Store sandbox. Run after 01d which needs existing bookmarks."
#
# Validates:
# - Onboarding wizard appears
# - Permission grants work via AppleScript
# - Security-scoped bookmark saved
# - Startup completes after onboarding
#
# Prerequisites:
# - App Store build available
# - Terminal has Accessibility permission for UI automation

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

  # Contract: transcripts: orchestrator
  require_isolation "Transcript isolation required"

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

  # Wait for onboarding wizard (step 1 - database location)
  log_info "Waiting for onboarding wizard..."
  if ! wait_for_log_pattern "\[ONBOARD-WIZARD\]" 15; then
    log_error "Onboarding wizard did not appear"
    TEST_FAILED=1
    return 1
  fi
  sleep 1

  # Step 1: Database location selection
  # Press Enter to open folder picker (folder card has keyboard shortcut)
  log_info "Step 1: Opening folder picker (Enter)..."
  activate_app
  press_return
  sleep 1

  # NSOpenPanel is open - press Enter to accept default location
  log_info "Selecting default folder in NSOpenPanel (Enter)..."
  press_return
  sleep 2

  # Wait for folder to be configured
  if ! wait_for_log_pattern "\[ONBOARD-DB\] Configured database location" 10; then
    log_warn "Database location config log not detected"
  fi

  # Press Enter to advance to step 2 (Next button now has keyboard shortcut)
  log_info "Advancing to step 2 (Enter)..."
  activate_app
  press_return
  sleep 1

  # Step 2: Permissions
  # Need to click "Grant Access" buttons (these require explicit clicks)
  # SwiftUI buttons are nested in groups and don't expose names to System Events
  log_info "Step 2: Granting transcript folder permissions..."

  # Click Grant Access for Claude Code (button 1 in group 1)
  log_info "Granting Claude Code access..."
  click_group_button 1 1
  sleep 1
  press_return  # Confirm NSOpenPanel
  sleep 2

  # Click Grant Access for Codex CLI (button 2 in group 1)
  log_info "Granting Codex CLI access..."
  activate_app
  click_group_button 1 2
  sleep 1
  press_return  # Confirm NSOpenPanel
  sleep 2

  # After granting permissions, press Enter to complete (Continue button)
  log_info "Completing onboarding (Enter)..."
  activate_app
  sleep 0.5
  press_return

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

  log_success "App launched and onboarding completed"
}

validate_results() {
  log_subheader "Validation"

  # App should be running
  assert_app_running "Contextify"

  # Database was created and has projects (custom location, so check logs instead of path)
  assert_log_contains "\[INIT-DB-STATE\] Database has" "Database initialized with projects"

  # Onboarding completed
  assert_log_contains "\[ONBOARD-DB\] Configured database location" "Database location configured"

  # Permissions were granted
  soft_assert_log_contains "\[PERMISSIONS\].*Granted access" "Transcript permissions granted"

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
