#!/bin/bash
# ============================================================================
# test-app.sh - Launch archived app in clean state for QA testing
# ============================================================================
#
# Purpose:
#   Quickly test the archived release build with a fresh first-run experience.
#   Cleans database, resets permissions, and launches the archived app.
#   For DMG builds, automatically mounts the DMG and runs from the volume.
#
# Usage:
#   ./scripts/release/test-app.sh [VERSION] [OPTIONS]
#
# Options:
#   VERSION      Version to test (default: 1.0.0)
#   --dmg        Test DMG build (default: App Store build)
#   --keep-db    Don't clean the database
#   --keep-tcc   Don't reset TCC permissions
#   --no-unmount Keep DMG mounted after test (default: stays mounted)
#
# Examples:
#   ./scripts/release/test-app.sh              # Test App Store build
#   ./scripts/release/test-app.sh --dmg        # Test DMG build (mounts DMG)
#   ./scripts/release/test-app.sh 1.1.0 --dmg  # Test v1.1.0 DMG
#   ./scripts/release/test-app.sh --keep-db    # Keep existing data
#
# DMG Testing:
#   The script mounts the DMG, launches the app from the volume, and leaves
#   the volume mounted so you can test. When done, eject via Finder or:
#     hdiutil detach "/Volumes/Contextify"
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
      head -30 "$0" | tail -28 | sed 's/^# //' | sed 's/^#//'
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
MOUNTED_VOLUME=""
if [ "$DIST" = "dmg" ]; then
  # DMG build - find the DMG file
  DMG_PATH="build/archives/v${VERSION}/dmg/Contextify-${VERSION}.dmg"
  if [ ! -f "$DMG_PATH" ]; then
    DMG_PATH="dist/Contextify-${VERSION}.dmg"
  fi
  if [ ! -f "$DMG_PATH" ]; then
    DMG_PATH="dist/Contextify.dmg"
  fi

  if [ ! -f "$DMG_PATH" ]; then
    echo -e "${RED}Error: DMG not found${NC}"
    echo "Searched:"
    echo "  - build/archives/v${VERSION}/dmg/Contextify-${VERSION}.dmg"
    echo "  - dist/Contextify-${VERSION}.dmg"
    echo "  - dist/Contextify.dmg"
    echo ""
    echo "Run: ./scripts/release/build.sh $VERSION"
    exit 1
  fi

  echo -e "${BLUE}Testing v$VERSION DMG build${NC}"
  echo "  DMG: $DMG_PATH"
  echo ""

  # Check if already mounted
  if [ -d "/Volumes/Contextify" ]; then
    echo "Contextify volume already mounted, using existing mount"
    MOUNTED_VOLUME="/Volumes/Contextify"
  else
    echo "Mounting DMG..."
    # Mount and capture the volume path
    MOUNT_OUTPUT=$(hdiutil attach "$DMG_PATH" -nobrowse 2>&1)
    MOUNTED_VOLUME=$(echo "$MOUNT_OUTPUT" | grep "/Volumes/" | awk '{print $NF}')

    if [ -z "$MOUNTED_VOLUME" ] || [ ! -d "$MOUNTED_VOLUME" ]; then
      echo -e "${RED}Error: Failed to mount DMG${NC}"
      echo "$MOUNT_OUTPUT"
      exit 1
    fi
    echo "  Mounted at: $MOUNTED_VOLUME"
  fi

  APP_PATH="$MOUNTED_VOLUME/Contextify.app"
  BUNDLE_ID="dev.contextify.Contextify"

  if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: Contextify.app not found in DMG${NC}"
    echo "Contents of volume:"
    ls -la "$MOUNTED_VOLUME"
    exit 1
  fi
else
  # App Store build
  ARCHIVE_PATH="build/archives/v${VERSION}/appstore/Contextify.xcarchive"
  APP_PATH="$ARCHIVE_PATH/Products/Applications/Contextify.app"
  BUNDLE_ID="sh.contextify.Contextify"

  if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: App not found at $APP_PATH${NC}"
    echo "Run: ./scripts/release/build.sh $VERSION"
    exit 1
  fi

  echo -e "${BLUE}Testing v$VERSION App Store build${NC}"
  echo "  Archive: $ARCHIVE_PATH"
  echo ""
fi

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
echo "Launching app..."
open "$APP_PATH"

echo ""
echo -e "${GREEN}✅ App launched from: $APP_PATH${NC}"
echo ""
echo -e "${YELLOW}QA Checklist:${NC}"
if [ "$DIST" = "dmg" ]; then
  echo "  □ App launches without crash"
  echo "  □ Projects discovered automatically"
  echo "  □ Timeline entries appear"
  echo "  □ LLM summaries generate"
  echo "  □ UI is responsive"
  echo "  □ Sparkle update check works (Help > Check for Updates)"
else
  # App Store (sandboxed) - requires permission grants
  echo "  □ Permission dialog appears on first launch"
  echo "  □ Grant access to ~/.claude/projects"
  echo "  □ Projects load after granting access"
  echo "  □ Timeline entries appear"
  echo "  □ LLM summaries generate"
  echo "  □ UI is responsive"
fi

if [ "$DIST" = "dmg" ] && [ -n "$MOUNTED_VOLUME" ]; then
  echo ""
  echo -e "${BLUE}Note:${NC} DMG volume remains mounted at: $MOUNTED_VOLUME"
  echo "      When done testing, eject via Finder or run:"
  echo "      hdiutil detach \"$MOUNTED_VOLUME\""
fi
