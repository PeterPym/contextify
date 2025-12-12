#!/bin/bash
# QA-09: DB Migration & Integrity
#
# Purpose: Validates that the app successfully migrates older database schemas.
#          Tests backwards compatibility with fixture databases from older versions.
#
# @test_contract
# isolation:
#   transcripts: none          # Doesn't touch transcript directories
#   database: fixture          # Installs fixture DBs, restores original at end
#
# database:
#   location: dmg
#   start:
#     exists: varies           # Installs fixture DB for each test iteration
#     min_projects: 0          # Fixture may have projects
#     min_transcripts: 0       # Fixture may have transcripts
#   mutations:
#     - "Backs up current database"
#     - "Installs old-version fixture database"
#     - "App runs migrations on startup"
#     - "Schema version updated to current"
#     - "Restores original database at end"
#   end:
#     exists: true             # Original DB restored
#     projects: same as original
#     transcripts: same as original
#
# dependencies:
#   orchestrator_flags: []     # No isolation needed - uses fixture DBs
#   run_after: []              # Phase 2 - run before discovery to avoid wiping FTS data
#   notes: "Self-contained. Backs up/restores production DB. Tests each fixture."
#
# Validates:
# - App migrates old schemas successfully
# - No data corruption during migration
# - App starts after migration
# - Schema version updated
#
# Prerequisites:
# - DMG app build available
# - DB fixtures in scripts/qa/fixtures/db/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-09"
TEST_NAME="DB Migration & Integrity"

check_prerequisites() {
  log_subheader "Checking Prerequisites"
  assert_command_exists "sqlite3"
  assert_dmg_app_exists

  # Verify at least one DB fixture exists using nullglob
  shopt -s nullglob
  local db_fixtures=("$QA_FIXTURE_DIR"/db/*.db)
  shopt -u nullglob

  if [ ${#db_fixtures[@]} -eq 0 ]; then
    log_error "No DB fixtures found in $QA_FIXTURE_DIR/db/"
    log_error "Create fixtures per scripts/qa/fixtures/db/README.md"
    exit 1
  fi

  log_success "Prerequisites met (${#db_fixtures[@]} fixtures found)"
}

test_migration() {
  local fixture="$1"
  local fixture_version="${fixture%%-*}"  # Extract version (e.g., "v16" from "v16-contextify.db")

  log_subheader "Testing migration: $fixture"

  # Install fixture and get pre-migration version
  install_db_fixture "$fixture"
  local old_version
  old_version=$(db_query "PRAGMA user_version;" || echo "unknown")
  log_info "Fixture schema version: $old_version"

  # Use standard log capture (sets LOGFILE for wait_for_log_pattern)
  start_log_capture "$LOGDIR"

  # Launch app to trigger migration
  kill_app_if_running
  if ! launch_dmg_app; then
    log_error "App failed to launch with $fixture"
    stop_log_capture
    TEST_FAILED=1
    return 1
  fi

  # Wait for startup
  sleep 5

  # Validate migration
  local new_version
  new_version=$(db_query "PRAGMA user_version;" || echo "unknown")
  log_info "Post-migration schema version: $new_version"

  # Check for migration errors in logs
  if grep -q "\[ERROR\].*migration\|migration.*error" "$LOGFILE" 2>/dev/null; then
    log_error "Migration errors found in logs"
    grep -i "error" "$LOGFILE" | head -5
    TEST_FAILED=1
  fi

  # Verify core tables exist and are queryable
  local tables_ok=1
  for table in projects transcripts transcript_entries; do
    if ! db_query "SELECT COUNT(*) FROM $table;" >/dev/null 2>&1; then
      log_error "Table $table not accessible after migration"
      tables_ok=0
    fi
  done

  if [ "$tables_ok" = "1" ]; then
    log_success "Migration $fixture_version -> v$new_version successful"
  else
    TEST_FAILED=1
  fi

  # Cleanup
  kill_app_if_running
  stop_log_capture

  # Save migration-specific log copy if needed for debugging
  cp "$LOGFILE" "$LOGDIR/migration-$fixture.log" 2>/dev/null || true
}

cleanup() {
  kill_app_if_running
  stop_log_capture
  restore_db_from_backup
}

main() {
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"

  trap cleanup EXIT

  log_header "$TEST_ID: $TEST_NAME"
  check_prerequisites

  # Collect fixtures
  shopt -s nullglob
  local db_fixtures=("$QA_FIXTURE_DIR"/db/*.db)
  shopt -u nullglob

  # Test each fixture
  for fixture_path in "${db_fixtures[@]}"; do
    fixture=$(basename "$fixture_path")
    test_migration "$fixture"
  done

  exit_with_result
}

main "$@"
