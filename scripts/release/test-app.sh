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
#   ./scripts/release/test-app.sh [VERSION] [OPTIONS]
#
# Options:
#   VERSION    Version to test (default: 1.0.0)
#   --dmg      Test DMG build (default: App Store build)
#   --keep-db  Don't clean the database
#   --keep-tcc Don't reset TCC permissions
#
# Examples:
#   ./scripts/release/test-app.sh              # Test App Store build
#   ./scripts/release/test-app.sh --dmg        # Test DMG build
#   ./scripts/release/test-app.sh 1.1.0 --dmg  # Test v1.1.0 DMG
#   ./scripts/release/test-app.sh --keep-db    # Keep existing data
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

# Defaults
VERSION="1.0.0"
DIST="appstore"
CLEAN_DB=true
RESET_TCC=true

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      DIST="dmg"
      shift
      ;;
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

# Set paths based on distribution
if [ "$DIST" = "dmg" ]; then
  # DMG build - check multiple locations
  APP_PATH="build/archives/v${VERSION}/dmg/Contextify.app"
  if [ ! -d "$APP_PATH" ]; then
    # Try mounted DMG or dist folder
    APP_PATH="dist/Contextify.app"
  fi
  if [ ! -d "$APP_PATH" ]; then
    # Try derived data
    APP_PATH=".derived/Build/Products/Release/Contextify.app"
  fi
  BUNDLE_ID="dev.contextify.Contextify"
else
  # App Store build
  ARCHIVE_PATH="build/archives/v${VERSION}/appstore/Contextify.xcarchive"
  APP_PATH="$ARCHIVE_PATH/Products/Applications/Contextify.app"
  BUNDLE_ID="sh.contextify.Contextify"
fi

# Verify archive exists
if [ ! -d "$APP_PATH" ]; then
  echo "Error: App not found at $APP_PATH"
  if [ "$DIST" = "dmg" ]; then
    echo "Run: ./scripts/release/build.sh $VERSION (or python3 scripts/release.py)"
  else
    echo "Run: ./scripts/release/build.sh $VERSION"
  fi
  exit 1
fi

echo "Testing v$VERSION $DIST build"
echo ""

# Quit any running instance
echo "Quitting Contextify..."
osascript -e 'tell application "Contextify" to quit' 2>/dev/null || true
pkill -x Contextify 2>/dev/null || true
sleep 1

# Clean database
if [ "$CLEAN_DB" = true ]; then
  echo "Cleaning database..."
  CONTEXTIFY_DIST="$DIST" ./scripts/db_manager.sh clean --force 2>&1 | grep -E "^[ℹ✓]" || true
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
