#!/bin/bash
# Add text overlay to App Store screenshots (Sketch-style)
# Usage: ./add-text-overlay.sh <input-image> <text> [output-image]
#
# Supports Pango markup for colored text:
#   <span foreground='#D77757'>Claude Code</span>  - Claude Code orange
#   <span foreground='#4A90D9'>Codex</span>        - Codex blue
#
# Examples:
#   ./add-text-overlay.sh screenshot.png "Real-time AI monitoring"
#   ./add-text-overlay.sh input.png "Never lose a conversation with <span foreground='#D77757'>Claude Code</span> or Codex"

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

# Detect image dimensions for responsive text box sizing
read IMG_WIDTH IMG_HEIGHT <<< "$(magick identify -format "%w %h" "$INPUT_IMAGE")"

# Font settings (Sketch-style large serif headline)
FONT=".New-York-Medium"
FONT_SIZE=120  # For caption-based single-color text
TEXT_COLOR="#FFFFFF"  # White text (works on dark backgrounds)
GRAVITY="north"  # Position at top
Y_OFFSET=100  # Pixels from top

# Make the text box span ~90% of the image width to avoid clipping long titles
OVERLAY_WIDTH=$(( IMG_WIDTH * 90 / 100 ))
OVERLAY_HEIGHT=300  # Tall enough for wrapped text with descenders (g, y, q, p)

# Check if text contains color markup (e.g., <span foreground='#D77757'>Claude Code</span>)
if [[ "$OVERLAY_TEXT" == *"<span"* ]]; then
    # Parse and render multi-color text by appending separate labels
    # Extract parts: before span, colored text, after span
    # Pattern: text <span foreground='#COLOR'>colored</span> text

    BEFORE=$(echo "$OVERLAY_TEXT" | sed "s/<span[^>]*>.*<\/span>.*//")
    COLOR=$(echo "$OVERLAY_TEXT" | sed -n "s/.*<span foreground='\([^']*\)'>.*<\/span>.*/\1/p")
    COLORED_TEXT=$(echo "$OVERLAY_TEXT" | sed -n "s/.*<span[^>]*>\([^<]*\)<\/span>.*/\1/p")
    AFTER=$(echo "$OVERLAY_TEXT" | sed "s/.*<\/span>//")

    # Use larger font for multi-color (label doesn't auto-scale like caption)
    MULTICOLOR_SIZE=120

    # Render two lines: first line has colored text, second line is plain
    # Line 1: BEFORE + COLORED_TEXT (horizontal append)
    # Line 2: AFTER (centered below)
    magick "$INPUT_IMAGE" \
        \( \
            \( \
                \( -background none -font "$FONT" -pointsize "$MULTICOLOR_SIZE" -fill "$TEXT_COLOR" label:"$BEFORE" \) \
                \( -background none -font "$FONT" -pointsize "$MULTICOLOR_SIZE" -fill "$COLOR" label:"$COLORED_TEXT" \) \
                +append \
            \) \
            \( -background none -font "$FONT" -pointsize "$MULTICOLOR_SIZE" -fill "$TEXT_COLOR" -gravity center label:"$AFTER" \) \
            -gravity center -append \
        \) \
        -gravity "$GRAVITY" \
        -geometry "+0+${Y_OFFSET}" \
        -composite \
        "$OUTPUT_IMAGE"
else
    # Standard caption for plain text
    magick "$INPUT_IMAGE" \
        \( -size ${OVERLAY_WIDTH}x${OVERLAY_HEIGHT} \
           -background none \
           -font "$FONT" \
           -pointsize "$FONT_SIZE" \
           -fill "$TEXT_COLOR" \
           -gravity center \
           caption:"$OVERLAY_TEXT" \
        \) \
        -gravity "$GRAVITY" \
        -geometry "+0+${Y_OFFSET}" \
        -composite \
        "$OUTPUT_IMAGE"
fi

echo "✅ Text overlay added!"
echo ""
echo "Preview: open \"$OUTPUT_IMAGE\""
echo ""

# Optionally open the result (only if run standalone, not from capture script)
if [ -z "$NO_AUTO_OPEN" ] && command -v open &> /dev/null; then
    open "$OUTPUT_IMAGE"
fi
