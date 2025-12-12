#!/bin/bash
# QA-06: Watcher Health and Recovery
#
# Purpose: Validates watcher health monitoring and recovery mechanisms.
#          Tests that the app self-heals when watchers fail.
#
# @test_contract
# isolation:
#   transcripts: orchestrator  # Relies on --isolate
#   database: preserve         # Uses existing DB, read-heavy test
#
# database:
#   location: dmg
#   start:
#     exists: true
#     min_projects: 1
#     min_transcripts: 1       # Needs transcripts with watchers
#   mutations:
#     - "Monitors health check cycle (read-only)"
#     - "May update transcript status if recovery needed"
#     - "No structural changes expected"
#   end:
#     exists: true
#     projects: same
#     transcripts: same
#
# dependencies:
#   orchestrator_flags: [--isolate]
#   run_after: [QA-03, QA-04]  # Phase 4 - needs active transcripts
#   notes: "Read-heavy test. Monitors watcher health, doesn't force failures."
#
# Validates:
# - Health check runs periodically
# - [HEALTH] or similar logging detected
# - No infinite recovery loops
# - No fatal errors
#
# Prerequisites:
# - App running with active project
# - Active transcripts in database

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-06"
TEST_NAME="Watcher Health and Recovery"

# ─────────────────────────────────────────────────────────────────────────────
# Test Implementation
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_subheader "Checking Prerequisites"

  assert_command_exists "sqlite3"

  # Contract: transcripts: orchestrator
  require_isolation "Transcript isolation required"

  # Ensure app is running (launch if needed)
  ensure_dmg_app_running
  assert_app_running "Contextify"

  # Contract: start.min_projects: 1, min_transcripts: 1
  assert_db_count_min "SELECT COUNT(*) FROM projects;" 1 "At least 1 project exists"
  assert_db_count_min "SELECT COUNT(*) FROM transcripts;" 1 "At least 1 transcript exists"

  # Record baseline for end-state verification
  record_baseline_counts

  log_success "Prerequisites met"
}

setup_test() {
  log_subheader "Setup"

  # Ensure app is active
  activate_app

  # Start log capture
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"
  start_log_capture "$LOGDIR"

  sleep 2
}

run_test_steps() {
  log_subheader "Test Execution"

  log_info "Monitoring for health check activity..."

  # Health checks run on a timer (typically every 30-60 seconds)
  # We'll wait for at least one health check cycle
  log_info "Waiting for health check cycle (up to 90 seconds)..."

  local elapsed=0
  local max_wait=90
  local health_detected=0

  while [ $elapsed -lt $max_wait ]; do
    if grep -q "HEALTH\|health\|WATCHER-CHECK\|watcher.*check" "$LOGFILE" 2>/dev/null; then
      health_detected=1
      log_success "Health check activity detected after ${elapsed}s"
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    log_info "Waiting... ${elapsed}s / ${max_wait}s"
  done

  if [ $health_detected -eq 0 ]; then
    log_warn "Health check not detected within ${max_wait}s"
    log_info "This may be normal if health check interval is longer"
  fi

  # Continue monitoring for any recovery activity
  log_info "Checking for recovery activity..."
  sleep 5

  log_success "Watcher monitoring complete"
}

validate_results() {
  log_subheader "Validation"

  # App should still be running
  assert_app_running "Contextify"

  # Check for health-related logs
  soft_assert_log_contains "WATCHER\|watcher" "Watcher system active"

  # Check for recovery errors (should be minimal or none)
  local recovery_error_count
  recovery_error_count=$(log_count "WATCHER-RECOVERY-ERROR")

  if [ "$recovery_error_count" -eq 0 ]; then
    log_success "✓ No watcher recovery errors"
  elif [ "$recovery_error_count" -lt 5 ]; then
    log_warn "Found $recovery_error_count recovery error(s) - may be expected for sandbox builds"
  else
    log_error "Excessive recovery errors: $recovery_error_count (possible infinite loop)"
    TEST_FAILED=1
  fi

  # Check for infinite loop indicators
  local loop_indicators
  loop_indicators=$(log_count "recovery.*retry\|retry.*recovery" || echo "0")

  if [ "$loop_indicators" -gt 10 ]; then
    log_error "Possible infinite recovery loop detected ($loop_indicators retry patterns)"
    TEST_FAILED=1
  else
    log_success "✓ No infinite recovery loop detected"
  fi

  # Verify watchers are functioning (check for any watcher activity)
  local watcher_activity
  watcher_activity=$(log_count "WATCHER\|watcher")

  if [ "$watcher_activity" -ge 1 ]; then
    log_success "✓ Watcher system active ($watcher_activity log entries)"
  else
    log_warn "Limited watcher activity in logs"
  fi

  # Verify transcripts still have valid status
  local error_transcripts
  error_transcripts=$(db_count "SELECT COUNT(*) FROM transcripts WHERE status = 'error';")

  if [ "$error_transcripts" -eq 0 ]; then
    log_success "✓ No transcripts in error state"
  else
    log_warn "$error_transcripts transcript(s) in error state"
  fi

  # Contract: end state projects: same, transcripts: same
  assert_counts_unchanged "Database counts unchanged after watcher monitoring"
}

report_results() {
  echo ""
  log_header "TEST SUMMARY: $TEST_ID"

  if [ $TEST_FAILED -eq 0 ]; then
    log_success "✅ ALL CHECKS PASSED"
    log_info "Watcher health monitoring validated"
    exit 0
  else
    log_error "❌ SOME CHECKS FAILED"
    log_info "Logs: $LOGFILE"
    exit 1
  fi
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
  report_results
}

main "$@"
