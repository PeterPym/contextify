#!/bin/bash
# Nightly E2E test runner with failure notification
# Designed to run via launchd at 4am
#
# Logs persist in scripts/qa/schedule/logs/ (gitignored)
# Pass/fail history tracked in scripts/qa/schedule/history.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
DATE=$(date +%Y%m%d)
TIMESTAMP=$(date +%Y-%m-%d\ %H:%M:%S)
LOG_FILE="$LOG_DIR/qa-$DATE.log"
HISTORY_FILE="$SCRIPT_DIR/history.log"
MARKER_FILE="$HOME/Desktop/QA-FAILED-$DATE.txt"

mkdir -p "$LOG_DIR"

# Remove old marker files (keep last 7 days)
find "$HOME/Desktop" -name "QA-FAILED-*.txt" -mtime +7 -delete 2>/dev/null || true

# Remove old log files (keep last 30 days)
find "$LOG_DIR" -name "qa-*.log" -mtime +30 -delete 2>/dev/null || true

# Run E2E tests
cd "$PROJECT_DIR"
if "$QA_DIR/run-all-tests.sh" --isolate --skip-appstore > "$LOG_FILE" 2>&1; then
  # Success - log to history
  echo "$TIMESTAMP PASS" >> "$HISTORY_FILE"

  # Remove any existing failure marker
  rm -f "$HOME/Desktop"/QA-FAILED-*.txt 2>/dev/null || true
else
  # Failure
  EXIT_CODE=$?

  # Log to history
  echo "$TIMESTAMP FAIL $LOG_FILE" >> "$HISTORY_FILE"

  # Create visible desktop marker
  {
    echo "E2E Tests Failed - $(date)"
    echo ""
    echo "Log: $LOG_FILE"
    echo ""
    echo "--- Last 50 lines ---"
    tail -50 "$LOG_FILE"
  } > "$MARKER_FILE"

  # Show silent notification
  osascript -e 'display notification "Tests failed - see Desktop" with title "Contextify E2E FAILED"'

  # Go back to sleep
  osascript -e 'tell application "System Events" to sleep'

  exit $EXIT_CODE
fi

# Go back to sleep
osascript -e 'tell application "System Events" to sleep'
