#!/bin/bash
# Restore windows to their original positions after screenshot
# Reads positions saved by setup-screenshot.sh

set -e

POSITIONS_FILE="/tmp/contextify-screenshot-positions.txt"

if [ ! -f "$POSITIONS_FILE" ]; then
    echo "⚠️  No saved window positions found (expected at $POSITIONS_FILE)"
    echo "   Windows may not have been positioned by setup-screenshot.sh"
    exit 0
fi

echo "🔄 Restoring windows to original positions..."

# Load saved positions
source "$POSITIONS_FILE"

# Restore Contextify window
if [ -n "$CONTEXTIFY_X" ]; then
    osascript <<EOF > /dev/null 2>&1
tell application "System Events"
    tell process "Contextify"
        if (count of windows) > 0 then
            set position of window 1 to {$CONTEXTIFY_X, $CONTEXTIFY_Y}
            set size of window 1 to {$CONTEXTIFY_W, $CONTEXTIFY_H}
        end if
    end tell
end tell
EOF
    echo "✅ Restored Contextify window to ($CONTEXTIFY_X, $CONTEXTIFY_Y) ${CONTEXTIFY_W}x${CONTEXTIFY_H}"
fi

# Restore iTerm2 window
if [ -n "$ITERM_INDEX" ] && [ -n "$ITERM_X" ]; then
    ITERM_X2=$((ITERM_X + ITERM_W))
    ITERM_Y2=$((ITERM_Y + ITERM_H))

    osascript <<EOF > /dev/null 2>&1
tell application "iTerm2"
    if (count of windows) >= $ITERM_INDEX then
        tell window $ITERM_INDEX
            set bounds to {$ITERM_X, $ITERM_Y, $ITERM_X2, $ITERM_Y2}
        end tell
    end if
end tell
EOF
    echo "✅ Restored iTerm2 window #$ITERM_INDEX to ($ITERM_X, $ITERM_Y) ${ITERM_W}x${ITERM_H}"
fi

# Clean up temp file
rm -f "$POSITIONS_FILE"

echo ""
echo "Windows restored!"
