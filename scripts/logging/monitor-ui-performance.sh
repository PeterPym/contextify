#!/bin/bash

# Monitor UI performance from user input (hotkey/click) to timeline render
# Tracks: Input → Switch → DB → Feed → Map → UI Update → Status Ready
# See README.md for how to create custom monitoring scripts
#
# IMPORTANT: All logged values must use privacy: .public to be visible
# Example: log.info("[TAG] Timing: \(ms)ms", privacy: .public)

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
echo "  [UIOPT-TABS-UPDATE]  - Project tab updates"
echo "  [UIOPT-SWITCH-*]     - Project switching flow"
echo "  [UIOPT-COORD-*]      - StartupCoordinator (DB, Git, Bookmark, Publish)"
echo "  [UIOPT-MONITOR-*]    - ConversationMonitor lifecycle"
echo "  [UIOPT-DB-INIT]      - Database initialization"
echo "  [UIOPT-FEED-*]       - Feed loading from SQL"
echo "  [UIOPT-SQL-QUERY]    - SQL query execution"
echo "  [UIOPT-MAP-*]        - Entry mapping to UI models"
echo "  [UIOPT-MAINACTOR-*]  - Main actor operation timing"
echo "  [UIOPT-RENDER-*]     - SwiftUI rendering events"
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
      *UIOPT-INPUT*)             echo -e "\033[1;35m$ts $msg\033[0m$detail" ;;  # Magenta - user input
      *UIOPT-TABS-UPDATE*)       echo -e "\033[1;36m$ts $msg\033[0m$detail" ;;  # Bright cyan - tab updates
      *UIOPT-SWITCH-START*)      echo -e "\033[1;33m$ts $msg\033[0m$detail" ;;  # Bright yellow - switch start
      *UIOPT-SWITCH-SPAWN*)      echo -e "\033[0;33m$ts $msg\033[0m$detail" ;;  # Yellow - task spawn
      *UIOPT-SWITCH-TASK-SPAWN-DELAY*) echo -e "\033[1;31m$ts $msg\033[0m$detail" ;; # BRIGHT RED - spawn delay (THE CULPRIT!)
      *UIOPT-SWITCH-TASK-START*) echo -e "\033[0;36m$ts $msg\033[0m$detail" ;;  # Cyan - task started
      *UIOPT-SWITCH-DB-START*)   echo -e "\033[0;33m$ts $msg\033[0m$detail" ;;  # Yellow - DB lookup
      *UIOPT-SWITCH-DB-DONE*)    echo -e "\033[0;32m$ts $msg\033[0m$detail" ;;  # Green - DB done
      *UIOPT-SWITCH-COORD-START*) echo -e "\033[0;34m$ts $msg\033[0m$detail" ;; # Blue - coord start
      *UIOPT-SWITCH-COORD-DONE*) echo -e "\033[0;32m$ts $msg\033[0m$detail" ;;  # Green - coord done
      *UIOPT-SWITCH-TASK-DONE*)  echo -e "\033[1;32m$ts $msg\033[0m$detail" ;;  # Bright green - task done
      *UIOPT-COORD-START*)       echo -e "\033[0;34m$ts $msg\033[0m$detail" ;;  # Blue - coordinator start
      *UIOPT-COORD-VALIDATE*)    echo -e "\033[0;37m$ts $msg\033[0m$detail" ;;  # White - validation
      *UIOPT-COORD-DB*)          echo -e "\033[0;33m$ts $msg\033[0m$detail" ;;  # Yellow - DB operations
      *UIOPT-COORD-GIT*)         echo -e "\033[0;36m$ts $msg\033[0m$detail" ;;  # Cyan - Git operations
      *UIOPT-COORD-BOOKMARK*)    echo -e "\033[0;35m$ts $msg\033[0m$detail" ;;  # Magenta - Bookmark
      *UIOPT-COORD-CONTEXT*)     echo -e "\033[0;37m$ts $msg\033[0m$detail" ;;  # White - Context creation
      *UIOPT-COORD-PUBLISH*)     echo -e "\033[0;36m$ts $msg\033[0m$detail" ;;  # Cyan - Publish
      *UIOPT-COORD-DONE*)        echo -e "\033[1;32m$ts $msg\033[0m$detail" ;;  # Bright green - coordinator done
      *UIOPT-MONITOR-START*)     echo -e "\033[1;34m$ts $msg\033[0m$detail" ;;  # Blue - monitor start
      *UIOPT-DB-INIT*)           echo -e "\033[1;33m$ts $msg\033[0m$detail" ;;  # Yellow - database
      *UIOPT-FEED-START*)        echo -e "\033[0;36m$ts $msg\033[0m$detail" ;;  # Cyan - feed start
      *UIOPT-FEED-DONE*)         echo -e "\033[0;32m$ts $msg\033[0m$detail" ;;  # Green - feed done
      *UIOPT-SQL-QUERY*)         echo -e "\033[0;33m$ts $msg\033[0m$detail" ;;  # Yellow - SQL
      *UIOPT-MAP-START*)         echo -e "\033[0;36m$ts $msg\033[0m$detail" ;;  # Cyan - mapping start
      *UIOPT-MAP-DONE*)          echo -e "\033[0;32m$ts $msg\033[0m$detail" ;;  # Green - mapping done
      *UIOPT-MAINACTOR-START*)   echo -e "\033[0;34m$ts $msg\033[0m$detail" ;;  # Blue - main actor start
      *UIOPT-MAINACTOR-DONE*)    echo -e "\033[0;32m$ts $msg\033[0m$detail" ;;  # Green - main actor done
      *UIOPT-RENDER-ENTRIES*)    echo -e "\033[0;35m$ts $msg\033[0m$detail" ;;  # Magenta - render entries
      *UIOPT-UI-UPDATE*)         echo -e "\033[0;35m$ts $msg\033[0m$detail" ;;  # Magenta - UI update
      *UIOPT-MONITOR-READY*)     echo -e "\033[1;32m$ts $msg\033[0m$detail" ;;  # GREEN - monitor ready
      *UIOPT-STATUS-READY*)      echo -e "\033[1;42m$ts $msg\033[0m$detail" ;;  # GREEN BG - fully ready!
      *) echo "$ts $msg$detail" ;;
    esac
  done
