#!/bin/bash
# Validate build artifacts
# Usage: ./scripts/release/validate-build.sh X.Y.Z

set -e

VERSION="${1}"
FAILED=0

if [ -z "$VERSION" ]; then
  echo "Usage: $0 X.Y.Z"
  exit 1
fi

echo "=========================================="
echo "Build Validation for v${VERSION}"
echo "=========================================="
echo ""

# Check 1: DMG exists
echo "1. Checking DMG..."
DMG_PATH="dist/Contextify-${VERSION}.dmg"
if [ -f "$DMG_PATH" ]; then
  SIZE=$(ls -lh "$DMG_PATH" | awk '{print $5}')
  echo "   PASS: DMG exists ($SIZE)"

  # Check code signature
  if codesign -dv "$DMG_PATH" 2>&1 | grep -q "Signature="; then
    echo "   PASS: DMG is code signed"
  else
    echo "   WARN: DMG signature not verified"
  fi
else
  echo "   FAIL: DMG not found at $DMG_PATH"
  FAILED=1
fi
echo ""

# Check 2: App Store archive exists
echo "2. Checking App Store archive..."
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
  FAILED=1
fi
echo ""

# Check 3: Export package
echo "3. Checking export package..."
PKG_PATH="build/appstore/Contextify.pkg"
if [ -f "$PKG_PATH" ]; then
  SIZE=$(ls -lh "$PKG_PATH" | awk '{print $5}')
  echo "   PASS: Package exists ($SIZE)"
else
  echo "   INFO: Package not found (may not be exported yet)"
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
  echo "Ready to proceed to Phase 3: Review Materials"
  exit 0
else
  echo "RESULT: Some artifacts missing"
  echo "Complete build phase before proceeding"
  exit 1
fi
