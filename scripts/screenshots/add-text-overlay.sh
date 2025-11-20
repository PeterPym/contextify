#!/bin/bash
# Add text overlay to App Store screenshots (Sketch-style)
# Usage: ./add-text-overlay.sh <input-image> <text> [output-image]
#
# Examples:
#   ./add-text-overlay.sh screenshot.png "Real-time AI monitoring"
#   ./add-text-overlay.sh input.png "Track multiple projects" output-final.png

set -e

# Check for required arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <input-image> <text> [output-image]"
    echo ""
    echo "Examples:"
    echo "  $0 screenshot.png \"Real-time AI monitoring\""
    echo "  $0 input.png \"Track multiple projects\" output-final.png"
    exit 1
fi

INPUT_IMAGE="$1"
OVERLAY_TEXT="$2"
OUTPUT_IMAGE="${3:-}"

# Validate input file exists
if [ ! -f "$INPUT_IMAGE" ]; then
    echo "Error: Input file '$INPUT_IMAGE' not found"
    exit 1
fi

# Generate output filename if not provided
if [ -z "$OUTPUT_IMAGE" ]; then
    # Extract filename without extension
    BASENAME=$(basename "$INPUT_IMAGE" .png)
    OUTPUT_DIR="appstore-metadata/screenshots/drafts"
    mkdir -p "$OUTPUT_DIR"
    OUTPUT_IMAGE="${OUTPUT_DIR}/${BASENAME}-with-text.png"
fi

echo "Adding text overlay to screenshot..."
echo "  Input:  $INPUT_IMAGE"
echo "  Text:   $OVERLAY_TEXT"
echo "  Output: $OUTPUT_IMAGE"
echo ""

# Font settings (Sketch-style large serif headline)
FONT=".New-York-Medium"
FONT_SIZE=120
TEXT_COLOR="#FFFFFF"  # White text (works on dark backgrounds)
GRAVITY="north"  # Position at top
Y_OFFSET=100  # Pixels from top
MAX_WIDTH=1200  # Text wrapping width

# Add text overlay with semi-transparent background for readability
magick "$INPUT_IMAGE" \
    \( -size ${MAX_WIDTH}x150 xc:none \
       -font "$FONT" \
       -pointsize "$FONT_SIZE" \
       -fill "$TEXT_COLOR" \
       -gravity center \
       -annotate +0+0 "$OVERLAY_TEXT" \
    \) \
    -gravity "$GRAVITY" \
    -geometry "+0+${Y_OFFSET}" \
    -composite \
    "$OUTPUT_IMAGE"

echo "✅ Text overlay added!"
echo ""
echo "Preview: open \"$OUTPUT_IMAGE\""
echo ""

# Optionally open the result (only if run standalone, not from capture script)
if [ -z "$NO_AUTO_OPEN" ] && command -v open &> /dev/null; then
    open "$OUTPUT_IMAGE"
fi
