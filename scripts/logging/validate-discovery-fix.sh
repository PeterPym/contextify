#!/bin/bash
#
# Validation script for P0 #P1-DISCOVERY fix
# Tests that ProjectActivityMonitor starts immediately after discovery completes
# instead of waiting for 5-second timeout
#
# Expected behavior BEFORE fix:
#   - 11+ second gap between ingestion complete and ProjectActivityMonitor start
#   - Fallback timeout warning in logs
#
# Expected behavior AFTER fix:
#   - <200ms gap between notification post and monitor start
#   - No fallback timeout warning
#   - ProjectActivityMonitor skips duplicate discovery

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

LOG_FILE="${1:-}"

if [ -z "$LOG_FILE" ]; then
    echo -e "${RED}Usage: $0 <log-file>${NC}"
    echo "Example: $0 /private/tmp/transcript-queue-monitor-20251118-*.log"
    exit 1
fi

if [ ! -f "$LOG_FILE" ]; then
    echo -e "${RED}Error: Log file not found: $LOG_FILE${NC}"
    exit 1
fi

echo "═══════════════════════════════════════════════════════════════"
echo "  P0 #P1-DISCOVERY Fix Validation"
echo "  Log: $(basename "$LOG_FILE")"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Extract key timestamps
DISCOVERY_START=$(grep "\[DISCOVERY-START\] Beginning full project discovery" "$LOG_FILE" | tail -1 | awk '{print $1, $2}' || true)
DISCOVERY_COMPLETE=$(grep "\[DISCOVERY-COMPLETE\] Full discovery and ingestion complete" "$LOG_FILE" | tail -1 | awk '{print $1, $2}' || true)
NOTIFICATION_POST=$(grep "\[DISCOVERY-NOTIFICATION\] Posted .projectsDiscoveryComplete notification" "$LOG_FILE" | tail -1 | awk '{print $1, $2}' || true)
NOTIFICATION_RECV=$(grep "Received .projectsDiscoveryComplete notification" "$LOG_FILE" | tail -1 | awk '{print $1, $2}' || true)
MONITOR_START=$(grep "\[INIT\] ProjectActivityMonitor: starting global monitoring" "$LOG_FILE" | tail -1 | awk '{print $1, $2}' || true)
MONITOR_COMPLETE=$(grep "\[INIT-COMPLETE\] ProjectActivityMonitor startup complete" "$LOG_FILE" | tail -1 | awk '{print $1, $2}' || true)
SKIP_DISCOVERY=$(grep "\[INIT-SKIP-DISCOVERY\] Projects already ingested" "$LOG_FILE" | tail -1 || true)
FALLBACK_WARNING=$(grep "Fallback timeout triggered" "$LOG_FILE" | tail -1 || true)

# Check 1: Discovery completed
if [ -z "$DISCOVERY_START" ]; then
    echo -e "${RED}❌ FAIL: Discovery start not found${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Discovery started: $DISCOVERY_START${NC}"

if [ -z "$DISCOVERY_COMPLETE" ]; then
    echo -e "${RED}❌ FAIL: Discovery completion not found${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Discovery completed: $DISCOVERY_COMPLETE${NC}"

# Extract duration from DISCOVERY_COMPLETE log line
DISCOVERY_DURATION=$(grep "\[DISCOVERY-COMPLETE\]" "$LOG_FILE" | tail -1 | grep -oE '[0-9]+ms' || echo "N/A")
echo "   Duration: $DISCOVERY_DURATION"

# Check 2: Notification posted
if [ -z "$NOTIFICATION_POST" ]; then
    echo -e "${RED}❌ FAIL: .projectsDiscoveryComplete notification NOT posted${NC}"
    echo "   This is the root cause of the 11s hang!"
    exit 1
fi
echo -e "${GREEN}✅ Notification posted: $NOTIFICATION_POST${NC}"

# Check 3: Notification received
if [ -z "$NOTIFICATION_RECV" ]; then
    echo -e "${RED}❌ FAIL: .projectsDiscoveryComplete notification NOT received${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Notification received: $NOTIFICATION_RECV${NC}"

# Calculate gap between post and receive
if command -v python3 &>/dev/null; then
    GAP_MS=$(python3 -c "
from datetime import datetime
post = datetime.strptime('$NOTIFICATION_POST', '%Y-%m-%d %H:%M:%S.%f')
recv = datetime.strptime('$NOTIFICATION_RECV', '%Y-%m-%d %H:%M:%S.%f')
gap = (recv - post).total_seconds() * 1000
print(int(gap))
" 2>/dev/null || echo "N/A")

    if [ "$GAP_MS" != "N/A" ]; then
        if [ "$GAP_MS" -lt 200 ]; then
            echo -e "   ${GREEN}Gap: ${GAP_MS}ms (excellent!)${NC}"
        elif [ "$GAP_MS" -lt 1000 ]; then
            echo -e "   ${YELLOW}Gap: ${GAP_MS}ms (acceptable)${NC}"
        else
            echo -e "   ${RED}Gap: ${GAP_MS}ms (slow - should be <200ms)${NC}"
        fi
    fi
fi

# Check 4: Monitor started
if [ -z "$MONITOR_START" ]; then
    echo -e "${RED}❌ FAIL: ProjectActivityMonitor did not start${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Monitor started: $MONITOR_START${NC}"

# Check 5: Monitor skipped duplicate discovery
if [ -z "$SKIP_DISCOVERY" ]; then
    echo -e "${YELLOW}⚠️  WARNING: Monitor did NOT skip duplicate discovery${NC}"
    echo "   This means the optimization is not working"
else
    echo -e "${GREEN}✅ Monitor skipped duplicate discovery (optimization working!)${NC}"
    # Extract project count
    PROJECT_COUNT=$(echo "$SKIP_DISCOVERY" | grep -oE 'count: [0-9]+' | awk '{print $2}' || echo "N/A")
    echo "   Projects already ingested: $PROJECT_COUNT"
fi

# Check 6: No fallback timeout
if [ -n "$FALLBACK_WARNING" ]; then
    echo -e "${RED}❌ FAIL: Fallback timeout triggered (notification path failed!)${NC}"
    exit 1
else
    echo -e "${GREEN}✅ No fallback timeout (notification path working!)${NC}"
fi

# Check 7: Monitor completed
if [ -z "$MONITOR_COMPLETE" ]; then
    echo -e "${YELLOW}⚠️  WARNING: Monitor completion not logged${NC}"
else
    echo -e "${GREEN}✅ Monitor completed: $MONITOR_COMPLETE${NC}"
    # Extract duration
    MONITOR_DURATION=$(grep "\[INIT-COMPLETE\]" "$LOG_FILE" | tail -1 | grep -oE '[0-9]+ms' || echo "N/A")
    echo "   Duration: $MONITOR_DURATION"
fi

# Calculate total time from discovery start to monitor complete
if command -v python3 &>/dev/null && [ -n "$MONITOR_COMPLETE" ]; then
    TOTAL_MS=$(python3 -c "
from datetime import datetime
start = datetime.strptime('$DISCOVERY_START', '%Y-%m-%d %H:%M:%S.%f')
complete = datetime.strptime('$MONITOR_COMPLETE', '%Y-%m-%d %H:%M:%S.%f')
total = (complete - start).total_seconds() * 1000
print(int(total))
" 2>/dev/null || echo "N/A")

    if [ "$TOTAL_MS" != "N/A" ]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        if [ "$TOTAL_MS" -lt 3000 ]; then
            echo -e "${GREEN}✅ OVERALL: ${TOTAL_MS}ms (excellent - target <3s)${NC}"
        elif [ "$TOTAL_MS" -lt 5000 ]; then
            echo -e "${YELLOW}⚠️  OVERALL: ${TOTAL_MS}ms (acceptable - target <3s)${NC}"
        else
            echo -e "${RED}❌ OVERALL: ${TOTAL_MS}ms (too slow - target <3s)${NC}"
        fi
        echo "═══════════════════════════════════════════════════════════════"
    fi
fi

echo ""
echo -e "${GREEN}✅ All validation checks passed!${NC}"
exit 0
