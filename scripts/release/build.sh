#!/bin/bash
# Release workflow build script - wraps build-release.sh with version tracking
#
# Usage: ./scripts/release/build.sh X.Y.Z [--skip-dmg] [--skip-appstore] [--dry-run]
#
# This script:
#   1. Validates release directory exists
#   2. Runs pre-flight checks (tests, version match)
#   3. Calls scripts/build-release.sh to build both distributions
#   4. Archives outputs to build/archives/v{VERSION}/
#   5. Updates releases/v{VERSION}/release.json with results
#
# For standalone builds without release tracking, use: scripts/build-release.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
VERSION=""
SKIP_DMG=false
SKIP_APPSTORE=false
DRY_RUN=false
NO_NOTARIZE=false
BUILD_ARGS=""

for arg in "$@"; do
  case $arg in
    --skip-dmg)
      SKIP_DMG=true
      BUILD_ARGS="$BUILD_ARGS --skip-dmg"
      ;;
    --skip-appstore)
      SKIP_APPSTORE=true
      BUILD_ARGS="$BUILD_ARGS --skip-appstore"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --no-notarize)
      NO_NOTARIZE=true
      BUILD_ARGS="$BUILD_ARGS --no-notarize"
      ;;
    --help|-h)
      echo "Usage: $0 X.Y.Z [--skip-dmg] [--skip-appstore] [--dry-run] [--no-notarize]"
      echo ""
      echo "Release workflow build with version tracking and archiving."
      echo ""
      echo "Options:"
      echo "  --skip-dmg       Skip DMG build"
      echo "  --skip-appstore  Skip App Store build"
      echo "  --dry-run        Show what would be done without executing"
      echo "  --no-notarize    Skip notarization (faster for testing)"
      echo ""
      echo "This script wraps scripts/build-release.sh and adds:"
      echo "  - Release directory validation"
      echo "  - Artifact archiving to build/archives/v{VERSION}/"
      echo "  - release.json updates"
      exit 0
      ;;
    *)
      if [ -z "$VERSION" ]; then
        VERSION="$arg"
      fi
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "Usage: $0 X.Y.Z [--skip-dmg] [--skip-appstore] [--dry-run]"
  exit 1
fi

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_DIR="$ROOT_DIR/releases/v${VERSION}"
ARCHIVE_DIR="$ROOT_DIR/build/archives/v${VERSION}"
RELEASE_JSON="$RELEASE_DIR/release.json"

# Validate release directory
if [ ! -d "$RELEASE_DIR" ]; then
  echo -e "${RED}Error: Release directory not found: $RELEASE_DIR${NC}"
  echo "Run './scripts/release/init.sh $VERSION' first"
  exit 1
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Release Build: v${VERSION}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Pre-flight: Version check
XCODE_VERSION=$(grep -m1 "MARKETING_VERSION" "$ROOT_DIR/Contextify/Contextify.xcodeproj/project.pbxproj" | sed 's/.*= //' | tr -d ';' | tr -d ' ')
if [ "$XCODE_VERSION" != "$VERSION" ]; then
  echo -e "${RED}Error: Version mismatch${NC}"
  echo "  Xcode project: $XCODE_VERSION"
  echo "  Expected: $VERSION"
  exit 1
fi

BUILD_NUMBER=$(grep -m1 "CURRENT_PROJECT_VERSION" "$ROOT_DIR/Contextify/Contextify.xcodeproj/project.pbxproj" | sed 's/.*= //' | tr -d ';' | tr -d ' ')
COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
COMMIT_SHORT="${COMMIT:0:8}"

echo "  Version:  $VERSION"
echo "  Build:    $BUILD_NUMBER"
echo "  Commit:   $COMMIT_SHORT"
echo "  Dry run:  $([ "$DRY_RUN" = true ] && echo 'Yes' || echo 'No')"
echo ""

# Pre-flight: Tests
echo -e "${BLUE}==>${NC} Running tests..."
if [ "$DRY_RUN" = false ]; then
  cd "$ROOT_DIR"
  if swift test 2>&1 | tail -3 | grep -q "with 0 failures"; then
    echo -e "${GREEN}OK${NC} Tests passed"
  else
    echo -e "${RED}Error: Tests failed${NC}"
    exit 1
  fi
else
  echo -e "${YELLOW}[dry-run]${NC} swift test"
fi

# Create archive directories
echo -e "${BLUE}==>${NC} Creating archive directories..."
if [ "$DRY_RUN" = false ]; then
  mkdir -p "$ARCHIVE_DIR/appstore"
  mkdir -p "$ARCHIVE_DIR/dmg"
else
  echo -e "${YELLOW}[dry-run]${NC} mkdir -p $ARCHIVE_DIR/{appstore,dmg}"
fi

# Run canonical build script
echo -e "${BLUE}==>${NC} Running build-release.sh..."
if [ "$DRY_RUN" = false ]; then
  cd "$ROOT_DIR"
  bash scripts/build-release.sh $BUILD_ARGS
else
  echo -e "${YELLOW}[dry-run]${NC} bash scripts/build-release.sh $BUILD_ARGS"
fi

# Archive artifacts
echo -e "${BLUE}==>${NC} Archiving artifacts..."
if [ "$DRY_RUN" = false ]; then
  # App Store artifacts
  if [ "$SKIP_APPSTORE" = false ] && [ -d "$ROOT_DIR/build/Contextify.xcarchive" ]; then
    cp -R "$ROOT_DIR/build/Contextify.xcarchive" "$ARCHIVE_DIR/appstore/Contextify.xcarchive"
    echo -e "${GREEN}OK${NC} Archived: appstore/Contextify.xcarchive"
  fi

  if [ "$SKIP_APPSTORE" = false ] && [ -f "$ROOT_DIR/build/appstore/Contextify.pkg" ]; then
    cp "$ROOT_DIR/build/appstore/Contextify.pkg" "$ARCHIVE_DIR/appstore/Contextify-${VERSION}.pkg"
    echo -e "${GREEN}OK${NC} Archived: appstore/Contextify-${VERSION}.pkg"
  fi

  # DMG artifacts
  if [ "$SKIP_DMG" = false ] && [ -f "$ROOT_DIR/dist/Contextify-${VERSION}.dmg" ]; then
    cp "$ROOT_DIR/dist/Contextify-${VERSION}.dmg" "$ARCHIVE_DIR/dmg/"
    echo -e "${GREEN}OK${NC} Archived: dmg/Contextify-${VERSION}.dmg"
  fi
else
  echo -e "${YELLOW}[dry-run]${NC} cp artifacts to $ARCHIVE_DIR/{appstore,dmg}/"
fi

# Update release.json
echo -e "${BLUE}==>${NC} Updating release.json..."
if [ "$DRY_RUN" = false ]; then
  python3 << EOF
import json
from datetime import date

with open('$RELEASE_JSON', 'r') as f:
    data = json.load(f)

# Update git info
data['git']['commit'] = '$COMMIT'
data['updated'] = str(date.today())

# Update build phase
data['phases']['build']['status'] = 'complete'

if not $SKIP_APPSTORE:
    data['phases']['build']['appstore']['archived'] = True
    data['phases']['build']['appstore']['archive_path'] = '$ARCHIVE_DIR/appstore/Contextify.xcarchive'
    data['phases']['build']['appstore']['build_number'] = $BUILD_NUMBER
    data['phases']['build']['appstore']['exported'] = True

if not $SKIP_DMG:
    data['phases']['build']['dmg']['built'] = True
    data['phases']['build']['dmg']['path'] = 'dist/Contextify-${VERSION}.dmg'
    data['phases']['build']['dmg']['signed'] = True
    data['phases']['build']['dmg']['notarized'] = not $NO_NOTARIZE

# Add note
data['notes'].append({
    'date': str(date.today()),
    'author': 'system',
    'note': f'Build $BUILD_NUMBER completed (commit $COMMIT_SHORT)'
})

with open('$RELEASE_JSON', 'w') as f:
    json.dump(data, f, indent=2)

print('Updated release.json')
EOF
else
  echo -e "${YELLOW}[dry-run]${NC} Update release.json"
fi

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Release Build Complete${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Version:  $VERSION"
echo "  Build:    $BUILD_NUMBER"
echo "  Commit:   $COMMIT_SHORT"
echo ""
echo "Archived to: $ARCHIVE_DIR"
if [ "$DRY_RUN" = false ]; then
  ls -la "$ARCHIVE_DIR" 2>/dev/null || true
fi
echo ""
echo "Next steps:"
if [ "$SKIP_APPSTORE" = false ]; then
  echo "  1. Upload to App Store: bash scripts/xc.sh upload"
fi
if [ "$SKIP_DMG" = false ]; then
  echo "  2. Update appcast.xml and deploy to website"
fi
echo "  3. Continue with Phase 3: releases/v${VERSION}/checklists/03-review-materials.md"
echo ""
