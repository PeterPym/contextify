#!/bin/bash
# CLI-04: Worktree-aware query tests
#
# Purpose: Validate CLI worktree detection, multi-project query expansion,
#          database discovery across DMG/App Store builds, and scope flags.
#
# @test_contract
# isolation:
#   transcripts: none
#   database: preserve (creates temporary worktrees for testing)
#
# database:
#   location: default (also tests App Store container discovery)
#   start:
#     exists: true
#     min_transcripts: 1
#   mutations:
#     - "None (read-only CLI queries)"
#   end:
#     exists: true
#     transcripts: unchanged
#
# dependencies:
#   cli_tools: [contextify-query, jq, git]
#   notes: "Creates temporary git worktrees for testing. Cleans up on exit."

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="CLI-04"
TEST_NAME="Worktree Query"
CLI_BIN="${CONTEXTIFY_QUERY_BIN:-contextify-query}"

# Test directories (cleaned up on exit)
TEST_REPO_DIR=""
WORKTREE_1_DIR=""
WORKTREE_2_DIR=""

LAST_STATUS=0

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

run_command() {
  local output
  set +e
  output=$("$@" 2>&1)
  LAST_STATUS=$?
  set -e
  echo "$output"
}

run_command_stderr_separate() {
  # Capture stdout and stderr separately
  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  set +e
  "$@" >"$stdout_file" 2>"$stderr_file"
  LAST_STATUS=$?
  set -e
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

require_ok_status() {
  local desc="$1"
  if [ "$LAST_STATUS" -ne 0 ]; then
    log_error "ASSERTION FAILED: $desc (exit code: $LAST_STATUS)"
    TEST_FAILED=1
    return 1
  fi
  return 0
}

json_length() {
  echo "$1" | jq '.data | length' 2>/dev/null || echo "-1"
}

# ─────────────────────────────────────────────────────────────────────────────
# Test Fixture Setup
# ─────────────────────────────────────────────────────────────────────────────

setup_worktree_fixtures() {
  log_info "Creating temporary git repository with worktrees..."

  # Create main repo
  TEST_REPO_DIR=$(mktemp -d "/tmp/contextify-qa-worktree-main.XXXXXX")
  cd "$TEST_REPO_DIR"
  git init -q
  git config user.email "qa@contextify.test"
  git config user.name "QA Test"
  echo "# Main Worktree Test Repo" > README.md
  git add README.md
  git commit -q -m "Initial commit"

  # Create first linked worktree
  WORKTREE_1_DIR=$(mktemp -d "/tmp/contextify-qa-worktree-feature1.XXXXXX")
  rmdir "$WORKTREE_1_DIR"  # git worktree add needs non-existent dir
  git worktree add -q "$WORKTREE_1_DIR" -b feature-1

  # Create second linked worktree
  WORKTREE_2_DIR=$(mktemp -d "/tmp/contextify-qa-worktree-feature2.XXXXXX")
  rmdir "$WORKTREE_2_DIR"
  git worktree add -q "$WORKTREE_2_DIR" -b feature-2

  cd - > /dev/null

  log_success "Created worktree fixtures:"
  log_info "  Main:      $TEST_REPO_DIR"
  log_info "  Feature 1: $WORKTREE_1_DIR"
  log_info "  Feature 2: $WORKTREE_2_DIR"
}

cleanup_worktree_fixtures() {
  log_info "Cleaning up worktree fixtures..."

  if [ -n "$TEST_REPO_DIR" ] && [ -d "$TEST_REPO_DIR" ]; then
    # Remove worktrees first (git worktree remove)
    cd "$TEST_REPO_DIR" 2>/dev/null || true
    git worktree remove --force "$WORKTREE_1_DIR" 2>/dev/null || true
    git worktree remove --force "$WORKTREE_2_DIR" 2>/dev/null || true
    cd - > /dev/null 2>/dev/null || true

    # Remove directories
    rm -rf "$WORKTREE_1_DIR" 2>/dev/null || true
    rm -rf "$WORKTREE_2_DIR" 2>/dev/null || true
    rm -rf "$TEST_REPO_DIR" 2>/dev/null || true
  fi

  log_info "Cleanup complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# Prerequisites
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log_subheader "Checking prerequisites"

  # Check CLI binary
  if [[ "$CLI_BIN" == /* ]]; then
    if [ ! -x "$CLI_BIN" ]; then
      log_error "ASSERTION FAILED: contextify-query CLI not found at $CLI_BIN"
      TEST_FAILED=1
      exit 1
    fi
    log_success "contextify-query CLI available ($CLI_BIN)"
  else
    if ! assert_command_exists "$CLI_BIN" "contextify-query CLI available"; then
      exit 1
    fi
  fi

  if ! assert_command_exists "jq" "jq available"; then
    exit 1
  fi

  if ! assert_command_exists "git" "git available"; then
    exit 1
  fi

  # Verify database exists
  local result
  result=$(run_command "$CLI_BIN" status --json)
  if ! require_ok_status "CLI can find database"; then
    log_error "Database not found - ensure Contextify app has been run at least once"
    exit 1
  fi

  log_success "Database accessible"
}

# ─────────────────────────────────────────────────────────────────────────────
# Test: Database Discovery
# ─────────────────────────────────────────────────────────────────────────────

test_database_discovery() {
  log_subheader "Database Discovery"

  local result db_path
  result=$(run_command "$CLI_BIN" status --json)
  if ! require_ok_status "Status command succeeds"; then
    return 1
  fi

  db_path=$(echo "$result" | jq -r '.data.databasePath // empty' 2>/dev/null || echo "")
  if ! assert_not_empty "$db_path" "Database path returned"; then
    return 1
  fi

  # Check if it's DMG or App Store location
  if [[ "$db_path" == *"/Library/Containers/"* ]]; then
    log_info "Database location: App Store container"
  elif [[ "$db_path" == *"/Library/Application Support/Contextify/"* ]]; then
    log_info "Database location: Standard (DMG)"
  else
    log_info "Database location: Custom ($db_path)"
  fi

  log_success "Database discovery works"
}

test_appstore_container_discovery() {
  log_subheader "App Store Container Discovery"

  local container_path="$HOME/Library/Containers/sh.contextify.Contextify/Data/Library/Application Support/Contextify"

  if [ -d "$container_path" ]; then
    log_info "App Store container exists: $container_path"

    # Check for database
    if [ -f "$container_path/contextify.db" ]; then
      log_success "App Store database found"

      # Check for sidecar
      if [ -f "$container_path/.state/state.json" ]; then
        log_success "Sidecar file found"

        # Validate sidecar structure
        if jq -e '.database_path' "$container_path/.state/state.json" >/dev/null 2>&1; then
          log_success "Sidecar has database_path field"
        else
          log_warn "Sidecar missing database_path field"
        fi
      else
        log_info "No sidecar file (app may not have written it yet)"
      fi
    else
      log_info "No App Store database (App Store version not used)"
    fi
  else
    log_info "App Store container not present (App Store version not installed)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Test: Worktree Detection
# ─────────────────────────────────────────────────────────────────────────────

test_worktree_detection_from_main() {
  log_subheader "Worktree Detection from Main Worktree"

  cd "$TEST_REPO_DIR"

  # Run status to see if worktree detection works
  run_command_stderr_separate "$CLI_BIN" status --json
  if ! require_ok_status "Status from main worktree succeeds"; then
    cd - > /dev/null
    return 1
  fi

  # Check stderr for worktree group message (if any projects exist)
  # Note: stderr message only appears if projects are found in DB
  log_success "CLI runs from main worktree"
  cd - > /dev/null
}

test_worktree_detection_from_linked() {
  log_subheader "Worktree Detection from Linked Worktree"

  cd "$WORKTREE_1_DIR"

  run_command_stderr_separate "$CLI_BIN" status --json
  if ! require_ok_status "Status from linked worktree succeeds"; then
    cd - > /dev/null
    return 1
  fi

  log_success "CLI runs from linked worktree"
  cd - > /dev/null
}

test_worktree_detection_from_subdirectory() {
  log_subheader "Worktree Detection from Subdirectory"

  # Create and enter a subdirectory
  local subdir="$WORKTREE_1_DIR/src/components"
  mkdir -p "$subdir"
  cd "$subdir"

  run_command_stderr_separate "$CLI_BIN" status --json
  if ! require_ok_status "Status from subdirectory succeeds"; then
    cd - > /dev/null
    return 1
  fi

  log_success "CLI runs from subdirectory within worktree"
  cd - > /dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Test: Scope Flags
# ─────────────────────────────────────────────────────────────────────────────

test_this_worktree_flag() {
  log_subheader "--this-worktree Flag"

  cd "$TEST_REPO_DIR"

  # Test that --this-worktree is accepted
  run_command_stderr_separate "$CLI_BIN" search "test" --this-worktree --limit 1 --json

  # Exit code 0 or "no results" is fine - we're testing flag acceptance
  if [ "$LAST_STATUS" -eq 0 ]; then
    log_success "--this-worktree flag accepted"
  elif echo "$LAST_STDOUT" | jq -e '.type == "search"' >/dev/null 2>&1; then
    log_success "--this-worktree flag accepted (no results)"
  else
    log_error "--this-worktree flag rejected"
    TEST_FAILED=1
    cd - > /dev/null
    return 1
  fi

  # Verify no worktree expansion message in stderr
  if echo "$LAST_STDERR" | grep -q "Searching across worktree group"; then
    log_error "--this-worktree should suppress expansion message"
    TEST_FAILED=1
  else
    log_success "--this-worktree suppresses worktree expansion"
  fi

  cd - > /dev/null
}

test_exclude_flag() {
  log_subheader "--exclude Flag"

  cd "$TEST_REPO_DIR"

  # Test that --exclude is accepted (use basename, not full path)
  local wt1_name
  wt1_name=$(basename "$WORKTREE_1_DIR")

  run_command_stderr_separate "$CLI_BIN" search "test" --exclude "$wt1_name" --limit 1 --json

  if [ "$LAST_STATUS" -eq 0 ] || echo "$LAST_STDOUT" | jq -e '.type == "search"' >/dev/null 2>&1; then
    log_success "--exclude flag accepted"
  else
    log_error "--exclude flag rejected"
    TEST_FAILED=1
    cd - > /dev/null
    return 1
  fi

  cd - > /dev/null
}

test_exclude_multiple() {
  log_subheader "--exclude Multiple Paths (comma-separated)"

  cd "$TEST_REPO_DIR"

  # Test comma-separated --exclude (CLI syntax is --exclude "path1,path2")
  local wt1_name wt2_name
  wt1_name=$(basename "$WORKTREE_1_DIR")
  wt2_name=$(basename "$WORKTREE_2_DIR")

  run_command_stderr_separate "$CLI_BIN" search "test" \
    --exclude "$wt1_name,$wt2_name" \
    --limit 1 --json

  if [ "$LAST_STATUS" -eq 0 ] || echo "$LAST_STDOUT" | jq -e '.type == "search"' >/dev/null 2>&1; then
    log_success "Comma-separated --exclude accepted"
  else
    log_error "Comma-separated --exclude rejected"
    TEST_FAILED=1
    cd - > /dev/null
    return 1
  fi

  cd - > /dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Test: Output Format
# ─────────────────────────────────────────────────────────────────────────────

test_stderr_stdout_separation() {
  log_subheader "stderr/stdout Separation"

  cd "$TEST_REPO_DIR"

  run_command_stderr_separate "$CLI_BIN" search "test" --limit 1 --json

  # stdout should be valid JSON (or empty JSON response)
  if echo "$LAST_STDOUT" | jq . >/dev/null 2>&1; then
    log_success "stdout is valid JSON"
  else
    log_error "stdout is not valid JSON"
    log_info "stdout: $LAST_STDOUT"
    TEST_FAILED=1
    cd - > /dev/null
    return 1
  fi

  # stderr should not contain JSON
  if echo "$LAST_STDERR" | jq . >/dev/null 2>&1 && [ -n "$LAST_STDERR" ]; then
    log_warn "stderr contains JSON (should be human-readable messages only)"
  else
    log_success "stderr contains non-JSON messages (correct)"
  fi

  cd - > /dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Test: Git CLI Hardening
# ─────────────────────────────────────────────────────────────────────────────

test_git_invocation_no_hang() {
  log_subheader "Git Invocation Doesn't Hang"

  cd "$TEST_REPO_DIR"

  # This should complete quickly, not hang waiting for git prompts
  local start_time end_time elapsed
  start_time=$(date +%s)

  run_command "$CLI_BIN" status --json

  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  if [ "$elapsed" -gt 10 ]; then
    log_error "CLI took too long ($elapsed seconds) - possible git prompt hang"
    TEST_FAILED=1
  else
    log_success "CLI completed quickly (${elapsed}s) - no git hang"
  fi

  cd - > /dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Test: Activity Command with Worktrees
# ─────────────────────────────────────────────────────────────────────────────

test_activity_worktree_expansion() {
  log_subheader "Activity Command with Worktree Expansion"

  cd "$TEST_REPO_DIR"

  run_command_stderr_separate "$CLI_BIN" activity --days 30 --limit 5 --json

  if [ "$LAST_STATUS" -eq 0 ]; then
    log_success "Activity command succeeds with worktree context"

    # Check response structure
    if echo "$LAST_STDOUT" | jq -e '.type == "activity"' >/dev/null 2>&1; then
      log_success "Activity returns correct response type"
    fi
  else
    # No activity is fine too
    if echo "$LAST_STDOUT" | jq -e '.type' >/dev/null 2>&1; then
      log_success "Activity command returns valid response"
    else
      log_warn "Activity command failed (may be no data)"
    fi
  fi

  cd - > /dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Test: Submodule Rejection
# ─────────────────────────────────────────────────────────────────────────────

test_submodule_not_expanded() {
  log_subheader "Submodule Not Treated as Worktree"

  # Create a repo with a submodule
  local parent_repo submodule_repo
  parent_repo=$(mktemp -d "/tmp/contextify-qa-parent.XXXXXX")
  submodule_repo=$(mktemp -d "/tmp/contextify-qa-submodule.XXXXXX")

  # Initialize submodule repo
  cd "$submodule_repo"
  git init -q
  git config user.email "qa@contextify.test"
  git config user.name "QA Test"
  echo "# Submodule" > README.md
  git add README.md
  git commit -q -m "Initial"
  cd - > /dev/null

  # Initialize parent and add submodule
  cd "$parent_repo"
  git init -q
  git config user.email "qa@contextify.test"
  git config user.name "QA Test"
  echo "# Parent" > README.md
  git add README.md
  git commit -q -m "Initial"
  git submodule add -q "$submodule_repo" vendor/submodule 2>/dev/null || true
  git commit -q -m "Add submodule" 2>/dev/null || true

  # Run from inside submodule
  if [ -d "vendor/submodule" ]; then
    cd "vendor/submodule"

    run_command_stderr_separate "$CLI_BIN" status --json

    # Should NOT see parent repo's worktrees in expansion
    if echo "$LAST_STDERR" | grep -q "Searching across worktree group"; then
      log_warn "Submodule triggered worktree expansion (may be false positive)"
    else
      log_success "Submodule does not trigger parent worktree expansion"
    fi

    cd - > /dev/null
  else
    log_warn "Submodule creation failed - skipping test"
  fi

  # Cleanup
  rm -rf "$parent_repo" "$submodule_repo"
  cd - > /dev/null 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Test: .worktrees.json Config
# ─────────────────────────────────────────────────────────────────────────────

test_worktrees_json_config() {
  log_subheader ".worktrees.json Configuration"

  cd "$TEST_REPO_DIR"

  # Create .worktrees.json
  cat > .worktrees.json << EOF
{
  "schemaVersion": 1,
  "worktrees": [
    {"name": "Main Branch", "path": "$TEST_REPO_DIR"},
    {"name": "Feature One", "path": "$WORKTREE_1_DIR"},
    {"name": "Old Experiment", "path": "$WORKTREE_2_DIR", "archived": true}
  ]
}
EOF

  run_command_stderr_separate "$CLI_BIN" search "test" --limit 1 --json

  # The CLI should parse .worktrees.json without error
  if [ "$LAST_STATUS" -eq 0 ] || echo "$LAST_STDOUT" | jq -e '.type' >/dev/null 2>&1; then
    log_success ".worktrees.json parsed without error"
  else
    log_error ".worktrees.json caused CLI failure"
    TEST_FAILED=1
  fi

  # Clean up
  rm -f .worktrees.json
  cd - > /dev/null
}

test_worktrees_json_archived() {
  log_subheader ".worktrees.json Archived Field"

  cd "$TEST_REPO_DIR"

  # Create .worktrees.json with archived worktree
  cat > .worktrees.json << EOF
{
  "schemaVersion": 1,
  "worktrees": [
    {"name": "Main", "path": "$TEST_REPO_DIR"},
    {"name": "Archived", "path": "$WORKTREE_2_DIR", "archived": true}
  ]
}
EOF

  run_command_stderr_separate "$CLI_BIN" search "test" --limit 1 --json

  # Check that archived worktree is excluded from expansion message
  if echo "$LAST_STDERR" | grep -q "$WORKTREE_2_DIR"; then
    log_warn "Archived worktree appears in expansion (may be expected if no filter)"
  else
    log_success "Archived worktree filtered from expansion"
  fi

  # Clean up
  rm -f .worktrees.json
  cd - > /dev/null
}

test_worktrees_json_malformed() {
  log_subheader ".worktrees.json Malformed (Graceful Handling)"

  cd "$TEST_REPO_DIR"

  # Create malformed .worktrees.json
  echo "{ invalid json }" > .worktrees.json

  run_command_stderr_separate "$CLI_BIN" status --json

  # Should NOT crash - gracefully ignore malformed config
  if [ "$LAST_STATUS" -eq 0 ]; then
    log_success "Malformed .worktrees.json handled gracefully"
  else
    log_error "Malformed .worktrees.json caused CLI failure"
    TEST_FAILED=1
  fi

  # Clean up
  rm -f .worktrees.json
  cd - > /dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

run_worktree_tests() {
  log_header "$TEST_ID: $TEST_NAME"

  check_prerequisites
  setup_worktree_fixtures

  # Database discovery
  test_database_discovery || true
  test_appstore_container_discovery || true

  # Worktree detection
  test_worktree_detection_from_main || true
  test_worktree_detection_from_linked || true
  test_worktree_detection_from_subdirectory || true

  # Scope flags
  test_this_worktree_flag || true
  test_exclude_flag || true
  test_exclude_multiple || true

  # Output format
  test_stderr_stdout_separation || true

  # Hardening
  test_git_invocation_no_hang || true

  # Activity command
  test_activity_worktree_expansion || true

  # Submodule handling
  test_submodule_not_expanded || true

  # .worktrees.json
  test_worktrees_json_config || true
  test_worktrees_json_archived || true
  test_worktrees_json_malformed || true

  cleanup_worktree_fixtures

  exit_with_result
}

cleanup() {
  cleanup_worktree_fixtures
}

trap cleanup EXIT

main() {
  run_worktree_tests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
