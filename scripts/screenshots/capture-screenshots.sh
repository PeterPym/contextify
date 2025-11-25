#!/bin/bash
# Capture App Store screenshots
# Orchestrates the full workflow for capturing screenshots 1 and 2
#
# Usage: ./capture-screenshots.sh [options] [window-number]
#   --from=N    Start from screenshot N (1 or 2)
#   If window-number not provided, lists windows and prompts for selection

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
START_FROM=1
WINDOW_NUM=""

# Parse arguments
for arg in "$@"; do
  case $arg in
    --from=*)
      START_FROM="${arg#*=}"
      ;;
    *)
      if [[ "$arg" =~ ^[0-9]+$ ]]; then
        WINDOW_NUM="$arg"
      fi
      ;;
  esac
done

echo "╭────────────────────────────────────────────╮"
echo "│  App Store Screenshot Capture              │"
echo "╰────────────────────────────────────────────╯"
echo ""

# Step 0: Get window number if not provided
if [ -z "$WINDOW_NUM" ]; then
  echo "Available iTerm windows:"
  echo ""
  "$SCRIPT_DIR/list-iterm-windows.sh"
  echo ""
  read -p "Enter window number for screenshot terminal: " WINDOW_NUM
  if [ -z "$WINDOW_NUM" ]; then
    echo "No window number provided"
    exit 1
  fi
fi

echo "Using iTerm window #$WINDOW_NUM"
echo "Starting from screenshot $START_FROM"
echo ""

# ============================================================================
# SCREENSHOT 1: Hero Shot (Main HUD)
# ============================================================================
capture_screenshot_1() {
  echo ""
  echo "════════════════════════════════════════════════════════════════════"
  echo "  SCREENSHOT 1: Hero Shot - Main HUD"
  echo "════════════════════════════════════════════════════════════════════"
  echo ""

  # Seed demo data
  echo "Step 1.1: Seeding demo data..."
  "$SCRIPT_DIR/setup-screenshot.sh" --seed-demo
  sleep 1

  # Restart Contextify
  echo ""
  echo "Step 1.2: Restart Contextify"
  echo "  Press Enter to quit and relaunch Contextify..."
  read -p ""

  osascript -e 'tell application "Contextify" to quit' 2>/dev/null || true
  sleep 1
  open "$SCRIPT_DIR/../../.derived/Build/Products/Debug/Contextify.app"
  sleep 2

  read -p "Press Enter when demo entries are visible in timeline..."
  echo ""

  # Start fake claude session
  echo "Step 1.3: Starting fake Claude session..."
  osascript <<EOF
tell application "iTerm2"
    tell window $WINDOW_NUM
        tell current session
            write text "cd '$SCRIPT_DIR' && ./fake-claude-session.sh"
        end tell
    end tell
end tell
EOF
  sleep 2

  # Position windows
  echo "Step 1.4: Positioning windows..."
  "$SCRIPT_DIR/setup-screenshot.sh" "$WINDOW_NUM"
  sleep 1

  # Capture screenshot
  echo "Step 1.5: Capturing screenshot..."
  "$SCRIPT_DIR/capture-screenshot.sh" 01-main-hud "$WINDOW_NUM"
  sleep 1

  # Kill fake session
  osascript <<EOF
tell application "iTerm2"
    tell window $WINDOW_NUM
        tell current session
            write text (ASCII character 3)
        end tell
    end tell
end tell
EOF
  sleep 1

  # Cleanup demo entries
  echo "Step 1.6: Cleaning up demo entries..."
  "$SCRIPT_DIR/setup-screenshot.sh" --cleanup-demo

  echo ""
  echo "Screenshot 1 complete!"
}

# ============================================================================
# SCREENSHOT 2: Dual Provider (Claude Code + Codex)
# ============================================================================
capture_screenshot_2() {
  echo ""
  echo "════════════════════════════════════════════════════════════════════"
  echo "  SCREENSHOT 2: Dual Provider - Claude Code + Codex"
  echo "════════════════════════════════════════════════════════════════════"
  echo ""

  # Seed mixed demo data
  echo "Step 2.1: Seeding mixed provider demo data..."
  "$SCRIPT_DIR/setup-screenshot.sh" --seed-mixed
  sleep 1

  # Restart Contextify
  echo ""
  echo "Step 2.2: Restart Contextify"
  echo "  Press Enter to quit and relaunch Contextify..."
  read -p ""

  osascript -e 'tell application "Contextify" to quit' 2>/dev/null || true
  sleep 1
  open "$SCRIPT_DIR/../../.derived/Build/Products/Debug/Contextify.app"
  sleep 2

  read -p "Press Enter when mixed provider entries are visible (look for Codex icon)..."
  echo ""

  # Start dual fake session (creates two tabs)
  echo "Step 2.3: Setting up dual-provider terminal (two tabs)..."
  "$SCRIPT_DIR/fake-dual-session.sh" "$WINDOW_NUM"
  sleep 2

  # Position windows
  echo "Step 2.4: Positioning windows..."
  "$SCRIPT_DIR/setup-screenshot.sh" "$WINDOW_NUM"
  sleep 1

  # Capture screenshot
  echo "Step 2.5: Capturing screenshot..."
  "$SCRIPT_DIR/capture-screenshot.sh" 02-dual-provider "$WINDOW_NUM"
  sleep 1

  # Kill fake sessions in both tabs
  osascript <<EOF
tell application "iTerm2"
    tell window $WINDOW_NUM
        -- Kill tab 1
        tell tab 1
            tell current session
                write text (ASCII character 3)
            end tell
        end tell
        -- Kill tab 2 if it exists
        if (count of tabs) > 1 then
            tell tab 2
                tell current session
                    write text (ASCII character 3)
                end tell
            end tell
            -- Close tab 2
            tell tab 2
                close
            end tell
        end if
    end tell
end tell
EOF
  sleep 1

  # Cleanup demo entries
  echo "Step 2.6: Cleaning up demo entries..."
  "$SCRIPT_DIR/setup-screenshot.sh" --cleanup-demo

  echo ""
  echo "Screenshot 2 complete!"
}

# ============================================================================
# Main execution
# ============================================================================

if [ "$START_FROM" -le 1 ]; then
  capture_screenshot_1

  echo ""
  read -p "Press Enter to continue to Screenshot 2, or Ctrl+C to stop..."
fi

if [ "$START_FROM" -le 2 ]; then
  capture_screenshot_2
fi

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "  All screenshots complete!"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Screenshots saved to: appstore-metadata/screenshots/drafts/"
echo ""
echo "Review and copy to final/ when ready:"
echo "  cp appstore-metadata/screenshots/drafts/01-main-hud-*.png \\"
echo "     appstore-metadata/screenshots/final/"
echo "  cp appstore-metadata/screenshots/drafts/02-dual-provider-*.png \\"
echo "     appstore-metadata/screenshots/final/"
