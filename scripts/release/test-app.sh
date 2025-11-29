#!/bin/bash
# ============================================================================
# test-app.sh - Launch archived app in clean state for QA testing
# ============================================================================
#
# Purpose:
#   Quickly test the archived release build with a fresh first-run experience.
#   Cleans database, resets permissions, and launches the archived app.
#
# Usage:
#   ./scripts/release/test-app.sh [VERSION]
#
# Options:
#   VERSION    Version to test (default: 1.0.0)
#   --keep-db  Don't clean the database
#   --keep-tcc Don't reset TCC permissions
#
# Examples:
#   ./scripts/release/test-app.sh           # Test v1.0.0 with full reset
#   ./scripts/release/test-app.sh 1.1.0     # Test v1.1.0
#   ./scripts/release/test-app.sh --keep-db # Keep existing data
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

# Defaults
VERSION="1.0.0"
CLEAN_DB=true
RESET_TCC=true

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-db)
      CLEAN_DB=false
      shift
      ;;
    --keep-tcc)
      RESET_TCC=false
      shift
      ;;
    --help|-h)
      head -25 "$0" | tail -23 | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      VERSION="$1"
      shift
      ;;
  esac
done

ARCHIVE_PATH="build/archives/v${VERSION}/appstore/Contextify.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Contextify.app"
BUNDLE_ID="sh.contextify.Contextify"

# Verify archive exists
if [ ! -d "$APP_PATH" ]; then
  echo "Error: Archive not found at $APP_PATH"
  echo "Run: ./scripts/release/build.sh $VERSION"
  exit 1
fi

echo "Testing v$VERSION archived build"
echo ""

# Quit any running instance
echo "Quitting Contextify..."
osascript -e 'tell application "Contextify" to quit' 2>/dev/null || true
pkill -x Contextify 2>/dev/null || true
sleep 1

# Clean database
if [ "$CLEAN_DB" = true ]; then
  echo "Cleaning database..."
  CONTEXTIFY_DIST=appstore ./scripts/db_manager.sh clean --force 2>&1 | grep -E "^[ℹ✓]" || true
fi

# Reset TCC permissions
if [ "$RESET_TCC" = true ]; then
  echo "Resetting TCC permissions..."
  tccutil reset All "$BUNDLE_ID" 2>/dev/null || true
fi

# Launch
echo ""
echo "Launching archived app..."
open "$APP_PATH"

echo ""
echo "✅ App launched from: $APP_PATH"
echo ""
echo "Watch for:"
echo "  - Permission dialog appears"
echo "  - Projects load after granting access"
echo "  - UI responsiveness"
