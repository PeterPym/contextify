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

# Step 3: Display monitoring context (shown once at startup)
SUBSYSTEM="dev.contextify.timeline"
CATEGORIES="ConversationMonitor, CacheMissGenerator"
LEVEL="debug"

echo "=== Timeline Cache Miss Generator Monitor ==="
echo "Process:    Contextify"
echo "Subsystem:  $SUBSYSTEM"
echo "Categories: $CATEGORIES"
echo "Log Level:  $LEVEL"
echo ""
echo "Watching for:"
echo "  [TIMELINE-INIT]   App/monitor initialization"
echo "  [TIMELINE-START]  Timeline monitoring started"
echo "  [TIMELINE-STOP]   Timeline monitoring stopped"
echo "  [SUMM-DEBOUNCE]   Viewport settled, queueing entries"
echo "  [SUMM-QUEUE]      Entries being added to queue"
echo "  Spawning task     Generator processing begins"
echo "  Batch complete    LLM generation finished"
echo ""
echo "Logs saved to: $LOGFILE"
echo "Press Ctrl+C to stop..."
echo ""

# Step 4: Stream logs with proper filtering
# GOTCHA: Use --line-buffered on grep to prevent buffering delays
# GOTCHA: Use "IFS= read -r" to preserve line formatting
log stream \
  --predicate "subsystem == \"$SUBSYSTEM\" AND (category == \"CacheMissGenerator\" OR category == \"ConversationMonitor\")" \
  --level "$LEVEL" \
  --style compact 2>&1 | \
  grep --line-buffered -E "TIMELINE-INIT|TIMELINE-START|TIMELINE-STOP|SUMM-DEBOUNCE|SUMM-QUEUE|Spawning processing task|processQueue: start|Processing batch|Batch complete" | \
  tee -a "$LOGFILE" | \
  while IFS= read -r line; do
    # Step 5: Parse log line components and simplify output
    # Extract: timestamp (with milliseconds), log level, and message
    # Input:  2025-11-07 10:12:10.633  I Contextify[67502:4b2540] [dev.contextify.timeline:ConversationMonitor] [TAG] Message
    # Output: 10:12:10.633 [TAG] Message

    # Extract time (HH:MM:SS.mmm) and everything after the subsystem bracket
    time=$(echo "$line" | awk '{print $2}')
    # Remove everything up to and including [subsystem:category] bracket (non-greedy)
    msg=$(echo "$line" | sed 's/^.*\[dev\.contextify[^]]*\] //')

    # Step 6: Color-code output by event type for visual debugging
    case "$msg" in
      *"TIMELINE-INIT"*)
        echo -e "\033[1;36m🚀 $time\033[0m $msg"  # Cyan - initialization
        ;;
      *"TIMELINE-START"*)
        echo -e "\033[1;32m▶️  $time\033[0m $msg"  # Green - start
        ;;
      *"TIMELINE-STOP"*)
        echo -e "\033[1;31m⏸️  $time\033[0m $msg"  # Red - stop
        ;;
      *"SUMM-DEBOUNCE"*"Timer completed"*)
        echo -e "\033[1;32m✅ $time\033[0m $msg"  # Green - timer completed (viewport settled)
        ;;
      *"SUMM-QUEUE"*"Queueing"*)
        echo -e "\033[1;33m📥 $time\033[0m $msg"  # Yellow - queueing entries
        ;;
      *"SUMM-QUEUE"*"Entry"*)
        echo -e "\033[0;33m   $time\033[0m $msg"  # Dim yellow - entry details (indented)
        ;;
      *"Spawning processing task"*)
        echo -e "\033[1;32m🟢 $time\033[0m $msg"  # Bright green - task spawn
        ;;
      *"processQueue: start"*)
        echo -e "\033[1;34m🔵 $time\033[0m $msg"  # Blue - processing starts
        ;;
      *"Processing batch"*)
        echo -e "\033[1;36m🔷 $time\033[0m $msg"  # Cyan - batch processing
        ;;
      *"Batch complete"*)
        echo -e "\033[1;35m🟣 $time\033[0m $msg"  # Magenta - batch complete
        ;;
      *)
        echo "$time $msg"
        ;;
    esac
  done
