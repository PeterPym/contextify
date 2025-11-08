#!/bin/bash

# Generic OSLog Monitor Template for Swift/macOS Projects
# Usage: ./monitor-template.sh [tag1] [tag2] [tag3] ...
# Examples:
#   ./monitor-template.sh FEATURE-START FEATURE-DONE
#   ./monitor-template.sh DEBUG-INIT DEBUG-STEP DEBUG-COMPLETE
#
# If no tags provided, monitors all logs from the configured subsystem/categories

# ============================================================================
# CONFIGURATION - Customize these for your monitoring needs
# ============================================================================

# Subsystem to monitor (reverse-DNS string identifying your feature area)
SUBSYSTEM="dev.contextify.timeline"

# Categories to monitor (space-separated, will be OR'd together in predicate)
CATEGORIES="ConversationMonitor CacheMissGenerator"

# Log level: debug (verbose) | info (default) | error (critical only)
LEVEL="debug"

# Process name (for display only)
PROCESS="Contextify"

# ============================================================================
# SCRIPT LOGIC - Generally no need to modify below this line
# ============================================================================

# Step 1: Create timestamped log file
LOGFILE="/tmp/monitor-$(date +%Y%m%d-%H%M%S).log"

# Step 2: Setup cleanup handler
cleanup() {
  echo ""
  echo "=== Logs saved to: $LOGFILE ==="
  echo "View with: cat $LOGFILE"
  exit 0
}

trap cleanup SIGINT SIGTERM

# Step 3: Build category predicate from CATEGORIES variable
# Converts "Cat1 Cat2 Cat3" → 'category == "Cat1" OR category == "Cat2" OR category == "Cat3"'
CATEGORY_PREDICATES=()
for cat in $CATEGORIES; do
  CATEGORY_PREDICATES+=("category == \"$cat\"")
done
CATEGORY_PREDICATE=$(IFS=" OR "; echo "${CATEGORY_PREDICATES[*]}")

# Step 4: Build grep pattern from command-line arguments or default to ".*" (all)
if [ $# -eq 0 ]; then
  GREP_PATTERN=".*"
  TAG_DISPLAY="all logs"
else
  GREP_PATTERN=$(IFS="|"; echo "$*")
  TAG_DISPLAY="$*"
fi

# Step 5: Display monitoring context
echo "=== OSLog Monitor ==="
echo "Process:    $PROCESS"
echo "Subsystem:  $SUBSYSTEM"
echo "Categories: $CATEGORIES"
echo "Log Level:  $LEVEL"
echo "Tags:       $TAG_DISPLAY"
echo ""
echo "Logs saved to: $LOGFILE"
echo "Press Ctrl+C to stop..."
echo ""

# Step 6: Stream logs with filtering
log stream \
  --predicate "subsystem == \"$SUBSYSTEM\" AND ($CATEGORY_PREDICATE)" \
  --level "$LEVEL" \
  --style compact 2>&1 | \
  grep --line-buffered -E "$GREP_PATTERN" | \
  tee -a "$LOGFILE" | \
  while IFS= read -r line; do
    # Step 7: Parse and simplify output
    # Input:  2025-11-07 10:12:10.633  I YourApp[67502:4b2540] [com.yourapp.yourfeature:Category] Message
    # Output: 10:12:10.633 Message

    time=$(echo "$line" | awk '{print $2}')
    # Remove everything up to and including the subsystem:category bracket
    # Note: This assumes subsystem format - customize if needed
    msg=$(echo "$line" | sed 's/^.*\[[^]]*:[^]]*\] //')

    # Step 8: Basic color-coding (customize as needed)
    case "$msg" in
      *INIT*)
        echo -e "\033[1;36m🚀 $time\033[0m $msg"  # Cyan - initialization
        ;;
      *START*)
        echo -e "\033[1;32m▶️  $time\033[0m $msg"  # Green - start
        ;;
      *STOP*|*DONE*|*COMPLETE*)
        echo -e "\033[1;35m✅ $time\033[0m $msg"  # Magenta - completion
        ;;
      *ERROR*|*FAIL*)
        echo -e "\033[1;31m❌ $time\033[0m $msg"  # Red - errors
        ;;
      *WARN*)
        echo -e "\033[1;33m⚠️  $time\033[0m $msg"  # Yellow - warnings
        ;;
      *)
        echo "$time $msg"
        ;;
    esac
  done
