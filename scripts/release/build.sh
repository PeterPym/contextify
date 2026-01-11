#!/bin/bash
# ============================================================================
# build.sh - Build both distributions with release tracking
# ============================================================================
#
# Purpose:
#   Builds DMG and App Store distributions for a release, archives artifacts,
#   and updates tracking state in both release.json and manifest.json.
#
# Usage:
#   ./scripts/release/build.sh X.Y.Z [OPTIONS]
#
# Options:
#   --skip-dmg       Skip DMG build
#   --skip-appstore  Skip App Store build
#   --skip-linux     Skip Linux build
#   --dry-run        Show what would be done without executing
#   --no-notarize    Skip notarization (faster for testing)
#
# State Changes:
#   - releases/vX.Y.Z/release.json: Build phase marked complete, artifact paths
#   - releases/manifest.json: Build status and build_number updated
#   - build/archives/vX.Y.Z/: Artifacts archived
#
# Prerequisites:
#   - Release directory exists (run init.sh first)
#   - Xcode MARKETING_VERSION matches X.Y.Z
#   - All tests must pass
#
# Exit Codes:
#   0 - Success
#   1 - Error (tests failed, version mismatch, build failed)
#
# Examples:
#   ./scripts/release/build.sh 1.0.0
#   ./scripts/release/build.sh 1.0.0 --skip-dmg
#   ./scripts/release/build.sh 1.0.0 --dry-run
#
# For standalone builds without tracking: scripts/build-release.sh
# ============================================================================

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
SKIP_LINUX=false
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
    --skip-linux)
      SKIP_LINUX=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --no-notarize)
      NO_NOTARIZE=true
      BUILD_ARGS="$BUILD_ARGS --no-notarize"
      ;;
    --help|-h)
      echo "Usage: $0 X.Y.Z [--skip-dmg] [--skip-appstore] [--skip-linux] [--dry-run] [--no-notarize]"
      echo ""
      echo "Release workflow build with version tracking and archiving."
      echo ""
      echo "Options:"
      echo "  --skip-dmg       Skip DMG build"
      echo "  --skip-appstore  Skip App Store build"
      echo "  --skip-linux     Skip Linux build"
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

# Source guards for targeting helpers
source "$ROOT_DIR/scripts/release/lib/guards.sh"

# Validate release directory
if [ ! -d "$RELEASE_DIR" ]; then
  echo -e "${RED}Error: Release directory not found: $RELEASE_DIR${NC}"
  echo "Run './scripts/release/init.sh $VERSION --dmg|--appstore|--both' first"
  exit 1
fi

# Get target channels and determine what to build
TARGET_CHANNELS=$(get_target_channels "$VERSION")
DMG_TARGETED=false
APPSTORE_TARGETED=false
LINUX_TARGETED=false
[[ " $TARGET_CHANNELS " == *" dmg "* ]] && DMG_TARGETED=true
[[ " $TARGET_CHANNELS " == *" appstore "* ]] && APPSTORE_TARGETED=true
[[ " $TARGET_CHANNELS " == *" linux "* ]] && LINUX_TARGETED=true

# Track skip reasons for logging
DMG_SKIP_REASON=""
APPSTORE_SKIP_REASON=""
LINUX_SKIP_REASON=""

# Auto-skip non-targeted channels (override any manual flags)
if [ "$DMG_TARGETED" = false ]; then
  SKIP_DMG=true
  DMG_SKIP_REASON="not targeted"
elif [ "$SKIP_DMG" = true ]; then
  DMG_SKIP_REASON="--skip-dmg"
fi

if [ "$APPSTORE_TARGETED" = false ]; then
  SKIP_APPSTORE=true
  APPSTORE_SKIP_REASON="not targeted"
elif [ "$SKIP_APPSTORE" = true ]; then
  APPSTORE_SKIP_REASON="--skip-appstore"
fi

if [ "$LINUX_TARGETED" = false ]; then
  SKIP_LINUX=true
  LINUX_SKIP_REASON="not targeted"
elif [ "$SKIP_LINUX" = true ]; then
  LINUX_SKIP_REASON="--skip-linux"
fi

# Rebuild BUILD_ARGS with actual skip flags
BUILD_ARGS=""
[ "$SKIP_DMG" = true ] && BUILD_ARGS="$BUILD_ARGS --skip-dmg"
[ "$SKIP_APPSTORE" = true ] && BUILD_ARGS="$BUILD_ARGS --skip-appstore"
[ "$NO_NOTARIZE" = true ] && BUILD_ARGS="$BUILD_ARGS --no-notarize"

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
echo "  Targets:  $TARGET_CHANNELS"
echo ""
echo "  Channels:"
if [ "$DMG_TARGETED" = true ] && [ "$SKIP_DMG" = false ]; then
  echo -e "    DMG:       ${GREEN}targeted, building${NC}"
elif [ "$DMG_TARGETED" = true ] && [ "$SKIP_DMG" = true ]; then
  echo -e "    DMG:       ${YELLOW}targeted, skipped by $DMG_SKIP_REASON${NC}"
else
  echo -e "    DMG:       ${YELLOW}not targeted, skipping${NC}"
fi
if [ "$APPSTORE_TARGETED" = true ] && [ "$SKIP_APPSTORE" = false ]; then
  echo -e "    App Store: ${GREEN}targeted, building${NC}"
elif [ "$APPSTORE_TARGETED" = true ] && [ "$SKIP_APPSTORE" = true ]; then
  echo -e "    App Store: ${YELLOW}targeted, skipped by $APPSTORE_SKIP_REASON${NC}"
else
  echo -e "    App Store: ${YELLOW}not targeted, skipping${NC}"
fi
if [ "$LINUX_TARGETED" = true ] && [ "$SKIP_LINUX" = false ]; then
  echo -e "    Linux:     ${GREEN}targeted, building${NC}"
elif [ "$LINUX_TARGETED" = true ] && [ "$SKIP_LINUX" = true ]; then
  echo -e "    Linux:     ${YELLOW}targeted, skipped by $LINUX_SKIP_REASON${NC}"
else
  echo -e "    Linux:     ${YELLOW}not targeted, skipping${NC}"
fi
echo ""
echo "  Dry run:  $([ "$DRY_RUN" = true ] && echo 'Yes' || echo 'No')"
echo ""

# Pre-flight: Tests
echo -e "${BLUE}==>${NC} Running tests..."
if [ "$DRY_RUN" = false ]; then
  cd "$ROOT_DIR"
  # Check for "with 0 failures" anywhere in output (not just last 3 lines)
  if swift test 2>&1 | grep -q "with 0 failures"; then
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
  mkdir -p "$ARCHIVE_DIR/linux"
else
  echo -e "${YELLOW}[dry-run]${NC} mkdir -p $ARCHIVE_DIR/{appstore,dmg,linux}"
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
    # Remove existing archive to prevent nesting (cp -R into existing dir creates subdirs)
    rm -rf "$ARCHIVE_DIR/appstore/Contextify.xcarchive"
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

# Build Linux via GitHub Actions
if [ "$SKIP_LINUX" = false ]; then
  echo -e "${BLUE}==>${NC} Building Linux via GitHub Actions..."
  if [ "$DRY_RUN" = false ]; then
    # Trigger the workflow
    echo "  Triggering linux-release.yml workflow with version=$VERSION..."
    gh workflow run linux-release.yml -f version="$VERSION"

    # Wait a moment for the workflow to start
    sleep 5

    # Get the run ID for the workflow we just triggered
    echo "  Waiting for workflow to start..."
    RUN_ID=""
    for i in {1..12}; do
      RUN_ID=$(gh run list --workflow=linux-release.yml --limit 5 --json databaseId,status,headBranch,createdAt \
        | python3 -c "import json,sys; runs=json.load(sys.stdin); print(next((r['databaseId'] for r in runs if r['status'] in ['queued','in_progress','pending']), ''))" 2>/dev/null)
      if [ -n "$RUN_ID" ]; then
        break
      fi
      sleep 5
    done

    if [ -z "$RUN_ID" ]; then
      echo -e "${RED}Error: Could not find triggered workflow run${NC}"
      echo "  Check manually: gh run list --workflow=linux-release.yml"
      exit 1
    fi

    echo "  Workflow run ID: $RUN_ID"
    echo "  Waiting for workflow to complete (this may take 10-20 minutes)..."

    # Wait for the workflow to complete
    if ! gh run watch "$RUN_ID" --exit-status; then
      echo -e "${RED}Error: Linux build failed${NC}"
      echo "  Check logs: gh run view $RUN_ID --log"
      exit 1
    fi

    echo -e "${GREEN}OK${NC} Linux build completed"

    # Download artifacts
    echo "  Downloading Linux artifacts..."
    cd "$ARCHIVE_DIR/linux"

    # Download both architecture artifacts
    gh run download "$RUN_ID" --name contextify-linux-x86_64 --dir . || {
      echo -e "${RED}Error: Failed to download x86_64 artifact${NC}"
      exit 1
    }
    gh run download "$RUN_ID" --name contextify-linux-arm64 --dir . || {
      echo -e "${RED}Error: Failed to download arm64 artifact${NC}"
      exit 1
    }

    # The artifacts are downloaded as directories, move the files up
    if [ -f "contextify-linux-x86_64/contextify-linux-x86_64.tar.gz" ]; then
      mv contextify-linux-x86_64/contextify-linux-x86_64.tar.gz .
      rmdir contextify-linux-x86_64 2>/dev/null || true
    fi
    if [ -f "contextify-linux-arm64/contextify-linux-arm64.tar.gz" ]; then
      mv contextify-linux-arm64/contextify-linux-arm64.tar.gz .
      rmdir contextify-linux-arm64 2>/dev/null || true
    fi

    cd "$ROOT_DIR"

    # Verify artifacts exist
    if [ -f "$ARCHIVE_DIR/linux/contextify-linux-x86_64.tar.gz" ]; then
      echo -e "${GREEN}OK${NC} Archived: linux/contextify-linux-x86_64.tar.gz"
    else
      echo -e "${RED}Error: x86_64 artifact not found${NC}"
      exit 1
    fi

    if [ -f "$ARCHIVE_DIR/linux/contextify-linux-arm64.tar.gz" ]; then
      echo -e "${GREEN}OK${NC} Archived: linux/contextify-linux-arm64.tar.gz"
    else
      echo -e "${RED}Error: arm64 artifact not found${NC}"
      exit 1
    fi
  else
    echo -e "${YELLOW}[dry-run]${NC} gh workflow run linux-release.yml -f version=$VERSION"
    echo -e "${YELLOW}[dry-run]${NC} gh run watch <run-id>"
    echo -e "${YELLOW}[dry-run]${NC} gh run download <run-id> to $ARCHIVE_DIR/linux/"
  fi
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

skip_appstore = '$SKIP_APPSTORE' == 'true'
skip_dmg = '$SKIP_DMG' == 'true'
skip_linux = '$SKIP_LINUX' == 'true'
no_notarize = '$NO_NOTARIZE' == 'true'

if not skip_appstore:
    data['phases']['build']['appstore']['archived'] = True
    data['phases']['build']['appstore']['archive_path'] = '$ARCHIVE_DIR/appstore/Contextify.xcarchive'
    data['phases']['build']['appstore']['build_number'] = $BUILD_NUMBER
    data['phases']['build']['appstore']['exported'] = True

if not skip_dmg:
    data['phases']['build']['dmg']['built'] = True
    data['phases']['build']['dmg']['path'] = 'dist/Contextify-${VERSION}.dmg'
    data['phases']['build']['dmg']['signed'] = True
    data['phases']['build']['dmg']['notarized'] = not no_notarize

if not skip_linux:
    import os
    import hashlib
    linux_dir = '$ARCHIVE_DIR/linux'
    data['phases']['build']['linux']['built'] = True

    # x86_64
    x86_path = os.path.join(linux_dir, 'contextify-linux-x86_64.tar.gz')
    if os.path.exists(x86_path):
        data['phases']['build']['linux']['x86_64']['built'] = True
        data['phases']['build']['linux']['x86_64']['path'] = x86_path
        data['phases']['build']['linux']['x86_64']['size_bytes'] = os.path.getsize(x86_path)
        with open(x86_path, 'rb') as f:
            data['phases']['build']['linux']['x86_64']['sha256'] = hashlib.sha256(f.read()).hexdigest()

    # arm64
    arm64_path = os.path.join(linux_dir, 'contextify-linux-arm64.tar.gz')
    if os.path.exists(arm64_path):
        data['phases']['build']['linux']['arm64']['built'] = True
        data['phases']['build']['linux']['arm64']['path'] = arm64_path
        data['phases']['build']['linux']['arm64']['size_bytes'] = os.path.getsize(arm64_path)
        with open(arm64_path, 'rb') as f:
            data['phases']['build']['linux']['arm64']['sha256'] = hashlib.sha256(f.read()).hexdigest()

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

# Update manifest.json
echo -e "${BLUE}==>${NC} Updating manifest.json..."
MANIFEST="$ROOT_DIR/releases/manifest.json"
if [ "$DRY_RUN" = false ] && [ -f "$MANIFEST" ]; then
  python3 << EOF
import json
from datetime import date, datetime

with open('$MANIFEST', 'r') as f:
    data = json.load(f)

# Ensure release exists
if '$VERSION' not in data.get('releases', {}):
    data.setdefault('releases', {})['$VERSION'] = {
        'created': str(date.today()),
        'status': 'in_progress',
        'dmg': {},
        'appstore': {},
        'linux': {}
    }

release = data['releases']['$VERSION']

# Ensure linux dict exists (backward compat)
if 'linux' not in release:
    release['linux'] = {}

# Update git info - track the commit this build is from
release['git_commit'] = '$COMMIT'
release['git_tag'] = 'v$VERSION'

# Update DMG status
if '$SKIP_DMG' != 'true':
    release['dmg']['status'] = 'built'
    release['dmg']['built_at'] = str(date.today())

# Update App Store status
if '$SKIP_APPSTORE' != 'true':
    release['appstore']['status'] = 'built'
    release['appstore']['build_number'] = int('$BUILD_NUMBER')
    release['appstore']['built_at'] = str(date.today())

# Update Linux status
if '$SKIP_LINUX' != 'true':
    release['linux']['status'] = 'built'
    release['linux']['built_at'] = str(date.today())

with open('$MANIFEST', 'w') as f:
    json.dump(data, f, indent=2)

print('Updated manifest.json')
EOF
else
  echo -e "${YELLOW}[dry-run]${NC} Update manifest.json"
fi

# Update git tag to point to this commit
echo -e "${BLUE}==>${NC} Updating git tag v${VERSION}..."
if [ "$DRY_RUN" = false ]; then
  # Delete existing tag if it exists (locally and remotely)
  if git tag -l "v$VERSION" | grep -q "v$VERSION"; then
    git tag -d "v$VERSION" 2>/dev/null || true
    git push origin ":refs/tags/v$VERSION" 2>/dev/null || true
  fi
  # Create new tag at current commit
  git tag "v$VERSION" "$COMMIT"
  git push origin "v$VERSION"
  echo -e "${GREEN}OK${NC} Tag v${VERSION} updated to $COMMIT_SHORT"
else
  echo -e "${YELLOW}[dry-run]${NC} git tag v$VERSION $COMMIT_SHORT"
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
STEP=1
if [ "$SKIP_APPSTORE" = false ] && [ "$APPSTORE_TARGETED" = true ]; then
  echo "  $STEP. Upload to App Store: bash scripts/xc.sh upload"
  STEP=$((STEP + 1))
fi
if [ "$SKIP_DMG" = false ] && [ "$DMG_TARGETED" = true ]; then
  echo "  $STEP. Update appcast.xml and deploy to website"
  STEP=$((STEP + 1))
fi
if [ "$SKIP_LINUX" = false ] && [ "$LINUX_TARGETED" = true ]; then
  echo "  $STEP. Ship Linux: ./scripts/release/mark-shipped.sh $VERSION --linux"
  STEP=$((STEP + 1))
fi
if [ "$APPSTORE_TARGETED" = true ]; then
  echo "  $STEP. Continue with Phase 3: releases/v${VERSION}/checklists/03-review-materials.md"
else
  echo "  $STEP. Continue with Phase 5: releases/v${VERSION}/checklists/05-marketing.md"
fi
echo ""
