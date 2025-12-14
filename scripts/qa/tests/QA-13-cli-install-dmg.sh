#!/bin/bash
# QA-13: CLI Install/Repair/Uninstall (DMG)
#
# Purpose: Validates Settings → CLI tab install/repair/uninstall flow and ensures
#          the shim binary runs and emits JSON.
#
# @test_contract
# isolation:
#   transcripts: none         # This test does not require transcript isolation
#   database: none            # Does not depend on DB contents
#
# database:
#   location: dmg
#   start:
#     exists: any
#   mutations:
#     - "Installs/removes CLI shim under a test-controlled directory"
#   end:
#     exists: any
#
# dependencies:
#   orchestrator_flags: []
#   run_after: []
#   notes: "Uses E2E log tags in subsystem dev.contextify category QueryCLIInstall"
#
# Prerequisites:
# - DMG app build available
# - Terminal has Accessibility permission

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

TEST_ID="QA-13"
TEST_NAME="CLI Install/Repair/Uninstall (DMG)"

INSTALL_DIR="/tmp/contextify-qa-bin"
INSTALL_SHIM_PATH="$INSTALL_DIR/contextify-query"

DEFAULTS_DOMAIN="$BUNDLE_ID_DMG"
DEFAULTS_KEY="Contextify.QueryCLI.DMGInstallDirOverride"
SETTINGS_TAB_OVERRIDE_KEY="Contextify.Settings.SelectedTabOverride"

cleanup() {
  # Best-effort cleanup; preserve logs for debugging.
  defaults delete "$DEFAULTS_DOMAIN" "$DEFAULTS_KEY" >/dev/null 2>&1 || true
  defaults delete "$DEFAULTS_DOMAIN" "$SETTINGS_TAB_OVERRIDE_KEY" >/dev/null 2>&1 || true
  rm -f "$INSTALL_SHIM_PATH" >/dev/null 2>&1 || true
  rmdir "$INSTALL_DIR" >/dev/null 2>&1 || true
  kill_app_if_running
  stop_log_capture
}

click_button_any_window() {
  local title="$1"
  local max_attempts="${2:-3}"
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    if osascript -e '
      tell application "System Events"
        tell process "Contextify"
          set didClick to false
          repeat with w in windows
            try
              if exists button "'"$title"'" of w then
                click button "'"$title"'" of w
                set didClick to true
                exit repeat
              end if
            end try
          end repeat
          if didClick is false then error "Button not found: '"$title"'"
        end tell
      end tell
    ' 2>/dev/null; then
      sleep 0.3
      return 0
    fi
    sleep 0.5
    attempt=$((attempt + 1))
  done

  log_warn "Could not click button in any window: $title"
  return 1
}

validate_status_json() {
  local bin_path="$1"

  set +e
  local output
  output=$("$bin_path" status --json 2>/dev/null)
  local rc=$?
  set -e

  # Must be JSON either way.
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'

  if [ "$rc" -eq 0 ]; then
    return 0
  fi

  # Under isolation / first-run, dbNotFound is an allowed contract failure.
  if [ "$rc" -eq 2 ] && echo "$output" | rg -q "\"code\"\\s*:\\s*\"dbNotFound\""; then
    return 0
  fi

  log_error "Unexpected exit code from status: $rc"
  log_error "Output: $output"
  TEST_FAILED=1
  return 1
}

check_prerequisites() {
  log_subheader "Checking Prerequisites"
  assert_command_exists "osascript"
  assert_command_exists "python3"
  assert_dmg_app_exists
  log_success "Prerequisites met"
}

run_test_steps() {
  log_subheader "Test Execution"

  # Ensure a deterministic, non-privileged install destination.
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  defaults write "$DEFAULTS_DOMAIN" "$DEFAULTS_KEY" -string "$INSTALL_DIR"
  defaults write "$DEFAULTS_DOMAIN" "$SETTINGS_TAB_OVERRIDE_KEY" -string "cli"

  # Start with app fresh.
  kill_app_if_running
  start_log_capture "$LOGDIR"

  if ! launch_dmg_app; then
    log_error "Failed to launch DMG app"
    TEST_FAILED=1
    return 1
  fi

  # Open Settings (Cmd+,) and switch to CLI tab.
  activate_app
  send_shortcut "," "command down"
  sleep 1.2

  if ! wait_for_log_pattern "\\[QUERYCLI-SETTINGS-TAB-OPEN\\]" 10; then
    log_error "CLI settings tab did not appear (missing log tag)"
    TEST_FAILED=1
    return 1
  fi

  # Install shim.
  log_info "Triggering install via default action (Enter)..."
  press_return

  if ! wait_for_any_pattern 20 \
    "\\[QUERYCLI-INSTALL-START\\]" \
    "\\[QUERYCLI-INSTALL-DONE\\]" \
    "\\[QUERYCLI-INSTALL-SUDO-REQUIRED\\]" \
    "\\[QUERYCLI-INSTALL-COLLISION\\]" \
    "\\[QUERYCLI-INSTALL-ERROR\\]"; then
    log_error "No install completion log observed"
    TEST_FAILED=1
    return 1
  fi

  assert_log_contains "\\[QUERYCLI-INSTALL-DIR\\] mode=dmg dir=$INSTALL_DIR" "Installer used override directory"
  assert_log_contains "\\[QUERYCLI-INSTALL-DONE\\]" "Install completed"
  assert_log_not_contains "\\[QUERYCLI-INSTALL-SUDO-REQUIRED\\]" "Install did not require sudo"

  # Verify filesystem + CLI behavior.
  assert_file_exists "$INSTALL_SHIM_PATH" "Shim installed at $INSTALL_SHIM_PATH"
  validate_status_json "$INSTALL_SHIM_PATH"

  # Uninstall.
  log_info "Triggering uninstall via keyboard shortcut (Cmd+Shift+U)..."
  send_shortcut "u" "command down, shift down"

  if ! wait_for_log_pattern "\\[QUERYCLI-UNINSTALL-DONE\\]" 10; then
    log_error "Uninstall completion log not observed"
    TEST_FAILED=1
    return 1
  fi

  assert_file_not_exists "$INSTALL_SHIM_PATH" "Shim removed"
  log_success "Test execution completed"
}

main() {
  LOGDIR="${LOGDIR:-/tmp/qa-${TEST_ID}-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$LOGDIR"

  trap cleanup EXIT

  log_header "$TEST_ID: $TEST_NAME"
  check_prerequisites
  run_test_steps
  exit_with_result
}

main "$@"
