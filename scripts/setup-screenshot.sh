#!/bin/bash
# Setup windows for Contextify screenshots
# Positions Terminal and Contextify for optimal screenshot composition
# within App Store screenshot dimensions

set -e

echo "Setting up windows for screenshot..."

# Get screen dimensions
SCREEN_WIDTH=$(system_profiler SPDisplaysDataType | grep Resolution | awk '{print $2}' | head -1)
SCREEN_HEIGHT=$(system_profiler SPDisplaysDataType | grep Resolution | awk '{print $4}' | head -1)

echo "Screen resolution: ${SCREEN_WIDTH}x${SCREEN_HEIGHT}"

# Target screenshot size (App Store requirement)
SHOT_WIDTH=1440
SHOT_HEIGHT=900

# Position the capture area in upper-left region (easier to see)
# Leave room at top for Terminal title bar (starts at Y=50)
CAPTURE_X=200
CAPTURE_Y=50

# Terminal: Left side within capture area, vertically centered
TERMINAL_WIDTH=800
TERMINAL_HEIGHT=850
TERMINAL_X=$((CAPTURE_X + 10))
TERMINAL_Y=$((CAPTURE_Y + 25))  # Vertically centered: (900 - 850) / 2 = 25

# Contextify: Right side within capture area, vertically centered
CONTEXTIFY_WIDTH=580
CONTEXTIFY_HEIGHT=700
CONTEXTIFY_X=$((CAPTURE_X + 830))  # 10px gap between windows
CONTEXTIFY_Y=$((CAPTURE_Y + 100))  # Vertically centered: (900 - 700) / 2 = 100

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
echo "Screenshot area: ${SHOT_WIDTH}x${SHOT_HEIGHT} centered at (${CAPTURE_X}, ${CAPTURE_Y})"
echo "Terminal:        ${TERMINAL_WIDTH}x${TERMINAL_HEIGHT} at (${TERMINAL_X}, ${TERMINAL_Y})"
echo "Contextify:      ${CONTEXTIFY_WIDTH}x${CONTEXTIFY_HEIGHT} at (${CONTEXTIFY_X}, ${CONTEXTIFY_Y})"
echo ""
echo "Ready for screenshot!"
echo "Press Cmd+Shift+4, then drag to select the ${SHOT_WIDTH}x${SHOT_HEIGHT} area containing both windows."
echo "Or use ./scripts/capture-screenshot.sh to auto-capture the region."
