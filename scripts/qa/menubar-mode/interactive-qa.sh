#!/bin/bash
# scripts/qa/menubar-mode/interactive-qa.sh
#
# Interactive QA script for menu bar / background utility mode transitions.
# Guides the user through every key mode-transition scenario and captures
# pass/fail proof for each step.
#
# Prerequisites:
#   - DMG build: bash scripts/xc.sh build
#   - Terminal Accessibility permission (System Settings > Privacy > Accessibility)
#
# Usage: ./scripts/qa/menubar-mode/interactive-qa.sh
#        ./scripts/qa/menubar-mode/interactive-qa.sh --dmg-only
#        ./scripts/qa/menubar-mode/interactive-qa.sh --skip-relaunch

set -e

# ─────────────────────────────────────────────────────────────────────────────
# Colors and constants
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DMG_APP_PATH="${DMG_APP_PATH:-$REPO_ROOT/.derived-dmg/Build/Products/Debug/Contextify.app}"
BUNDLE_ID="dev.contextify"
DEFAULTS_DOMAIN="dev.contextify"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROOF_FILE="/tmp/ct-461-menubar-qa-proof-${TIMESTAMP}.md"

# Counters
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Flags
SKIP_RELAUNCH=false
DMG_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --skip-relaunch) SKIP_RELAUNCH=true ;;
    --dmg-only) DMG_ONLY=true ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────

header() {
  echo ""
  echo -e "${BLUE}${BOLD}=== $1 ===${NC}"
  echo ""
  echo "## $1" >> "$PROOF_FILE"
  echo "" >> "$PROOF_FILE"
}

step() {
  echo -e "${CYAN}> $1${NC}"
}

pass() {
  echo -e "${GREEN}  PASS: $1${NC}"
  echo "- [x] $1" >> "$PROOF_FILE"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo -e "${RED}  FAIL: $1${NC}"
  echo "- [ ] **FAIL:** $1" >> "$PROOF_FILE"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

skip() {
  echo -e "${YELLOW}  SKIP: $1${NC}"
  echo "- [ ] *SKIP:* $1" >> "$PROOF_FILE"
  SKIP_COUNT=$((SKIP_COUNT + 1))
}

info() {
  echo -e "${YELLOW}  i $1${NC}"
}

prompt_continue() {
  echo ""
  read -p "Press Enter to continue (or Ctrl+C to abort)..."
  echo ""
}

prompt_yn() {
  local question="$1"
  echo ""
  read -p "$question [y/n] " answer
  echo ""
  if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    return 0
  else
    return 1
  fi
}

prompt_observe() {
  # Ask the user to perform an action and then confirm the observation
  local action="$1"
  local observation="$2"
  local pass_msg="$3"
  local fail_msg="$4"

  echo ""
  echo -e "${BOLD}ACTION: $action${NC}"
  echo -e "EXPECTED: $observation"
  echo ""
  if prompt_yn "Did you observe the expected behavior?"; then
    pass "$pass_msg"
  else
    fail "$fail_msg"
  fi
}

app_is_running() {
  pgrep -x "Contextify" > /dev/null 2>&1
}

quit_app() {
  if app_is_running; then
    step "Quitting Contextify..."
    osascript -e 'tell application "Contextify" to quit' 2>/dev/null || true
    # Wait up to 5 seconds for quit
    for i in $(seq 1 10); do
      if ! app_is_running; then
        break
      fi
      sleep 0.5
    done
    if app_is_running; then
      info "App did not quit gracefully, force killing..."
      pkill -x "Contextify" 2>/dev/null || true
      sleep 1
    fi
  fi
}

launch_app() {
  step "Launching Contextify (DMG build)..."
  open "$DMG_APP_PATH"
  sleep 2
  if app_is_running; then
    info "App is running."
  else
    info "Waiting for app to start..."
    sleep 3
  fi
}

set_pref() {
  local key="$1"
  local value="$2"
  defaults write "$DEFAULTS_DOMAIN" "$key" -bool "$value"
}

get_pref() {
  local key="$1"
  defaults read "$DEFAULTS_DOMAIN" "$key" 2>/dev/null || echo "unset"
}

check_dock_presence() {
  # Returns 0 if Contextify appears in the Dock (activation policy = regular)
  local policy
  policy=$(osascript -e '
    tell application "System Events"
      set dockApps to name of every process whose visible is true
      if "Contextify" is in dockApps then
        return "visible"
      else
        return "hidden"
      end if
    end tell
  ' 2>/dev/null || echo "error")
  if [ "$policy" = "visible" ]; then
    return 0
  else
    return 1
  fi
}

check_status_item_exists() {
  # Use AppleScript to check if a menu bar item for Contextify exists.
  # This is best-effort; menu bar extras are not always queryable via System Events.
  local result
  result=$(osascript -e '
    tell application "System Events"
      tell process "Contextify"
        try
          set menuBarItems to menu bar items of menu bar 2
          if (count of menuBarItems) > 0 then
            return "present"
          else
            return "absent"
          end if
        on error
          return "absent"
        end try
      end tell
    end tell
  ' 2>/dev/null || echo "error")
  if [ "$result" = "present" ]; then
    return 0
  else
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Initialize proof file
# ─────────────────────────────────────────────────────────────────────────────

cat > "$PROOF_FILE" << EOF
---
feature: menubar-background-mode
branch: $(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "unknown")
worktree: $REPO_ROOT
date: $(date +%Y-%m-%d)
generated: $(date -Iseconds)
tester: interactive
status: in-progress
---

# Menu Bar / Background Utility Mode - QA Proof

EOF

echo -e "${BOLD}Menu Bar / Background Utility Mode - Interactive QA${NC}"
echo "Proof file: $PROOF_FILE"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────────────────────────────────────────

header "Pre-Flight Checks"

step "Checking DMG build..."
if [ -d "$DMG_APP_PATH" ]; then
  pass "DMG build found at $DMG_APP_PATH"
else
  fail "DMG build not found. Run: bash scripts/xc.sh build"
  echo ""
  echo "Cannot proceed without a DMG build."
  exit 1
fi

step "Checking current preferences..."
MENU_BAR_PREF=$(get_pref "dev.contextify.menuBarExtraEnabled")
UTILITY_PREF=$(get_pref "dev.contextify.backgroundUtilityModeEnabled")
info "menuBarExtraEnabled = $MENU_BAR_PREF"
info "backgroundUtilityModeEnabled = $UTILITY_PREF"
echo "Current prefs: menuBarExtra=$MENU_BAR_PREF, backgroundUtility=$UTILITY_PREF" >> "$PROOF_FILE"
echo "" >> "$PROOF_FILE"

step "Quitting any running Contextify instance..."
quit_app

prompt_continue

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 1: Launch in normal mode (both prefs OFF)
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 1: Launch in Normal Mode"

step "Setting preferences: menuBarExtra=OFF, backgroundUtility=OFF"
set_pref "dev.contextify.menuBarExtraEnabled" false
set_pref "dev.contextify.backgroundUtilityModeEnabled" false

launch_app

echo ""
echo -e "${BOLD}OBSERVE the following:${NC}"
echo "  1. The main Contextify window should appear"
echo "  2. Contextify should appear in the Dock"
echo "  3. Contextify should appear in Command-Tab switcher"
echo "  4. No menu bar extra icon should be visible"
echo ""

if prompt_yn "Does the main window appear?"; then
  pass "S1: Main window appears in normal mode"
else
  fail "S1: Main window did NOT appear in normal mode"
fi

if prompt_yn "Does Contextify appear in the Dock?"; then
  pass "S1: Dock icon present in normal mode"
else
  fail "S1: Dock icon NOT present in normal mode"
fi

if prompt_yn "Is the menu bar extra icon ABSENT (no status item in menu bar)?"; then
  pass "S1: Menu bar extra correctly absent when disabled"
else
  fail "S1: Menu bar extra visible when it should be disabled"
fi

quit_app

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 2: Launch in utility (background) mode
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 2: Launch in Utility (Background) Mode"

step "Setting preferences: menuBarExtra=ON (forced), backgroundUtility=ON"
set_pref "dev.contextify.menuBarExtraEnabled" true
set_pref "dev.contextify.backgroundUtilityModeEnabled" true

launch_app

echo ""
echo -e "${BOLD}OBSERVE the following:${NC}"
echo "  1. The main Contextify window should NOT appear (no window flash)"
echo "  2. Contextify should NOT appear in the Dock"
echo "  3. Contextify should NOT appear in Command-Tab switcher"
echo "  4. A menu bar extra icon SHOULD be visible"
echo ""

if prompt_yn "Is the main window ABSENT (no window appeared or flashed)?"; then
  pass "S2: No window flash on utility mode launch"
else
  fail "S2: Window appeared or flashed on utility mode launch"
fi

if prompt_yn "Is Contextify ABSENT from the Dock?"; then
  pass "S2: No Dock presence in utility mode"
else
  fail "S2: Dock icon visible in utility mode (should be hidden)"
fi

if prompt_yn "Is the menu bar extra icon PRESENT?"; then
  pass "S2: Menu bar extra present in utility mode"
else
  fail "S2: Menu bar extra NOT present in utility mode"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 3: Close main window in utility mode - app stays reachable
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 3: Close Main Window in Utility Mode"

step "First, open the main window via menu bar extra..."
echo ""
echo -e "${BOLD}ACTION: Click the menu bar extra icon, then click 'Show Contextify'.${NC}"
echo "EXPECTED: The main window opens, Dock icon appears temporarily."
prompt_continue

if prompt_yn "Did the main window open?"; then
  pass "S3: Main window opened from menu bar extra"
else
  fail "S3: Main window did NOT open from menu bar extra"
fi

step "Now close the main window..."
echo ""
echo -e "${BOLD}ACTION: Close the main window (Cmd+W or click the red close button).${NC}"
echo "EXPECTED: Window closes, Dock icon disappears, menu bar extra remains."
prompt_continue

if prompt_yn "Did the Dock icon disappear after closing the window?"; then
  pass "S3: Dock icon removed after window close in utility mode"
else
  fail "S3: Dock icon persisted after window close in utility mode"
fi

if prompt_yn "Is the menu bar extra still present?"; then
  pass "S3: Menu bar extra still present after window close"
else
  fail "S3: Menu bar extra disappeared after window close"
fi

if prompt_yn "Is the app still running (not quit)?"; then
  pass "S3: App remains running after window close in utility mode"
else
  fail "S3: App quit when window was closed in utility mode"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 4: Reopen main window from menu bar in utility mode
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 4: Reopen Main Window from Menu Bar"

echo -e "${BOLD}ACTION: Click the menu bar extra icon, then click 'Show Contextify'.${NC}"
echo "EXPECTED: The main window reappears, app activates (comes to front), Dock icon appears."
prompt_continue

if prompt_yn "Did the main window reappear and come to the front?"; then
  pass "S4: Main window reopened from menu bar extra"
else
  fail "S4: Main window did NOT reopen from menu bar extra"
fi

if prompt_yn "Did the Dock icon reappear?"; then
  pass "S4: Dock icon reappeared when window opened"
else
  fail "S4: Dock icon did NOT reappear when window opened"
fi

quit_app

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 5: Quit/relaunch with utility mode enabled
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 5: Quit and Relaunch with Utility Mode"

if [ "$SKIP_RELAUNCH" = true ]; then
  skip "S5: Skipped (--skip-relaunch flag)"
else
  step "Verifying prefs are still set for utility mode..."
  UTILITY_PREF_NOW=$(get_pref "dev.contextify.backgroundUtilityModeEnabled")
  info "backgroundUtilityModeEnabled = $UTILITY_PREF_NOW"

  step "Relaunching app..."
  launch_app

  echo ""
  echo -e "${BOLD}OBSERVE:${NC}"
  echo "  1. Main window should NOT appear after relaunch"
  echo "  2. No Dock presence"
  echo "  3. Menu bar extra should be present"
  echo ""

  if prompt_yn "Is the main window ABSENT after relaunch?"; then
    pass "S5: No main window on relaunch with utility mode"
  else
    fail "S5: Main window appeared on relaunch with utility mode"
  fi

  if prompt_yn "Is the Dock icon ABSENT?"; then
    pass "S5: No Dock presence on relaunch with utility mode"
  else
    fail "S5: Dock icon visible on relaunch with utility mode"
  fi

  if prompt_yn "Is the menu bar extra PRESENT?"; then
    pass "S5: Menu bar extra present after relaunch"
  else
    fail "S5: Menu bar extra NOT present after relaunch"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 6: Toggle utility mode ON while app is running
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 6: Toggle Utility Mode ON While Running"

step "Ensuring app is running in normal mode..."
quit_app
set_pref "dev.contextify.menuBarExtraEnabled" false
set_pref "dev.contextify.backgroundUtilityModeEnabled" false
launch_app

echo ""
echo -e "${BOLD}ACTION:${NC}"
echo "  1. Open Settings (Cmd+,)"
echo "  2. Go to the General tab"
echo "  3. Turn ON 'Run as background utility'"
echo ""
echo -e "EXPECTED: Dock icon should disappear. Menu bar extra should appear."
echo "  The main window should remain visible (it is already open)."
prompt_continue

if prompt_yn "Did the menu bar extra icon appear?"; then
  pass "S6: Menu bar extra appeared when enabling utility mode at runtime"
else
  fail "S6: Menu bar extra did NOT appear when enabling utility mode"
fi

if prompt_yn "Is the main window still visible?"; then
  pass "S6: Main window persisted during mode transition"
else
  fail "S6: Main window disappeared during mode transition"
fi

echo ""
step "Now close all windows (Cmd+W on main window, close Settings)."
prompt_continue

if prompt_yn "After closing windows, did the Dock icon disappear?"; then
  pass "S6: Dock icon removed after closing windows in utility mode"
else
  fail "S6: Dock icon persisted after closing windows in utility mode"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 7: Toggle utility mode OFF while app is running
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 7: Toggle Utility Mode OFF While Running"

echo -e "${BOLD}ACTION:${NC}"
echo "  1. Click the menu bar extra, choose 'Settings' (or 'Show Contextify' then Cmd+,)"
echo "  2. Go to the General tab"
echo "  3. Turn OFF 'Run as background utility'"
echo ""
echo "EXPECTED: Dock icon should reappear. Menu bar extra may remain or disappear"
echo "  depending on its independent toggle state."
prompt_continue

if prompt_yn "Did the Dock icon reappear?"; then
  pass "S7: Dock icon returned when disabling utility mode"
else
  fail "S7: Dock icon did NOT return when disabling utility mode"
fi

if prompt_yn "Does the Command-Tab switcher show Contextify?"; then
  pass "S7: Command-Tab presence restored"
else
  fail "S7: Command-Tab presence NOT restored"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 8: Toggle menu bar extra ON/OFF independently
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 8: Toggle Menu Bar Extra ON/OFF"

step "Ensure utility mode is OFF and menu bar extra is OFF..."
echo ""
echo -e "${BOLD}ACTION:${NC}"
echo "  1. In Settings > General, ensure 'Run as background utility' is OFF"
echo "  2. Turn ON 'Show menu bar extra'"
echo ""
echo "EXPECTED: Menu bar extra icon appears in the menu bar."
prompt_continue

if prompt_yn "Did the menu bar extra icon appear?"; then
  pass "S8a: Menu bar extra appeared when toggled on"
else
  fail "S8a: Menu bar extra did NOT appear when toggled on"
fi

echo ""
echo -e "${BOLD}ACTION: Turn OFF 'Show menu bar extra'.${NC}"
echo "EXPECTED: Menu bar extra icon disappears from the menu bar."
prompt_continue

if prompt_yn "Did the menu bar extra icon disappear?"; then
  pass "S8b: Menu bar extra disappeared when toggled off"
else
  fail "S8b: Menu bar extra did NOT disappear when toggled off"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 9: Open auxiliary windows from popover in utility mode
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 9: Open Settings from Popover (Utility Mode)"

step "Switching to utility mode..."
echo ""
echo -e "${BOLD}ACTION:${NC}"
echo "  1. In Settings > General, turn ON 'Run as background utility'"
echo "  2. Close all windows"
echo "  3. Click the menu bar extra"
echo ""
prompt_continue

echo -e "${BOLD}ACTION: From the popover, click 'Settings'.${NC}"
echo "EXPECTED: Settings window opens, app activates, Dock icon appears, popover closes."
prompt_continue

if prompt_yn "Did the Settings window open and the app come to the front?"; then
  pass "S9a: Settings window opened from popover in utility mode"
else
  fail "S9a: Settings window did NOT open from popover"
fi

if prompt_yn "Did the popover close automatically after clicking Settings?"; then
  pass "S9b: Popover dismissed automatically after action"
else
  fail "S9b: Popover remained open after Settings action"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 10: Popover dismiss behavior
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 10: Popover Behavior"

echo "Close any open windows."
prompt_continue

echo -e "${BOLD}ACTION: Click the menu bar extra to open the popover.${NC}"
echo "EXPECTED: Popover appears below the menu bar icon."
prompt_continue

if prompt_yn "Did the popover appear?"; then
  pass "S10a: Popover opens on click"
else
  fail "S10a: Popover did NOT open on click"
fi

echo -e "${BOLD}ACTION: Click somewhere outside the popover (e.g., the Desktop).${NC}"
echo "EXPECTED: Popover dismisses."
prompt_continue

if prompt_yn "Did the popover dismiss when clicking outside?"; then
  pass "S10b: Popover dismisses on outside click"
else
  fail "S10b: Popover did NOT dismiss on outside click"
fi

echo -e "${BOLD}ACTION: Click the menu bar extra to open the popover again, then click it again.${NC}"
echo "EXPECTED: Popover toggles (opens then closes)."
prompt_continue

if prompt_yn "Did the popover toggle correctly?"; then
  pass "S10c: Popover toggles on repeated clicks"
else
  fail "S10c: Popover did NOT toggle correctly"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 11: Activation policy – Settings close while main window visible
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 11: Close Settings While Main Window Still Open (Utility Mode)"

echo ""
echo -e "${BOLD}ACTION:${NC}"
echo "  1. Ensure utility mode is ON and the main window is visible"
echo "  2. Open Settings (Cmd+, or from menu bar popover)"
echo "  3. Close Settings (Cmd+W)"
echo ""
echo "EXPECTED: Dock icon remains while the main window is still visible."
echo "  The Dock icon should NOT disappear until the main window is also closed."
prompt_continue

if prompt_yn "Does the Dock icon persist after closing Settings (while main window is still open)?"; then
  pass "S11: Dock icon not removed when only Settings is closed (main window still visible)"
else
  fail "S11: Dock icon incorrectly disappeared when Settings closed (main window still open)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Scenario 12: Keep on Top window level ordering
# ─────────────────────────────────────────────────────────────────────────────

header "Scenario 12: Keep on Top + Settings Elevation"

echo "Ensure main window is open and app is in normal mode."
quit_app
set_pref "dev.contextify.menuBarExtraEnabled" false
set_pref "dev.contextify.backgroundUtilityModeEnabled" false
launch_app
prompt_continue

echo -e "${BOLD}ACTION:${NC}"
echo "  1. In the menu bar, choose Window > Keep on Top (or use the menu item)"
echo "  2. The main window should float above all other windows"
prompt_continue

if prompt_yn "Does the main window float above other app windows after enabling Keep on Top?"; then
  pass "S12a: Keep on Top makes window float above others"
else
  fail "S12a: Keep on Top did NOT make window float"
fi

echo ""
echo -e "${BOLD}ACTION: Open Settings (Cmd+,) while Keep on Top is active.${NC}"
echo "EXPECTED: Settings window should appear ABOVE the floating main window, not behind it."
prompt_continue

if prompt_yn "Does the Settings window appear above (in front of) the floating main window?"; then
  pass "S12b: Settings window appears above floating main window"
else
  fail "S12b: Settings window appeared BEHIND the floating main window"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────────────

header "Cleanup"

step "Restoring default preferences..."
set_pref "dev.contextify.menuBarExtraEnabled" false
set_pref "dev.contextify.backgroundUtilityModeEnabled" false

quit_app
pass "Preferences restored to defaults and app quit"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

header "QA Summary"

cat >> "$PROOF_FILE" << EOF

---

## Summary

| Metric | Count |
|--------|-------|
| Passed | $PASS_COUNT |
| Failed | $FAIL_COUNT |
| Skipped | $SKIP_COUNT |
| Total | $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT)) |

EOF

echo -e "${BOLD}Results:${NC}"
echo -e "  ${GREEN}Passed:  $PASS_COUNT${NC}"
echo -e "  ${RED}Failed:  $FAIL_COUNT${NC}"
echo -e "  ${YELLOW}Skipped: $SKIP_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
  echo "**Result: ALL TESTS PASSED**" >> "$PROOF_FILE"
  echo -e "${GREEN}${BOLD}ALL TESTS PASSED${NC}"
  RESULT="PASS"
else
  echo "**Result: $FAIL_COUNT TEST(S) FAILED**" >> "$PROOF_FILE"
  echo -e "${RED}${BOLD}$FAIL_COUNT TEST(S) FAILED${NC}"
  RESULT="FAIL"
fi

echo ""
echo -e "${BOLD}Proof file:${NC} $PROOF_FILE"
echo ""
echo "Done."

if [ "$RESULT" = "FAIL" ]; then
  exit 1
fi
