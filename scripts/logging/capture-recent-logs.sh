#!/bin/bash
# Capture recent Contextify logs (last N minutes)
# Usage: ./scripts/capture-recent-logs.sh [minutes] [output-file]

set -e

MINUTES="${1:-5}"
OUTPUT_FILE="${2:-/tmp/contextify-recent.log}"

echo "Capturing Contextify logs from last $MINUTES minutes..."

# Calculate start time (N minutes ago)
START_TIME=$(date -v-${MINUTES}M "+%Y-%m-%d %H:%M:%S")

/usr/bin/log show \
  --predicate 'process == "Contextify"' \
  --style compact \
  --start "$START_TIME" \
  --color none \
  > "$OUTPUT_FILE"

LINE_COUNT=$(wc -l < "$OUTPUT_FILE")
echo "Captured $LINE_COUNT lines to: $OUTPUT_FILE"
echo ""
echo "To view errors only:"
echo "  grep -i error $OUTPUT_FILE"
echo ""
echo "To view specific subsystem:"
echo "  grep 'dev.contextify' $OUTPUT_FILE"
