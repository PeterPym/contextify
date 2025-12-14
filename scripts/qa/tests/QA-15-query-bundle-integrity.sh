#!/bin/bash
# QA-15: contextify-query bundle integrity (DMG + App Store)
#
# Purpose: Ensures release builds always include the bundled CLI, shim, and skills/plugin assets
#          that Claude Code skills depend on.
#
# @test_contract
# isolation:
#   transcripts: none
#   database: none
#
# database:
#   location: dmg
#   start:
#     exists: any
#   mutations: []
#   end:
#     exists: any
#
# dependencies:
#   run_after: []

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-15"
TEST_NAME="contextify-query bundle integrity"

assert_bundle_assets() {
  local app_path="$1"
  local label="$2"

  log_subheader "Asserting bundled assets ($label)"

  assert_file_exists "$app_path/Contents/MacOS/contextify-query" "$label: bundled CLI present"
  assert_file_exists "$app_path/Contents/Resources/contextify-query/shim/contextify-query-shim" "$label: bundled shim present"
  assert_directory_exists "$app_path/Contents/Resources/contextify-query/skills" "$label: bundled skills dir present"
  assert_file_exists "$app_path/Contents/Resources/contextify-query/skills/claude/contextify-reinject/SKILL.md" "$label: reinject skill present"
  assert_file_exists "$app_path/Contents/Resources/contextify-query/skills/claude/contextify-query-debug/SKILL.md" "$label: debug skill present"
  assert_file_exists "$app_path/Contents/Resources/contextify-query/claude-plugin/.claude-plugin/plugin.json" "$label: plugin.json present"
}

check_prerequisites() {
  log_subheader "Checking Prerequisites"
  assert_dmg_app_exists
  log_success "Prerequisites met"
}

main() {
  log_header "$TEST_ID: $TEST_NAME"
  check_prerequisites

  assert_bundle_assets "$DMG_APP_PATH" "DMG"

  if [ "${SKIP_APPSTORE:-0}" = "1" ]; then
    log_info "Skipping App Store assertions (SKIP_APPSTORE=1)"
    exit_with_result
  fi

  if [ -d "$APPSTORE_APP_PATH" ]; then
    assert_bundle_assets "$APPSTORE_APP_PATH" "App Store"
  else
    log_warn "App Store build not found at $APPSTORE_APP_PATH; skipping App Store assertions"
  fi

  exit_with_result
}

main "$@"

