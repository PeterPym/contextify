#!/bin/bash
# QA-13b: CLI Install Admin Fallback (DMG Build)
#
# Purpose: Validates admin dialog appears for non-homebrew users and fallback works
#
# Test Strategy:
# - Cannot test actual admin install in automation (requires real password)
# - CAN test dialog appearance via OSLog tags
# - CAN test ~/bin fallback path after dialog choice
# - Manual QA required for full admin password flow

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/assertions.sh"

echo "═══════════════════════════════════════════════════════════════"
echo "  QA-13b: CLI Install Admin Fallback (DMG)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Verify we're running DMG build
if is_appstore_build; then
  echo "❌ SKIP: This test requires DMG build (admin fallback not available in App Store)"
  exit 0
fi

# Check if homebrew paths are writable (skip test if they are)
if [[ -w "/opt/homebrew/bin" ]] || [[ -w "/usr/local/bin" ]]; then
  echo "⚠️  SKIP: Homebrew paths are writable - admin dialog won't appear"
  echo "   To test admin fallback, run:"
  echo "   sudo chown root:wheel /opt/homebrew/bin /usr/local/bin"
  echo "   Then rerun this test"
  echo "   (Don't forget to restore: sudo chown \$(whoami):admin /opt/homebrew/bin /usr/local/bin)"
  exit 0
fi

echo "✓ Non-homebrew environment detected (no writable system paths)"
echo ""

# Clean any existing CLI installation
echo "Cleaning existing CLI installation..."
rm -f ~/bin/contextify-query 2>/dev/null || true
rm -rf ~/.claude/plugins/cache/contextify 2>/dev/null || true

# Start log monitoring
echo "Starting log monitoring..."
LOG_FILE="/tmp/qa-13b-logs-$$.txt"
log stream --predicate 'subsystem == "dev.contextify" AND category == "CLICoordinator"' --level debug > "$LOG_FILE" 2>&1 &
LOG_PID=$!
sleep 2  # Give log stream time to start

# Cleanup function
cleanup() {
  if [[ -n "${LOG_PID:-}" ]]; then
    kill "$LOG_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE" 2>/dev/null || true
}
trap cleanup EXIT

echo "Launching app..."
launch_app

echo "Waiting for app to fully start..."
sleep 5

# Navigate to CLI settings
echo "Opening Settings > CLI & Skills..."
# TODO: Add UI automation to click Settings and navigate to CLI tab
# For now, this requires manual intervention

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  MANUAL STEPS REQUIRED"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "1. In the running app, open Settings > CLI & Skills"
echo "2. Click 'Enable' button"
echo "3. When dialog appears, click 'Install to ~/bin'"
echo "   (Do NOT click 'Request Admin Access' - we can't test password in automation)"
echo "4. Wait for installation to complete"
echo "5. Press ENTER here to continue test validation"
echo ""
read -p "Press ENTER after completing manual steps... "

echo ""
echo "Validating results..."
echo ""

# Stop log monitoring
kill "$LOG_PID" 2>/dev/null || true
wait "$LOG_PID" 2>/dev/null || true

# Validate log tags
echo "Checking OSLog tags..."

if grep -q "\[CLI-NO-WRITABLE-PATHS\]" "$LOG_FILE"; then
  echo "✓ Found [CLI-NO-WRITABLE-PATHS]"
else
  echo "❌ Missing [CLI-NO-WRITABLE-PATHS] - admin dialog should have been triggered"
  cat "$LOG_FILE"
  exit 1
fi

if grep -q "\[CLI-ADMIN-DIALOG-SHOWN\]" "$LOG_FILE" || grep -q "\[CLI-ADMIN-DIALOG-DECLINED-HOMEBIN\]" "$LOG_FILE"; then
  echo "✓ Found admin dialog log tag"
else
  echo "❌ Missing admin dialog log tags"
  cat "$LOG_FILE"
  exit 1
fi

if grep -q "\[CLI-FALLBACK-HOMEBIN\]" "$LOG_FILE"; then
  echo "✓ Found [CLI-FALLBACK-HOMEBIN]"
else
  echo "❌ Missing [CLI-FALLBACK-HOMEBIN]"
  cat "$LOG_FILE"
  exit 1
fi

if grep -q "\[CLI-INSTALL-SUCCESS\]" "$LOG_FILE"; then
  echo "✓ Found [CLI-INSTALL-SUCCESS]"
else
  echo "❌ Missing [CLI-INSTALL-SUCCESS]"
  cat "$LOG_FILE"
  exit 1
fi

# Validate shim installation
echo ""
echo "Checking shim installation..."

if [[ -x ~/bin/contextify-query ]]; then
  echo "✓ Shim installed at ~/bin/contextify-query"
else
  echo "❌ Shim not found at ~/bin/contextify-query"
  exit 1
fi

# Validate plugin installation
echo "Checking plugin installation..."

if [[ -d ~/.claude/plugins/cache/contextify ]]; then
  echo "✓ Plugin directory exists"
else
  echo "❌ Plugin directory not found"
  exit 1
fi

# Validate manifest
if grep -q "query@contextify" ~/.claude/plugins/installed_plugins.json 2>/dev/null; then
  echo "✓ Plugin manifest updated"
else
  echo "❌ Plugin manifest not updated"
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ QA-13b PASSED: Admin Fallback Working"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Validated:"
echo "  • Admin dialog was shown (log tags present)"
echo "  • User chose ~/bin option"
echo "  • Installation succeeded to ~/bin"
echo "  • Plugin installed correctly"
echo ""
echo "⚠️  Note: Full admin install flow requires manual testing"
echo "   See Test 13 in QA test plan for password prompt validation"
echo ""

exit 0
