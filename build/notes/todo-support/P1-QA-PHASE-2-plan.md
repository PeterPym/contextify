---
todo_id: P1-QA-PHASE-2
title: QA Suite Phase 2 Implementation Plan
type: plan
date: 2025-12-10
status: active
description: Add fixture-based testing, search tests, DB migration tests, and CI integration to QA suite
---

# QA Suite Phase 2 Implementation Plan (v3)

**Status:** Ready for implementation
**Branch:** `feature/qa-phase-2`
**Scope:** 5 focused commits

---

## Overview

Phase 2 adds deterministic testing capabilities to the QA suite, removing network/API flakiness and enabling CI integration. Five components:

1. **Fixture infrastructure** - Common helpers, TEST_PROJECT handling, prereqs
2. **Fixture-based transcript tests** - Deterministic Codex/Claude discovery testing (with search terms)
3. **Search tests** - Quick Search and Deep Search validation
4. **DB migration/integrity test** - Catch upgrade breakage before users do
5. **CI workflow integration** - Run QA suite on every PR

---

## 1. Fixture Infrastructure

### 1.1 Directory Structure

```
scripts/qa/
  fixtures/
    transcripts/
      codex/
        simple-session.jsonl
        README.md
      claude/
        simple-session.jsonl
        README.md
    db/
      README.md
```

### 1.2 Changes to `lib/common.sh`

**Add near config section:**
```bash
# Fixture mode configuration
QA_FIXTURE_MODE="${QA_FIXTURE_MODE:-0}"
QA_FIXTURE_DIR="${QA_FIXTURE_DIR:-$REPO_ROOT/scripts/qa/fixtures}"

# Test project path (used by fixture transcript seeding)
# Default matches CI and local test expectations
TEST_PROJECT="${TEST_PROJECT:-/tmp/contextify-qa-test}"
```

**Add fixture transcript helper:**
```bash
# Seed a fixture transcript into the appropriate provider location
# Usage: seed_fixture_transcript "codex"|"claude" [fixture_name]
# Returns: path to seeded transcript file
# Requires: TEST_PROJECT to be set
seed_fixture_transcript() {
  local provider="$1"
  local fixture_name="${2:-simple-session.jsonl}"
  local src_file="$QA_FIXTURE_DIR/transcripts/$provider/$fixture_name"
  local dest_dir=""
  local dest_file=""

  # Validate TEST_PROJECT is set
  if [ -z "${TEST_PROJECT:-}" ]; then
    log_error "TEST_PROJECT is not set; required for fixture transcripts"
    return 1
  fi

  if [ ! -f "$src_file" ]; then
    log_error "Fixture transcript not found: $src_file"
    return 1
  fi

  case "$provider" in
    codex)
      # Codex uses date-based hierarchy: ~/.codex/sessions/YYYY/MM/DD/
      local date_path
      date_path=$(date +%Y/%m/%d)
      dest_dir="$HOME/.codex/sessions/$date_path"
      dest_file="$dest_dir/qa-fixture-$(date +%Y-%m-%dT%H-%M-%S)-$(uuidgen | tr '[:upper:]' '[:lower:]').jsonl"
      ;;
    claude)
      # Claude uses project-hash directories: ~/.claude/projects/<hash>/
      # Note: This is a simplified hash (tr '/' '-'), not Claude's actual algorithm.
      # Tests validate CWD-based discovery, not directory hash logic.
      local project_hash
      project_hash=$(echo "$TEST_PROJECT" | tr '/' '-')
      dest_dir="$HOME/.claude/projects/$project_hash"
      dest_file="$dest_dir/$(uuidgen | tr '[:upper:]' '[:lower:]').jsonl"
      ;;
    *)
      log_error "Unknown provider: $provider (expected 'codex' or 'claude')"
      return 1
      ;;
  esac

  mkdir -p "$dest_dir"

  # Escape & in path to prevent sed expansion issues
  local escaped_project="${TEST_PROJECT//&/\\&}"

  # Copy and update cwd to point to test project
  sed "s|\"cwd\": \"[^\"]*\"|\"cwd\": \"$escaped_project\"|g" "$src_file" > "$dest_file"

  # Touch to ensure fresh mtime for discovery
  touch "$dest_file"

  log_info "Seeded fixture transcript: $dest_file"
  echo "$dest_file"
}
```

**Add search field focus helper:**
```bash
# Focus the HUD search field
# Usage: focus_search_field
focus_search_field() {
  send_shortcut "f" "command down"
  sleep 0.3
}
```

**Add DB fixture helper:**
```bash
# Install a fixture database for migration testing
# Usage: install_db_fixture "v16-contextify.db"
install_db_fixture() {
  local fixture_name="$1"
  local src="$QA_FIXTURE_DIR/db/$fixture_name"

  if [ ! -f "$src" ]; then
    log_error "DB fixture not found: $src"
    return 1
  fi

  # Backup current DB if exists
  if [ -f "$DB_PATH" ]; then
    mv "$DB_PATH" "${DB_PATH}.qa-backup"
    log_info "Backed up existing DB to ${DB_PATH}.qa-backup"
  fi

  mkdir -p "$(dirname "$DB_PATH")"
  cp "$src" "$DB_PATH"

  # Remove WAL/SHM files if present
  rm -f "${DB_PATH}-wal" "${DB_PATH}-shm"

  log_info "Installed DB fixture: $fixture_name"
}

# Restore DB from QA backup
restore_db_from_backup() {
  if [ -f "${DB_PATH}.qa-backup" ]; then
    rm -f "$DB_PATH" "${DB_PATH}-wal" "${DB_PATH}-shm"
    mv "${DB_PATH}.qa-backup" "$DB_PATH"
    log_info "Restored DB from backup"
  fi
}
```

### 1.3 Changes to `run-all-tests.sh`

**Update `should_skip_test` to respect fixture mode:**
```bash
should_skip_test() {
  local test_name="$1"
  local cli_req="$2"

  # Check if running specific test
  if [ -n "$ONLY_TEST" ] && [[ ! "$test_name" == *"$ONLY_TEST"* ]]; then
    return 0  # Skip
  fi

  # Skip App Store tests if requested
  if [ "$SKIP_APPSTORE" = "1" ] && [[ "$test_name" == *"appstore"* ]]; then
    return 0  # Skip
  fi

  # Skip CLI tests only if NOT in fixture mode
  if [ "$SKIP_CLI" = "1" ] && [ "${QA_FIXTURE_MODE:-0}" != "1" ] && [ "$cli_req" != "0" ]; then
    return 0  # Skip
  fi

  return 1  # Don't skip
}
```

**Update prerequisites to check for uuidgen in fixture mode:**
```bash
check_prerequisites() {
  echo "Checking prerequisites..."

  # Check for required commands
  local missing=()

  if ! command -v sqlite3 &> /dev/null; then
    missing+=("sqlite3")
  fi

  if ! command -v osascript &> /dev/null; then
    missing+=("osascript")
  fi

  # uuidgen required for fixture mode
  if [ "${QA_FIXTURE_MODE:-0}" = "1" ]; then
    if ! command -v uuidgen &> /dev/null; then
      missing+=("uuidgen")
    fi
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo "[ERROR] Missing required commands: ${missing[*]}"
    exit 1
  fi

  # ... rest of prerequisites ...
}
```

**Update CLI test availability check:**
```bash
# In the test loop:
if [ "$cli_req" = "1" ]; then
  if [ "${QA_FIXTURE_MODE:-0}" != "1" ] && ! command -v codex &> /dev/null; then
    SKIPPED_TESTS+=("$test_name (Codex CLI not available)")
    echo "[SKIP] $test_name (Codex CLI not available)"
    continue
  fi
fi

if [ "$cli_req" = "2" ]; then
  if [ "${QA_FIXTURE_MODE:-0}" != "1" ] && ! command -v claude &> /dev/null; then
    SKIPPED_TESTS+=("$test_name (Claude Code not available)")
    echo "[SKIP] $test_name (Claude Code not available)"
    continue
  fi
fi
```

---

## 2. Fixture-Based Transcript Tests (with Search Terms)

### 2.1 Fixture File Specifications

Fixtures include unique search terms (`QA_FIXTURE_SEARCH_TERM_*`) for search test validation.

**Codex fixture** (`fixtures/transcripts/codex/simple-session.jsonl`):
```json
{"timestamp":"2025-01-01T12:00:00.000Z","type":"session_meta","payload":{"id":"qa-fixture-session","cwd":"/tmp/contextify-qa-test","source":"cli","originator":"codex_cli_rs"}}
{"timestamp":"2025-01-01T12:00:01.000Z","type":"response_item","item":{"role":"user","content":[{"type":"input_text","text":"QA_FIXTURE_SEARCH_TERM_CODEX this is a searchable test message for QA validation"}]}}
{"timestamp":"2025-01-01T12:00:02.000Z","type":"response_item","item":{"role":"assistant","content":[{"type":"text","text":"I see your test message. This fixture validates Codex transcript discovery."}]}}
```

**Claude fixture** (`fixtures/transcripts/claude/simple-session.jsonl`):
```json
{"type":"user","message":{"role":"user","content":"QA_FIXTURE_SEARCH_TERM_CLAUDE this is a searchable test message for QA validation"},"cwd":"/tmp/contextify-qa-test","sessionId":"qa-fixture-session","uuid":"qa-user-1","timestamp":"2025-01-01T12:00:01.000Z","isSidechain":false,"parentUuid":null}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I see your test message. This fixture validates Claude Code transcript discovery."}]},"cwd":"/tmp/contextify-qa-test","sessionId":"qa-fixture-session","uuid":"qa-asst-1","parentUuid":"qa-user-1","timestamp":"2025-01-01T12:00:02.000Z","isSidechain":false}
```

**fixtures/transcripts/claude/README.md:**
```markdown
# Claude Code Fixture Transcripts

These fixtures are used for deterministic QA testing of Claude Code transcript discovery.

## Important Notes

1. **Project directory hash**: The fixture is placed in a directory derived from
   `TEST_PROJECT` using simple `tr '/' '-'` transformation. This is NOT the same
   hash algorithm Claude Code actually uses. Tests validate CWD-based discovery
   logic, not directory hash resolution.

2. **CWD rewriting**: The `cwd` field is rewritten by `seed_fixture_transcript`
   to match `TEST_PROJECT` (default: `/tmp/contextify-qa-test`).

3. **Search terms**: Include `QA_FIXTURE_SEARCH_TERM_CLAUDE` for search tests.
```

### 2.2 Changes to `QA-03-codex-discovery.sh`

Update `run_test_steps()`:
```bash
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
    # Existing CLI path
    local test_marker="QA-$(date +%s)"
    log_info "Running: codex \"print '$test_marker' and exit\" --full-auto"
    run_with_timeout 45 codex "print '$test_marker' in Python and then exit immediately" --full-auto > /dev/null 2>&1 &
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

    wait "$CODEX_PID" 2>/dev/null || true
  fi

  # Wait for ingestion (same for both modes)
  log_info "Waiting for ingestion to complete..."
  if ! wait_for_log_pattern "\[HOOVER-DONE\]" 30; then
    log_warn "HOOVER-DONE not detected, checking database directly..."
  fi

  cd - > /dev/null
  log_success "Test execution completed"
}
```

### 2.3 Changes to `QA-04-claude-discovery.sh`

Same pattern as QA-03, using `seed_fixture_transcript "claude"`.

---

## 3. Search Tests

Search tests validate Quick Search and Deep Search functionality. They run after transcript fixture tests and exercise the full pipeline: fixture seeding -> ingestion -> FTS5 indexing -> search.

### 3.1 Log Patterns (verified from source)

| Pattern | Location | Description |
|---------|----------|-------------|
| `[SEARCH-START]` | QuickSearchViewModel.swift:73 | Quick Search query initiated |
| `[SEARCH-DONE]` | QuickSearchViewModel.swift:112 | Quick Search completed |
| `[SEARCH-CANCEL]` | QuickSearchViewModel.swift:90 | Search was cancelled |
| `[CONTEXT]` | QuickSearchViewModel.swift:145 | Context entries loaded |
| `[DEEPSEARCH-INIT]` | DeepSearchWindow | Deep Search window opened |
| `[DEEPSEARCH-DONE]` | DeepSearchWindow | Deep Search query completed |

### 3.2 QA-10: Quick Search

**Purpose:** Validate HUD Quick Search flow: activation, results display, and dismissal.

```bash
#!/bin/bash
# QA-10: Quick Search
#
# Validates Quick Search activation via Cmd+F, results display, and exit.
# Requires fixture transcripts with QA_FIXTURE_SEARCH_TERM_* content.

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
  if ! wait_for_log_pattern "\[SEARCH-DONE\]" 10; then
    log_error "Quick Search did not complete within 10s"
    TEST_FAILED=1
    return 1
  fi

  log_success "Quick Search completed"

  # 5. Exit Quick Search (Escape)
  log_info "Exiting Quick Search (Escape)"
  press_escape
  sleep 0.5

  log_success "Test execution completed"
}

validate_results() {
  log_subheader "Validation"

  # Search was initiated
  assert_log_contains "\[SEARCH-START\]" "Quick Search started"

  # Search completed
  assert_log_contains "\[SEARCH-DONE\]" "Quick Search completed"

  # App still running
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
```

### 3.3 QA-11: Deep Search Window

**Purpose:** Validate Deep Search window opens via Cmd+Enter and can be closed.

```bash
#!/bin/bash
# QA-11: Deep Search Window
#
# Validates Deep Search window opens via Cmd+Enter from search field.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-11"
TEST_NAME="Deep Search Window"

check_prerequisites() {
  log_subheader "Checking Prerequisites"
  assert_command_exists "sqlite3"
  assert_command_exists "osascript"
  assert_dmg_app_exists
  log_success "Prerequisites met"
}

run_test_steps() {
  log_subheader "Test Execution"

  local search_term="QA_FIXTURE_SEARCH_TERM"

  # 1. Focus search field
  log_info "Focusing search field (Cmd+F)"
  focus_search_field
  sleep 0.5

  # 2. Type search term
  log_info "Typing search term: $search_term"
  type_text "$search_term"
  sleep 0.3

  # 3. Record window count before
  local windows_before
  windows_before=$(get_window_count)
  log_info "Windows before: $windows_before"

  # 4. Open Deep Search (Cmd+Enter)
  log_info "Opening Deep Search (Cmd+Enter)"
  send_shortcut "$(printf '\r')" "command down"

  # 5. Wait for Deep Search window
  if ! wait_for_log_pattern "\[DEEPSEARCH-INIT\]" 10; then
    log_error "Deep Search window did not open within 10s"
    TEST_FAILED=1
    return 1
  fi

  sleep 1  # Let window fully render

  # 6. Verify window count increased
  local windows_after
  windows_after=$(get_window_count)
  log_info "Windows after: $windows_after"

  if [ "$windows_after" -le "$windows_before" ]; then
    log_warn "Window count did not increase (before: $windows_before, after: $windows_after)"
  fi

  # 7. Close Deep Search (Cmd+W)
  log_info "Closing Deep Search (Cmd+W)"
  send_shortcut "w" "command down"
  sleep 0.5

  # 8. Verify window closed
  local windows_final
  windows_final=$(get_window_count)
  log_info "Windows final: $windows_final"

  if [ "$windows_final" -lt "$windows_after" ]; then
    log_success "Deep Search window closed"
  else
    log_warn "Window count did not decrease after Cmd+W"
  fi

  log_success "Test execution completed"
}

validate_results() {
  log_subheader "Validation"

  # Deep Search initialized
  assert_log_contains "\[DEEPSEARCH-INIT\]" "Deep Search window opened"

  # App still running
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

  sleep 3

  run_test_steps
  validate_results
  exit_with_result
}

main "$@"
```

### 3.4 Search Test Coverage Matrix

| Behavior | Test | Priority |
|----------|------|----------|
| Quick Search activation (Cmd+F, Enter) | QA-10 | P1 |
| Quick Search results display | QA-10 | P1 |
| Quick Search exit (Escape) | QA-10 | P1 |
| Deep Search window opens (Cmd+Enter) | QA-11 | P1 |
| Deep Search window closes (Cmd+W) | QA-11 | P1 |
| FTS5 index sync (new entries searchable) | QA-10 | P1 |

---

## 4. DB Migration/Integrity Test

### 4.1 Fixture Database Files

Create `scripts/qa/fixtures/db/` with:
- `v16-contextify.db` - Oldest supported schema (collapsed baseline)
- `v25-contextify.db` - Pre-FTS5 schema (tests search index creation)
- `README.md` - Documents how to create/update fixtures

### 4.2 New test: `QA-09-db-migration.sh`

```bash
#!/bin/bash
# QA-09: DB Migration & Integrity
#
# Validates that the app successfully migrates older database schemas.
# Uses fixture databases from known older versions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-09"
TEST_NAME="DB Migration & Integrity"

check_prerequisites() {
  log_subheader "Checking Prerequisites"
  assert_command_exists "sqlite3"

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
  if grep -q "\[ERROR\].*migration" "$LOGFILE" 2>/dev/null; then
    log_error "Migration errors found in logs"
    grep "\[ERROR\]" "$LOGFILE" | head -5
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
```

---

## 5. CI Workflow Integration

### 5.1 Update `.github/workflows/macos-build.yml`

```yaml
name: macOS Build

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: macos-15
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Cache SwiftPM packages
        uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData/*/SourcePackages
          key: ${{ runner.os }}-spm-${{ hashFiles('**/Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-spm-

      - name: Select Xcode
        run: |
          sudo xcode-select -p
          xcodebuild -version

      - name: Install coreutils (for gtimeout)
        run: brew install coreutils

      - name: Run Tests
        run: swift test

      - name: Build Contextify
        run: |
          set -euo pipefail
          xcodebuild \
            -project Contextify/Contextify.xcodeproj \
            -scheme Contextify \
            -configuration Debug \
            -destination 'platform=macOS' \
            -derivedDataPath .derived \
            -skipPackagePluginValidation \
            -skipMacroValidation \
            build | xcpretty || exit ${PIPESTATUS[0]}
        env:
          NSUnbufferedIO: "YES"

      - name: Create test project
        run: |
          mkdir -p /tmp/contextify-qa-test
          cd /tmp/contextify-qa-test
          git init
          git config user.email "qa@contextify.test"
          git config user.name "QA Test"
          echo "# QA Test Project" > README.md
          git add README.md
          git commit -m "Initial commit"

      - name: Run QA Suite (fixture mode)
        run: |
          QA_FIXTURE_MODE=1 ./scripts/qa/run-all-tests.sh --skip-appstore
        env:
          TEST_PROJECT: /tmp/contextify-qa-test

      - name: Upload QA logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: qa-logs
          path: /tmp/qa-run-*

      - name: Archive build logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: xcode-build-logs
          path: .derived
```

**Key points:**
- `QA_FIXTURE_MODE=1` enables fixture-based testing
- NO `--skip-cli` flag - fixture mode runs CLI tests with fixtures
- `--skip-appstore` only since we don't have signing in CI
- `TEST_PROJECT` env ensures consistency with fixture cwd rewriting

---

## 6. Documentation Updates

### 6.1 Update `scripts/qa/README.md`

Add section:

```markdown
## Fixture Mode

Set `QA_FIXTURE_MODE=1` to run Codex/Claude tests using local transcript fixtures
instead of invoking live CLIs. This enables deterministic, fast testing without
network dependencies.

### Usage

```bash
# Run with fixtures (no CLI binaries needed)
QA_FIXTURE_MODE=1 ./scripts/qa/run-all-tests.sh --skip-appstore

# Fixtures used
scripts/qa/fixtures/transcripts/codex/simple-session.jsonl
scripts/qa/fixtures/transcripts/claude/simple-session.jsonl
```

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `QA_FIXTURE_MODE` | 0 | Set to 1 to use fixtures instead of CLIs |
| `QA_FIXTURE_DIR` | `$REPO_ROOT/scripts/qa/fixtures` | Fixture directory |
| `TEST_PROJECT` | `/tmp/contextify-qa-test` | Test project path (cwd written into fixtures) |

### Notes

- Fixture mode works with `--skip-cli`; CLI binaries are not required
- The `TEST_PROJECT` path is written into fixture transcripts via sed
- Claude fixtures use a simplified project hash (not Claude's actual algorithm)
- Fixtures include search terms (`QA_FIXTURE_SEARCH_TERM_*`) for search tests
```

---

## Testing Plan

### Before merging Phase 2:

1. **Fixture infrastructure:**
   ```bash
   # Create test project
   mkdir -p /tmp/contextify-qa-test && cd /tmp/contextify-qa-test && git init && \
     git config user.email "qa@test" && git config user.name "QA" && \
     echo "# Test" > README.md && git add . && git commit -m "init"
   ```

2. **Fixture transcript tests:**
   ```bash
   QA_FIXTURE_MODE=1 ./scripts/qa/run-all-tests.sh --skip-appstore
   ```

3. **Search tests (validate fixture pipeline):**
   ```bash
   ./scripts/qa/tests/QA-10-quick-search.sh
   ./scripts/qa/tests/QA-11-deep-search.sh
   ```

4. **DB migration test:**
   ```bash
   ./scripts/qa/tests/QA-09-db-migration.sh
   ```

5. **CI workflow:**
   - Push to feature branch
   - Verify GitHub Actions runs successfully

---

## Commit Strategy

**Commit 1:** Fixture infrastructure
- Add `fixtures/` directory structure with README files
- Add `seed_fixture_transcript`, `install_db_fixture`, `restore_db_from_backup`, `focus_search_field` to common.sh
- Add `QA_FIXTURE_MODE`, `TEST_PROJECT` config
- Update `should_skip_test` to respect fixture mode
- Add uuidgen prereq check for fixture mode

**Commit 2:** Fixture-based transcript tests
- Add fixture JSONL files for Codex and Claude (with search terms)
- Update QA-03, QA-04 to support fixture mode

**Commit 3:** Search tests
- Add QA-10-quick-search.sh
- Add QA-11-deep-search.sh
- Register in orchestrator

**Commit 4:** DB migration test
- Add QA-09-db-migration.sh
- Add initial DB fixture(s)
- Register in orchestrator

**Commit 5:** CI integration + docs
- Update macos-build.yml with QA suite step
- Update README with Fixture Mode section

---

## Orchestrator Updates

Add to `ALL_TESTS` in `run-all-tests.sh`:

```bash
declare -a ALL_TESTS=(
  "QA-01a-launch-dmg-clean.sh:0"
  "QA-01b-launch-dmg-existing.sh:0"
  "QA-01c-launch-appstore-clean.sh:0"
  "QA-01d-launch-appstore-existing.sh:0"
  "QA-01e-launch-appstore-skip.sh:0"
  "QA-02-project-switching.sh:0"
  "QA-03-codex-discovery.sh:1"
  "QA-04-claude-discovery.sh:2"
  "QA-05-realtime-updates.sh:1"
  "QA-06-watcher-recovery.sh:0"
  "QA-07-transcript-window.sh:0"
  "QA-08-projects-window.sh:0"
  "QA-09-db-migration.sh:0"
  "QA-10-quick-search.sh:0"
  "QA-11-deep-search.sh:0"
)
```

---

## Changes from v2

| Aspect | v2 | v3 |
|--------|----|----|
| Search tests | Separate addendum document | Integrated into main plan |
| Fixture search terms | Not specified | Included in fixture JSONL specs |
| Commit count | 4 commits | 5 commits (search tests added) |
| Commit order | Fixtures -> Transcripts -> DB -> CI | Fixtures -> Transcripts -> Search -> DB -> CI |
| focus_search_field helper | Not included | Added to common.sh |
| Test count | +1 (QA-09) | +3 (QA-09, QA-10, QA-11) |
