#!/bin/bash
# Nightly QA test runner with failure notification
# Designed to run via cron/launchd at 4am

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="/tmp/qa-nightly"
DATE=$(date +%Y%m%d)
LOG_FILE="$LOG_DIR/qa-$DATE.log"
MARKER_FILE="$HOME/Desktop/QA-FAILED-$DATE.txt"

mkdir -p "$LOG_DIR"

# Remove old marker files (keep last 7 days)
find "$HOME/Desktop" -name "QA-FAILED-*.txt" -mtime +7 -delete 2>/dev/null || true

# Run QA tests
cd "$PROJECT_DIR"
if ./scripts/qa/run-all-tests.sh --isolate --skip-appstore > "$LOG_FILE" 2>&1; then
  # Success - remove any existing failure marker
  rm -f "$HOME/Desktop"/QA-FAILED-*.txt 2>/dev/null || true
else
  # Failure
  EXIT_CODE=$?

  # Create visible desktop marker
  {
    echo "QA Tests Failed - $(date)"
    echo ""
    echo "Log: $LOG_FILE"
    echo ""
    echo "--- Last 50 lines ---"
    tail -50 "$LOG_FILE"
  } > "$MARKER_FILE"

  # Show notification
  osascript -e 'display notification "Tests failed - see Desktop" with title "Contextify QA FAILED"'

  exit $EXIT_CODE
fi
