#!/bin/bash
# Capture Screenshot 01: Hero Shot
# Orchestrates the full workflow for capturing the main HUD screenshot
#
# Usage: ./capture-hero-shot.sh [window-number]
#   If window-number not provided, lists windows and prompts for selection

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WINDOW_NUM="${1:-}"

echo "╭────────────────────────────────────────────╮"
echo "│  Screenshot 01: Hero Shot                  │"
echo "╰────────────────────────────────────────────╯"
echo ""

# Step 0: Get window number if not provided
if [ -z "$WINDOW_NUM" ]; then
  echo "📋 Available iTerm windows:"
  echo ""
  "$SCRIPT_DIR/list-iterm-windows.sh"
  echo ""
  read -p "Enter window number for screenshot terminal: " WINDOW_NUM
  if [ -z "$WINDOW_NUM" ]; then
    echo "❌ No window number provided"
    exit 1
  fi
fi

echo ""
echo "Using iTerm window #$WINDOW_NUM"
echo ""

# Step 1: Seed demo data
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Seeding demo data..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPT_DIR/setup-screenshot.sh" --seed-demo
sleep 1

# Step 2: Restart Contextify
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Restart Contextify"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  1. Quit Contextify (Cmd+Q)"
echo "  2. Press Enter to relaunch"
echo "  3. Select the 'contextify' project"
echo ""
read -p "Press Enter to launch Contextify..."

# Kill existing Contextify and relaunch
osascript -e 'tell application "Contextify" to quit' 2>/dev/null || true
sleep 1
open "$SCRIPT_DIR/../../.derived/Build/Products/Debug/Contextify.app"
sleep 2

read -p "Press Enter when demo entries are visible in timeline..."
echo ""

# Step 3: Start fake claude session in the target terminal
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Starting fake Claude session in window #$WINDOW_NUM"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Run the fake session in the specified iTerm window
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

# Step 4: Position windows
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Positioning windows..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPT_DIR/setup-screenshot.sh" "$WINDOW_NUM"
sleep 1

# Step 5: Capture screenshot
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Capturing screenshot..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPT_DIR/capture-screenshot.sh" 01-main-hud "$WINDOW_NUM"
sleep 1

# Step 6: Cleanup
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 6: Cleaning up..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Kill the fake session
osascript <<EOF
tell application "iTerm2"
    tell window $WINDOW_NUM
        tell current session
            write text ""
        end tell
    end tell
end tell
EOF

# Send Ctrl+C to stop the fake session
osascript <<EOF
tell application "iTerm2"
    tell window $WINDOW_NUM
        tell current session
            -- Send Ctrl+C
            write text (ASCII character 3)
        end tell
    end tell
end tell
EOF

sleep 1

"$SCRIPT_DIR/setup-screenshot.sh" --cleanup-demo

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Done! Screenshot saved to drafts/"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Review the screenshot and copy to final/ when ready:"
echo "  cp appstore-metadata/screenshots/drafts/01-main-hud-*.png \\"
echo "     appstore-metadata/screenshots/final/"
