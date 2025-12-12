#!/bin/bash
# Export highlight segments into a single video
# Usage: ./export-highlights.sh /path/to/input.mp4 /path/to/output.mp4

set -e

INPUT="${1:-}"
OUTPUT="${2:-highlights.mp4}"
TMPDIR=$(mktemp -d)

if [[ -z "$INPUT" ]]; then
  echo "Usage: $0 /path/to/input.mp4 [/path/to/output.mp4]"
  exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
  echo "Error: ffmpeg required. Install with: brew install ffmpeg"
  exit 1
fi

echo "Input:  $INPUT"
echo "Output: $OUTPUT"
echo "Temp:   $TMPDIR"
echo ""

# Segments to extract (adjust timestamps after review!)
# Format: START DURATION
SEGMENTS=(
  "00:00:00 100"   # Intro - origin story (1:40)
  "00:03:50 50"    # Directives feature (0:50)
  "00:09:10 50"    # Apple Intelligence (0:50)
  "00:10:10 40"    # Core value prop (0:40)
  "00:13:40 60"    # Privacy emphasis (1:00)
  "00:16:40 40"    # Lazy summarization (0:40)
  # "00:18:40 40"  # No Xcode (optional - uncomment if you want)
  # "00:23:30 60"  # Multi-project (optional)
  "00:25:30 60"    # Tool calling retention (1:00)
  "00:27:00 90"    # Codex demo + outro (1:30)
)

LABELS=(
  "intro"
  "directives"
  "apple-intelligence"
  "value-prop"
  "privacy"
  "lazy-summarization"
  # "no-xcode"
  # "multi-project"
  "tool-calling"
  "outro"
)

echo "Extracting ${#SEGMENTS[@]} segments..."
echo ""

CONCAT_LIST="$TMPDIR/concat.txt"
> "$CONCAT_LIST"

for i in "${!SEGMENTS[@]}"; do
  IFS=' ' read -r START DURATION <<< "${SEGMENTS[$i]}"
  LABEL="${LABELS[$i]}"
  SEGMENT_FILE="$TMPDIR/segment_${i}_${LABEL}.mp4"

  echo "[$((i+1))/${#SEGMENTS[@]}] $LABEL ($START, ${DURATION}s)"

  # Re-encode for clean cuts and consistent format
  ffmpeg -y -ss "$START" -i "$INPUT" -t "$DURATION" \
    -c:v libx264 -preset fast -crf 22 \
    -c:a aac -b:a 192k \
    -movflags +faststart \
    "$SEGMENT_FILE" 2>/dev/null

  echo "file '$SEGMENT_FILE'" >> "$CONCAT_LIST"
done

echo ""
echo "Concatenating segments..."

ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" \
  -c copy \
  "$OUTPUT" 2>/dev/null

# Get duration of output
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT" 2>/dev/null)
DURATION_MIN=$(echo "$DURATION / 60" | bc)
DURATION_SEC=$(echo "$DURATION % 60" | bc)

echo ""
echo "=========================================="
echo "Export complete!"
echo ""
echo "Output: $OUTPUT"
printf "Duration: %d:%02d\n" "$DURATION_MIN" "${DURATION_SEC%.*}"
echo ""
echo "Next steps:"
echo "  1. Review: mpv '$OUTPUT'"
echo "  2. Adjust timestamps in this script if needed"
echo "  3. Re-run to regenerate"
echo "=========================================="

# Cleanup
rm -rf "$TMPDIR"
