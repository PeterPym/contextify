#!/bin/bash
# Speed-run through interesting parts of the demo video
# Usage: ./review-highlights.sh /path/to/video.mp4

VIDEO="${1:-}"

if [[ -z "$VIDEO" ]]; then
  echo "Usage: $0 /path/to/video.mp4"
  exit 1
fi

if [[ ! -f "$VIDEO" ]]; then
  echo "Error: File not found: $VIDEO"
  exit 1
fi

# Interesting segments from transcript analysis
# Format: "START END DESCRIPTION"
SEGMENTS=(
  "00:00:00 00:01:40 Intro - Origin story, FileKitty, problem statement"
  "00:03:50 00:04:40 Directives - Blue arrow, completion tracking feature"
  "00:09:10 00:10:00 Apple Intelligence - Local LLM summarization"
  "00:10:10 00:10:50 Core Value - Ambient flow monitor + SQL database"
  "00:13:40 00:14:40 Privacy - Little Snitch, works offline, never uploads"
  "00:16:40 00:17:20 Lazy Summarization - Hourglass icons, battery efficient"
  "00:18:40 00:19:20 No Xcode - Built without Xcode, uses PyCharm"
  "00:23:30 00:24:30 Multi-project - Spinning plates, unread counts"
  "00:25:30 00:26:30 Tool Calling - Retains full history in database"
  "00:27:00 00:28:30 Codex Demo + Outro - Shows both tools, contact info"
)

# Check for video player
if command -v mpv &> /dev/null; then
  PLAYER="mpv"
elif command -v ffplay &> /dev/null; then
  PLAYER="ffplay"
else
  echo "Error: Install mpv (brew install mpv) or ffmpeg for ffplay"
  exit 1
fi

echo "=========================================="
echo "Demo Video Highlight Review"
echo "=========================================="
echo ""
echo "Video: $VIDEO"
echo "Player: $PLAYER"
echo "Segments: ${#SEGMENTS[@]}"
echo ""
echo "Controls:"
echo "  SPACE  - pause/play"
echo "  q      - skip to next segment"
echo "  Ctrl+C - exit review"
echo ""
echo "=========================================="
echo ""

for i in "${!SEGMENTS[@]}"; do
  IFS=' ' read -r START END DESC <<< "${SEGMENTS[$i]}"

  # Calculate duration
  START_SEC=$(echo "$START" | awk -F: '{print ($1*3600) + ($2*60) + $3}')
  END_SEC=$(echo "$END" | awk -F: '{print ($1*3600) + ($2*60) + $3}')
  DURATION=$((END_SEC - START_SEC))

  echo "[$((i+1))/${#SEGMENTS[@]}] $DESC"
  echo "         $START - $END (${DURATION}s)"
  echo ""

  if [[ "$PLAYER" == "mpv" ]]; then
    mpv --start="$START" --length="$DURATION" --force-window=yes --quiet "$VIDEO" 2>/dev/null
  else
    ffplay -ss "$START" -t "$DURATION" -autoexit -loglevel quiet "$VIDEO" 2>/dev/null
  fi

  # Brief pause between segments
  echo "---"
  echo "Press ENTER for next segment, or 's' to skip rest, or 'r' to replay..."
  read -r -n 1 -t 3 REPLY || true
  echo ""

  if [[ "$REPLY" == "s" ]]; then
    echo "Skipping remaining segments."
    break
  elif [[ "$REPLY" == "r" ]]; then
    ((i--))  # Replay current segment
  fi
done

echo ""
echo "=========================================="
echo "Review complete!"
echo ""
echo "Total highlight duration: ~3-4 minutes"
echo "Full video duration: ~35 minutes"
echo ""
echo "To export these clips, run:"
echo "  ./export-highlights.sh $VIDEO output.mp4"
echo "=========================================="
