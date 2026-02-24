#!/bin/bash
# Read timeline diagnostics from running Contextify app
# Usage: ./scripts/logging/read_timeline_state.sh [--request|--state|--report]

set -euo pipefail

STATE_FILE="/tmp/contextify-state.json"
TRIGGER_FILE="/tmp/contextify-diag-request"
RESPONSE_FILE="/tmp/contextify-diag-response.json"
REPORT_FILE="/tmp/contextify-diag-report.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

MODE="${1:---state}"

case "$MODE" in
  --request)
    # Request fresh diagnostics (blocking, waits for response)
    echo -e "${BLUE}Requesting fresh diagnostics from app...${NC}"

    # Create trigger
    echo "request" > "$TRIGGER_FILE"

    # Wait for response (max 5 seconds)
    for i in {1..50}; do
      if [ -f "$RESPONSE_FILE" ]; then
        echo -e "${GREEN}✓ Response received${NC}"
        cat "$RESPONSE_FILE"
        rm -f "$RESPONSE_FILE"
        exit 0
      fi
      sleep 0.1
    done

    echo -e "${RED}✗ Timeout waiting for response${NC}"
    rm -f "$TRIGGER_FILE"
    exit 1
    ;;

  --state)
    # Read periodic state export (non-blocking, immediate)
    if [ ! -f "$STATE_FILE" ]; then
      echo -e "${RED}✗ No state file found${NC}"
      echo "App may not be running or diagnostics API not initialized"
      exit 1
    fi

    # Show file age
    if [[ "$OSTYPE" == "darwin"* ]]; then
      AGE=$(( $(date +%s) - $(stat -f %m "$STATE_FILE") ))
    else
      AGE=$(( $(date +%s) - $(stat -c %Y "$STATE_FILE") ))
    fi

    echo -e "${BLUE}State file age: ${AGE}s${NC}"
    cat "$STATE_FILE"
    ;;

  --report)
    # Request fresh diagnostics and show human-readable report
    echo -e "${BLUE}Requesting fresh diagnostics report from app...${NC}"

    # Create trigger
    echo "request" > "$TRIGGER_FILE"

    # Wait for response (max 5 seconds)
    for i in {1..50}; do
      if [ -f "$REPORT_FILE" ]; then
        echo -e "${GREEN}✓ Report generated${NC}"
        echo ""
        cat "$REPORT_FILE"
        exit 0
      fi
      sleep 0.1
    done

    echo -e "${RED}✗ Timeout waiting for report${NC}"
    rm -f "$TRIGGER_FILE"
    exit 1
    ;;

  --help)
    cat <<EOF
Usage: $0 [MODE]

Modes:
  --state     Read most recent periodic state (fast, non-blocking)
  --request   Request fresh diagnostics (waits for app response)
  --report    Request fresh diagnostics and show human-readable report
  --help      Show this help

Examples:
  # Quick check (reads cached state, ~0s)
  $0 --state | jq '.hooverState'

  # Fresh snapshot (waits for app, ~0.1s)
  $0 --request | jq '.issues'

  # Human-readable report
  $0 --report

Files:
  State:    $STATE_FILE (updated every 10s by app)
  Response: $RESPONSE_FILE (created on request)
  Report:   $REPORT_FILE (created on request)
  Trigger:  $TRIGGER_FILE (create to request fresh diagnostics)

EOF
    ;;

  *)
    echo -e "${RED}Unknown mode: $MODE${NC}"
    echo "Use --help for usage information"
    exit 1
    ;;
esac
