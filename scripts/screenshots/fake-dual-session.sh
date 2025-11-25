#!/bin/bash
# Fake dual-provider terminal for screenshots
# Creates two tabs: Claude Code and Codex, with fake session output
#
# Usage: ./fake-dual-session.sh <window-number>
#
# This script:
# 1. Creates a new tab in the specified iTerm window for Codex
# 2. Runs fake claude session in tab 1
# 3. Runs fake codex session in tab 2
# 4. Switches back to tab 1 (Claude Code) for the screenshot

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WINDOW_NUM="${1:-}"

if [ -z "$WINDOW_NUM" ]; then
  echo "Usage: $0 <window-number>"
  echo ""
  echo "Run ./list-iterm-windows.sh to see available windows"
  exit 1
fi

echo "Setting up dual-provider terminal in window #$WINDOW_NUM..."

# Set tab 1 title and run Claude Code fake session
osascript <<EOF
tell application "iTerm2"
    activate
    delay 0.5

    tell window $WINDOW_NUM
        select
        delay 0.5

        -- Ensure tab 1 is selected
        select tab 1
        delay 0.3

        tell current session of tab 1
            -- Send Ctrl-C to clear any running processes
            write text (ASCII character 3)
            delay 0.3

            set name to "✽ Refactor auth module"
            write text "cd '$SCRIPT_DIR' && ./fake-claude-session.sh --mixed-claude"
        end tell
    end tell
end tell
EOF

sleep 1

# Create new tab for Codex and run fake session
osascript <<EOF
tell application "iTerm2"
    activate
    delay 0.5

    tell window $WINDOW_NUM
        select
        delay 0.5

        -- Create new tab
        set newTab to (create tab with default profile)
        delay 0.5

        -- The new tab is automatically selected, get its session
        tell current session of current tab
            -- Send Ctrl-C to clear any running processes
            write text (ASCII character 3)
            delay 0.3

            set name to "Codex - Write auth tests"
            write text "cd '$SCRIPT_DIR' && ./fake-claude-session.sh --mixed-codex"
        end tell

        -- Switch back to first tab (Claude Code)
        select tab 1
        delay 0.3
    end tell
end tell
EOF

echo "✅ Dual-provider terminal ready"
echo "   Tab 1: Claude Code - Refactor auth module"
echo "   Tab 2: Codex - Write auth tests"
