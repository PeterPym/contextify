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
        set output to output & "Window #" & i & ":" & return

        tell window i
            try
                set tabCount to count of tabs
                set output to output & "  " & tabCount & " tab(s)" & return

                repeat with j from 1 to tabCount
                    tell tab j
                        tell current session
                            set tabName to name
                            set output to output & "    Tab " & j & ": " & tabName & return
                        end tell
                    end tell
                end repeat
            on error errMsg
                set output to output & "  Error reading tabs: " & errMsg & return
            end try
        end tell

        set output to output & return
    end repeat

    return output
end tell
EOF

echo ""
echo "Usage: ./scripts/capture-screenshot.sh [name] [window-number]"
echo "Example: ./scripts/capture-screenshot.sh main-hud 2"
