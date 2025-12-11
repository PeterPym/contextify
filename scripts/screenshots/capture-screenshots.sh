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
  echo "Step 1.2: Restarting Contextify..."
  osascript -e 'tell application "Contextify" to quit' 2>/dev/null || true
  sleep 1
  open "$SCRIPT_DIR/../../.derived-dmg/Build/Products/Debug/Contextify.app"
  sleep 2

  # Return focus to terminal for user input
  osascript -e 'tell application "iTerm2" to activate' 2>/dev/null || osascript -e 'tell application "Terminal" to activate' 2>/dev/null || true
  sleep 0.3

  read -p "Press Enter when demo entries are visible and summarized in timeline..."
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

  # Capture screenshot (uses preset for consistent text overlay)
  # Note: capture-screenshot.sh will handle window positioning
  echo "Step 1.4: Capturing screenshot..."
  "$SCRIPT_DIR/capture-preset.sh" main-hud "$WINDOW_NUM"
  sleep 1

  # Kill fake session
  echo "Step 1.5: Cleaning up fake session..."
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
  echo "Step 2.2: Restarting Contextify..."
  osascript -e 'tell application "Contextify" to quit' 2>/dev/null || true
  sleep 1
  open "$SCRIPT_DIR/../../.derived-dmg/Build/Products/Debug/Contextify.app"
  sleep 2

  # Return focus to terminal for user input
  osascript -e 'tell application "iTerm2" to activate' 2>/dev/null || osascript -e 'tell application "Terminal" to activate' 2>/dev/null || true
  sleep 0.3

  read -p "Press Enter when mixed provider entries are visible and summarized (look for Codex icon)..."
  echo ""

  # Manual setup for dual-provider tabs (automation wasn't reliable)
  echo ""
  echo "Step 2.3: Manual setup for dual-provider terminal..."
  echo "  IMPORTANT: Follow this order to ensure correct window positioning:"
  echo ""
  echo "  1. In iTerm window #$WINDOW_NUM, tab 1:"
  echo "     cd '$SCRIPT_DIR' && ./fake-claude-session.sh --mixed-claude"
  echo ""
  echo "  2. Position windows manually (BEFORE creating tab 2):"
  echo "     - Contextify: Left side, compact HUD"
  echo "     - iTerm window #$WINDOW_NUM: Right side, showing full terminal content"
  echo "     - Make sure terminal is tall enough to show all content"
  echo ""
  echo "  3. Create tab 2 (Codex) in iTerm window #$WINDOW_NUM:"
  echo "     - Create new tab (⌘T)"
  echo "     - cd '$SCRIPT_DIR' && ./fake-claude-session.sh --mixed-codex"
  echo "     - Switch back to tab 1 (⌘1)"
  echo ""

  # Return focus to terminal for user input
  osascript -e 'tell application "iTerm2" to activate' 2>/dev/null || osascript -e 'tell application "Terminal" to activate' 2>/dev/null || true
  sleep 0.3

  read -p "Press Enter when both tabs are ready and windows are positioned..."
  echo ""

  # Capture screenshot (uses preset for consistent text overlay)
  # Note: Windows already positioned in step 2.3, just need to capture
  echo "Step 2.4: Capturing screenshot..."

  # Give focus to Contextify before capture
  osascript -e 'tell application "Contextify" to activate' > /dev/null 2>&1
  sleep 0.5

  # Capture with the already-positioned windows
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  OUTPUT_DIR="appstore-metadata/screenshots/drafts"
  mkdir -p "$OUTPUT_DIR"
  FILENAME="${OUTPUT_DIR}/02-dual-provider-${TIMESTAMP}.png"

  echo ""
  echo "📸 Taking screenshot in 3 seconds..."
  sleep 3

  # Capture region (1440x900 at 200,50)
  screencapture -x -R"200,50,1440,900" "$FILENAME"
  afplay /System/Library/Sounds/Glass.aiff &

  # Add text overlay
  FINAL_FILENAME="${OUTPUT_DIR}/02-dual-provider-${TIMESTAMP}-with-text.png"
  NO_AUTO_OPEN=1 "$SCRIPT_DIR/add-text-overlay.sh" "$FILENAME" "Works seamlessly with both Claude Code and Codex CLI" "$FINAL_FILENAME" > /dev/null

  echo "✅ Screenshot saved: $FINAL_FILENAME"

  # Open in positioned Preview window
  open "$FINAL_FILENAME"
  sleep 0.5
  osascript <<'PREVIEW_EOF'
tell application "Preview"
    activate
end tell
delay 0.3

tell application "System Events"
    tell process "Preview"
        set frontmost to true
        if (count of windows) > 0 then
            tell front window
                set position to {2040, 100}
                set size to {1000, 900}
            end tell
        end if
    end tell
end tell
PREVIEW_EOF

  sleep 1

  # Kill fake sessions in both tabs
  echo "Step 2.5: Cleaning up fake sessions..."
  osascript <<EOF
tell application "iTerm2"
    activate
    delay 0.3

    tell window $WINDOW_NUM
        select
        delay 0.3

        -- Kill tab 1 (Claude Code)
        select tab 1
        delay 0.2
        tell tab 1
            tell current session
                write text (ASCII character 3)
            end tell
        end tell

        -- Kill tab 2 if it exists (Codex)
        if (count of tabs) > 1 then
            select tab 2
            delay 0.2
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
