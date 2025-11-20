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
        TEXT="Explore source transcripts and gain insights"
        echo "Setting up transcript inventory window..."

        # Save window positions for restoration
        SAVED_POSITIONS=$(osascript <<EOF
tell application "System Events"
    tell process "Contextify"
        repeat with w in (every window)
            if name of w is "Contextify" then
                set pos to position of w
                return "contextify:" & (item 1 of pos) & "," & (item 2 of pos)
            end if
        end repeat
    end tell
end tell
return "contextify:0,0"
EOF
)

        if [ -n "$WINDOW_INDEX" ]; then
            SAVED_ITERM_POS=$(osascript <<EOF
tell application "iTerm2"
    if (count of windows) >= $WINDOW_INDEX then
        tell window $WINDOW_INDEX
            set bnds to bounds
            return (item 1 of bnds) & "," & (item 2 of bnds)
        end tell
    else
        return "0,0"
    end if
end tell
EOF
)
        fi

        # For single-window screenshot, bypass setup-screenshot.sh
        # and manually position just the transcript window
        osascript <<EOF
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

-- Move main Contextify window and iTerm2 out of frame, position transcript inventory
tell application "System Events"
    tell process "Contextify"
        repeat with w in (every window)
            set wName to name of w
            if wName contains "Transcript Inventory" then
                -- Center in 1440x900 capture area at (200, 50)
                -- Window: 968x633, so center at 200 + (1440-968)/2 = 436
                -- Vertically bias lower: base center 184, push down to give more top space for headline
                set position of w to {436, 230}
                set size of w to {968, 633}
            else if wName is "Contextify" then
                -- Move main HUD to the right (beyond capture frame)
                set position of w to {2000, 0}
            end if
        end repeat
    end tell
end tell

-- Move specified iTerm2 window to the right (beyond capture frame)
tell application "iTerm2"
    if (count of windows) >= $WINDOW_INDEX then
        tell window $WINDOW_INDEX
            -- Move to the right, beyond X=1640 (capture ends at 200+1440)
            set bounds to {2000, 700, 2800, 1300}
        end tell
    end if
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

        # Restore main Contextify window
        if [[ "$SAVED_POSITIONS" =~ contextify:([0-9]+),([0-9]+) ]]; then
            CONTEXTIFY_X="${BASH_REMATCH[1]}"
            CONTEXTIFY_Y="${BASH_REMATCH[2]}"
            osascript <<EOF
tell application "System Events"
    tell process "Contextify"
        repeat with w in (every window)
            if name of w is "Contextify" then
                set position of w to {$CONTEXTIFY_X, $CONTEXTIFY_Y}
                exit repeat
            end if
        end repeat
    end tell
end tell
EOF
            echo ""
            echo "Main Contextify window restored to ($CONTEXTIFY_X, $CONTEXTIFY_Y)."
        fi

        # Restore iTerm2 window to original position
        if [ -n "$WINDOW_INDEX" ] && [ -n "$SAVED_ITERM_POS" ]; then
            IFS=',' read -r SAVED_X SAVED_Y <<< "$SAVED_ITERM_POS"
            if [[ "$SAVED_X" =~ ^-?[0-9]+$ && "$SAVED_Y" =~ ^-?[0-9]+$ ]]; then
                osascript <<EOF
tell application "iTerm2"
    if (count of windows) >= $WINDOW_INDEX then
        tell window $WINDOW_INDEX
            set bnds to bounds
            set w to (item 3 of bnds) - (item 1 of bnds)
            set h to (item 4 of bnds) - (item 2 of bnds)
            set bounds to {$SAVED_X, $SAVED_Y, $SAVED_X + w, $SAVED_Y + h}
        end tell
    end if
end tell
EOF
                echo "iTerm2 window restored to ($SAVED_X, $SAVED_Y)."
            else
                echo "Skipping iTerm2 restore (invalid saved coords: $SAVED_ITERM_POS)"
            fi
        fi
        exit 0
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
