#!/bin/bash
# Automated screenshot capture for Contextify
# Usage: ./capture-screenshot.sh [name]
#   name: Optional description (e.g., "timeline-view", "project-switcher")

set -e

# Get optional name parameter
SHOT_NAME="${1:-screenshot}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_DIR="appstore-metadata/screenshots"
FILENAME="${OUTPUT_DIR}/${SHOT_NAME}-${TIMESTAMP}.png"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Run setup script first
./scripts/setup-screenshot.sh

# Capture region (must match setup script exactly)
SHOT_WIDTH=1440
SHOT_HEIGHT=900
CAPTURE_X=200
CAPTURE_Y=0

echo ""
echo "📸 Taking screenshot in 3 seconds..."
sleep 3

# Capture specific region (x, y, width, height)
screencapture -x -R"${CAPTURE_X},${CAPTURE_Y},${SHOT_WIDTH},${SHOT_HEIGHT}" "$FILENAME"

echo "✅ Screenshot saved: $FILENAME"

# Get dimensions
DIMENSIONS=$(sips -g pixelWidth -g pixelHeight "$FILENAME" | grep -E "pixelWidth|pixelHeight" | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')

echo "   Dimensions: $DIMENSIONS"
echo ""
echo "Next: Review the screenshot and run again for different views:"
echo "  ./scripts/capture-screenshot.sh timeline-view"
echo "  ./scripts/capture-screenshot.sh project-switcher"
echo "  ./scripts/capture-screenshot.sh settings-panel"
