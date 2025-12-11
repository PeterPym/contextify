#!/bin/bash
# QA-03: New Codex Transcript Discovery
#
# Purpose: Validates end-to-end pipeline from file creation to timeline display
#          for Codex CLI transcripts.
#
# Pipeline stages verified:
# 1. File System Events (FSEvents detects new .jsonl file)
# 2. Transcript Discovery (File identified and project extracted from CWD field)
# 3. Database Ingestion (Transcript + entries written to SQLite)
# 4. Watcher Creation (TranscriptWatcher started for real-time updates)
# 5. Timeline Update (ConversationMonitor displays entries)
#
# Prerequisites:
# - App running with FSEvents monitoring active
# - Test project exists: /tmp/contextify-qa-test (git repo initialized)
# - Codex CLI installed and authenticated

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-03"
TEST_NAME="New Codex Transcript Discovery"
TEST_PROJECT="${TEST_PROJECT:-/tmp/contextify-qa-test}"
TRANSCRIPT=""
TEST_MARKER=""

# ─────────────────────────────────────────────────────────────────────────────
# Test Implementation
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_subheader "Checking Prerequisites"

  assert_command_exists "sqlite3"

  # Codex CLI only required if not in fixture mode
  if [ "${QA_FIXTURE_MODE:-0}" != "1" ]; then
    assert_command_exists "codex"
  else
    log_info "Fixture mode: skipping Codex CLI check"
    assert_command_exists "uuidgen"
  fi

  # Create test project if doesn't exist
  create_test_project "$TEST_PROJECT"

  log_success "Prerequisites met"
}

setup_test() {
  log_subheader "Setup"

  # Kill any existing instance for clean state
  kill_app_if_running

  # Start log capture before launching app
  start_log_capture "$LOGDIR"

  # Launch the app
  log_info "Launching DMG build..."
  if ! launch_dmg_app; then
    log_error "Failed to launch app"
    TEST_FAILED=1
    return 1
  fi

  log_success "Setup complete"
}

run_test_steps() {
  log_subheader "Test Execution"

  cd "$TEST_PROJECT"

  if [ "${QA_FIXTURE_MODE:-0}" = "1" ]; then
    log_info "Fixture mode: seeding Codex transcript"
    TRANSCRIPT=$(seed_fixture_transcript "codex")
    if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
      log_error "Failed to seed fixture transcript"
      TEST_FAILED=1
      cd - > /dev/null
      return 1
    fi
    log_success "Fixture transcript seeded: $TRANSCRIPT"
  else
    log_info "Creating new Codex conversation in test project..."

    # Generate unique test identifier
    TEST_MARKER="QA-$(date +%s)"

    # Start Codex conversation with simple prompt (use 'exec' for non-interactive mode)
    # See: appstore-metadata/review-materials/generate-transcripts.sh for pattern
    log_info "Running: codex exec -C $TEST_PROJECT \"print '$TEST_MARKER' in Python\""

    # Run codex exec (non-interactive mode) with timeout in background
    run_with_timeout 45 codex exec -C "$TEST_PROJECT" --dangerously-bypass-approvals-and-sandbox "print '$TEST_MARKER' in Python and then exit immediately" > /dev/null 2>&1 &
    local CODEX_PID=$!

    # Wait for transcript file creation
    log_info "Waiting for transcript file creation (max 20s)..."
    local elapsed=0
    local max_wait=20

    while [ $elapsed -lt $max_wait ]; do
      TRANSCRIPT=$(find ~/.codex/sessions -name "*.jsonl" -mmin -1 2>/dev/null | head -1)
      if [ -n "$TRANSCRIPT" ]; then
        log_success "Transcript file created: $TRANSCRIPT"
        break
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done

    if [ -z "$TRANSCRIPT" ]; then
      log_error "Transcript file not created within ${max_wait}s"
      TEST_FAILED=1
      cd - > /dev/null
      return 1
    fi

    # Wait for Codex to complete (with timeout)
    wait "$CODEX_PID" 2>/dev/null || true
  fi

  # Wait for ingestion to complete (same for both modes)
  log_info "Waiting for ingestion to complete..."
  if ! wait_for_log_pattern "\[HOOVER-DONE\]" 30; then
    log_warn "HOOVER-DONE not detected, checking database directly..."
  fi

  cd - > /dev/null
  log_success "Test execution completed"
}

validate_results() {
  log_subheader "Validation"

  local transcript_basename
  transcript_basename=$(basename "$TRANSCRIPT")
  local transcript_dir
  transcript_dir=$(dirname "$TRANSCRIPT")

  # Stage 1: File System Events
  log_info "Stage 1: Validating FSEvents detection..."
  # FSEvents tags include: [FSEVENTS-CHANGE], [FSEVENTS-TRANSCRIPT], [FSEVENTS-CODEX]
  soft_assert_log_contains "\[FSEVENTS-" "FSEvents system active"

  # Stage 2: Transcript Discovery
  log_info "Stage 2: Validating transcript discovery..."
  soft_assert_log_contains "contextify-qa-test" "Test project referenced in logs"

  # Stage 3: Database Ingestion
  log_info "Stage 3: Validating database ingestion..."

  # Check transcript exists in database
  local db_transcript_count
  db_transcript_count=$(db_count "SELECT COUNT(*) FROM transcripts WHERE file_path LIKE '%${transcript_basename}%';")

  if [ "$db_transcript_count" -ge 1 ]; then
    log_success "✓ Transcript row exists in database"
  else
    # Try broader search
    db_transcript_count=$(db_count "SELECT COUNT(*) FROM transcripts WHERE file_path LIKE '%codex%' AND updated_at > datetime('now', '-2 minutes');")
    if [ "$db_transcript_count" -ge 1 ]; then
      log_success "✓ Recent Codex transcript found in database"
    else
      log_error "ASSERTION FAILED: Transcript not in database"
      log_error "  Expected 1+ rows, got: $db_transcript_count"
      TEST_FAILED=1
    fi
  fi

  # Get transcript ID for further checks
  local transcript_id
  transcript_id=$(db_query "SELECT id FROM transcripts WHERE file_path LIKE '%${transcript_basename}%' LIMIT 1;")

  if [ -z "$transcript_id" ]; then
    transcript_id=$(db_query "SELECT id FROM transcripts WHERE file_path LIKE '%codex%' ORDER BY updated_at DESC LIMIT 1;")
  fi

  if [ -n "$transcript_id" ]; then
    log_info "Transcript ID: $transcript_id"

    # Verify entries ingested
    local entry_count
    entry_count=$(db_count "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id = '$transcript_id';")

    if [ "$entry_count" -ge 1 ]; then
      log_success "✓ Entries ingested (count: $entry_count)"
    else
      log_warn "No entries found for transcript (may still be processing)"
    fi

    # Verify provider
    local provider
    provider=$(db_query "SELECT provider FROM transcripts WHERE id = '$transcript_id';")

    if [ "$provider" = "codex.cli" ]; then
      log_success "✓ Provider correctly identified as 'codex.cli'"
    else
      log_warn "Provider is '$provider' (expected 'codex.cli')"
    fi
  else
    log_error "Could not retrieve transcript ID from database"
    TEST_FAILED=1
  fi

  # Stage 4: Watcher Creation
  log_info "Stage 4: Validating watcher creation..."
  soft_assert_log_contains "\[WATCHER" "Watcher activity detected"

  # Stage 5: Content verification - check test marker made it through
  log_info "Stage 5: Validating test content ingested..."
  if [ -n "$TEST_MARKER" ] && [ -n "$transcript_id" ]; then
    local content_match
    content_match=$(db_count "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id = '$transcript_id' AND content LIKE '%$TEST_MARKER%';")
    if [ "$content_match" -ge 1 ]; then
      log_success "✓ Test marker '$TEST_MARKER' found in ingested content"
    else
      log_error "ASSERTION FAILED: Test marker not found in database"
      log_error "  Expected content containing: $TEST_MARKER"
      TEST_FAILED=1
    fi
  else
    soft_assert_log_contains "\[TIMELINE" "Timeline activity detected"
  fi

  # Optional: LLM summary queueing (informational)
  if grep -q "\[LLM" "$LOGFILE" 2>/dev/null; then
    log_success "✓ LLM processing detected (async)"
  else
    log_info "⚠ LLM processing not detected (may complete later)"
  fi
}

report_results() {
  echo ""
  log_header "TEST SUMMARY: $TEST_ID"

  if [ $TEST_FAILED -eq 0 ]; then
    log_success "✅ ALL CHECKS PASSED"
    log_info "Pipeline verified: File System → Discovery → Database → Watcher → Timeline"
    echo ""
    log_info "Test artifacts:"
    log_info "  Transcript: $TRANSCRIPT"
    log_info "  Logs: $LOGFILE"
    exit 0
  else
    log_error "❌ SOME CHECKS FAILED"
    echo ""
    log_info "Troubleshooting:"
    log_info "  1. Check app logs: $LOGFILE"
    log_info "  2. Verify transcript: ls -la $TRANSCRIPT"
    log_info "  3. Check database: sqlite3 \"$DB_PATH\" 'SELECT * FROM transcripts ORDER BY updated_at DESC LIMIT 5;'"
    exit 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

cleanup() {
  kill_app_if_running
  stop_log_capture
}

main() {
  # Set up log directory
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"

  # Ensure cleanup runs on exit
  trap cleanup EXIT

  log_header "$TEST_ID: $TEST_NAME"

  check_prerequisites
  setup_test
  run_test_steps
  validate_results
  report_results
}

main "$@"
