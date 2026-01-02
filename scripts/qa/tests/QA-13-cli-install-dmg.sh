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
ALT_DEFAULTS_DOMAIN="sh.contextify.Contextify"
DEFAULTS_KEY="Contextify.QueryCLI.DMGInstallDirOverride"
SETTINGS_TAB_OVERRIDE_KEY="Contextify.Settings.SelectedTabOverride"

cleanup() {
  # Best-effort cleanup; preserve logs for debugging.
  defaults delete "$DEFAULTS_DOMAIN" "$DEFAULTS_KEY" >/dev/null 2>&1 || true
  defaults delete "$ALT_DEFAULTS_DOMAIN" "$DEFAULTS_KEY" >/dev/null 2>&1 || true
  defaults delete "$DEFAULTS_DOMAIN" "$SETTINGS_TAB_OVERRIDE_KEY" >/dev/null 2>&1 || true
  defaults delete "$ALT_DEFAULTS_DOMAIN" "$SETTINGS_TAB_OVERRIDE_KEY" >/dev/null 2>&1 || true
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
  local stderr_path="$LOGDIR/contextify-query-status.stderr"
  output=$(CONTEXTIFY_QUERY_APP_PATH="$DMG_APP_PATH" "$bin_path" status --json 2>"$stderr_path")
  local rc=$?
  set -e

  # Must be JSON either way.
  if ! echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
    log_error "contextify-query status --json did not emit valid JSON"
    log_error "STDOUT:"
    echo "$output" | cat -n >&2
    if [ -s "$stderr_path" ]; then
      log_error "STDERR (saved to $stderr_path):"
      cat -n "$stderr_path" >&2
    fi
    TEST_FAILED=1
    return 1
  fi

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

select_cli_tab() {
  # Settings tabs are exposed as unnamed toolbar buttons; in DMG builds this is:
  # 1) Database, 2) CLI
  osascript -e '
    tell application "System Events"
      tell process "Contextify"
        try
          click button 2 of toolbar 1 of window 1
        end try
      end tell
    end tell
  ' 2>/dev/null || true
  sleep 0.3
}

click_cli_actions_button() {
  local idx="$1"
  osascript -e '
    tell application "System Events"
      tell process "Contextify"
        try
          click button '"$idx"' of group 1 of group 1 of window "CLI"
        on error
          error "button missing"
        end try
      end tell
    end tell
  ' >/dev/null 2>&1
}

trigger_install() {
  if ! click_cli_actions_button 1; then
    return 1
  fi
  wait_for_any_pattern 5 "\\[CLI-INSTALL\\]" "\\[CLI-INSTALL-SUCCESS\\]"
}

trigger_uninstall() {
  if ! click_cli_actions_button 2; then
    return 1
  fi
  wait_for_any_pattern 5 "\\[CLI-REMOVE\\]" "\\[CLI-DISABLE-START\\]"
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
  defaults write "$ALT_DEFAULTS_DOMAIN" "$DEFAULTS_KEY" -string "$INSTALL_DIR"
  defaults write "$ALT_DEFAULTS_DOMAIN" "$SETTINGS_TAB_OVERRIDE_KEY" -string "cli"

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
  select_cli_tab

  if ! wait_for_log_pattern "\\[CLI-SETTINGS-TAB-OPEN\\]" 10; then
    log_error "CLI settings tab did not appear (missing log tag)"
    TEST_FAILED=1
    return 1
  fi

  # Install shim.
  log_info "Triggering install..."
  if ! trigger_install; then
    log_error "Could not trigger install action in UI"
    TEST_FAILED=1
    return 1
  fi

  if ! wait_for_any_pattern 20 \
    "\\[CLI-INSTALL\\]" \
    "\\[CLI-INSTALL-SUCCESS\\]" \
    "\\[CLI-ADMIN-INSTALL-START\\]" \
    "\\[CLI-NO-WRITABLE-PATHS\\]"; then
    log_error "No install completion log observed"
    TEST_FAILED=1
    return 1
  fi

  assert_log_contains "\\[CLI-INSTALL-SUCCESS\\]" "Install completed"
  assert_log_not_contains "\\[CLI-ADMIN-INSTALL-START\\]" "Install did not require admin"

  # Verify filesystem + CLI behavior.
  assert_file_exists "$INSTALL_SHIM_PATH" "Shim installed at $INSTALL_SHIM_PATH"
  validate_status_json "$INSTALL_SHIM_PATH"

  # Uninstall.
  log_info "Triggering uninstall..."
  if ! trigger_uninstall; then
    log_error "Could not trigger uninstall action in UI"
    TEST_FAILED=1
    return 1
  fi

  if ! wait_for_log_pattern "\\[CLI-REMOVE\\]" 10; then
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
