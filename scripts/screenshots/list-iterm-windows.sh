#!/bin/bash
# List all iTerm2 windows with their indices
# Usage: ./list-iterm-windows.sh

echo "iTerm2 Windows:"
echo "==============="
echo ""

osascript <<'EOF'
tell application "iTerm2"
    set windowCount to count of windows
    if windowCount is 0 then
        return "No iTerm2 windows open"
    end if

    set output to ""
    repeat with i from 1 to windowCount
        tell window i
            set windowName to name
            set currentSession to current session
            tell currentSession
                set sessionName to name
                set currentPath to variable named "user.currentDirectory"
            end tell
        end tell

        set output to output & "Window #" & i & ": " & windowName & return
        set output to output & "  Session: " & sessionName & return
        if currentPath is not missing value then
            set output to output & "  Path: " & currentPath & return
        end if
        set output to output & return
    end repeat

    return output
end tell
EOF

echo ""
echo "Usage: ./scripts/capture-screenshot.sh [name] [window-number]"
echo "Example: ./scripts/capture-screenshot.sh main-hud 2"
