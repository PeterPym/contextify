#!/usr/bin/env bash
# Build Contextify and automatically capture logs for debugging
# Usage: ./scripts/logging/build-and-capture-logs.sh [duration_seconds]

set -euo pipefail

CAPTURE_DURATION="${1:-30}"
LOG_DIR="build/logs/runtime"
TIMESTAMP=$(date "+%Y%m%d-%H%M%S")
LOG_FILE="$LOG_DIR/contextify-$TIMESTAMP.log"

# Create log directory
mkdir -p "$LOG_DIR"

echo "🔨 Building Contextify..."
bash scripts/xc.sh build

echo ""
echo "📝 Capturing logs for $CAPTURE_DURATION seconds..."
echo "   Output: $LOG_FILE"
echo ""

# Start log capture in background
/usr/bin/log stream \
  --predicate 'process == "Contextify"' \
  --style compact \
  --color none \
  > "$LOG_FILE" 2>&1 &

LOG_PID=$!

# Wait for specified duration
sleep "$CAPTURE_DURATION"

# Stop log capture
kill $LOG_PID 2>/dev/null || true

LINE_COUNT=$(wc -l < "$LOG_FILE" | tr -d ' ')
echo ""
echo "✅ Captured $LINE_COUNT lines to: $LOG_FILE"
echo ""

# Show summary
ERROR_COUNT=$(grep -ci error "$LOG_FILE" 2>/dev/null || echo "0")
WARNING_COUNT=$(grep -ci warning "$LOG_FILE" 2>/dev/null || echo "0")

echo "Summary:"
echo "  Errors:   $ERROR_COUNT"
echo "  Warnings: $WARNING_COUNT"
echo ""

if [[ $ERROR_COUNT -gt 0 ]]; then
  echo "Recent errors:"
  grep -i error "$LOG_FILE" | tail -5
  echo ""
fi

echo "To view full log:"
echo "  less $LOG_FILE"
echo ""
echo "To filter by category:"
echo "  grep 'HooverEngine' $LOG_FILE"
echo "  grep 'TranscriptOrchestrator' $LOG_FILE"
echo "  grep 'ConversationMonitor' $LOG_FILE"
