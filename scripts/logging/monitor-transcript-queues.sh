#!/bin/bash

# Transcript Pipeline Monitor
# ---------------------------
# Captures *all* Contextify logs (every subsystem) into /tmp for post-hoc analysis.
# Restores the original monitor-transcript-queues.sh functionality referenced in the
# diagnostics playbook. Use this before running analyze-pipeline.sh or analyze-gaps.sh
# so that File System, Discovery, Watcher, and Hoover events are present.

set -euo pipefail

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
log stream \
  --predicate "${PREDICATE}" \
  --style "$STYLE" \
  --level info \
  2>&1 | tee "$LOGFILE" >/dev/null &

LOG_PID=$!

sleep "$DURATION" 2>/dev/null || true

echo "⏹️  Stopping log capture"
kill "$LOG_PID" 2>/dev/null || true
wait "$LOG_PID" 2>/dev/null || true

echo ""
echo "Logs saved to: $LOGFILE"
echo "Run analyze-pipeline.sh or analyze-gaps.sh against this file for automatic reports."
