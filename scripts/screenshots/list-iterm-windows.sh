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
        log "No iTerm2 windows open"
        return
    end if

    repeat with i from 1 to windowCount
        log "Window #" & i & ":"

        tell window i
            try
                set tabCount to count of tabs
                log "  " & tabCount & " tab(s)"

                repeat with j from 1 to tabCount
                    tell tab j
                        tell current session
                            set tabName to name
                            log "    Tab " & j & ": " & tabName
                        end tell
                    end tell
                end repeat
            on error errMsg
                log "  Error reading tabs: " & errMsg
            end try
        end tell

        log ""
    end repeat
end tell
EOF

echo ""
echo "Usage: ./scripts/screenshots/capture-screenshot.sh [name] [window-number]"
echo "Example: ./scripts/screenshots/capture-screenshot.sh main-hud 2"
