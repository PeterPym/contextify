#!/bin/bash
# Automated screenshot capture for Contextify
# Usage: ./capture-screenshot.sh [name] [window-number] [--no-open]
#   name: Optional description (e.g., "timeline-view", "project-switcher")
#   window-number: Optional iTerm2 window index (1, 2, 3, etc.)
#   --no-open: Optional flag to skip opening the screenshot

set -e

# Parse arguments
AUTO_OPEN=true
SHOT_NAME=""
WINDOW_INDEX=""

for arg in "$@"; do
    if [ "$arg" = "--no-open" ]; then
        AUTO_OPEN=false
    elif [ -z "$SHOT_NAME" ]; then
        SHOT_NAME="$arg"
    elif [ -z "$WINDOW_INDEX" ]; then
        WINDOW_INDEX="$arg"
    fi
done

# Set defaults
SHOT_NAME="${SHOT_NAME:-screenshot}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_DIR="appstore-metadata/screenshots"
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

# Open screenshot by default
if [ "$AUTO_OPEN" = true ]; then
    echo "   Opening screenshot..."
    open "$FILENAME"
else
    echo "   (Use 'open \"$FILENAME\"' to view)"
fi

echo ""
echo "Next: Review the screenshot and run again for different views:"
echo "  ./scripts/screenshots/capture-screenshot.sh timeline-view 2"
echo "  ./scripts/screenshots/capture-screenshot.sh project-switcher 3"
echo "  ./scripts/screenshots/capture-screenshot.sh settings-panel 1 --no-open"
