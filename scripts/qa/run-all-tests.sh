#!/bin/bash
# Contextify QA Test Suite Orchestrator
# Runs all QA tests sequentially and generates summary report

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common helpers for transcript backup/restore
source "$SCRIPT_DIR/lib/common.sh"

# Configuration
LOGDIR="/tmp/qa-run-$(date +%Y%m%d-%H%M%S)"
SKIP_APPSTORE="${SKIP_APPSTORE:-0}"
SKIP_CLI="${SKIP_CLI:-0}"
ONLY_TEST="${ONLY_TEST:-}"
ISOLATE_TRANSCRIPTS="${ISOLATE_TRANSCRIPTS:-0}"

# Fixture mode (set via environment)
QA_FIXTURE_MODE="${QA_FIXTURE_MODE:-0}"
export QA_FIXTURE_MODE
export TEST_PROJECT="${TEST_PROJECT:-/tmp/contextify-qa-test}"

# Test suite definition
# Format: "test_script:requires_cli"
# requires_cli: 0 = no CLI needed, 1 = needs Codex, 2 = needs Claude Code, 3 = needs contextify-query

declare -a ALL_TESTS=(
  # Phase 1: Tests that need existing data (run first, before destructive tests)
  "QA-01b-launch-dmg-existing.sh:0"

  # Phase 2: Destructive tests (delete DB, reset state)
  "QA-01a-launch-dmg-clean.sh:0"
  "QA-01c-launch-appstore-clean.sh:0"
  "QA-09-db-migration.sh:0"       # Uses fixture DBs, restores original - run before discovery

  # Phase 3: Discovery tests (repopulate data after clean install)
  "QA-03-codex-discovery.sh:1"
  "QA-04-claude-discovery.sh:2"

  # Phase 4: Tests that need discovery data (projects, transcripts, FTS)
  "QA-01d-launch-appstore-existing.sh:0"
  "QA-01e-launch-appstore-skip.sh:0"
  "QA-02-project-switching.sh:0"  # Needs 2+ projects from discovery
  "QA-05-realtime-updates.sh:1"
  "QA-06-watcher-recovery.sh:0"
  "QA-07-transcript-window.sh:0"
  "QA-08-projects-window.sh:0"

  # Phase 5: Search tests (require FTS5 index populated by discovery tests)
  "QA-10-quick-search.sh:0"
  "QA-11-deep-search.sh:0"

  # Phase 6: Feature tests
  "QA-12-git-branch-display.sh:0"
  "QA-13-cli-install-dmg.sh:0"
  "QA-15-query-bundle-integrity.sh:0"
  "QA-16-agent-decoration.sh:0"

  # Phase 7: CLI query tests
  "CLI-01-query-baseline.sh:3"
  "CLI-02-query-issues.sh:3"
  "CLI-03-skill-invocation.sh:3"
)

# Track results
declare -a PASSED_TESTS=()
declare -a FAILED_TESTS=()
declare -a SKIPPED_TESTS=()

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

print_header() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Run Contextify QA test suite.

OPTIONS:
  --skip-appstore    Skip App Store build tests (QA-01c/d/e)
  --skip-cli         Skip tests requiring CLI tools (QA-03/04/05)
  --isolate          Backup production transcripts, use empty dirs for tests
  --restore          Restore production transcripts (if QA was interrupted)
  --only TEST        Run only specified test (e.g., QA-03)
  --list             List all available tests
  --help             Show this help

ENVIRONMENT:
  QA_DEBUG=1         Enable debug output
  QA_CLEANUP=1       Clean up test artifacts after run

EXAMPLES:
  $0                          # Run all tests
  $0 --skip-appstore          # Skip App Store tests
  $0 --isolate                # Run with isolated transcripts (recommended)
  $0 --restore                # Restore if interrupted mid-test
  $0 --only QA-03             # Run only QA-03
  $0 --skip-cli --skip-appstore  # Run only basic tests

EOF
}

list_tests() {
  echo "Available QA Tests:"
  echo ""
  for test_def in "${ALL_TESTS[@]}"; do
    local test_name="${test_def%%:*}"
    local cli_req="${test_def##*:}"
    local req_note=""
    case $cli_req in
      1) req_note=" (requires Codex CLI)" ;;
      2) req_note=" (requires Claude Code)" ;;
      3) req_note=" (requires contextify-query)" ;;
    esac
    echo "  - $test_name$req_note"
  done
}

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

  # Skip CLI tests only if NOT in fixture mode (contextify-query always skipped)
  if [ "$SKIP_CLI" = "1" ] && [ "$cli_req" != "0" ]; then
    if [ "$cli_req" = "3" ] || [ "${QA_FIXTURE_MODE:-0}" != "1" ]; then
      return 0  # Skip
    fi
  fi

  return 1  # Don't skip
}

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

  # Check for DMG build
  if [ ! -d "$REPO_ROOT/.derived-dmg/Build/Products/Debug/Contextify.app" ]; then
    echo "[WARN] DMG build not found. Run: bash scripts/xc.sh build"
  fi

  # Check for App Store build (only warn if not skipping)
  if [ "$SKIP_APPSTORE" != "1" ]; then
    if [ ! -d "$REPO_ROOT/.derived-appstore/Build/Products/Debug/Contextify.app" ]; then
      echo "[WARN] App Store build not found. Run: bash scripts/xc.sh --dist=appstore Debug build"
      echo "[INFO] Use --skip-appstore to skip App Store tests"
    fi
  fi

  # Check for CLI tools (only warn if not skipping)
  if [ "$SKIP_CLI" != "1" ]; then
    # timeout/gtimeout required for CLI tests (prevents hangs)
    if ! command -v timeout &> /dev/null && ! command -v gtimeout &> /dev/null; then
      echo "[ERROR] timeout or gtimeout required for CLI tests."
      echo "[INFO] Install with: brew install coreutils"
      echo "[INFO] Or use --skip-cli to skip CLI tests"
      exit 1
    fi
    if ! command -v codex &> /dev/null; then
      echo "[WARN] Codex CLI not found. QA-03/05 will be skipped."
    fi
    if ! command -v claude &> /dev/null; then
      echo "[WARN] Claude Code not found. QA-04 will be skipped."
    fi
    if ! command -v contextify-query &> /dev/null; then
      echo "[WARN] contextify-query not found. CLI-01/02/03 will be skipped."
    fi
    if ! command -v jq &> /dev/null; then
      echo "[WARN] jq not found. CLI-01/02/03 will be skipped."
    fi
  fi

  # Check Terminal accessibility permission
  echo "[INFO] Ensure Terminal has Accessibility permission for UI automation"
  echo "[INFO] System Settings → Privacy & Security → Accessibility → Terminal"

  echo "Prerequisites check complete"
  echo ""
}

run_test() {
  local test_name="$1"
  local test_path="$SCRIPT_DIR/tests/$test_name"

  if [ ! -f "$test_path" ]; then
    echo "[SKIP] Test not implemented: $test_name"
    SKIPPED_TESTS+=("$test_name (not implemented)")
    return 0
  fi

  if [ ! -x "$test_path" ]; then
    chmod +x "$test_path"
  fi

  echo ""
  echo "┌──────────────────────────────────────────────────────────────────────┐"
  echo "│ Running: $test_name"
  echo "└──────────────────────────────────────────────────────────────────────┘"

  # Run test and capture output
  local start_time
  start_time=$(date +%s)

  if "$test_path" 2>&1 | tee "$LOGDIR/$test_name.log"; then
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    PASSED_TESTS+=("$test_name (${duration}s)")
    echo ""
    echo "[PASS] $test_name (${duration}s)"
    return 0
  else
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    FAILED_TESTS+=("$test_name (${duration}s)")
    echo ""
    echo "[FAIL] $test_name (${duration}s)"
    return 1
  fi
}

generate_summary() {
  local total=$((${#PASSED_TESTS[@]} + ${#FAILED_TESTS[@]}))

  # Categorize failures: prerequisite vs test logic
  local prereq_failures=()
  local test_failures=()

  if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
  for f in "${FAILED_TESTS[@]}"; do
    local test_name="${f%% *}"
    local log_file="$LOGDIR/$test_name.log"
    if [ -f "$log_file" ]; then
      # Check for prerequisite failure patterns
      if grep -q "build not found\|not found:.*\.app\|Build with:" "$log_file" 2>/dev/null; then
        prereq_failures+=("$f (missing build)")
      elif grep -q "CLI not available\|not found:.*CLI\|command not found" "$log_file" 2>/dev/null; then
        prereq_failures+=("$f (missing CLI)")
      else
        test_failures+=("$f")
      fi
    else
      test_failures+=("$f")
    fi
  done
  fi

  cat > "$LOGDIR/SUMMARY.md" << EOF
# Contextify QA Run Summary

**Date:** $(date)
**Log Directory:** \`$LOGDIR\`
**Total Tests:** $total
**Passed:** ${#PASSED_TESTS[@]}
**Failed:** ${#FAILED_TESTS[@]}$(if [ ${#prereq_failures[@]} -gt 0 ]; then echo " (${#prereq_failures[@]} due to missing prerequisites)"; fi)
**Skipped:** ${#SKIPPED_TESTS[@]}

## Results

### Passed ✅
$(if [ ${#PASSED_TESTS[@]} -gt 0 ]; then
  for t in "${PASSED_TESTS[@]}"; do echo "- $t"; done
else
  echo "- None"
fi)

### Failed ❌
$(if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
  if [ ${#prereq_failures[@]} -gt 0 ]; then
    echo ""
    echo "**Prerequisite Failures** (missing build or CLI - not test logic failures):"
    for t in "${prereq_failures[@]}"; do echo "- $t"; done
  fi
  if [ ${#test_failures[@]} -gt 0 ]; then
    echo ""
    echo "**Test Failures:**"
    for t in "${test_failures[@]}"; do echo "- $t"; done
  fi
  if [ ${#prereq_failures[@]} -gt 0 ] && [ ${#test_failures[@]} -eq 0 ]; then
    echo ""
    echo "> **Note:** All failures are due to missing prerequisites, not test logic."
    echo "> Build the missing app or use \`--skip-appstore\` / \`--skip-cli\` flags."
  fi
else
  echo "- None"
fi)

### Skipped ⏭️
$(if [ ${#SKIPPED_TESTS[@]} -gt 0 ]; then
  for t in "${SKIPPED_TESTS[@]}"; do echo "- $t"; done
else
  echo "- None"
fi)

## Failed Test Logs

$(if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
  for f in "${FAILED_TESTS[@]}"; do
    test_name="${f%% *}"
    if [ -f "$LOGDIR/$test_name.log" ]; then
      echo "### $test_name"
      echo '```'
      tail -100 "$LOGDIR/$test_name.log"
      echo '```'
      echo ""
    fi
  done
else
  echo "No failed tests."
fi)

## Environment

- **macOS:** $(sw_vers -productVersion 2>/dev/null || echo "N/A")
- **Xcode:** $(xcodebuild -version 2>/dev/null | head -1 || echo "N/A")
- **Repo:** $REPO_ROOT

EOF
}

print_summary() {
  local total=$((${#PASSED_TESTS[@]} + ${#FAILED_TESTS[@]}))

  # Categorize failures for terminal output
  local prereq_failures=()
  local test_failures=()

  if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
  for f in "${FAILED_TESTS[@]}"; do
    local test_name="${f%% *}"
    local log_file="$LOGDIR/$test_name.log"
    if [ -f "$log_file" ]; then
      if grep -q "build not found\|not found:.*\.app\|Build with:" "$log_file" 2>/dev/null; then
        prereq_failures+=("$f (missing build)")
      elif grep -q "CLI not available\|not found:.*CLI\|command not found" "$log_file" 2>/dev/null; then
        prereq_failures+=("$f (missing CLI)")
      else
        test_failures+=("$f")
      fi
    else
      test_failures+=("$f")
    fi
  done
  fi

  print_header "QA SUMMARY"
  echo ""
  echo "  Total:   $total tests"
  echo "  Passed:  ${#PASSED_TESTS[@]}"
  if [ ${#prereq_failures[@]} -gt 0 ]; then
    echo "  Failed:  ${#FAILED_TESTS[@]} (${#prereq_failures[@]} prerequisite, ${#test_failures[@]} test)"
  else
    echo "  Failed:  ${#FAILED_TESTS[@]}"
  fi
  echo "  Skipped: ${#SKIPPED_TESTS[@]}"
  echo ""

  if [ ${#prereq_failures[@]} -gt 0 ]; then
    echo "  Prerequisite failures (missing build/CLI):"
    for t in "${prereq_failures[@]}"; do
      echo "    ⚠️  $t"
    done
    echo ""
  fi

  if [ ${#test_failures[@]} -gt 0 ]; then
    echo "  Test failures:"
    for t in "${test_failures[@]}"; do
      echo "    ❌ $t"
    done
    echo ""
  fi

  if [ ${#SKIPPED_TESTS[@]} -gt 0 ]; then
    echo "  Skipped tests:"
    for t in "${SKIPPED_TESTS[@]}"; do
      echo "    ⏭️  $t"
    done
    echo ""
  fi

  if [ ${#prereq_failures[@]} -gt 0 ] && [ ${#test_failures[@]} -eq 0 ]; then
    echo "  Note: All failures are prerequisite issues, not test logic."
    echo "  Build missing apps or use --skip-appstore / --skip-cli"
    echo ""
  fi

  echo "  Logs:    $LOGDIR"
  echo "  Summary: $LOGDIR/SUMMARY.md"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --skip-appstore)
        SKIP_APPSTORE=1
        shift
        ;;
      --skip-cli)
        SKIP_CLI=1
        shift
        ;;
      --isolate)
        ISOLATE_TRANSCRIPTS=1
        shift
        ;;
      --restore)
        # Manual restore if QA was interrupted
        restore_transcripts_from_backup
        exit 0
        ;;
      --only)
        ONLY_TEST="$2"
        shift 2
        ;;
      --list)
        list_tests
        exit 0
        ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        print_usage
        exit 1
        ;;
    esac
  done

  # Create log directory
  mkdir -p "$LOGDIR"

  print_header "Contextify QA Suite"
  echo ""
  echo "  Log directory: $LOGDIR"
  echo "  Skip App Store: $SKIP_APPSTORE"
  echo "  Skip CLI tests: $SKIP_CLI"
  echo "  Isolate transcripts: $ISOLATE_TRANSCRIPTS"
  echo "  Fixture mode: $QA_FIXTURE_MODE"
  [ "$QA_FIXTURE_MODE" = "1" ] && echo "  Test project: $TEST_PROJECT"
  [ -n "$ONLY_TEST" ] && echo "  Only test: $ONLY_TEST"
  echo ""

  check_prerequisites

  # Isolate transcripts if requested (backup production data)
  if [ "$ISOLATE_TRANSCRIPTS" = "1" ]; then
    backup_and_isolate_transcripts
    # Enable fixture mode when isolated - CLI tools write to paths that won't be discovered
    QA_FIXTURE_MODE=1
    export QA_FIXTURE_MODE
    # Ensure app is killed and transcripts restored on exit (success or failure)
    orchestrator_cleanup() {
      echo "[INFO] Orchestrator cleanup..."
      kill_app_if_running
      restore_transcripts_from_backup
    }
    trap orchestrator_cleanup EXIT
  fi

  # Run tests
  for test_def in "${ALL_TESTS[@]}"; do
    local test_name="${test_def%%:*}"
    local cli_req="${test_def##*:}"

    if should_skip_test "$test_name" "$cli_req"; then
      SKIPPED_TESTS+=("$test_name")
      echo "[SKIP] $test_name"
      continue
    fi

    # Check CLI availability for tests that need it (skip check in fixture mode)
    if [ "$cli_req" = "1" ] && [ "${QA_FIXTURE_MODE:-0}" != "1" ] && ! command -v codex &> /dev/null; then
      SKIPPED_TESTS+=("$test_name (Codex CLI not available)")
      echo "[SKIP] $test_name (Codex CLI not available)"
      continue
    fi

    if [ "$cli_req" = "2" ] && [ "${QA_FIXTURE_MODE:-0}" != "1" ] && ! command -v claude &> /dev/null; then
      SKIPPED_TESTS+=("$test_name (Claude Code not available)")
      echo "[SKIP] $test_name (Claude Code not available)"
      continue
    fi
    if [ "$cli_req" = "3" ] && ! command -v contextify-query &> /dev/null; then
      SKIPPED_TESTS+=("$test_name (contextify-query not available)")
      echo "[SKIP] $test_name (contextify-query not available)"
      continue
    fi
    if [ "$cli_req" = "3" ] && ! command -v jq &> /dev/null; then
      SKIPPED_TESTS+=("$test_name (jq not available)")
      echo "[SKIP] $test_name (jq not available)"
      continue
    fi

    run_test "$test_name" || true  # Continue even if test fails
  done

  # Generate summary
  generate_summary
  print_summary

  # Exit with appropriate code
  if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo "❌ Some QA tests failed"
    exit 1
  else
    echo "✅ All QA tests passed"
    exit 0
  fi
}

main "$@"
