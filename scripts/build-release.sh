#!/bin/bash
# Canonical release build script - builds both DMG and App Store distributions
# Counterpart to scripts/xc.sh (used during development)
#
# Usage: ./scripts/build-release.sh [--skip-dmg] [--skip-appstore] [--no-notarize]
#
# This is the core build logic. For release workflow integration with
# version tracking and release.json updates, use: ./scripts/release/build.sh
#
# Outputs:
#   - App Store: build/Contextify.xcarchive, build/appstore/Contextify.pkg
#   - DMG: dist/Contextify-{VERSION}.dmg (signed, notarized)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
SKIP_DMG=false
SKIP_APPSTORE=false
NO_NOTARIZE=false

for arg in "$@"; do
  case $arg in
    --skip-dmg)
      SKIP_DMG=true
      ;;
    --skip-appstore)
      SKIP_APPSTORE=true
      ;;
    --no-notarize)
      NO_NOTARIZE=true
      ;;
    --help|-h)
      echo "Usage: $0 [--skip-dmg] [--skip-appstore] [--no-notarize]"
      echo ""
      echo "Builds both DMG and App Store distributions for release."
      echo ""
      echo "Options:"
      echo "  --skip-dmg       Skip DMG build (App Store only)"
      echo "  --skip-appstore  Skip App Store build (DMG only)"
      echo "  --no-notarize    Skip notarization (faster for testing)"
      echo ""
      echo "Related scripts:"
      echo "  scripts/xc.sh              - Development builds and Xcode operations"
      echo "  scripts/release/build.sh   - Release workflow with version tracking"
      exit 0
      ;;
  esac
done

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get version from Xcode project
VERSION=$(grep -m1 "MARKETING_VERSION" "$ROOT_DIR/Contextify/Contextify.xcodeproj/project.pbxproj" | sed 's/.*= //' | tr -d ';' | tr -d ' ')
BUILD_NUMBER=$(grep -m1 "CURRENT_PROJECT_VERSION" "$ROOT_DIR/Contextify/Contextify.xcodeproj/project.pbxproj" | sed 's/.*= //' | tr -d ';' | tr -d ' ')

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Contextify Release Build${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Version:     $VERSION"
echo "  Build:       $BUILD_NUMBER"
echo "  DMG:         $([ "$SKIP_DMG" = true ] && echo 'Skip' || echo 'Build')"
echo "  App Store:   $([ "$SKIP_APPSTORE" = true ] && echo 'Skip' || echo 'Build')"
echo "  Notarize:    $([ "$NO_NOTARIZE" = true ] && echo 'Skip' || echo 'Yes')"
echo ""

cd "$ROOT_DIR"

# Build App Store
if [ "$SKIP_APPSTORE" = false ]; then
  echo -e "${BLUE}==>${NC} Building App Store archive..."

  bash scripts/xc.sh --dist=appstore Release dev-archive

  if [ ! -d "build/Contextify.xcarchive" ]; then
    echo -e "${RED}Error: Archive not created${NC}"
    exit 1
  fi
  echo -e "${GREEN}OK${NC} Archive: build/Contextify.xcarchive"

  echo -e "${BLUE}==>${NC} Exporting .pkg..."
  bash scripts/xc.sh export-pkg

  if [ -f "build/appstore/Contextify.pkg" ]; then
    PKG_SIZE=$(stat -f%z "build/appstore/Contextify.pkg" 2>/dev/null || stat -c%s "build/appstore/Contextify.pkg" 2>/dev/null)
    echo -e "${GREEN}OK${NC} Package: build/appstore/Contextify.pkg ($PKG_SIZE bytes)"
  else
    echo -e "${YELLOW}Warning: .pkg export may have failed${NC}"
  fi
fi

# Build DMG
if [ "$SKIP_DMG" = false ]; then
  echo -e "${BLUE}==>${NC} Building DMG..."

  RELEASE_ARGS="--version $VERSION --yes"
  if [ "$NO_NOTARIZE" = true ]; then
    RELEASE_ARGS="$RELEASE_ARGS --no-notarize"
  fi

  python3 scripts/release.py $RELEASE_ARGS

  DMG_PATH="dist/Contextify-${VERSION}.dmg"
  if [ -f "$DMG_PATH" ]; then
    DMG_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat -c%s "$DMG_PATH" 2>/dev/null)
    DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)
    echo -e "${GREEN}OK${NC} DMG: $DMG_PATH ($DMG_SIZE bytes)"
    echo -e "${GREEN}OK${NC} SHA256: $DMG_SHA256"

    # Sign for Sparkle if available
    if [ -x "scripts/sparkle/sign.sh" ]; then
      echo -e "${BLUE}==>${NC} Signing for Sparkle..."
      scripts/sparkle/sign.sh "$DMG_PATH" || true
    fi
  else
    echo -e "${RED}Error: DMG not created${NC}"
    exit 1
  fi
fi

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Build Complete${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Artifacts:"
[ "$SKIP_APPSTORE" = false ] && echo "  - build/Contextify.xcarchive"
[ "$SKIP_APPSTORE" = false ] && echo "  - build/appstore/Contextify.pkg"
[ "$SKIP_DMG" = false ] && echo "  - dist/Contextify-${VERSION}.dmg"
echo ""
echo "Next steps:"
[ "$SKIP_APPSTORE" = false ] && echo "  - Upload to App Store: bash scripts/xc.sh upload"
[ "$SKIP_DMG" = false ] && echo "  - Deploy DMG to website"
echo ""
