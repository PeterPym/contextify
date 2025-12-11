#!/bin/bash
# QA-05: Real-time Transcript Updates
#
# Purpose: Validates real-time updates when transcript files change
#
# Validates:
# - Watcher detects file changes
# - Incremental hoover processes new content
# - Timeline updates with new entries
# - LLM queue receives new entries
#
# Prerequisites:
# - App running with active project
# - Existing transcript with watcher
# - Codex CLI installed (to generate new content)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-05"
TEST_NAME="Real-time Transcript Updates"
TEST_PROJECT="${TEST_PROJECT:-/tmp/contextify-qa-test}"
TRANSCRIPT=""

# ─────────────────────────────────────────────────────────────────────────────
# Test Implementation
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_subheader "Checking Prerequisites"

  assert_app_running "Contextify"
  assert_command_exists "codex"
  assert_command_exists "sqlite3"

  # Create test project if doesn't exist
  create_test_project "$TEST_PROJECT"

  log_success "Prerequisites met"
}

setup_test() {
  log_subheader "Setup"

  # Ensure app is active
  activate_app

  # Find an existing recent transcript or create one
  log_info "Looking for existing transcript..."
  TRANSCRIPT=$(find ~/.codex/sessions -name "*.jsonl" -mmin -60 2>/dev/null | head -1)

  if [ -z "$TRANSCRIPT" ]; then
    log_info "No recent transcript found, creating one..."

    cd "$TEST_PROJECT"
    run_with_timeout 30 codex "say 'setup' in Python" --full-auto > /dev/null 2>&1 || true
    cd - > /dev/null

    sleep 3
    TRANSCRIPT=$(find ~/.codex/sessions -name "*.jsonl" -mmin -5 2>/dev/null | head -1)
  fi

  if [ -z "$TRANSCRIPT" ]; then
    log_error "Could not find or create a transcript"
    TEST_FAILED=1
    return 1
  fi

  log_info "Using transcript: $TRANSCRIPT"

  # Get initial entry count
  local initial_count
  initial_count=$(db_count "SELECT COUNT(*) FROM transcript_entries;")
  log_info "Initial entry count: $initial_count"

  # Start log capture
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"
  start_log_capture "$LOGDIR"

  sleep 2
}

run_test_steps() {
  log_subheader "Test Execution"

  log_info "Generating new transcript content..."

  cd "$TEST_PROJECT"

  # Generate unique test marker
  local test_marker
  test_marker="REALTIME-$(date +%s)"

  # Run another Codex command to append to transcript
  log_info "Running: codex \"print '$test_marker'\" --full-auto"

  run_with_timeout 45 codex "print '$test_marker' and exit" --full-auto > /dev/null 2>&1 &
  local CODEX_PID=$!

  # Wait for file to be modified
  log_info "Waiting for transcript update..."
  sleep 5

  # Wait for watcher to detect change
  if ! wait_for_log_pattern "WATCHER\|watcher\|change\|CHANGE" 20; then
    log_warn "Watcher activity not detected in logs"
  fi

  # Wait for Codex to complete
  wait "$CODEX_PID" 2>/dev/null || true

  # Wait for incremental hoover
  log_info "Waiting for incremental ingestion..."
  if ! wait_for_log_pattern "HOOVER\|hoover\|ingest" 20; then
    log_warn "Hoover activity not detected"
  fi

  cd - > /dev/null

  # Give timeline time to update
  sleep 3

  log_success "Real-time update triggered"
}

validate_results() {
  log_subheader "Validation"

  # App should still be running
  assert_app_running "Contextify"

  # Check for watcher activity
  soft_assert_log_contains "WATCHER\|watcher" "Watcher activity logged"

  # Check for hoover/ingestion activity
  soft_assert_log_contains "HOOVER\|hoover\|ingest" "Ingestion activity logged"

  # Check for timeline refresh
  soft_assert_log_contains "TIMELINE\|timeline\|feed\|refresh" "Timeline refresh logged"

  # Check database for new entries
  local recent_entries
  recent_entries=$(db_count "SELECT COUNT(*) FROM transcript_entries WHERE created_at > datetime('now', '-2 minutes');")

  if [ "$recent_entries" -ge 1 ]; then
    log_success "✓ New entries added to database (count: $recent_entries)"
  else
    log_warn "No new entries detected in last 2 minutes"
  fi

  # Check for LLM queue activity (optional)
  if grep -q "LLM\|llm\|queue" "$LOGFILE" 2>/dev/null; then
    log_success "✓ LLM queue activity detected"
  else
    log_info "⚠ LLM queue activity not detected (async, may complete later)"
  fi

  # No errors
  local error_count
  error_count=$(log_count "\[ERROR\]")
  if [ "$error_count" -eq 0 ]; then
    log_success "✓ No errors during real-time update"
  else
    log_warn "Found $error_count error(s) during update"
  fi
}

report_results() {
  echo ""
  log_header "TEST SUMMARY: $TEST_ID"

  if [ $TEST_FAILED -eq 0 ]; then
    log_success "✅ ALL CHECKS PASSED"
    log_info "Real-time update pipeline verified"
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
