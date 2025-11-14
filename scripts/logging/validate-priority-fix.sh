#!/bin/bash
set -euo pipefail

LOG_FILE="${1:-$(ls -t /tmp/transcript-queue-monitor-*.log 2>/dev/null | head -1)}"
TARGET_MS="${2:-200}"

if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
  echo "❌ No log file found"
  echo "Usage: $0 [log_file] [target_ms]"
  exit 1
fi

echo "=== Validating Git Priority Fix ==="
echo "Log: $LOG_FILE"
echo "Target: ${TARGET_MS}ms"
echo ""

# Extract git task timings
GIT_TIMINGS=$(grep "UIOPT-COORD-GIT-TASK-DONE" "$LOG_FILE" | \
  grep -oE '[0-9]+ms' | sed 's/ms//' || true)

if [ -z "$GIT_TIMINGS" ]; then
  echo "❌ No git timings found"
  exit 1
fi

# Calculate statistics
COUNT=$(echo "$GIT_TIMINGS" | wc -l | tr -d ' ')
MAX=$(echo "$GIT_TIMINGS" | sort -n | tail -1)
P95=$(echo "$GIT_TIMINGS" | sort -n | awk "NR==int($COUNT*0.95){print; exit}")

echo "Git task latencies:"
echo "  Count: $COUNT"
echo "  Max: ${MAX}ms"
echo "  P95: ${P95}ms"
echo "  Target: ${TARGET_MS}ms"
echo ""

if [ "$P95" -gt "$TARGET_MS" ]; then
  echo "❌ FAIL: P95 ($P95ms) > target (${TARGET_MS}ms)"
  exit 1
else
  echo "✅ PASS: P95 ($P95ms) ≤ target (${TARGET_MS}ms)"
fi

# Check for CRITICAL gaps
echo ""
echo "Checking for CRITICAL gaps (>5s)..."
CRITICAL=$(bash "$(dirname "$0")/analyze-gaps.sh" "$LOG_FILE" 5000 2>/dev/null | grep -c "CRITICAL" || true)

if [ "$CRITICAL" -gt 0 ]; then
  echo "❌ FAIL: $CRITICAL CRITICAL gaps found"
  exit 1
else
  echo "✅ PASS: No CRITICAL gaps"
fi

echo ""
echo "✅ Priority fix validation PASSED"
