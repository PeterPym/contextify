#!/bin/bash
#
# Monitor viewport-aware queueing behavior during project switches
#
# Usage:
#   ./scripts/logging/monitor-viewport-queueing.sh
#
# Expected behavior:
#   - SUMM-LOAD-DEFER should appear (not SUMM-QUEUE with 12 entries)
#   - SUMM-VIEWPORT-INIT should appear within ~100ms
#   - Queued count should match viewport count
#
# Exit codes:
#   0 = PASS (viewport-aware queueing working)
#   1 = FAIL (fallback to 12-entry queueing detected)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0.32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Viewport Queueing Behavior Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This test monitors timeline loading to ensure:"
echo "  1. No immediate queueing of 12 entries (fallback path)"
echo "  2. Viewport tracking reports within ~100ms"
echo "  3. Only visible entries are queued"
echo ""
echo "Instructions:"
echo "  1. Run this script"
echo "  2. Switch to a different project in Contextify"
echo "  3. Wait for analysis (auto-stops after 5 seconds)"
echo ""
echo "Starting monitor in 3 seconds..."
sleep 3

# Capture logs for 5 seconds
LOGFILE=$(mktemp)
trap "rm -f $LOGFILE" EXIT

echo "📊 Capturing logs (5 seconds)..."
log stream \
    --predicate 'subsystem == "dev.contextify" AND (category == "ConversationMonitor" OR category == "UIRender")' \
    --level debug \
    --style compact \
    --timeout 5 \
    2>/dev/null | tee "$LOGFILE" || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Analysis"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check for problematic fallback behavior
FALLBACK_QUEUE=$(grep -c "SUMM-QUEUE.*Queueing.*visible entries after load" "$LOGFILE" 2>/dev/null || true)
DEFER_COUNT=$(grep -c "SUMM-LOAD-DEFER" "$LOGFILE" 2>/dev/null || true)
VIEWPORT_INIT=$(grep -c "SUMM-VIEWPORT-INIT.*Initial viewport snapshot" "$LOGFILE" 2>/dev/null || true)

# Extract queued vs visible counts
if [ "$FALLBACK_QUEUE" -gt 0 ]; then
    QUEUED_COUNT=$(grep "SUMM-QUEUE.*Queueing.*visible entries after load" "$LOGFILE" | sed -E 's/.*Queueing ([0-9]+).*/\1/' | head -1)
    TOTAL_MISSES=$(grep "SUMM-QUEUE.*Queueing.*visible entries after load" "$LOGFILE" | sed -E 's/.*Queueing [0-9]+\/([0-9]+).*/\1/' | head -1)
else
    QUEUED_COUNT=0
    TOTAL_MISSES=0
fi

# Extract viewport count
if [ "$VIEWPORT_INIT" -gt 0 ]; then
    VIEWPORT_COUNT=$(grep "SUMM-VIEWPORT-INIT.*Initial viewport snapshot" "$LOGFILE" | sed -E 's/.*snapshot: ([0-9]+).*/\1/' | head -1)
else
    VIEWPORT_COUNT=0
fi

# Extract timing
TIMING_MS=$(grep "SUMM-VIEWPORT-TIMING" "$LOGFILE" 2>/dev/null | sed -E 's/.*report ([0-9]+)ms.*/\1/' || echo "N/A")

# Results
echo "Results:"
echo "  Fallback Queue Events: $FALLBACK_QUEUE"
echo "  Defer Events: $DEFER_COUNT"
echo "  Viewport Init Events: $VIEWPORT_INIT"
echo ""

if [ "$FALLBACK_QUEUE" -gt 0 ]; then
    echo "  ⚠️  Queued Count: $QUEUED_COUNT / $TOTAL_MISSES (using fallback)"
fi

if [ "$VIEWPORT_INIT" -gt 0 ]; then
    echo "  ✅ Viewport Count: $VIEWPORT_COUNT"
    echo "  ⏱️  Timing: ${TIMING_MS}ms (load → viewport)"
fi

echo ""

# Pass/Fail determination
if [ "$FALLBACK_QUEUE" -gt 0 ] && [ "$QUEUED_COUNT" -eq 12 ]; then
    echo -e "${RED}❌ FAIL${NC}: Detected 12-entry fallback queueing"
    echo "This indicates loadFeedFromSQL is using the fallback path instead of"
    echo "waiting for viewport tracking."
    echo ""
    echo "Expected: SUMM-LOAD-DEFER message, followed by SUMM-VIEWPORT-INIT"
    echo "Actual: SUMM-QUEUE with 12 entries"
    exit 1
elif [ "$DEFER_COUNT" -gt 0 ] && [ "$VIEWPORT_INIT" -gt 0 ]; then
    echo -e "${GREEN}✅ PASS${NC}: Viewport-aware queueing working correctly"
    echo "Load deferred to viewport, which queued $VIEWPORT_COUNT entries"
    if [ "$TIMING_MS" != "N/A" ]; then
        if [ "$TIMING_MS" -lt 100 ]; then
            echo -e "${GREEN}✅ Timing${NC}: ${TIMING_MS}ms (excellent)"
        else
            echo -e "${YELLOW}⚠️  Timing${NC}: ${TIMING_MS}ms (acceptable, but >100ms)"
        fi
    fi
    exit 0
else
    echo -e "${YELLOW}⚠️  UNCLEAR${NC}: Could not determine queueing behavior"
    echo "No project switch detected in captured logs."
    echo ""
    echo "Please:"
    echo "  1. Re-run this script"
    echo "  2. Switch projects while logs are capturing"
    exit 1
fi
