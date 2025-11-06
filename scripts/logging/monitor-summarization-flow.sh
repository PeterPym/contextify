#!/bin/bash

# Example: Monitor summarization flow from project selection through LLM queue
# See README.md for how to create custom monitoring scripts
#
# IMPORTANT: All logged values must use privacy: .public to be visible
# Example: log.info("[TAG] Count: \(count)", privacy: .public)

# Step 1: Create timestamped log file for session capture
LOGFILE="/tmp/summarization-flow-$(date +%Y%m%d-%H%M%S).log"

# Step 2: Setup cleanup handler to save logs on exit
cleanup() {
  echo ""
  echo "=== Logs saved to: $LOGFILE ==="
  echo "View with: cat $LOGFILE"
  exit 0
}

trap cleanup SIGINT SIGTERM

# Step 3: Display help text showing which tags are being monitored
echo "=== Summarization Flow Monitor ==="
echo "Watching for:"
echo "  [SUMM-TAP]         - User taps project tab"
echo "  [SUMM-SWITCH]      - ProjectSwitcherState initiates switch"
echo "  [SUMM-COORD]       - StartupCoordinator processes switch"
echo "  [SUMM-MONITOR]     - ConversationMonitor handles context update"
echo "  [SUMM-LOAD]        - Timeline feed loading"
echo "  [SUMM-MISSES]      - Cache misses detected"
echo "  [SUMM-QUEUE]       - LLM queue operations"
echo "  [SUMM-SKIP]        - Summarization skipped (feature flag)"
echo ""
echo "Logs will be saved to: $LOGFILE"
echo "Press Ctrl+C to stop and save..."
echo ""

# Step 4: Stream logs with proper filtering
# GOTCHA: Use "BEGINSWITH" not "==" for subsystem predicate (macOS requirement)
# GOTCHA: Use --line-buffered on grep to prevent buffering delays
# GOTCHA: Use "IFS= read -r" to preserve line formatting
log stream \
  --predicate 'subsystem BEGINSWITH "dev.contextify"' \
  --level info \
  --style compact 2>&1 | \
  grep --line-buffered -E "\[SUMM-" | \
  tee -a "$LOGFILE" | \
  while IFS= read -r line; do
    # Step 5: Parse log line components
    ts=$(echo "$line" | awk '{print $1, $2}')
    msg=$(echo "$line" | grep -oE "\[SUMM-[^]]+\]" | head -1)
    detail=$(echo "$line" | sed 's/.*\]//')

    # Step 6: Color-code output by tag for visual debugging
    case "$msg" in
      *SUMM-TAP*)       echo -e "\033[1;34m$ts $msg\033[0m$detail" ;;  # Blue - user action
      *SUMM-SWITCH*)    echo -e "\033[1;36m$ts $msg\033[0m$detail" ;;  # Cyan - switch layer
      *SUMM-COORD*)     echo -e "\033[1;35m$ts $msg\033[0m$detail" ;;  # Magenta - coordinator
      *SUMM-MONITOR*)   echo -e "\033[1;33m$ts $msg\033[0m$detail" ;;  # Yellow - monitor
      *SUMM-LOAD*)      echo -e "\033[0;32m$ts $msg\033[0m$detail" ;;  # Green - loading
      *SUMM-MISSES*)    echo -e "\033[0;36m$ts $msg\033[0m$detail" ;;  # Cyan - cache misses
      *SUMM-QUEUE*)     echo -e "\033[0;35m$ts $msg\033[0m$detail" ;;  # Magenta - queue
      *SUMM-SKIP*)      echo -e "\033[1;31m$ts $msg\033[0m$detail" ;;  # RED - skipped!
      *) echo "$ts $msg$detail" ;;
    esac
  done
