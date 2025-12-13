#!/bin/bash

# Transcript Pipeline Monitor
# ---------------------------
# This script captures *every* Contextify subsystem (dev.contextify*, dev.contextify.timeline,
# dev.contextify.metadata) into a single log file under /tmp. It is the canonical tool referenced
# by build/docs/guides/timeline-diagnostics.md for gathering ground-truth evidence before running
# automated analyzers like analyze-pipeline.sh or analyze-gaps.sh.
#
# Raison d'être:
#   • Guarantee that File System, Discovery, Hoover, Watcher, Timeline, and UI logs all land in
#     the same capture so automated tools have the tags they expect ([FSEVENTS-*], [HOOVER-*],
#     [TIMELINE-*], [COORD-*], etc.).
#   • Provide a single command agents/humans can run (even headless) to reproduce the
#     monitor-transcript-queues.sh workflow mentioned throughout the diagnostics docs.
#   • Ensure new instrumentation (e.g., `[WATCHER-SCOPE]` from TranscriptWatcher) is recorded
#     without having to remember which subsystem predicate to use.
#
# Usage:
#   ./monitor-transcript-queues.sh [options] [duration]
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
LOG_DIR="${LOG_DIR:-/tmp}"
LOGFILE="${LOGFILE:-${LOG_DIR}/transcript-queue-monitor-$(date +%Y%m%d-%H%M%S).log}"
LOGFILE_BASE="${LOGFILE%.log}"
PREDICATE="${PREDICATE:-subsystem CONTAINS \"dev.contextify\"}"
STYLE="${STYLE:-compact}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Transcript Pipeline Monitor"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Duration: ${DURATION}s"
echo "Predicate: ${PREDICATE}"
echo "Log file: ${LOGFILE}"
echo ""
echo "Incremental snapshots will be written every 30 seconds:"
echo "  ${LOGFILE_BASE}.partial.1.log"
echo "  ${LOGFILE_BASE}.partial.2.log"
echo "  ${LOGFILE_BASE}.partial.3.log ..."
echo ""

echo "📡 Capturing log stream... (Ctrl+C to stop early)"

# In quiet mode, redirect output to /dev/null (file only)
# Otherwise, show real-time output on terminal AND save to file
if [[ $QUIET -eq 1 ]]; then
  log stream \
    --predicate "${PREDICATE}" \
    --style "$STYLE" \
    --level debug \
    2>&1 | tee "$LOGFILE" >/dev/null &
else
  log stream \
    --predicate "${PREDICATE}" \
    --style "$STYLE" \
    --level debug \
    2>&1 | tee "$LOGFILE" &
fi

LOG_PID=$!

# Background job to write partial snapshots every 30 seconds
PARTIAL_INTERVAL=30
PARTIAL_COUNTER=0

write_partial_snapshot() {
  while kill -0 "$LOG_PID" 2>/dev/null; do
    sleep "$PARTIAL_INTERVAL"
    if [[ -f "$LOGFILE" ]]; then
      PARTIAL_COUNTER=$((PARTIAL_COUNTER + 1))
      PARTIAL_FILE="${LOGFILE_BASE}.partial.${PARTIAL_COUNTER}.log"
      cp "$LOGFILE" "$PARTIAL_FILE" 2>/dev/null || true
      if [[ $QUIET -eq 0 ]]; then
        local size=$(wc -l < "$PARTIAL_FILE" 2>/dev/null || echo "0")
        echo "[$(date +%H:%M:%S)] Partial snapshot #${PARTIAL_COUNTER}: $PARTIAL_FILE (${size} lines)"
      fi
    fi
  done
}

# Start background partial writer
write_partial_snapshot &
PARTIAL_PID=$!

# Cleanup function
cleanup() {
  echo ""
  echo "⏹️  Stopping log capture"
  kill "$LOG_PID" 2>/dev/null || true
  wait "$LOG_PID" 2>/dev/null || true

  kill "$PARTIAL_PID" 2>/dev/null || true
  wait "$PARTIAL_PID" 2>/dev/null || true

  # Write final complete log and clean up partials
  echo ""
  echo "Complete logs saved to: $LOGFILE"

  # Remove all partial snapshots
  rm -f "${LOGFILE_BASE}.partial."*.log 2>/dev/null || true

  echo "Run analyze-pipeline.sh or analyze-gaps.sh against this file for automatic reports."
}

trap cleanup EXIT INT TERM

sleep "$DURATION" 2>/dev/null || true
