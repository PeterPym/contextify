#!/bin/bash
# Automated screenshot capture for Contextify
# Usage: ./capture-screenshot.sh [name] [window-number] [--text "Overlay text"] [--no-open]
#   name: Optional description (e.g., "timeline-view", "project-switcher")
#   window-number: Optional iTerm2 window index (1, 2, 3, etc.)
#   --text "Text": Optional text overlay to add to screenshot
#   --no-open: Optional flag to skip opening the screenshot
#
# Examples:
#   ./capture-screenshot.sh 01-main-hud 2
#   ./capture-screenshot.sh 02-ai-summaries 2 --text "Intelligent summaries for every session"
#   ./capture-screenshot.sh 03-project-switcher 1 --text "Track multiple projects" --no-open

set -e

# Parse arguments
AUTO_OPEN=true
SHOT_NAME=""
WINDOW_INDEX=""
OVERLAY_TEXT=""

i=1
while [ $i -le $# ]; do
    arg="${!i}"
    if [ "$arg" = "--no-open" ]; then
        AUTO_OPEN=false
    elif [ "$arg" = "--text" ]; then
        i=$((i + 1))
        OVERLAY_TEXT="${!i}"
    elif [ -z "$SHOT_NAME" ]; then
        SHOT_NAME="$arg"
    elif [ -z "$WINDOW_INDEX" ]; then
        WINDOW_INDEX="$arg"
    fi
    i=$((i + 1))
done

# Set defaults
SHOT_NAME="${SHOT_NAME:-screenshot}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_DIR="appstore-metadata/screenshots/drafts"
FILENAME="${OUTPUT_DIR}/${SHOT_NAME}-${TIMESTAMP}.png"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Run setup script first, passing window index if provided
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "$WINDOW_INDEX" ]; then
    "$SCRIPT_DIR/setup-screenshot.sh" "$WINDOW_INDEX"
else
    "$SCRIPT_DIR/setup-screenshot.sh"
fi

# Capture region (must match setup script exactly)
SHOT_WIDTH=1440
SHOT_HEIGHT=900
CAPTURE_X=200
CAPTURE_Y=50

echo ""
echo "📸 Taking screenshot in 3 seconds..."

# Ensure Contextify has focus for the shot
osascript -e 'tell application "Contextify" to activate' > /dev/null 2>&1
sleep 0.5

sleep 2.5  # Remaining countdown

# Capture specific region (x, y, width, height)
screencapture -x -R"${CAPTURE_X},${CAPTURE_Y},${SHOT_WIDTH},${SHOT_HEIGHT}" "$FILENAME"

# Play camera shutter sound
afplay /System/Library/Sounds/Glass.aiff &

# Get original file size
ORIGINAL_SIZE=$(stat -f%z "$FILENAME")

echo "✅ Screenshot saved: $FILENAME"

# Get dimensions
DIMENSIONS=$(sips -g pixelWidth -g pixelHeight "$FILENAME" | grep -E "pixelWidth|pixelHeight" | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')

echo "   Dimensions: $DIMENSIONS"
echo "   Original size: $(numfmt --to=iec-i --suffix=B $ORIGINAL_SIZE 2>/dev/null || echo "$ORIGINAL_SIZE bytes")"

# Compress PNG (lossless)
if command -v oxipng &> /dev/null; then
    echo "   Compressing..."
    oxipng -o 3 -q "$FILENAME"
    COMPRESSED_SIZE=$(stat -f%z "$FILENAME")
    SAVED=$((ORIGINAL_SIZE - COMPRESSED_SIZE))
    PERCENT=$((SAVED * 100 / ORIGINAL_SIZE))
    echo "   Compressed size: $(numfmt --to=iec-i --suffix=B $COMPRESSED_SIZE 2>/dev/null || echo "$COMPRESSED_SIZE bytes") (saved ${PERCENT}%)"
else
    echo "   (Install 'oxipng' via homebrew for PNG compression)"
fi

# Create text overlay version if requested
if [ -n "$OVERLAY_TEXT" ]; then
    echo ""
    echo "📝 Adding text overlay..."

    # Generate final filename (still in drafts, user moves to releases when ready)
    FINAL_DIR="appstore-metadata/screenshots/drafts"
    mkdir -p "$FINAL_DIR"
    FINAL_FILENAME="${FINAL_DIR}/${SHOT_NAME}-${TIMESTAMP}-with-text.png"

    # Call text overlay script (suppress auto-open, we handle it here)
    NO_AUTO_OPEN=1 "$SCRIPT_DIR/add-text-overlay.sh" "$FILENAME" "$OVERLAY_TEXT" "$FINAL_FILENAME" > /dev/null

    echo "✅ Text overlay created: $FINAL_FILENAME"

    # Open the final version instead of original
    if [ "$AUTO_OPEN" = true ]; then
        echo "   Opening final screenshot with text..."
        open "$FINAL_FILENAME"
    else
        echo "   (Use 'open \"$FINAL_FILENAME\"' to view)"
    fi
else
    # Open original screenshot if no text overlay
    if [ "$AUTO_OPEN" = true ]; then
        echo "   Opening screenshot..."
        open "$FILENAME"
    else
        echo "   (Use 'open \"$FILENAME\"' to view)"
    fi
fi

# Restore windows to original positions
# "$SCRIPT_DIR/restore-screenshot.sh"  # Commented out temporarily for iterative screenshot capture

echo ""
echo "Next: Review and capture more screenshots:"
echo "  ./scripts/screenshots/capture-screenshot.sh 01-main-hud 2 --text \"Real-time AI monitoring\""
echo "  ./scripts/screenshots/capture-screenshot.sh 02-ai-summaries 2 --text \"Intelligent summaries\""
echo "  ./scripts/screenshots/capture-screenshot.sh 03-project-switcher 1 --no-open"
