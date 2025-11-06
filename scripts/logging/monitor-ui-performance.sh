#!/bin/bash

# Monitor UI performance from user input (hotkey/click) to timeline render
# Tracks: Input → Switch → DB → Feed → Map → UI Update → Status Ready
# See README.md for how to create custom monitoring scripts

# Step 1: Create timestamped log file for session capture
LOGFILE="/tmp/ui-performance-$(date +%Y%m%d-%H%M%S).log"

# Step 2: Setup cleanup handler to save logs on exit
cleanup() {
  echo ""
  echo "=== Logs saved to: $LOGFILE ==="
  echo "View with: cat $LOGFILE"
  exit 0
}

trap cleanup SIGINT SIGTERM

# Step 3: Display help text showing which tags are being monitored
echo "=== UI Performance Monitor ==="
echo "Watching for:"
echo "  [UIOPT-INPUT]        - User input (hotkey/click)"
echo "  [UIOPT-MONITOR-*]    - ConversationMonitor lifecycle"
echo "  [UIOPT-DB-INIT]      - Database initialization"
echo "  [UIOPT-FEED-*]       - Feed loading from SQL"
echo "  [UIOPT-SQL-QUERY]    - SQL query execution"
echo "  [UIOPT-MAP-*]        - Entry mapping to UI models"
echo "  [UIOPT-UI-UPDATE]    - Timeline UI update"
echo "  [UIOPT-STATUS-READY] - Status bar shows 'Up to date'"
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
  grep --line-buffered -E "\[UIOPT-" | \
  tee -a "$LOGFILE" | \
  while IFS= read -r line; do
    # Step 5: Parse log line components
    ts=$(echo "$line" | awk '{print $1, $2}')
    msg=$(echo "$line" | grep -oE "\[UIOPT-[^]]+\]" | head -1)
    detail=$(echo "$line" | sed 's/.*\]//')

    # Step 6: Color-code output by tag for visual debugging
    case "$msg" in
      *UIOPT-INPUT*)         echo -e "\033[1;35m$ts $msg\033[0m$detail" ;;  # Magenta - user input
      *UIOPT-MONITOR-START*) echo -e "\033[1;34m$ts $msg\033[0m$detail" ;;  # Blue - monitor start
      *UIOPT-DB-INIT*)       echo -e "\033[1;33m$ts $msg\033[0m$detail" ;;  # Yellow - database
      *UIOPT-FEED-START*)    echo -e "\033[0;36m$ts $msg\033[0m$detail" ;;  # Cyan - feed start
      *UIOPT-FEED-DONE*)     echo -e "\033[0;32m$ts $msg\033[0m$detail" ;;  # Green - feed done
      *UIOPT-SQL-QUERY*)     echo -e "\033[0;33m$ts $msg\033[0m$detail" ;;  # Yellow - SQL
      *UIOPT-MAP-START*)     echo -e "\033[0;36m$ts $msg\033[0m$detail" ;;  # Cyan - mapping start
      *UIOPT-MAP-DONE*)      echo -e "\033[0;32m$ts $msg\033[0m$detail" ;;  # Green - mapping done
      *UIOPT-UI-UPDATE*)     echo -e "\033[0;35m$ts $msg\033[0m$detail" ;;  # Magenta - UI update
      *UIOPT-MONITOR-READY*) echo -e "\033[1;32m$ts $msg\033[0m$detail" ;;  # GREEN - monitor ready
      *UIOPT-STATUS-READY*)  echo -e "\033[1;42m$ts $msg\033[0m$detail" ;;  # GREEN BG - fully ready!
      *) echo "$ts $msg$detail" ;;
    esac
  done
