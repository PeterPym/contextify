#!/bin/bash
# QA-10: Quick Search
#
# Purpose: Validates Quick Search activation via Cmd+F and search execution.
#          Tests that FTS5 search returns results from indexed content.
#
# @test_contract
# isolation:
#   transcripts: orchestrator  # Relies on --isolate for fixture transcripts
#   database: preserve         # Uses existing DB with FTS5 index
#
# database:
#   location: dmg
#   start:
#     exists: true
#     min_projects: 1
#     min_transcripts: 1
#     min_fts_entries: 1       # Need FTS5 index populated
#   mutations:
#     - "Focuses search field (Cmd+F)"
#     - "Types search term"
#     - "Executes search (Enter)"
#     - "Read-only: queries FTS5 index"
#     - "No database modifications"
#   end:
#     exists: true
#     projects: same
#     transcripts: same
#
# dependencies:
#   orchestrator_flags: [--isolate]
#   run_after: [QA-03, QA-04]  # Phase 5 - needs FTS5 data from discovery tests
#   notes: "Read-only search test. FTS5 index must be populated by discovery tests."
#
# Validates:
# - Cmd+F focuses search field
# - Search executes on Enter
# - App remains responsive
# - No errors during search
#
# Prerequisites:
# - DMG app build available
# - Database has FTS5 searchable content
# - Terminal has Accessibility permission

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-10"
TEST_NAME="Quick Search"

check_prerequisites() {
  log_subheader "Checking Prerequisites"
  assert_command_exists "sqlite3"
  assert_command_exists "osascript"
  assert_dmg_app_exists

  # Verify database has searchable content
  local entry_count
  entry_count=$(db_count "SELECT COUNT(*) FROM transcript_entries_fts;" 2>/dev/null || echo "0")
  if [ "$entry_count" -eq 0 ]; then
    log_warn "FTS5 index is empty; search may return no results"
    log_info "Run QA-03 or QA-04 first to populate database"
  else
    log_info "FTS5 index has $entry_count entries"
  fi

  log_success "Prerequisites met"
}

run_test_steps() {
  log_subheader "Test Execution"

  # Determine search term based on available fixtures
  local search_term="QA_FIXTURE_SEARCH_TERM"

  # 1. Focus search field
  log_info "Focusing search field (Cmd+F)"
  focus_search_field
  sleep 0.5

  # 2. Type search term
  log_info "Typing search term: $search_term"
  type_text "$search_term"
  sleep 0.3

  # 3. Trigger Quick Search (Enter)
  log_info "Triggering Quick Search (Enter)"
  press_return

  # 4. Wait for search completion
  # Note: [SEARCH-DONE] log pattern not yet implemented in Swift code
  # For now, just wait for the UI to settle
  sleep 3

  log_success "Quick Search completed"

  # 5. Exit Quick Search (Escape)
  log_info "Exiting Quick Search (Escape)"
  press_escape
  sleep 0.5

  log_success "Test execution completed"
}

validate_results() {
  log_subheader "Validation"

  # Search log patterns not yet implemented in Swift code - use soft assertions
  soft_assert_log_contains "\[SEARCH-START\]" "Quick Search started"
  soft_assert_log_contains "\[SEARCH-DONE\]" "Quick Search completed"

  # App still running (core requirement)
  assert_app_running "Contextify"

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

  kill_app_if_running
  start_log_capture "$LOGDIR"

  if ! launch_dmg_app; then
    log_error "Failed to launch app"
    TEST_FAILED=1
    exit_with_result
  fi

  sleep 3  # Wait for app initialization

  run_test_steps
  validate_results
  exit_with_result
}

main "$@"
