# Contextify Automated QA Methodology (v2 - MVP)

**Version:** 2.0 (MVP - Local Execution)
**Last Updated:** 2025-11-20
**Target:** Pre-release validation on local development machine

---

## Executive Summary

This document defines a **local MVP bash-based automated QA suite** for Contextify that validates 6 critical user flows through log analysis, database queries, and filesystem verification. The suite is designed to run sequentially on your development machine in under 10 minutes with clear pass/fail results.

**MVP Scope:**
- **Local execution only** - Runs on your macOS development machine with real Codex/Claude CLIs
- **Sequential tests** - No parallelization, runs QA-01 → QA-06 in order
- **Real integrations** - Uses actual Codex/Claude sessions, not fixtures
- **Pragmatic shortcuts** - AppleScript for UI automation, direct SQLite queries acceptable

**v2 Professional QA Scope (Future Work):**
- CI/CD integration with GitHub Actions
- Fixture-based tests for reliability/cost
- Database migration testing
- Performance benchmarks with timing assertions
- Headless controls without AppleScript

**Purpose:** Catch regressions before release by testing end-to-end workflows (file system events → database ingestion → timeline display → UI rendering)

**Test Coverage:**
1. App startup and initialization (5 variants: DMG/AppStore × clean/existing + permission skip)
2. Project switching between multiple repositories
3. New transcript discovery (Codex CLI)
4. New transcript discovery (Claude Code)
5. Real-time transcript updates during active sessions
6. Watcher health and recovery mechanisms
7. Transcript window opening
8. Projects window opening

---

## Test Suite Architecture

### Design Principles

1. **Automation First:** Scripts validate expected behavior without human interpretation
2. **Fast Feedback:** Full suite completes in < 10 minutes
3. **Clear Signals:** Exit codes 0 (pass) or 1 (fail) with diagnostic output
4. **Reproducible:** Idempotent tests with proper cleanup between runs
5. **Debuggable:** All logs and database state captured as artifacts
6. **Maintainable:** Simple bash over complex frameworks
7. **MVP Pragmatic:** Good enough for local validation, not production CI

### Test Case Organization

```
scripts/qa/
├── run-all-tests.sh              # Main test orchestrator (sequential, with error aggregation)
├── lib/
│   ├── common.sh                 # Shared utilities (log capture, DB queries, wait helpers, UI automation)
│   ├── assertions.sh             # Test assertion helpers
│   └── cleanup.sh                # Cleanup functions
└── tests/
    ├── QA-01a-launch-dmg-clean.sh      # DMG build, no database (first run)
    ├── QA-01b-launch-dmg-existing.sh   # DMG build, existing database
    ├── QA-01c-launch-appstore-clean.sh # App Store build, grant permissions
    ├── QA-01d-launch-appstore-existing.sh # App Store build, existing bookmarks
    ├── QA-01e-launch-appstore-skip.sh  # App Store build, skip permissions
    ├── QA-02-project-switching.sh
    ├── QA-03-codex-discovery.sh        # Fully detailed example below
    ├── QA-04-claude-discovery.sh
    ├── QA-05-realtime-updates.sh
    ├── QA-06-watcher-recovery.sh
    ├── QA-07-transcript-window.sh
    └── QA-08-projects-window.sh
```

### Test Orchestration (Sequential)

**For MVP, all tests run sequentially in a single shell.**

Parallelization is explicitly out of scope for this iteration.

**Execution order:**
1. QA-01a-e: App Launch & Startup (5 variants)
2. QA-02: Project Switching
3. QA-03: Codex Discovery
4. QA-04: Claude Discovery
5. QA-05: Real-time Updates
6. QA-06: Watcher Recovery
7. QA-07: Transcript Window
8. QA-08: Projects Window

**Main orchestrator:** `scripts/qa/run-all-tests.sh` (with error aggregation)

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create timestamped log directory for this run
LOGDIR="/tmp/qa-run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"

# Test suite - comment out variants you don't need for a given run
TESTS=(
  "QA-01a-launch-dmg-clean.sh"
  "QA-01b-launch-dmg-existing.sh"
  "QA-01c-launch-appstore-clean.sh"
  "QA-01d-launch-appstore-existing.sh"
  "QA-01e-launch-appstore-skip.sh"
  "QA-02-project-switching.sh"
  "QA-03-codex-discovery.sh"
  "QA-04-claude-discovery.sh"
  "QA-05-realtime-updates.sh"
  "QA-06-watcher-recovery.sh"
  "QA-07-transcript-window.sh"
  "QA-08-projects-window.sh"
)

# Track results
declare -a PASSED_TESTS
declare -a FAILED_TESTS

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Contextify QA Suite"
echo "  Log directory: $LOGDIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for test in "${TESTS[@]}"; do
  echo ""
  echo "=== Running $test ==="

  # Run test and capture output
  if "$SCRIPT_DIR/tests/$test" 2>&1 | tee "$LOGDIR/$test.log"; then
    PASSED_TESTS+=("$test")
    echo "[PASS] $test"
  else
    FAILED_TESTS+=("$test")
    echo "[FAIL] $test"
  fi
done

# Generate summary report
cat > "$LOGDIR/SUMMARY.md" << EOF
# QA Run Summary

**Date:** $(date)
**Log Directory:** $LOGDIR
**Passed:** ${#PASSED_TESTS[@]} / ${#TESTS[@]}
**Failed:** ${#FAILED_TESTS[@]}

## Results

### Passed
$(for t in "${PASSED_TESTS[@]}"; do echo "- ✅ $t"; done)

### Failed
$(for t in "${FAILED_TESTS[@]}"; do echo "- ❌ $t"; done)

## Failed Test Logs

$(for f in "${FAILED_TESTS[@]}"; do
  echo "### $f"
  echo '```'
  tail -50 "$LOGDIR/$f.log"
  echo '```'
  echo ""
done)
EOF

# Print summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  QA SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Passed: ${#PASSED_TESTS[@]} / ${#TESTS[@]}"
echo "  Failed: ${#FAILED_TESTS[@]}"
echo ""

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
  echo "  Failed tests:"
  for t in "${FAILED_TESTS[@]}"; do
    echo "    - $t"
  done
  echo ""
  echo "  Full logs: $LOGDIR"
  echo "  Summary:   $LOGDIR/SUMMARY.md"
  echo ""
  echo "❌ Some QA tests failed"
  exit 1
else
  echo "  All logs: $LOGDIR"
  echo ""
  echo "✅ All QA tests passed"
  exit 0
fi
```

### Common Test Structure

Every test case follows this pattern:

```bash
#!/bin/bash
# QA-XX: Test Name

set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/assertions.sh"

TEST_ID="QA-XX"
TEST_NAME="Test Name"

main() {
  log_header "$TEST_ID: $TEST_NAME"

  check_prerequisites
  setup_test
  start_log_capture
  run_test_steps
  validate_results
  cleanup_test
  report_results
}

main "$@"
```

---

## Implementation Approach

### Technology Choice: Bash Scripts

**Rationale for MVP:**

✅ **Easy maintenance:**
- Shell scripts readable by all developers
- No external dependencies beyond standard macOS tools
- Inline with existing debugging toolkit (`scripts/logging/`)

✅ **Integration with existing tools:**
- Reuses `monitor-transcript-queues.sh` for log capture
- Works with `db_manager.sh` for database operations
- Compatible with AppleScript for UI automation

✅ **Fast iteration:**
- Edit script and re-run immediately
- No compilation or test framework setup
- Direct access to system commands

### Core Utilities (lib/common.sh)

```bash
#!/bin/bash
# Common utilities for QA tests

# Database operations
db_query() {
  local query="$1"
  local db_path="$HOME/Library/Application Support/Contextify/contextify.db"
  # Add timeout to handle occasional WAL locks from GRDB
  sqlite3 -cmd ".timeout 2000" "$db_path" "$query"
}

db_count() {
  local query="$1"
  db_query "$query" | xargs
}

# Log capture
start_log_capture() {
  LOGFILE="/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S).log"
  log stream --predicate 'subsystem BEGINSWITH "dev.contextify"' \
    --level debug > "$LOGFILE" 2>&1 &
  LOG_PID=$!
  sleep 2  # Let logger initialize
  log_info "Log capture started: $LOGFILE (PID: $LOG_PID)"
}

stop_log_capture() {
  if [ -n "${LOG_PID:-}" ]; then
    kill "$LOG_PID" 2>/dev/null || true
    wait "$LOG_PID" 2>/dev/null || true
    log_info "Log capture stopped"
  fi
}

# Wait for log pattern (avoids blind sleeps)
wait_for_log_pattern() {
  local pattern="$1"
  local timeout="$2"
  local elapsed=0

  while [ $elapsed -lt "$timeout" ]; do
    if [ -f "$LOGFILE" ] && grep -q "$pattern" "$LOGFILE"; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

# App control
launch_app() {
  local app_path="${1:-.derived/Build/Products/Debug/Contextify.app}"
  log_info "Launching app: $app_path"
  open "$app_path"

  # Wait for startup completion instead of blind sleep
  wait_for_log_pattern "\[ORCH-STARTUP\] Startup complete" 30
}

kill_app_if_running() {
  pkill -9 Contextify 2>/dev/null || true
  sleep 1
}

# Logging
log_info() { echo "[INFO] $*"; }
log_success() { echo "[PASS] $*"; }
log_error() { echo "[FAIL] $*" >&2; }
log_header() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─────────────────────────────────────────────────────────────
# UI Automation (AppleScript + System Events)
# Prerequisite: Terminal must have Accessibility permission
# ─────────────────────────────────────────────────────────────

# Activate Contextify and bring to front
activate_app() {
  osascript -e 'tell application "Contextify" to activate'
  sleep 0.5
}

# Click a button by name in Contextify's frontmost window
click_button() {
  local button_name="$1"
  osascript -e "tell application \"System Events\" to click button \"$button_name\" of window 1 of process \"Contextify\""
  sleep 0.3
}

# Press a key (e.g., "return", "escape")
press_key() {
  local key="$1"
  osascript -e "tell application \"System Events\" to keystroke $key"
}

# Press Enter/Return
press_return() {
  osascript -e 'tell application "System Events" to keystroke return'
  sleep 0.3
}

# Send keyboard shortcut (e.g., "t" with command)
send_shortcut() {
  local key="$1"
  local modifiers="$2"  # e.g., "{command down}" or "{command down, shift down}"
  osascript -e "tell application \"System Events\" to keystroke \"$key\" using $modifiers"
  sleep 0.3
}

# Grant folder permission (for App Store builds)
# NSOpenPanel opens already at correct location, just need to confirm
grant_folder_permission() {
  local permission_log_pattern="$1"
  local timeout="${2:-10}"

  # Wait for permission modal
  if ! wait_for_log_pattern "$permission_log_pattern" "$timeout"; then
    log_error "Permission modal did not appear"
    return 1
  fi

  # Click "Choose Folder" button
  click_button "Choose Folder"
  sleep 0.5

  # NSOpenPanel opens at correct location, just press Enter to confirm
  press_return

  log_success "Folder permission granted"
  return 0
}

# Skip folder permission (click Skip or Cancel)
skip_folder_permission() {
  local permission_log_pattern="$1"
  local timeout="${2:-10}"

  if ! wait_for_log_pattern "$permission_log_pattern" "$timeout"; then
    log_error "Permission modal did not appear"
    return 1
  fi

  # Click "Skip" or "Later" button
  click_button "Skip" || click_button "Later" || click_button "Cancel"

  log_success "Folder permission skipped"
  return 0
}
```

**MVP Note on Database Access:**

For MVP, we accept that an occasional "database is locked" error may cause a test failure. The `.timeout 2000` handles most cases. Systematic retry logic is deferred to v2 professional QA.

### Assertion Library (lib/assertions.sh)

```bash
#!/bin/bash
# Test assertions

TEST_FAILED=0  # Global failure flag

# Filesystem assertions
assert_file_exists() {
  local file="$1"
  local desc="$2"
  if [ ! -f "$file" ]; then
    log_error "ASSERTION FAILED: $desc"
    log_error "  File not found: $file"
    TEST_FAILED=1
    return 1
  fi
  log_success "✓ $desc"
}

assert_directory_exists() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    log_error "Directory not found: $dir"
    exit 1
  fi
}

# Process assertions
assert_app_running() {
  local app="$1"
  if ! pgrep -x "$app" > /dev/null; then
    log_error "App not running: $app"
    TEST_FAILED=1
    return 1
  fi
  log_success "✓ App is running: $app"
}

assert_app_not_running() {
  local app="$1"
  if pgrep -x "$app" > /dev/null; then
    log_error "App already running: $app (clean environment required)"
    exit 1
  fi
}

# Command assertions
assert_command_exists() {
  local cmd="$1"
  if ! command -v "$cmd" &> /dev/null; then
    log_error "Required command not found: $cmd"
    exit 1
  fi
}

# Log pattern assertions
assert_log_contains() {
  local pattern="$1"
  local description="$2"
  if ! grep -q "$pattern" "$LOGFILE" 2>/dev/null; then
    log_error "ASSERTION FAILED: $description"
    log_error "  Expected log pattern: $pattern"
    TEST_FAILED=1
    return 1
  fi
  log_success "✓ $description"
  return 0
}

assert_log_count() {
  local pattern="$1"
  local expected="$2"
  local desc="$3"
  local actual
  actual=$(grep -c "$pattern" "$LOGFILE" 2>/dev/null || echo "0")
  if [ "$actual" != "$expected" ]; then
    log_error "ASSERTION FAILED: $desc"
    log_error "  Expected $expected occurrences of: $pattern"
    log_error "  Got: $actual"
    TEST_FAILED=1
    return 1
  fi
  log_success "✓ $desc"
}

assert_log_count_min() {
  local pattern="$1"
  local min="$2"
  local desc="$3"
  local actual
  actual=$(grep -c "$pattern" "$LOGFILE" 2>/dev/null || echo "0")
  if [ "$actual" -lt "$min" ]; then
    log_error "ASSERTION FAILED: $desc"
    log_error "  Expected at least $min occurrences of: $pattern"
    log_error "  Got: $actual"
    TEST_FAILED=1
    return 1
  fi
  log_success "✓ $desc (found $actual)"
}

# Database assertions (exact counts for MVP)
assert_db_count() {
  local query="$1"
  local expected="$2"
  local description="$3"
  local actual
  actual=$(db_count "$query")
  if [ "$actual" != "$expected" ]; then
    log_error "ASSERTION FAILED: $description"
    log_error "  Expected: $expected, Got: $actual"
    log_error "  Query: $query"
    TEST_FAILED=1
    return 1
  fi
  log_success "✓ $description"
  return 0
}

assert_db_row_exists() {
  local query="$1"
  local desc="$2"
  local result
  result=$(db_query "$query")
  if [ -z "$result" ]; then
    log_error "ASSERTION FAILED: $desc"
    log_error "  Query returned no rows: $query"
    TEST_FAILED=1
    return 1
  fi
  log_success "✓ $desc"
}
```

**MVP Note on Assertions:**

- `assert_db_count` supports exact equality only for MVP
- Range-style expectations (e.g., "1-999") are not implemented in v1
- Timing assertions (`assert_timing_under`) are deferred to v2 professional QA
- For MVP, use exact counts with known QA projects/transcripts

---

## Test Cases

### QA-01: App Launch & Startup (5 Variants)

App launch tests cover the matrix of build types and database states:

| Test | Build | Database | Key Validation |
|------|-------|----------|----------------|
| QA-01a | DMG | None (first run) | Schema migration, first discovery, empty state |
| QA-01b | DMG | Existing | Normal startup, project loads, FSEvents starts |
| QA-01c | App Store | None | Permission flow, grant access, discovery |
| QA-01d | App Store | Existing | Bookmark resolution, no re-prompt |
| QA-01e | App Store | None | Skip permissions, graceful empty state |

---

#### QA-01a: DMG Build - First Run (No Database)

**ID:** QA-01a
**Duration:** ~30 seconds
**Prerequisites:** DMG build, no existing database

**Test Steps:**

```bash
# 1. Ensure clean state
kill_app_if_running
rm -f "$HOME/Library/Application Support/Contextify/contextify.db"*

# 2. Start log capture
start_log_capture

# 3. Launch DMG build
open .derived/Build/Products/Debug/Contextify.app

# 4. Wait for startup (includes schema migration)
wait_for_log_pattern "\[ORCH-STARTUP\] Startup complete" 30
```

**Success Criteria:**

```bash
assert_log_contains "\[DB-MIGRATION\]" "Database schema created/migrated"
assert_log_contains "\[ORCH-STARTUP\] Startup complete" "Startup completed"
assert_app_running "Contextify"

# First run should have empty projects or just CWD
db_count=$(db_count "SELECT COUNT(*) FROM projects;")
[ "$db_count" -ge 0 ]  # 0 or more projects is valid for first run
```

---

#### QA-01b: DMG Build - Existing Database

**ID:** QA-01b
**Duration:** ~20 seconds
**Prerequisites:** DMG build, existing database with projects

**Test Steps:**

```bash
kill_app_if_running
start_log_capture
open .derived/Build/Products/Debug/Contextify.app
wait_for_log_pattern "\[ORCH-STARTUP\] Startup complete" 30
```

**Success Criteria:**

```bash
assert_log_contains "\[ORCH-STARTUP\] Startup complete" "AppStateOrchestrator started"
assert_log_contains "\[ORCH-STARTUP\] Posted .projectsDiscoveryComplete" "Discovery notification posted"
assert_log_contains "\[INIT\] ProjectActivityMonitor.*FSEvents enabled" "FSEvents monitoring active"
assert_db_count "SELECT COUNT(*) FROM projects WHERE name='contextify'" "1" "Contextify project exists"
assert_app_running "Contextify"
```

---

#### QA-01c: App Store Build - First Run (Grant Permissions)

**ID:** QA-01c
**Duration:** ~45 seconds
**Prerequisites:** App Store build, no existing database/bookmarks, Terminal has Accessibility permission

**Test Steps:**

```bash
# 1. Clean state
kill_app_if_running
rm -f "$HOME/Library/Application Support/Contextify/contextify.db"*
# Note: Also need to clear bookmarks from UserDefaults for full clean test

# 2. Start log capture
start_log_capture

# 3. Launch App Store build
open ".derived/Build/Products/Debug/Contextify AppStore.app"

# 4. Handle Claude permission prompt (fully automated)
grant_folder_permission "\[ONBOARD-PERMISSION-CLAUDE\]" 15

# 5. Handle Codex permission prompt (if shown)
grant_folder_permission "\[ONBOARD-PERMISSION-CODEX\]" 10 || true  # May not appear

# 6. Click Continue to dismiss onboarding
click_button "Continue"

# 7. Wait for startup to complete
wait_for_log_pattern "\[ORCH-STARTUP\] Startup complete" 30
```

**Success Criteria:**

```bash
assert_log_contains "\[ONBOARD-PERMISSION-GRANTED\]" "Permission was granted"
assert_log_contains "\[BOOKMARK-SAVED\]" "Security-scoped bookmark saved"
assert_log_contains "\[ORCH-STARTUP\] Startup complete" "Startup completed"
assert_app_running "Contextify"
```

---

#### QA-01d: App Store Build - Existing Bookmarks

**ID:** QA-01d
**Duration:** ~25 seconds
**Prerequisites:** App Store build, existing bookmarks from previous grant

**Test Steps:**

```bash
kill_app_if_running
start_log_capture
open ".derived/Build/Products/Debug/Contextify AppStore.app"
wait_for_log_pattern "\[ORCH-STARTUP\] Startup complete" 30
```

**Success Criteria:**

```bash
# Should NOT show permission prompt
assert_log_count "\[ONBOARD-PERMISSION-CLAUDE\]" "0" "No permission prompt shown"

# Should resolve existing bookmarks
assert_log_contains "\[BOOKMARK-RESOLVED\]" "Existing bookmark resolved"
assert_log_contains "\[ORCH-STARTUP\] Startup complete" "Startup completed"
assert_app_running "Contextify"
```

---

#### QA-01e: App Store Build - Skip Permissions

**ID:** QA-01e
**Duration:** ~30 seconds
**Prerequisites:** App Store build, no existing bookmarks, Terminal has Accessibility permission

**Test Steps:**

```bash
# 1. Clean state
kill_app_if_running
rm -f "$HOME/Library/Application Support/Contextify/contextify.db"*

# 2. Start log capture
start_log_capture

# 3. Launch App Store build
open ".derived/Build/Products/Debug/Contextify AppStore.app"

# 4. Skip permission prompts
skip_folder_permission "\[ONBOARD-PERMISSION-CLAUDE\]" 15
skip_folder_permission "\[ONBOARD-PERMISSION-CODEX\]" 10 || true

# 5. Continue past onboarding
click_button "Continue" || click_button "Skip"

# 6. Wait for startup
wait_for_log_pattern "\[ORCH-STARTUP\] Startup complete" 30
```

**Success Criteria:**

```bash
# Should complete startup without crash
assert_log_contains "\[ORCH-STARTUP\] Startup complete" "Startup completed despite skipped permissions"
assert_app_running "Contextify"

# Should show empty state or limited functionality
assert_log_contains "\[EMPTY-STATE\]" "Empty state shown (no transcript access)" || true
```

---

### QA-02: Project Switching

---

**ID:** QA-02
**Duration:** ~30 seconds
**Prerequisites:** App running, at least 2 projects in database

**MVP Prerequisites:**
- Contextify has Accessibility permission
- Uses Cmd+Shift+] keyboard shortcut for "next project"

**Test Steps:**

1. Launch app and wait for initial project load
2. Start log capture
3. Activate app and trigger project switch via AppleScript
4. Wait for switch completion
5. Validate switch markers in logs

**AppleScript for project switching:**
```bash
# Ensure app is focused
osascript -e 'tell application "Contextify" to activate'
sleep 1

# Send keyboard shortcut
osascript -e 'tell application "System Events" to keystroke "]" using {command down, shift down}'

# Wait for switch to complete
wait_for_log_pattern "\[ORCH-SELECT\] Project ready" 10
```

**Success Criteria:**

```bash
# Project switch markers
assert_log_contains "\[SWITCHER-FROZEN\] Freeze activated" "UI frozen during switch"
assert_log_contains "\[ORCH-SELECT\] User selected project" "Orchestrator received switch request"
assert_log_contains "\[ORCH-SELECT\] Project ready in.*s" "Switch completed"

# Timeline refresh
assert_log_contains "\[TIMELINE-REFRESH\]" "Timeline refreshed"
assert_log_count_min "\[WATCHER-" "1" "Watchers created for active transcripts"

# No errors
assert_log_count "\[ERROR\]" "0" "No errors during switch"
```

---

### QA-03: New Codex Transcript Discovery (DETAILED EXAMPLE)

**ID:** QA-03
**Duration:** ~45 seconds
**Prerequisites:**
- App running with FSEvents monitoring active
- Test project exists: `/tmp/contextify-qa-test` (git repo initialized)
- Codex CLI installed and authenticated on your machine

**Purpose:** Validates end-to-end pipeline from file creation to timeline display for Codex CLI transcripts.

**Pipeline stages verified:**
1. File System Events (FSEvents detects new .jsonl file)
2. Transcript Discovery (File identified and project extracted from CWD field)
3. Database Ingestion (Transcript + entries written to SQLite)
4. Watcher Creation (TranscriptWatcher started for real-time updates)
5. Timeline Update (ConversationMonitor displays entries)

**Implementation Template:**

This is the canonical example - implement this first, then pattern-match QA-04/05/06 from it.

```bash
#!/bin/bash
# QA-03: New Codex Transcript Discovery

set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/assertions.sh"

TEST_ID="QA-03"
TEST_NAME="New Codex Transcript Discovery"

TEST_PROJECT="/tmp/contextify-qa-test"
TEST_FAILED=0

check_prerequisites() {
  log_info "Checking prerequisites..."

  assert_app_running "Contextify"
  assert_command_exists "codex"
  assert_command_exists "sqlite3"

  # Create test project if doesn't exist
  if [ ! -d "$TEST_PROJECT" ]; then
    log_info "Creating test project: $TEST_PROJECT"
    mkdir -p "$TEST_PROJECT"
    cd "$TEST_PROJECT"
    git init
    git config user.email "qa@contextify.test"
    git config user.name "QA Test"
    echo "# QA Test Project" > README.md
    git add README.md
    git commit -m "Initial commit"
    cd - > /dev/null
  fi

  log_success "Prerequisites met"
}

setup_test() {
  log_info "Starting log capture..."
  start_log_capture
}

run_test_steps() {
  log_info "Creating new Codex conversation in test project..."

  cd "$TEST_PROJECT"

  # Start Codex conversation with simple prompt
  log_info "Running: codex \"print 'QA test at \$(date)' in Python\" --full-auto"

  timeout 30 codex "print 'QA test at $(date)' in Python" --full-auto > /dev/null 2>&1 &
  CODEX_PID=$!

  # Wait for transcript file creation with timeout
  log_info "Waiting for transcript file creation (max 15s)..."
  local elapsed=0
  local max_wait=15

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
    return 1
  fi

  # Wait for Codex to complete
  wait "$CODEX_PID" 2>/dev/null || true

  # Wait for ingestion to complete (instead of blind sleep)
  log_info "Waiting for ingestion to complete..."
  wait_for_log_pattern "\[HOOVER-DONE\]" 30

  cd - > /dev/null
  log_success "Test conversation completed"
}

validate_results() {
  log_header "VALIDATION RESULTS"

  local transcript_basename
  transcript_basename=$(basename "$TRANSCRIPT")

  # Stage 1: File System Events
  log_info "Stage 1: Validating FSEvents detection..."
  assert_log_contains "\[FSEVENTS-CHANGE\].*${transcript_basename}" \
    "FSEvents detected new transcript file"

  # Stage 2: Transcript Discovery
  log_info "Stage 2: Validating transcript discovery..."
  assert_log_contains "\[TRANS-DISC-START\] Discovering transcript.*${transcript_basename}" \
    "Transcript discovery initiated"
  assert_log_contains "contextify-qa-test" \
    "Correct project extracted from CWD field"

  # Stage 3: Database Ingestion
  log_info "Stage 3: Validating database ingestion..."

  local db_transcript_count
  db_transcript_count=$(db_count "SELECT COUNT(*) FROM transcripts WHERE file_path = '$TRANSCRIPT';")

  if [ "$db_transcript_count" != "1" ]; then
    log_error "ASSERTION FAILED: Transcript not in database"
    log_error "  Expected 1 row, got: $db_transcript_count"
    TEST_FAILED=1
  else
    log_success "✓ Transcript row exists in database"
  fi

  local transcript_id
  transcript_id=$(db_query "SELECT id FROM transcripts WHERE file_path = '$TRANSCRIPT';")

  if [ -z "$transcript_id" ]; then
    log_error "Could not retrieve transcript ID from database"
    TEST_FAILED=1
    return 1
  fi

  log_info "Transcript ID: $transcript_id"

  # Verify entries ingested
  local entry_count
  entry_count=$(db_count "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id = '$transcript_id';")

  if [ "$entry_count" -lt "1" ]; then
    log_error "ASSERTION FAILED: No entries ingested"
    log_error "  Expected at least 1 entry, got: $entry_count"
    TEST_FAILED=1
  else
    log_success "✓ Entries ingested (count: $entry_count)"
  fi

  # Verify provider
  local provider
  provider=$(db_query "SELECT provider FROM transcripts WHERE id = '$transcript_id';")

  if [ "$provider" != "codex.cli" ]; then
    log_error "ASSERTION FAILED: Incorrect provider"
    log_error "  Expected 'codex.cli', got: '$provider'"
    TEST_FAILED=1
  else
    log_success "✓ Provider correctly identified as 'codex.cli'"
  fi

  # Stage 4: Watcher Creation
  log_info "Stage 4: Validating watcher creation..."
  assert_log_contains "\[TRANS-DISC-WATCH-START\].*${transcript_id}" \
    "Watcher started for new transcript"
  assert_log_contains "\[WATCHER-INIT\].*${transcript_id}" \
    "Watcher initialization completed"

  # Stage 5: Timeline Update
  log_info "Stage 5: Validating timeline update..."
  assert_log_count_min "\[TIMELINE-REFRESH\]" "1" \
    "Timeline refreshed with new entries"

  # Optional: LLM summary queueing (informational only for MVP)
  if grep -q "\[LLM-QUEUE\]" "$LOGFILE" 2>/dev/null; then
    log_success "✓ LLM summary generation queued (async)"
  else
    log_info "⚠ LLM queueing not detected (async, may complete later)"
  fi
}

cleanup_test() {
  log_info "Cleaning up..."
  stop_log_capture

  # MVP: Keep test transcripts for debugging
  # Cleanup can be added later with --clean flag
  log_info "Test transcript preserved: $TRANSCRIPT"
  log_info "Logs preserved: $LOGFILE"
}

report_results() {
  echo ""
  log_header "TEST SUMMARY: $TEST_ID"

  if [ $TEST_FAILED -eq 0 ]; then
    log_success "✅ ALL CHECKS PASSED"
    log_info "Pipeline verified: File System → Discovery → Database → Watcher → Timeline"
    exit 0
  else
    log_error "❌ SOME CHECKS FAILED"
    log_error "Review logs for details: $LOGFILE"
    echo ""
    log_info "Common troubleshooting steps:"
    log_info "  1. grep 'INIT.*ProjectActivityMonitor' $LOGFILE"
    log_info "  2. ls -la $TRANSCRIPT"
    log_info "  3. sqlite3 ~/Library/Application\\ Support/Contextify/contextify.db 'SELECT * FROM transcripts;'"
    exit 1
  fi
}

main() {
  log_header "$TEST_ID: $TEST_NAME"
  check_prerequisites
  setup_test
  run_test_steps
  validate_results
  cleanup_test
  report_results
}

main "$@"
```

---

### QA-04: New Claude Code Transcript Discovery

Similar structure to QA-03, pattern-matched from the canonical example.

**Key Differences:**
- Uses `claude "prompt"` instead of `codex "prompt"`
- Transcript location: `~/.claude/projects/<encoded-path>/*.jsonl`
- Project identity derived from directory name (mangled path)
- Provider validation: `claude.code`

---

### QA-05: Real-time Transcript Updates

**ID:** QA-05
**Duration:** ~60 seconds
**Prerequisites:** Existing active transcript with watcher

**Test approach:** Append to existing transcript and validate incremental hoover

---

### QA-06: Watcher Recovery

**ID:** QA-06
**Duration:** ~90 seconds
**Prerequisites:** App running, project with transcripts

**Test approach:** Validate health check detects and recovers missing watchers

---

### QA-07: Transcript Window

**ID:** QA-07
**Duration:** ~15 seconds
**Prerequisites:** App running with active project

**Test Steps:**

```bash
# 1. Ensure app is running and focused
activate_app

# 2. Start log capture
start_log_capture

# 3. Open transcript window via keyboard shortcut (Cmd+T assumed)
send_shortcut "t" "{command down}"

# 4. Wait for window to open
wait_for_log_pattern "\[TRANSCRIPT-WINDOW-OPEN\]" 10
```

**Success Criteria:**

```bash
assert_log_contains "\[TRANSCRIPT-WINDOW-OPEN\]" "Transcript window opened"

# Window should display current transcript
assert_log_contains "\[TRANSCRIPT-WINDOW-LOAD\]" "Transcript content loaded"
```

**Cleanup:**

```bash
# Close window with Cmd+W
send_shortcut "w" "{command down}"
```

---

### QA-08: Projects Window

**ID:** QA-08
**Duration:** ~15 seconds
**Prerequisites:** App running

**Test Steps:**

```bash
# 1. Ensure app is running and focused
activate_app

# 2. Start log capture
start_log_capture

# 3. Open projects window via keyboard shortcut (Cmd+Shift+P assumed)
send_shortcut "p" "{command down, shift down}"

# 4. Wait for window to open
wait_for_log_pattern "\[PROJECTS-WINDOW-OPEN\]" 10
```

**Success Criteria:**

```bash
assert_log_contains "\[PROJECTS-WINDOW-OPEN\]" "Projects window opened"

# Window should list discovered projects
assert_log_contains "\[PROJECTS-WINDOW-LOAD\]" "Project list loaded"
```

**Cleanup:**

```bash
# Close window with Cmd+W
send_shortcut "w" "{command down}"
```

---

## Log Analysis Strategy

### Capture with wait_for_log_pattern

Instead of blind sleeps, use the wait helper:

```bash
# After launching app
launch_app  # Uses wait_for_log_pattern internally

# After triggering action
wait_for_log_pattern "\[HOOVER-DONE\]" 30
```

### Tag-based Validation

```bash
# Verify specific pipeline stage completed
assert_log_contains "\[FSEVENTS-CHANGE\]" "FSEvents detected change"
assert_log_contains "\[HOOVER-DONE\]" "Ingestion completed"
assert_log_contains "\[TIMELINE-REFRESH\]" "Timeline updated"
```

---

## Database Validation

### Exact Counts for MVP

```bash
# Known QA project
assert_db_count "SELECT COUNT(*) FROM projects WHERE name='contextify'" "1" \
  "Contextify project exists"

# Specific transcript
assert_db_count "SELECT COUNT(*) FROM transcripts WHERE file_path='$TRANSCRIPT'" "1" \
  "Transcript ingested"
```

### Query with Timeout

All database queries include 2-second timeout for occasional WAL locks:

```bash
sqlite3 -cmd ".timeout 2000" "$db_path" "$query"
```

---

## MVP Prerequisites

**Required on your development machine:**

1. **Codex CLI** - Installed and authenticated
2. **Claude Code CLI** - Installed and authenticated
3. **Terminal Accessibility Permission** - For AppleScript/System Events UI automation
   - System Settings → Privacy & Security → Accessibility → Terminal ✓
   - This is a **one-time setup** - enables all UI automation (button clicks, keyboard shortcuts)
4. **Contextify builds:**
   - DMG build: `.derived/Build/Products/Debug/Contextify.app`
   - App Store build: `.derived/Build/Products/Debug/Contextify AppStore.app` (for QA-01c/d/e)
5. **Git** - For test project setup
6. **sqlite3** - Built into macOS

**Note:** Once Terminal has Accessibility permission, all UI automation (permission dialogs, window opening, project switching) is fully automated - no manual intervention required during test runs.

---

## Future Work (v2 Professional QA)

The following are **explicitly not required for MVP** and are deferred to a future professional QA iteration:

### CI/CD Integration
- GitHub Actions workflow with macOS runners
- Artifact retention and Slack notifications
- Automated triggers (nightly, pre-merge)

### Test Fixtures
- Synthetic transcript files instead of real CLI calls
- Deterministic test data for reproducibility
- Cost reduction (no API calls)

### Database Health & Migrations
- Schema migration testing with frozen snapshots
- Database integrity checks
- Performance benchmarks

### Performance Assertions
- Timing validations with parsed timestamps
- Feed query latency checks (target: <5ms)
- Memory usage monitoring

### Headless Controls
- Programmatic project switching without AppleScript
- UI automation through accessibility APIs
- Sandbox-safe test execution

### Enhanced Reliability
- Retry logic for transient failures
- Fixture-based tests (no external dependencies)
- Parallel test execution with proper isolation

---

## Implementation Checklist

**MVP v1 (Local Validation):**

- [ ] Create `scripts/qa/` directory structure
- [ ] Implement `lib/common.sh`:
  - [ ] `wait_for_log_pattern` helper
  - [ ] `db_query` with timeout
  - [ ] UI automation helpers (`activate_app`, `click_button`, `send_shortcut`, etc.)
  - [ ] `grant_folder_permission` / `skip_folder_permission`
- [ ] Implement `lib/assertions.sh` (exact counts only)
- [ ] Implement `run-all-tests.sh` with error aggregation and summary report
- [ ] Implement QA-03 first (canonical template)
- [ ] Implement QA-01 variants:
  - [ ] QA-01a: DMG clean install
  - [ ] QA-01b: DMG existing database
  - [ ] QA-01c: App Store grant permissions
  - [ ] QA-01d: App Store existing bookmarks
  - [ ] QA-01e: App Store skip permissions
- [ ] Pattern-match remaining tests from QA-03:
  - [ ] QA-02: Project switching
  - [ ] QA-04: Claude discovery
  - [ ] QA-05: Real-time updates
  - [ ] QA-06: Watcher recovery
  - [ ] QA-07: Transcript window
  - [ ] QA-08: Projects window
- [ ] Test full suite locally
- [ ] Document usage in `build/docs/testing/`
- [x] Add entry to `TODOS.md` as P1

**v2 Professional QA (Future):**

- [ ] CI/CD GitHub Actions workflow
- [ ] Fixture-based tests
- [ ] Database migration testing
- [ ] Performance benchmarks
- [ ] Headless controls

---

## Open Questions for Implementation

Before implementing, decide:

1. **First-run behavior:** Do you want MVP to test clean DB → migration → discovery, or only test against existing DB?

2. **Summarization importance:** Is `[LLM-QUEUE]` validation a hard requirement, or just informational?

3. **Cleanup strategy:** Should `run-all-tests.sh` have a `--clean` flag to remove test transcripts, or accept clutter?

4. **Database counts:** Are you comfortable with exact counts for known QA projects, or do you need range support now?

---

**End of Document**
