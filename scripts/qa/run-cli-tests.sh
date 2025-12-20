#!/bin/bash
# Contextify CLI query integration tests runner

set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_BIN="${CONTEXTIFY_QUERY_BIN:-contextify-query}"
source "$RUNNER_DIR/lib/common.sh"
source "$RUNNER_DIR/lib/assertions.sh"

LOGDIR="/tmp/qa-cli-run-$(date +%Y%m%d-%H%M%S)"

CLI_TESTS=(
  "CLI-01-query-baseline.sh"
  "CLI-02-query-issues.sh"
  "CLI-03-skill-invocation.sh"
)

PASSED_TESTS=()
FAILED_TESTS=()
SKIPPED_TESTS=()

check_prerequisites() {
  if [[ "$CLI_BIN" == /* ]]; then
    if [ ! -x "$CLI_BIN" ]; then
      log_error "contextify-query CLI not found at $CLI_BIN"
      exit 1
    fi
  else
    if ! command -v "$CLI_BIN" >/dev/null 2>&1; then
      log_error "contextify-query CLI not found"
      exit 1
    fi
  fi
  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq not found"
    exit 1
  fi
}

run_test() {
  local test_name="$1"
  local test_path="$RUNNER_DIR/tests/$test_name"

  if [ ! -f "$test_path" ]; then
    log_warn "Test not implemented: $test_name"
    SKIPPED_TESTS+=("$test_name (not implemented)")
    return 0
  fi

  if [ ! -x "$test_path" ]; then
    chmod +x "$test_path"
  fi

  echo ""
  log_header "Running: $test_name"

  local start_time
  start_time=$(date +%s)

  if "$test_path" 2>&1 | tee "$LOGDIR/$test_name.log"; then
    local end_time
    end_time=$(date +%s)
    PASSED_TESTS+=("$test_name ($((end_time - start_time))s)")
    return 0
  else
    local end_time
    end_time=$(date +%s)
    FAILED_TESTS+=("$test_name ($((end_time - start_time))s)")
    return 1
  fi
}

print_summary() {
  local total
  total=$((${#PASSED_TESTS[@]} + ${#FAILED_TESTS[@]} + ${#SKIPPED_TESTS[@]}))

  log_header "CLI TEST SUMMARY"
  echo ""
  echo "  Total:   $total tests"
  echo "  Passed:  ${#PASSED_TESTS[@]}"
  echo "  Failed:  ${#FAILED_TESTS[@]}"
  echo "  Skipped: ${#SKIPPED_TESTS[@]}"
  echo ""

  if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo "  Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
      echo "    - $t"
    done
    echo ""
  fi

  if [ ${#SKIPPED_TESTS[@]} -gt 0 ]; then
    echo "  Skipped tests:"
    for t in "${SKIPPED_TESTS[@]}"; do
      echo "    - $t"
    done
    echo ""
  fi

  echo "  Logs:    $LOGDIR"
  echo ""
}

main() {
  mkdir -p "$LOGDIR"

  log_header "Contextify CLI Query Tests"
  echo ""
  echo "  Log directory: $LOGDIR"
  echo ""

  check_prerequisites

  local test_name
  for test_name in "${CLI_TESTS[@]}"; do
    run_test "$test_name" || true
  done

  print_summary

  if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    exit 1
  fi
}

main "$@"
