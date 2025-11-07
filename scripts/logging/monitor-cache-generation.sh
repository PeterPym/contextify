#!/bin/bash

# Monitor Timeline Cache Miss Generator activity
# See README.md for how to create custom monitoring scripts
#
# IMPORTANT: All logged values must use privacy: .public to be visible
# Example: log.debug("[TAG] Count: \(count, privacy: .public)")

# Step 1: Create timestamped log file for session capture
LOGFILE="/tmp/cache-generation-$(date +%Y%m%d-%H%M%S).log"

# Step 2: Setup cleanup handler to save logs on exit
cleanup() {
  echo ""
  echo "=== Logs saved to: $LOGFILE ==="
  echo "View with: cat $LOGFILE"
  exit 0
}

trap cleanup SIGINT SIGTERM

# Step 3: Display help text showing which events are being monitored
echo "=== Timeline Cache Miss Generator Monitor ==="
echo "Watching for:"
echo "  Spawning processing task - Task creation"
echo "  processQueue: start      - Processing begins"
echo "  Queued cache misses      - Items added to queue"
echo "  Processing batch         - Batch execution"
echo "  Batch complete           - Batch finished"
echo ""
echo "Logs will be saved to: $LOGFILE"
echo "Press Ctrl+C to stop and save..."
echo ""

# Step 4: Stream logs with proper filtering
# GOTCHA: Use "BEGINSWITH" not "==" for subsystem predicate (macOS requirement)
# GOTCHA: Use --line-buffered on grep to prevent buffering delays
# GOTCHA: Use "IFS= read -r" to preserve line formatting
log stream \
  --predicate 'subsystem == "dev.contextify.timeline" AND category == "CacheMissGenerator"' \
  --level debug \
  --style compact 2>&1 | \
  grep --line-buffered -E "Spawning processing task|processQueue: start|Queued.*cache misses|Processing batch|Batch complete" | \
  tee -a "$LOGFILE" | \
  while IFS= read -r line; do
    # Step 5: Parse log line components
    ts=$(echo "$line" | awk '{print $1, $2}')
    rest=$(echo "$line" | awk '{$1=$2=""; print $0}')

    # Step 6: Color-code output by event type for visual debugging
    case "$line" in
      *"Spawning processing task"*)
        echo -e "\033[1;32m🟢 $ts\033[0m$rest"  # Green - task spawn
        ;;
      *"processQueue: start"*)
        echo -e "\033[1;34m🔵 $ts\033[0m$rest"  # Blue - processing starts
        ;;
      *"Queued"*)
        echo -e "\033[1;33m🟡 $ts\033[0m$rest"  # Yellow - queue event
        ;;
      *"Processing batch"*)
        echo -e "\033[1;36m🔷 $ts\033[0m$rest"  # Cyan - batch processing
        ;;
      *"Batch complete"*)
        echo -e "\033[1;35m🟣 $ts\033[0m$rest"  # Magenta - batch complete
        ;;
      *)
        echo "$line"
        ;;
    esac
  done
