#!/bin/bash
# ============================================================================
# validate-build.sh - Validate build artifacts for a release
# ============================================================================
#
# Purpose:
#   Validates that required build artifacts exist for targeted channels.
#   Only requires artifacts for channels specified in target_channels.
#
# Usage:
#   ./scripts/release/validate-build.sh X.Y.Z
#
# Exit Codes:
#   0 - All required artifacts present
#   1 - Missing required artifacts
#
# Examples:
#   ./scripts/release/validate-build.sh 1.0.0
#   ./scripts/release/validate-build.sh 1.0.1  # DMG-only, won't require App Store
# ============================================================================

set -e

VERSION="${1}"
FAILED=0

if [ -z "$VERSION" ]; then
  echo "Usage: $0 X.Y.Z"
  exit 1
fi

# Source guards for target channel detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/scripts/release/lib/guards.sh"

# Get targeting info
TARGETS=$(get_target_channels "$VERSION")
DMG_TARGETED=false
APPSTORE_TARGETED=false
[[ " $TARGETS " == *" dmg "* ]] && DMG_TARGETED=true
[[ " $TARGETS " == *" appstore "* ]] && APPSTORE_TARGETED=true

echo "=========================================="
echo "Build Validation for v${VERSION}"
echo "Targeting: ${TARGETS:-both (default)}"
echo "=========================================="
echo ""

# Check 1: DMG (only if targeted)
echo "1. Checking DMG..."
if [ "$DMG_TARGETED" = true ]; then
  DMG_PATH="dist/Contextify-${VERSION}.dmg"
  PRESERVED_DMG="build/archives/v${VERSION}/dmg/Contextify-${VERSION}.dmg"

  if [ -f "$DMG_PATH" ] || [ -f "$PRESERVED_DMG" ]; then
    if [ -f "$PRESERVED_DMG" ]; then
      SIZE=$(ls -lh "$PRESERVED_DMG" | awk '{print $5}')
      echo "   PASS: DMG exists at archives/ ($SIZE)"
    else
      SIZE=$(ls -lh "$DMG_PATH" | awk '{print $5}')
      echo "   PASS: DMG exists at dist/ ($SIZE)"
    fi

    # Check code signature
    ACTUAL_DMG="${PRESERVED_DMG:-$DMG_PATH}"
    [ -f "$PRESERVED_DMG" ] && ACTUAL_DMG="$PRESERVED_DMG"
    if codesign -dv "$ACTUAL_DMG" 2>&1 | grep -q "Signature="; then
      echo "   PASS: DMG is code signed"
    else
      echo "   WARN: DMG signature not verified"
    fi
  else
    echo "   FAIL: DMG not found"
    echo "         Expected: $DMG_PATH or $PRESERVED_DMG"
    FAILED=1
  fi
else
  echo "   SKIP: DMG not targeted"
fi
echo ""

# Check 2: App Store archive (only if targeted)
echo "2. Checking App Store archive..."
if [ "$APPSTORE_TARGETED" = true ]; then
  ARCHIVE_PATH="build/Contextify.xcarchive"
  PRESERVED_ARCHIVE="build/archives/v${VERSION}/appstore/Contextify.xcarchive"

  if [ -d "$ARCHIVE_PATH" ] || [ -d "$PRESERVED_ARCHIVE" ]; then
    if [ -d "$PRESERVED_ARCHIVE" ]; then
      echo "   PASS: Preserved archive exists at appstore/"
    else
      echo "   INFO: Archive at $ARCHIVE_PATH (not yet archived)"
    fi
  else
    echo "   FAIL: Archive not found"
    echo "         Expected: $ARCHIVE_PATH or $PRESERVED_ARCHIVE"
    FAILED=1
  fi
else
  echo "   SKIP: App Store not targeted"
fi
echo ""

# Check 3: Export package (only if App Store targeted)
echo "3. Checking export package..."
if [ "$APPSTORE_TARGETED" = true ]; then
  PKG_PATH="build/appstore/Contextify.pkg"
  PRESERVED_PKG="build/archives/v${VERSION}/appstore/Contextify-${VERSION}.pkg"

  if [ -f "$PKG_PATH" ] || [ -f "$PRESERVED_PKG" ]; then
    if [ -f "$PRESERVED_PKG" ]; then
      SIZE=$(ls -lh "$PRESERVED_PKG" | awk '{print $5}')
      echo "   PASS: Package exists at archives/ ($SIZE)"
    else
      SIZE=$(ls -lh "$PKG_PATH" | awk '{print $5}')
      echo "   INFO: Package at $PKG_PATH (not yet archived)"
    fi
  else
    echo "   INFO: Package not found (may not be exported yet)"
  fi
else
  echo "   SKIP: App Store not targeted"
fi
echo ""

# Check 4: Release directory
echo "4. Checking release directory..."
RELEASE_DIR="releases/v${VERSION}"
if [ -d "$RELEASE_DIR" ]; then
  echo "   PASS: Release directory exists"

  if [ -f "$RELEASE_DIR/release.json" ]; then
    echo "   PASS: release.json exists"
  else
    echo "   WARN: release.json not found"
  fi
else
  echo "   WARN: Release directory not found at $RELEASE_DIR"
fi
echo ""

# Summary
echo "=========================================="
if [ "$FAILED" -eq 0 ]; then
  echo "RESULT: Build artifacts validated"
  if [ "$APPSTORE_TARGETED" = true ]; then
    echo "Ready to proceed to Phase 3: Review Materials"
  else
    echo "Ready to proceed to Phase 5: Marketing (DMG-only)"
  fi
  exit 0
else
  echo "RESULT: Some artifacts missing"
  echo "Complete build phase before proceeding"
  exit 1
fi
