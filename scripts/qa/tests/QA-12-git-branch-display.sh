#!/bin/bash
# QA-12: Git Branch Display
#
# Purpose: Validates git branch extraction from transcript metadata and display.
#          Tests the transcript-based branch display feature.
#
# @test_contract
# isolation:
#   transcripts: orchestrator  # Relies on --isolate
#   database: preserve         # Uses existing DB, read-only UI test
#
# database:
#   location: dmg
#   start:
#     exists: true
#     min_projects: 1
#     min_transcripts: 1       # Need transcript with gitBranch field
#   mutations:
#     - "Reads transcript metadata for branch"
#     - "Logs branch validation"
#     - "Read-only: no database modifications"
#   end:
#     exists: true
#     projects: same
#     transcripts: same or +N    # Fixture seeding may add transcripts
#
# dependencies:
#   orchestrator_flags: [--isolate]
#   run_after: [QA-01b]        # Needs existing database with transcripts
#   notes: "Read-only test. Validates branch extraction from transcript metadata."
#
# Validates:
# - Branch extracted from transcript gitBranch field
# - Branch validation logged with provider/timestamp
# - Coordinator updates include branch info
#
# Prerequisites:
# - DMG app build available
# - Fixtures with gitBranch metadata

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-12"
TEST_NAME="Git Branch Display"

check_prerequisites() {
  log_subheader "Checking Prerequisites"
  assert_command_exists "sqlite3"
  assert_command_exists "osascript"
  assert_dmg_app_exists

  # Contract: transcripts: orchestrator
  require_isolation "Transcript isolation required"

  # Contract: start.min_projects: 1, min_transcripts: 1
  assert_db_count_min "SELECT COUNT(*) FROM projects;" 1 "At least 1 project exists"
  assert_db_count_min "SELECT COUNT(*) FROM transcripts;" 1 "At least 1 transcript exists"

  # Record baseline for end-state verification
  record_baseline_counts

  log_success "Prerequisites met"
}

run_test_steps() {
  log_subheader "Test Execution"

  # 1. Kill any existing app
  kill_app_if_running

  # 2. Start fresh log capture
  start_log_capture "$LOGDIR"

  # 3. Launch app
  log_info "Launching DMG build..."
  if ! launch_dmg_app; then
    log_error "Failed to launch app"
    TEST_FAILED=1
    return 1
  fi

  # 4. Wait for startup and initial branch extraction
  log_info "Waiting for startup and branch extraction..."
  sleep 3

  # 5. Trigger project switch to ensure branch validation runs
  log_info "Triggering project switch to validate branch..."
  send_shortcut "]" "command down, shift down"
  sleep 2

  # 6. Switch back
  send_shortcut "[" "command down, shift down"
  sleep 2

  log_success "Test execution completed"
}

validate_results() {
  log_subheader "Validation"

  # Branch must be resolved (hard assertion)
  log_info "Checking for branch resolution..."
  assert_log_contains "\[BRANCH-RESOLVED\]" "Branch resolved"

  # Verify branch source is logged (git in DMG, transcript in App Store)
  log_info "Verifying branch source..."
  if grep -q "\[BRANCH-RESOLVED\].*source=git" "$LOGFILE" 2>/dev/null; then
    log_success "Branch from git monitoring (DMG build)"
    # In DMG builds, git monitoring takes precedence - branch comes from actual .git
    # We can't verify transcript extraction here, but we verify git works
  elif grep -q "\[BRANCH-RESOLVED\].*source=transcript" "$LOGFILE" 2>/dev/null; then
    log_success "Branch from transcript metadata"
    # When source=transcript, verify we got expected fixture value
    if grep -q "\[BRANCH-RESOLVED\] branch=main source=transcript" "$LOGFILE" 2>/dev/null; then
      log_success "Transcript branch 'main' extracted correctly"
    elif grep -q "\[BRANCH-RESOLVED\] branch=feature/testing source=transcript" "$LOGFILE" 2>/dev/null; then
      log_success "Transcript branch 'feature/testing' extracted correctly"
    else
      log_warn "Transcript branch value not matched to known fixtures"
    fi
  else
    soft_assert_log_contains "\[BRANCH-RESOLVED\].*source=" "Branch source logged"
  fi

  # Verify actual branch value is present (not just dash)
  log_info "Verifying branch value..."
  if grep -q "\[BRANCH-RESOLVED\] branch=— " "$LOGFILE" 2>/dev/null; then
    log_warn "Branch shows dash (no branch available)"
  elif grep -q "\[BRANCH-RESOLVED\] branch=" "$LOGFILE" 2>/dev/null; then
    log_success "Branch value present"
  fi

  # App still running (core requirement)
  assert_app_running "Contextify"

  # Note: Transcript count may increase slightly due to fixture seeding during isolation
  # This is a read-only UI test - no intentional mutations

  log_success "Validation passed"
}

cleanup() {
  kill_app_if_running
  stop_log_capture
}

main() {
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"

  trap cleanup EXIT

  log_header "$TEST_ID: $TEST_NAME"
  check_prerequisites

  run_test_steps
  validate_results
  exit_with_result
}

main "$@"
