#!/bin/bash
# Setup windows for Contextify screenshots
# Positions Terminal and Contextify for optimal screenshot composition

set -e

echo "Setting up windows for screenshot..."

# Get screen dimensions
SCREEN_WIDTH=$(system_profiler SPDisplaysDataType | grep Resolution | awk '{print $2}' | head -1)
SCREEN_HEIGHT=$(system_profiler SPDisplaysDataType | grep Resolution | awk '{print $4}' | head -1)

echo "Screen resolution: ${SCREEN_WIDTH}x${SCREEN_HEIGHT}"

# Calculate positions
# Terminal: Left side, 60% width
TERMINAL_WIDTH=$((SCREEN_WIDTH * 6 / 10))
TERMINAL_HEIGHT=$((SCREEN_HEIGHT - 100))
TERMINAL_X=20
TERMINAL_Y=50

# Contextify: Right side, smaller HUD
CONTEXTIFY_WIDTH=600
CONTEXTIFY_HEIGHT=700
CONTEXTIFY_X=$((SCREEN_WIDTH - CONTEXTIFY_WIDTH - 40))
CONTEXTIFY_Y=80

# Position Terminal (create window if none exists)
osascript <<EOF
tell application "Terminal"
    activate
    if (count of windows) is 0 then
        do script ""
        delay 0.5
    end if
    set position of front window to {$TERMINAL_X, $TERMINAL_Y}
    set size of front window to {$TERMINAL_WIDTH, $TERMINAL_HEIGHT}
end tell
EOF

sleep 0.5

# Position Contextify
osascript <<EOF
tell application "Contextify"
    activate
    delay 0.3
end tell

tell application "System Events"
    tell process "Contextify"
        set position of window 1 to {$CONTEXTIFY_X, $CONTEXTIFY_Y}
        set size of window 1 to {$CONTEXTIFY_WIDTH, $CONTEXTIFY_HEIGHT}
    end tell
end tell
EOF

echo "✅ Windows positioned!"
echo ""
echo "Terminal:   ${TERMINAL_WIDTH}x${TERMINAL_HEIGHT} at (${TERMINAL_X}, ${TERMINAL_Y})"
echo "Contextify: ${CONTEXTIFY_WIDTH}x${CONTEXTIFY_HEIGHT} at (${CONTEXTIFY_X}, ${CONTEXTIFY_Y})"
echo ""
echo "Ready for screenshot! Press Cmd+Shift+3 for full screen or Cmd+Shift+4 to select area."
