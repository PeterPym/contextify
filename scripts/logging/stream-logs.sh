#!/bin/bash
# Stream Contextify logs to a file for debugging
# Usage: ./scripts/stream-logs.sh [output-file]

set -e

OUTPUT_FILE="${1:-/tmp/contextify-live.log}"
BUNDLE_ID="peterpym.contextify.debug"

echo "Streaming Contextify logs to: $OUTPUT_FILE"
echo "Press Ctrl+C to stop"
echo ""

# Clear the file
> "$OUTPUT_FILE"

# Stream logs with timestamp and filter for Contextify
/usr/bin/log stream \
  --predicate 'process == "Contextify"' \
  --style compact \
  --color none \
  | tee "$OUTPUT_FILE"
