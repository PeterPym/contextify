#!/bin/bash
# Setup windows for Contextify screenshots
# Positions Terminal and Contextify for optimal screenshot composition
# within App Store screenshot dimensions
#
# Usage: ./setup-screenshot.sh [window-number]
#   window-number: Optional. iTerm2 window index (1, 2, 3, etc.)
#                 If omitted, uses current window after 3-second countdown.

set -e

WINDOW_INDEX="${1:-}"

echo "Setting up windows for screenshot..."
echo ""

# Save original window positions to temp file for restoration
POSITIONS_FILE="/tmp/contextify-screenshot-positions.txt"
rm -f "$POSITIONS_FILE"

echo "💾 Saving original window positions..."

# Save Contextify window position
osascript <<EOF > /dev/null 2>&1
tell application "System Events"
    tell process "Contextify"
        if (count of windows) > 0 then
            set pos to position of window 1
            set sz to size of window 1
            do shell script "echo 'CONTEXTIFY_X=" & (item 1 of pos) & "' >> $POSITIONS_FILE"
            do shell script "echo 'CONTEXTIFY_Y=" & (item 2 of pos) & "' >> $POSITIONS_FILE"
            do shell script "echo 'CONTEXTIFY_W=" & (item 1 of sz) & "' >> $POSITIONS_FILE"
            do shell script "echo 'CONTEXTIFY_H=" & (item 2 of sz) & "' >> $POSITIONS_FILE"
        end if
    end tell
end tell
EOF

if [ -n "$WINDOW_INDEX" ]; then
    echo "🔍 Using iTerm2 window #$WINDOW_INDEX"
    # Save specified iTerm2 window position
    osascript <<EOF > /dev/null 2>&1
tell application "iTerm2"
    if (count of windows) >= $WINDOW_INDEX then
        tell window $WINDOW_INDEX
            set bnds to bounds
            do shell script "echo 'ITERM_INDEX=$WINDOW_INDEX' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_X=" & (item 1 of bnds) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_Y=" & (item 2 of bnds) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_W=" & ((item 3 of bnds) - (item 1 of bnds)) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_H=" & ((item 4 of bnds) - (item 2 of bnds)) & "' >> $POSITIONS_FILE"
        end tell
    end if
end tell
EOF
else
    echo "⏱️  You have 3 seconds to click on the iTerm2 window you want to use..."
    echo "   (The frontmost iTerm2 window will be positioned)"
    echo ""

    # Countdown to let user select the correct iTerm2 window
    for i in 3 2 1; do
        echo "   $i..."
        sleep 1
    done

    # Save current iTerm2 window position
    osascript <<EOF > /dev/null 2>&1
tell application "iTerm2"
    if (count of windows) > 0 then
        tell current window
            set bnds to bounds
            set idx to index
            do shell script "echo 'ITERM_INDEX=" & idx & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_X=" & (item 1 of bnds) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_Y=" & (item 2 of bnds) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_W=" & ((item 3 of bnds) - (item 1 of bnds)) & "' >> $POSITIONS_FILE"
            do shell script "echo 'ITERM_H=" & ((item 4 of bnds) - (item 2 of bnds)) & "' >> $POSITIONS_FILE"
        end tell
    end if
end tell
EOF
fi

echo ""
echo "Positioning windows..."

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

# Window dimensions and positions (Apple marketing style: compact HUD + context)
# 15% larger than original, centered with equal left/right padding
# Contextify: Compact HUD design (~483px wide, stays out of the way)
CONTEXTIFY_WIDTH=483
CONTEXTIFY_HEIGHT=633
CONTEXTIFY_X=337
CONTEXTIFY_Y=277

# iTerm2: Terminal for context (shows real development workflow)
# Positioned with 50px gap, bottoms aligned at Y=910, centered in 1440px frame
TERMINAL_WIDTH=633
TERMINAL_HEIGHT=460
TERMINAL_X=870
TERMINAL_Y=450

# OLD DIMENSIONS (split-screen style, equal emphasis):
# CONTEXTIFY_WIDTH=580
# CONTEXTIFY_HEIGHT=700
# CONTEXTIFY_X=$((CAPTURE_X + 10))  # 210
# CONTEXTIFY_Y=$((CAPTURE_Y + 100))  # 150
# TERMINAL_WIDTH=800
# TERMINAL_HEIGHT=850
# TERMINAL_X=$((CAPTURE_X + 610))  # 810
# TERMINAL_Y=$((CAPTURE_Y + 25))  # 75

# Position Contextify first (on the left, showcasing the app!)
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

sleep 0.5

# Position iTerm2 (uses specified window or current window)
if [ -n "$WINDOW_INDEX" ]; then
    # Use specified window index
    osascript <<EOF
tell application "iTerm2"
    if (count of windows) < $WINDOW_INDEX then
        error "iTerm2 window #$WINDOW_INDEX not found. Only " & (count of windows) & " windows available."
    end if
    tell window $WINDOW_INDEX
        set bounds to {$TERMINAL_X, $TERMINAL_Y, $TERMINAL_X + $TERMINAL_WIDTH, $TERMINAL_Y + $TERMINAL_HEIGHT}
    end tell
end tell
EOF
else
    # Use current window (user selected during countdown)
    osascript <<EOF
tell application "iTerm2"
    if (count of windows) is 0 then
        activate
        create window with default profile
        delay 0.5
    end if
    tell current window
        set bounds to {$TERMINAL_X, $TERMINAL_Y, $TERMINAL_X + $TERMINAL_WIDTH, $TERMINAL_Y + $TERMINAL_HEIGHT}
    end tell
end tell
EOF
fi

echo "✅ Windows positioned!"
echo ""
echo "Screenshot area: ${SHOT_WIDTH}x${SHOT_HEIGHT} at (${CAPTURE_X}, ${CAPTURE_Y})"
echo "Contextify (L):  ${CONTEXTIFY_WIDTH}x${CONTEXTIFY_HEIGHT} at (${CONTEXTIFY_X}, ${CONTEXTIFY_Y})"
echo "iTerm2 (R):      ${TERMINAL_WIDTH}x${TERMINAL_HEIGHT} at (${TERMINAL_X}, ${TERMINAL_Y})"
echo ""
echo "Ready for screenshot!"
echo "Press Cmd+Shift+4, then drag to select the ${SHOT_WIDTH}x${SHOT_HEIGHT} area containing both windows."
echo "Or use ./scripts/capture-screenshot.sh to auto-capture the region."
