#!/bin/bash
# Contextify QA Test Suite Orchestrator
# Runs all QA tests sequentially and generates summary report

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
LOGDIR="/tmp/qa-run-$(date +%Y%m%d-%H%M%S)"
SKIP_APPSTORE="${SKIP_APPSTORE:-0}"
SKIP_CLI="${SKIP_CLI:-0}"
ONLY_TEST="${ONLY_TEST:-}"

# Test suite definition
# Format: "test_script:requires_cli"
# requires_cli: 0 = no CLI needed, 1 = needs Codex, 2 = needs Claude Code

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
  --only TEST        Run only specified test (e.g., QA-03)
  --list             List all available tests
  --help             Show this help

ENVIRONMENT:
  QA_DEBUG=1         Enable debug output
  QA_CLEANUP=1       Clean up test artifacts after run

EXAMPLES:
  $0                          # Run all tests
  $0 --skip-appstore          # Skip App Store tests
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

  # Skip CLI tests if requested
  if [ "$SKIP_CLI" = "1" ] && [ "$cli_req" != "0" ]; then
    return 0  # Skip
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

  if [ ${#missing[@]} -gt 0 ]; then
    echo "[ERROR] Missing required commands: ${missing[*]}"
    exit 1
  fi

  # Check for DMG build
  if [ ! -d "$REPO_ROOT/.derived/Build/Products/Debug/Contextify.app" ]; then
    echo "[WARN] DMG build not found. Run: bash scripts/xc.sh build"
  fi

  # Check for App Store build (only warn if not skipping)
  if [ "$SKIP_APPSTORE" != "1" ]; then
    if [ ! -d "$REPO_ROOT/.derived/Build/Products/Debug/Contextify AppStore.app" ]; then
      echo "[WARN] App Store build not found. Run: bash scripts/xc.sh --dist=appstore Debug build"
      echo "[INFO] Use --skip-appstore to skip App Store tests"
    fi
  fi

  # Check for CLI tools (only warn if not skipping)
  if [ "$SKIP_CLI" != "1" ]; then
    if ! command -v codex &> /dev/null; then
      echo "[WARN] Codex CLI not found. QA-03/05 will be skipped."
    fi
    if ! command -v claude &> /dev/null; then
      echo "[WARN] Claude Code not found. QA-04 will be skipped."
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

  cat > "$LOGDIR/SUMMARY.md" << EOF
# Contextify QA Run Summary

**Date:** $(date)
**Log Directory:** \`$LOGDIR\`
**Total Tests:** $total
**Passed:** ${#PASSED_TESTS[@]}
**Failed:** ${#FAILED_TESTS[@]}
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
  for t in "${FAILED_TESTS[@]}"; do echo "- $t"; done
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

  print_header "QA SUMMARY"
  echo ""
  echo "  Total:   $total tests"
  echo "  Passed:  ${#PASSED_TESTS[@]}"
  echo "  Failed:  ${#FAILED_TESTS[@]}"
  echo "  Skipped: ${#SKIPPED_TESTS[@]}"
  echo ""

  if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo "  Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
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
  [ -n "$ONLY_TEST" ] && echo "  Only test: $ONLY_TEST"
  echo ""

  check_prerequisites

  # Run tests
  for test_def in "${ALL_TESTS[@]}"; do
    local test_name="${test_def%%:*}"
    local cli_req="${test_def##*:}"

    if should_skip_test "$test_name" "$cli_req"; then
      SKIPPED_TESTS+=("$test_name")
      echo "[SKIP] $test_name"
      continue
    fi

    # Check CLI availability for tests that need it
    if [ "$cli_req" = "1" ] && ! command -v codex &> /dev/null; then
      SKIPPED_TESTS+=("$test_name (Codex CLI not available)")
      echo "[SKIP] $test_name (Codex CLI not available)"
      continue
    fi

    if [ "$cli_req" = "2" ] && ! command -v claude &> /dev/null; then
      SKIPPED_TESTS+=("$test_name (Claude Code not available)")
      echo "[SKIP] $test_name (Claude Code not available)"
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
