#!/bin/bash
# Capture preset screenshots with predefined text and window setup
# Usage: ./capture-preset.sh <preset-name> [window-number]

set -e

PRESET="${1:-}"
WINDOW_INDEX="${2:-2}"

if [ -z "$PRESET" ]; then
    echo "Usage: $0 <preset> [window-number]"
    echo ""
    echo "Available presets:"
    echo "  main-hud              - Main HUD with timeline"
    echo "  ai-summaries          - AI-generated summaries"
    echo "  transcript-inventory  - Session history browser"
    echo "  project-switcher      - Multiple projects view"
    echo "  settings              - Settings panel"
    echo "  real-time-monitoring  - Live conversation updates"
    echo ""
    echo "Example:"
    echo "  $0 transcript-inventory 2"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$PRESET" in
    main-hud)
        SHOT_NAME="01-main-hud"
        TEXT="Real-time AI conversation monitoring"
        # Main window is already open, no special setup
        ;;

    ai-summaries)
        SHOT_NAME="02-ai-summaries"
        TEXT="Intelligent summaries for every session"
        # Just ensure timeline is visible in main window
        ;;

    transcript-inventory)
        SHOT_NAME="03-transcript-inventory"
        TEXT="Explore session history and insights"
        echo "Setting up transcript inventory window..."

        # For single-window screenshot, bypass setup-screenshot.sh
        # and manually position just the transcript window
        osascript <<'EOF'
tell application "Contextify"
    activate
end tell
delay 0.5

tell application "System Events"
    tell process "Contextify"
        keystroke "i" using {command down, control down}
    end tell
end tell
delay 1.5

-- Position transcript inventory and hide other windows
tell application "System Events"
    tell process "Contextify"
        repeat with w in (every window)
            set wName to name of w
            if wName contains "Transcript Inventory" then
                -- Center in 1440x900 capture area at (200, 50)
                -- Window: 968x633, so center at 200 + (1440-968)/2 = 436
                -- Vertically center: 50 + (900-633)/2 = 184
                set position of w to {436, 184}
                set size of w to {968, 633}
            end if
        end repeat
    end tell
end tell

-- Move other windows off-screen (can't minimize via System Events)
tell application "System Events"
    tell process "Contextify"
        repeat with w in (every window)
            set wName to name of w
            if wName is "Contextify" then
                -- Move main HUD off-screen to the left
                set position of w to {-5000, 0}
            end if
        end repeat
    end tell
end tell

-- Move iTerm2 windows off-screen
tell application "System Events"
    tell process "iTerm2"
        repeat with w in (every window)
            set position of w to {-5000, 0}
        end repeat
    end tell
end tell
EOF

        # Capture without running setup-screenshot.sh
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        OUTPUT_DIR="appstore-metadata/screenshots/drafts"
        mkdir -p "$OUTPUT_DIR"
        FILENAME="${OUTPUT_DIR}/${SHOT_NAME}-${TIMESTAMP}.png"

        echo ""
        echo "📸 Taking screenshot in 2 seconds..."
        sleep 2

        # Capture region (1440x900 at 200,50)
        screencapture -x -R"200,50,1440,900" "$FILENAME"
        afplay /System/Library/Sounds/Glass.aiff &

        # Add text overlay
        FINAL_FILENAME="${OUTPUT_DIR}/${SHOT_NAME}-${TIMESTAMP}-with-text.png"
        NO_AUTO_OPEN=1 "$SCRIPT_DIR/add-text-overlay.sh" "$FILENAME" "$TEXT" "$FINAL_FILENAME" > /dev/null

        echo "✅ Screenshot saved: $FINAL_FILENAME"
        open "$FINAL_FILENAME"

        # Note: This preset doesn't use setup-screenshot.sh so there are no saved positions to restore.
        # The windows were manually positioned by the preset's own AppleScript above.
        # Since we moved windows off-screen temporarily, restore them to reasonable default positions.
        osascript <<'EOF'
tell application "System Events"
    tell process "Contextify"
        repeat with w in (every window)
            set wName to name of w
            if wName is "Contextify" then
                -- Restore main HUD to center-ish position
                set position of w to {480, 360}
            end if
        end repeat
    end tell
end tell

tell application "System Events"
    tell process "iTerm2"
        -- Restore first iTerm2 window to default position
        if (count of windows) > 0 then
            set position of window 1 to {950, 450}
        end if
    end tell
end tell
EOF

        echo ""
        echo "Windows restored to default positions (original positions not saved for this preset)."
        return 0
        ;;

    project-switcher)
        SHOT_NAME="04-project-switcher"
        TEXT="Track multiple projects effortlessly"
        echo "Opening projects window..."
        osascript <<'EOF'
tell application "Contextify"
    activate
end tell
delay 0.5
tell application "System Events"
    tell process "Contextify"
        keystroke "p" using {command down, shift down}
    end tell
end tell
delay 1
EOF
        ;;

    settings)
        SHOT_NAME="05-settings"
        TEXT="Customize your development workflow"
        echo "Opening settings (transcript sources)..."
        osascript <<'EOF'
tell application "Contextify"
    activate
end tell
delay 0.5
tell application "System Events"
    tell process "Contextify"
        keystroke "t" using {command down, option down}
    end tell
end tell
delay 1
EOF
        ;;

    real-time-monitoring)
        SHOT_NAME="06-real-time-monitoring"
        TEXT="Never lose context while coding"
        # Main window with active monitoring
        ;;

    *)
        echo "Error: Unknown preset '$PRESET'"
        echo "Run '$0' without arguments to see available presets"
        exit 1
        ;;
esac

echo ""
echo "📸 Capturing: $SHOT_NAME"
echo "📝 Text: $TEXT"
echo ""

# Call the main capture script
"$SCRIPT_DIR/capture-screenshot.sh" "$SHOT_NAME" "$WINDOW_INDEX" --text "$TEXT"
