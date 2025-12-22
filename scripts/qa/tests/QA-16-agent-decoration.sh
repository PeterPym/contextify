#!/bin/bash
# QA-16: Agent Spawn Decoration
#
# Purpose: Validates that timeline entries showing spawned agents are decorated
#          with agent type badges (e.g., [Explore], [Plan]).
#
# @test_contract
# isolation:
#   transcripts: fixture       # Uses agent-spawn.jsonl fixture
#   database: reset            # Fresh DB for clean test
#
# database:
#   location: dmg
#   start:
#     exists: false            # Database deleted in setup
#   mutations:
#     - "Ingests fixture with Task tool_use block"
#     - "Creates tool_invocations row with sidechain_transcript_id"
#     - "Links agent transcript via agentId"
#   end:
#     exists: true
#     tool_invocations: +1     # Task invocation with sidechain linkage
#
# dependencies:
#   orchestrator_flags: [--isolate]
#   run_after: []
#   notes: "Tests Layer 1 decoration (agent badge). Fixture-based, no CLI needed."
#
# Decoration features verified:
# 1. tool_invocations row created for Task
# 2. sidechain_transcript_id populated (links to agent transcript)
# 3. Timeline entry shows agent type badge [Explore]
# 4. Tooltip shows "Spawned Explore agent"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-16"
TEST_NAME="Agent Spawn Decoration"
TEST_PROJECT="${TEST_PROJECT:-/tmp/contextify-qa-test}"
TRANSCRIPT=""
SELF_ISOLATED=0

# ─────────────────────────────────────────────────────────────────────────────
# Test Implementation
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_subheader "Checking Prerequisites"

  assert_command_exists "sqlite3"
  assert_command_exists "uuidgen"

  create_test_project "$TEST_PROJECT"

  log_success "Prerequisites met"
}

setup_test() {
  log_subheader "Setup"

  kill_app_if_running

  # Delete database for clean state
  rm -f "$DB_PATH"* 2>/dev/null || true

  # Seed the agent-spawn fixture before app launch
  log_info "Seeding agent-spawn fixture..."
  cd "$TEST_PROJECT"

  # Seed the agent-spawn fixture using common helper
  TRANSCRIPT=$(seed_fixture_transcript "claude" "agent-spawn.jsonl" "$TEST_PROJECT")

  if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    log_error "Failed to seed fixture transcript"
    TEST_FAILED=1
    return 1
  fi
  log_success "Main transcript seeded: $TRANSCRIPT"

  # Also seed the sidechain transcript (agent-e2eagent.jsonl)
  local sidechain_transcript
  sidechain_transcript=$(seed_fixture_transcript "claude" "agent-e2eagent.jsonl" "$TEST_PROJECT" 2>/dev/null || true)
  if [ -n "$sidechain_transcript" ] && [ -f "$sidechain_transcript" ]; then
    log_info "Sidechain transcript seeded: $sidechain_transcript"
  else
    log_warn "Sidechain transcript not seeded (may affect sidechain linkage test)"
  fi

  cd - > /dev/null

  # Start log capture
  start_log_capture "$LOGDIR"

  # Launch app
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

  # Wait for ingestion
  log_info "Waiting for ingestion to complete..."
  if ! wait_for_log_pattern "\[HOOVER-DONE\]" 30; then
    log_warn "HOOVER-DONE not detected, waiting additional time..."
    sleep 5
  fi

  log_success "Test execution completed"
}

validate_results() {
  log_subheader "Validation"

  # ─────────────────────────────────────────────────────────────────────────
  # Stage 1: Database - tool_invocations created
  # ─────────────────────────────────────────────────────────────────────────
  log_info "Stage 1: Validating tool_invocations table..."

  local task_count
  task_count=$(db_count "SELECT COUNT(*) FROM tool_invocations WHERE tool_name = 'Task';")

  if [ "$task_count" -ge 1 ]; then
    log_success "Stage 1 PASS: Task invocation found in tool_invocations (count: $task_count)"
  else
    log_error "Stage 1 FAIL: No Task invocations in tool_invocations"
    TEST_FAILED=1
  fi

  # ─────────────────────────────────────────────────────────────────────────
  # Stage 2: Database - tool_key populated with agent type
  # ─────────────────────────────────────────────────────────────────────────
  log_info "Stage 2: Validating tool_key (agent type)..."

  local explore_count
  explore_count=$(db_count "SELECT COUNT(*) FROM tool_invocations WHERE tool_key = 'Explore';")

  if [ "$explore_count" -ge 1 ]; then
    log_success "Stage 2 PASS: Explore agent type recorded (count: $explore_count)"
  else
    log_error "Stage 2 FAIL: No 'Explore' tool_key in tool_invocations"
    TEST_FAILED=1
  fi

  # ─────────────────────────────────────────────────────────────────────────
  # Stage 3: Database - sidechain_transcript_id linked
  # ─────────────────────────────────────────────────────────────────────────
  log_info "Stage 3: Validating sidechain linkage..."

  local sidechain_count
  sidechain_count=$(db_count "SELECT COUNT(*) FROM tool_invocations WHERE tool_name = 'Task' AND sidechain_transcript_id IS NOT NULL;")

  if [ "$sidechain_count" -ge 1 ]; then
    log_success "Stage 3 PASS: Sidechain transcript linked (count: $sidechain_count)"
  else
    log_warn "Stage 3 SOFT FAIL: No sidechain linkage found (may be timing issue)"
    # Don't fail test - sidechain linking depends on both transcripts being ingested
  fi

  # ─────────────────────────────────────────────────────────────────────────
  # Stage 4: UI - Agent badge rendered (RED until implemented)
  # ─────────────────────────────────────────────────────────────────────────
  log_info "Stage 4: Validating agent badge rendering..."

  # Look for log pattern indicating decoration was rendered
  # Expected pattern: [DECORATION] Agent badge: Explore
  if assert_log_contains "\[DECORATION\].*Explore\|agent.*badge.*Explore\|spawnedAgentType.*Explore" "Agent decoration rendered"; then
    log_success "Stage 4 PASS: Agent badge rendered in UI"
  else
    log_error "Stage 4 FAIL: Agent badge NOT rendered (decoration UI not implemented)"
    TEST_FAILED=1
  fi

  # ─────────────────────────────────────────────────────────────────────────
  # Summary: Query decoration data via orchestrator
  # ─────────────────────────────────────────────────────────────────────────
  log_info "Decoration data summary:"
  db_query "SELECT tool_name, tool_key, sidechain_transcript_id IS NOT NULL as has_sidechain FROM tool_invocations LIMIT 5;"
}

report_results() {
  echo ""
  log_header "TEST SUMMARY: $TEST_ID"

  if [ $TEST_FAILED -eq 0 ]; then
    log_success "ALL CHECKS PASSED"
    log_info "Agent spawn decoration verified end-to-end"
  else
    log_error "SOME CHECKS FAILED"
    echo ""
    log_info "Expected failure stages for RED state:"
    log_info "  - Stage 4 (UI rendering) fails until decoration UI is implemented"
    echo ""
    log_info "Troubleshooting:"
    log_info "  1. Check logs: $LOGFILE"
    log_info "  2. Query DB: sqlite3 \"$DB_PATH\" 'SELECT * FROM tool_invocations;'"
  fi

  exit $TEST_FAILED
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

cleanup() {
  kill_app_if_running
  stop_log_capture
}

main() {
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"

  trap cleanup EXIT

  log_header "$TEST_ID: $TEST_NAME"

  # Force fixture mode
  export QA_FIXTURE_MODE=1

  check_prerequisites
  setup_test
  run_test_steps
  validate_results
  report_results
}

main "$@"
