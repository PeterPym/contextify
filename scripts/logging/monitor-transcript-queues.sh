#!/bin/bash

# Transcript Pipeline Monitor
# ---------------------------
# Captures *all* Contextify logs (every subsystem) into /tmp for post-hoc analysis.
# Restores the original monitor-transcript-queues.sh functionality referenced in the
# diagnostics playbook. Use this before running analyze-pipeline.sh or analyze-gaps.sh
# so that File System, Discovery, Watcher, and Hoover events are present.
#
# Usage:
#   ./monitor-transcript-queues.sh [options] [duration]
#
# Options:
#   -q, --quiet    Only write to file (no real-time output on terminal)
#
# Default: Shows real-time output AND saves to file

set -euo pipefail

QUIET=0

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quiet)
      QUIET=1
      shift
      ;;
    *)
      break
      ;;
  esac
done

DURATION="${DURATION:-${1:-30}}"
LOGFILE="${LOGFILE:-/tmp/transcript-queue-monitor-$(date +%Y%m%d-%H%M%S).log}"
PREDICATE="${PREDICATE:-subsystem CONTAINS \"dev.contextify\"}"
STYLE="${STYLE:-compact}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Transcript Pipeline Monitor"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Duration: ${DURATION}s"
echo "Predicate: ${PREDICATE}"
echo "Log file: ${LOGFILE}"
echo ""

echo "📡 Capturing log stream... (Ctrl+C to stop early)"

# In quiet mode, redirect output to /dev/null (file only)
# Otherwise, show real-time output on terminal AND save to file
if [[ $QUIET -eq 1 ]]; then
  log stream \
    --predicate "${PREDICATE}" \
    --style "$STYLE" \
    --level info \
    2>&1 | tee "$LOGFILE" >/dev/null &
else
  log stream \
    --predicate "${PREDICATE}" \
    --style "$STYLE" \
    --level info \
    2>&1 | tee "$LOGFILE" &
fi

LOG_PID=$!

sleep "$DURATION" 2>/dev/null || true

echo "⏹️  Stopping log capture"
kill "$LOG_PID" 2>/dev/null || true
wait "$LOG_PID" 2>/dev/null || true

echo ""
echo "Logs saved to: $LOGFILE"
echo "Run analyze-pipeline.sh or analyze-gaps.sh against this file for automatic reports."
