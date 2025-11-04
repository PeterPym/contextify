#!/bin/bash
# Timeline HTTP API helper - quick access to running app state
# Usage: ./scripts/timeline_api.sh [command]

set -euo pipefail

API_BASE="http://127.0.0.1:17329"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Timeline HTTP API Helper

Usage: $0 <command>

Commands:
  health              Check if API is responding
  latest              Get most recent timeline entry
  recent [N]          Get N most recent entries (default: 10)
  diagnostics         Get full diagnostic snapshot
  issues              List detected issues
  status              Quick health dashboard
  watch               Monitor timeline in real-time (5s poll)

Examples:
  $0 status           # Quick health check
  $0 latest           # See most recent entry
  $0 recent 5         # Last 5 entries
  $0 issues           # Check for problems

API runs on: $API_BASE (localhost only)
EOF
    exit 1
}

check_api() {
    if ! curl -sf "$API_BASE/health" > /dev/null 2>&1; then
        echo -e "${RED}✗ API not responding${NC}"
        echo "Make sure Contextify app is running with monitoring active"
        exit 1
    fi
}

cmd_health() {
    check_api
    curl -s "$API_BASE/health" | jq '.'
}

cmd_latest() {
    check_api
    echo -e "${BLUE}Most recent timeline entry:${NC}"
    curl -s "$API_BASE/timeline/latest" | jq '.entry | {
        timestamp,
        role,
        provider,
        summary: .present_summary,
        is_generating,
        is_error,
        content_preview: (.content | .[0:150])
    }'
}

cmd_recent() {
    check_api
    local count="${1:-10}"
    echo -e "${BLUE}Last $count timeline entries:${NC}"
    curl -s "$API_BASE/timeline/recent?count=$count" | jq '.entries[] | {
        timestamp,
        role,
        summary: .present_summary,
        is_generating,
        is_error
    }'
}

cmd_diagnostics() {
    check_api
    curl -s "$API_BASE/diagnostics" | jq '.'
}

cmd_issues() {
    check_api
    echo -e "${BLUE}Detected issues:${NC}"
    local issues=$(curl -s "$API_BASE/diagnostics" | jq -r '.issues')

    if [ "$issues" = "[]" ]; then
        echo -e "${GREEN}✓ No issues detected${NC}"
    else
        echo "$issues" | jq -r '.[] | "  [\(.severity | ascii_upcase)] \(.category): \(.message)"'
    fi
}

cmd_status() {
    check_api
    echo -e "${BLUE}=== Timeline Status ===${NC}"
    curl -s "$API_BASE/diagnostics" | jq -r '
        "Project: \(.projectState.projectPath // "none")",
        "Monitoring: \(if .projectState.isMonitoring then "✅ Active" else "❌ Stopped" end)",
        "",
        "Watcher: \(if .watcherState.isWatching then "✅" else "❌" end)",
        "Hoover: \(if .hooverState.isStalled then "❌ STALLED" else "✅ Running" end)",
        "  Lag: \(.hooverState.linesUnprocessed) lines (\(.hooverState.bytesUnprocessed) bytes)",
        "",
        "Timeline:",
        "  Total entries: \(.timelineState.entryCount)",
        "  Visible: \(.timelineState.visibleEntryCount)",
        "  Last update: \(.timelineState.lastUpdate)",
        "",
        "Issues: \(.issues | length)"
    '
}

cmd_watch() {
    check_api
    echo -e "${BLUE}Monitoring timeline (Ctrl-C to stop)...${NC}"
    echo ""

    while true; do
        local timestamp=$(date "+%H:%M:%S")
        local data=$(curl -s "$API_BASE/diagnostics")
        local lag=$(echo "$data" | jq -r '.hooverState.linesUnprocessed')
        local stalled=$(echo "$data" | jq -r '.hooverState.isStalled')
        local issues=$(echo "$data" | jq -r '.issues | length')

        local status_icon="${GREEN}✓${NC}"
        if [ "$stalled" = "true" ]; then
            status_icon="${RED}✗${NC}"
        elif [ "$lag" -gt 10 ]; then
            status_icon="${YELLOW}⚠${NC}"
        fi

        echo -e "$timestamp $status_icon Lag: $lag lines | Issues: $issues"
        sleep 5
    done
}

# Main
if [ $# -eq 0 ]; then
    usage
fi

case "${1:-}" in
    health)
        cmd_health
        ;;
    latest)
        cmd_latest
        ;;
    recent)
        cmd_recent "${2:-10}"
        ;;
    diagnostics)
        cmd_diagnostics
        ;;
    issues)
        cmd_issues
        ;;
    status)
        cmd_status
        ;;
    watch)
        cmd_watch
        ;;
    *)
        usage
        ;;
esac
