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

  # Always unmount any existing Contextify volume to ensure we test the correct DMG
  if [ -d "/Volumes/Contextify" ]; then
    echo "Unmounting existing Contextify volume (may be stale)..."

    # Aggressively quit app - try graceful, then force kill
    osascript -e 'tell application "Contextify" to quit' 2>/dev/null || true
    sleep 1
    pkill -x Contextify 2>/dev/null || true
    sleep 1
    # Force kill if still running
    pkill -9 -x Contextify 2>/dev/null || true
    sleep 1

    # Try to unmount, retry with force if needed
    if ! hdiutil detach "/Volumes/Contextify" 2>/dev/null; then
      echo "  Retrying unmount with force..."
      hdiutil detach "/Volumes/Contextify" -force 2>/dev/null || true
      sleep 1
    fi

    # Verify unmount succeeded
    if [ -d "/Volumes/Contextify" ]; then
      echo -e "${RED}Error: Failed to unmount existing Contextify volume${NC}"
      echo "  The app may still be running or the volume is in use."
      echo "  Try: diskutil eject \$(diskutil list | grep -B2 Contextify | grep '/dev' | awk '{print \$1}')"
      exit 1
    fi
  fi

  # Record the DMG we're about to mount (for verification)
  DMG_MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$DMG_PATH")
  DMG_SIZE=$(stat -f "%z" "$DMG_PATH")
  echo "  DMG modified: $DMG_MODIFIED"
  echo "  DMG size: $DMG_SIZE bytes"
  echo ""

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

  APP_PATH="$MOUNTED_VOLUME/Contextify.app"
  BUNDLE_ID="dev.contextify.Contextify"

  if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: Contextify.app not found in DMG${NC}"
    echo "Contents of volume:"
    ls -la "$MOUNTED_VOLUME"
    exit 1
  fi

  # Verify the mounted app matches the DMG we intended to mount
  APP_BINARY="$APP_PATH/Contents/MacOS/Contextify"
  if [ -f "$APP_BINARY" ]; then
    APP_MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$APP_BINARY")
    echo "  App binary: $APP_MODIFIED"

    # Compare timestamps - app should be within a few hours of DMG
    DMG_EPOCH=$(stat -f "%m" "$DMG_PATH")
    APP_EPOCH=$(stat -f "%m" "$APP_BINARY")
    TIME_DIFF=$((DMG_EPOCH - APP_EPOCH))

    # If app is more than 2 hours older than DMG, something is wrong
    if [ $TIME_DIFF -gt 7200 ]; then
      echo ""
      echo -e "${RED}⚠️  WARNING: App binary is significantly older than DMG!${NC}"
      echo -e "${RED}   This may indicate the wrong DMG was mounted.${NC}"
      echo ""
      echo "  DMG modified: $DMG_MODIFIED"
      echo "  App binary:   $APP_MODIFIED"
      echo ""
      read -p "Continue anyway? [y/N] " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting."
        hdiutil detach "$MOUNTED_VOLUME" -force 2>/dev/null || true
        exit 1
      fi
    fi
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
