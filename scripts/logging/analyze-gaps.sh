#!/bin/bash

# Analyze UIOPT logs for multi-second gaps between consecutive entries
# Usage: ./analyze-gaps.sh <logfile> [min-gap-ms]
#
# Identifies timing gaps that indicate performance bottlenecks
# Default minimum gap: 1000ms (1 second)

set -euo pipefail

# Configuration
MIN_GAP_MS=${2:-1000}  # Default 1 second
LOGFILE=${1:-}

# Colors for output
RED='\033[1;31m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
CYAN='\033[0;36m'
RESET='\033[0m'

usage() {
  cat <<EOF
Usage: $0 <logfile> [min-gap-ms]

Analyze UIOPT performance logs for timing gaps between consecutive entries.

Arguments:
  logfile      Path to log file (required)
  min-gap-ms   Minimum gap to report in milliseconds (default: 1000)

Examples:
  # Find all gaps >= 1 second
  $0 /tmp/ui-performance-20251106-101959.log

  # Find gaps >= 500ms
  $0 /tmp/ui-performance-20251106-101959.log 500

  # Find gaps >= 5 seconds
  $0 /tmp/ui-performance-20251106-101959.log 5000

Output:
  - Gap size and duration
  - Previous log entry (before gap)
  - Next log entry (after gap)
  - Line numbers for context
EOF
  exit 1
}

# Validate arguments
if [[ -z "$LOGFILE" ]]; then
  echo "Error: Log file required"
  usage
fi

if [[ ! -f "$LOGFILE" ]]; then
  echo "Error: File not found: $LOGFILE"
  exit 1
fi

# Parse timestamp from log line
# Format: 2025-11-06 10:14:53.786
parse_timestamp() {
  local line="$1"
  # Extract timestamp (first 23 chars: YYYY-MM-DD HH:MM:SS.mmm)
  echo "$line" | awk '{print $1, $2}' | head -c 23
}

# Convert timestamp to seconds since epoch
timestamp_to_seconds() {
  local ts="$1"
  # macOS compatible date command (extract date and time without milliseconds)
  local datetime=$(echo "$ts" | cut -d. -f1)
  date -jf "%Y-%m-%d %H:%M:%S" "$datetime" "+%s" 2>/dev/null || echo "0"
}

# Add milliseconds to epoch time
add_milliseconds() {
  local epoch_s="$1"
  local ms="$2"
  echo "$((epoch_s * 1000 + ms))"
}

# Parse milliseconds from timestamp
get_milliseconds() {
  local ts="$1"
  local ms=$(echo "$ts" | grep -oE '\.[0-9]{3}$' | tr -d '.' || echo "0")
  # Remove leading zeros to avoid octal interpretation
  echo "$ms" | sed 's/^0*//' | grep -E '^[0-9]+$' || echo "0"
}

echo -e "${CYAN}=== Analyzing UIOPT Log Gaps ===${RESET}"
echo "Log file: $LOGFILE"
echo "Minimum gap: ${MIN_GAP_MS}ms"
echo ""

# Extract UIOPT lines with line numbers
TMPFILE=$(mktemp)
grep -n "\[UIOPT-" "$LOGFILE" > "$TMPFILE" || {
  echo "No UIOPT entries found in log file"
  rm -f "$TMPFILE"
  exit 0
}

# Read lines into arrays
declare -a line_numbers=()
declare -a timestamps=()
declare -a messages=()

while IFS=: read -r linenum content; do
  ts=$(parse_timestamp "$content")
  if [[ -n "$ts" ]]; then
    line_numbers+=("$linenum")
    timestamps+=("$ts")
    messages+=("$content")
  fi
done < "$TMPFILE"

rm -f "$TMPFILE"

# Calculate gaps
total_lines=${#timestamps[@]}
echo "Found $total_lines UIOPT log entries"
echo ""

gap_count=0
for ((i=1; i<total_lines; i++)); do
  prev_ts="${timestamps[$((i-1))]}"
  curr_ts="${timestamps[$i]}"

  # Convert to seconds
  prev_s=$(timestamp_to_seconds "$prev_ts")
  curr_s=$(timestamp_to_seconds "$curr_ts")

  # Extract milliseconds from timestamp
  prev_ms=$(get_milliseconds "$prev_ts")
  curr_ms=$(get_milliseconds "$curr_ts")

  # Calculate total milliseconds
  prev_total=$(add_milliseconds "$prev_s" "$prev_ms")
  curr_total=$(add_milliseconds "$curr_s" "$curr_ms")

  # Calculate gap
  gap_ms=$((curr_total - prev_total))

  # Report if gap exceeds threshold
  if [[ $gap_ms -ge $MIN_GAP_MS ]]; then
    gap_count=$((gap_count + 1))

    # Color code by severity
    if [[ $gap_ms -ge 10000 ]]; then
      color="$RED"
      severity="CRITICAL"
    elif [[ $gap_ms -ge 5000 ]]; then
      color="$YELLOW"
      severity="WARNING"
    else
      color="$GREEN"
      severity="INFO"
    fi

    echo -e "${color}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${color}Gap #${gap_count}: ${gap_ms}ms (${severity})${RESET}"
    echo -e "${color}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo -e "${CYAN}Before (line ${line_numbers[$((i-1))]]}):${RESET}"
    echo "  ${messages[$((i-1))]}"
    echo ""
    echo -e "${CYAN}After (line ${line_numbers[$i]}):${RESET}"
    echo "  ${messages[$i]}"
    echo ""

    # Extract tags for analysis
    prev_tag=$(echo "${messages[$((i-1))]}" | grep -oE "\[UIOPT-[^]]+\]" | head -1)
    curr_tag=$(echo "${messages[$i]}" | grep -oE "\[UIOPT-[^]]+\]" | head -1)

    echo -e "${CYAN}Analysis:${RESET}"
    echo "  Previous tag: $prev_tag"
    echo "  Next tag:     $curr_tag"
    echo "  Gap location: Between these operations"
    echo ""
  fi
done

# Summary
echo -e "${CYAN}=== Summary ===${RESET}"
echo "Total UIOPT entries: $total_lines"
echo "Gaps >= ${MIN_GAP_MS}ms: $gap_count"

if [[ $gap_count -eq 0 ]]; then
  echo -e "${GREEN}✓ No significant gaps found${RESET}"
else
  echo -e "${YELLOW}⚠ Found $gap_count significant gap(s)${RESET}"
  echo ""
  echo "Tip: Use lower min-gap-ms to find smaller delays:"
  echo "  $0 $LOGFILE 500"
fi
