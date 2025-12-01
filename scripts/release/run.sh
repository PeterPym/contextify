#!/bin/bash
# ============================================================================
# run.sh - Interactive release workflow orchestrator
# ============================================================================
#
# Purpose:
#   Guides you through the complete release process step-by-step,
#   running appropriate subscripts and tracking state.
#
# Usage:
#   ./scripts/release/run.sh X.Y.Z [OPTIONS]
#
# Options:
#   --from PHASE    Start from specific phase (init|build|qa|demo|upload|review|ship)
#   --dry-run       Show steps without executing
#   --help          Show this help
#
# Behavior:
#   1. Shows current release state
#   2. Determines next action based on state
#   3. Prompts user before each step
#   4. Executes subscript, validates result
#   5. Advances to next step or handles errors
#
# State Changes:
#   None directly - all state changes via subscripts
#
# Examples:
#   ./scripts/release/run.sh 1.0.0
#   ./scripts/release/run.sh 1.0.0 --from build
#   ./scripts/release/run.sh 1.0.0 --dry-run
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

# Parse arguments
VERSION=""
START_FROM=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      START_FROM="$2"
      shift 2
      ;;
    --from=*)
      START_FROM="${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      head -35 "$0" | tail -33 | sed 's/^# //' | sed 's/^#//'
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

if [ -z "$VERSION" ]; then
  echo "Usage: $0 X.Y.Z [--from PHASE] [--dry-run]"
  echo ""
  echo "Run '$0 --help' for more information"
  exit 1
fi

MANIFEST="$ROOT_DIR/releases/manifest.json"
RELEASE_DIR="$ROOT_DIR/releases/v${VERSION}"

# Helper functions
prompt() {
  local message="$1"
  local default="${2:-Y}"

  if [ "$default" = "Y" ]; then
    echo -en "${CYAN}$message [Y/n]${NC} "
  else
    echo -en "${CYAN}$message [y/N]${NC} "
  fi

  read -r answer
  answer="${answer:-$default}"

  [[ "$answer" =~ ^[Yy] ]]
}

run_step() {
  local description="$1"
  shift
  local cmd="$@"

  echo ""
  echo -e "${BLUE}━━━ $description ━━━${NC}"
  echo -e "${YELLOW}Command:${NC} $cmd"
  echo ""

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[dry-run]${NC} Would execute: $cmd"
    return 0
  fi

  if prompt "Execute?"; then
    echo ""
    eval "$cmd"
    return $?
  else
    echo "Skipped."
    return 1
  fi
}

get_status() {
  local channel="$1"
  python3 -c "
import json
try:
    with open('$MANIFEST') as f:
        data = json.load(f)
    print(data.get('releases', {}).get('$VERSION', {}).get('$channel', {}).get('status', 'none'))
except:
    print('none')
" 2>/dev/null
}

get_build_number() {
  python3 -c "
import json
try:
    with open('$MANIFEST') as f:
        data = json.load(f)
    print(data.get('releases', {}).get('$VERSION', {}).get('appstore', {}).get('build_number', '?'))
except:
    print('?')
" 2>/dev/null
}

get_build_commit() {
  local release_json="$ROOT_DIR/releases/v${VERSION}/release.json"
  if [ -f "$release_json" ]; then
    python3 -c "
import json
try:
    with open('$release_json') as f:
        data = json.load(f)
    print(data.get('git', {}).get('commit', 'unknown')[:8])
except:
    print('unknown')
" 2>/dev/null
  else
    echo "none"
  fi
}

# Header
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${BOLD}Contextify Release Orchestrator${NC}                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  Version: ${GREEN}$VERSION${NC}                                              ${BLUE}║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}⚠️  DRY RUN MODE - No changes will be made${NC}"
  echo ""
fi

# ============================================================================
# PHASE 1: Check Current State
# ============================================================================
echo -e "${BOLD}Phase 1: Current State${NC}"
echo ""

DMG_STATUS=$(get_status "dmg")
APPSTORE_STATUS=$(get_status "appstore")
BUILD_NUM=$(get_build_number)
BUILD_COMMIT=$(get_build_commit)

# P1.1 fix: two-step to avoid pipeline masking git failure
HEAD_COMMIT_FULL=$(git rev-parse HEAD 2>/dev/null) || HEAD_COMMIT_FULL=""
if [ -n "$HEAD_COMMIT_FULL" ]; then
  HEAD_COMMIT=${HEAD_COMMIT_FULL:0:8}
else
  HEAD_COMMIT="unknown"
fi

# P2.1 fix: handle detached HEAD (git branch --show-current returns empty with exit 0)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [ -z "$CURRENT_BRANCH" ]; then
  CURRENT_BRANCH="(detached HEAD)"
fi

echo "  DMG:       $DMG_STATUS"
echo "  App Store: $APPSTORE_STATUS (build $BUILD_NUM)"
echo ""
echo "  Branch:       $CURRENT_BRANCH"
echo "  Build commit: $BUILD_COMMIT"
echo "  HEAD:         $HEAD_COMMIT"

if [ "$CURRENT_BRANCH" != "main" ]; then
  echo ""
  echo -e "  ${YELLOW}⚠️  NOT ON MAIN BRANCH${NC}"
  echo -e "  ${YELLOW}   Release builds should typically come from main${NC}"
fi

# P2.2 fix: also guard on HEAD_COMMIT being unknown
if [ "$BUILD_COMMIT" != "none" ] && \
   [ "$BUILD_COMMIT" != "unknown" ] && \
   [ "$HEAD_COMMIT" != "unknown" ] && \
   [ "$BUILD_COMMIT" != "$HEAD_COMMIT" ]; then
  echo ""
  echo -e "  ${YELLOW}⚠️  EXISTING BUILD DOES NOT MATCH HEAD${NC}"
  echo -e "  ${YELLOW}   Rebuild required to include latest changes${NC}"
fi
echo ""

# Determine if release exists
RELEASE_EXISTS=false
if [ -d "$RELEASE_DIR" ]; then
  RELEASE_EXISTS=true
fi

# Skip to requested phase if --from specified
CURRENT_PHASE="init"
if [ -n "$START_FROM" ]; then
  CURRENT_PHASE="$START_FROM"
  echo -e "${YELLOW}Starting from phase: $START_FROM${NC}"
  echo ""
fi

# ============================================================================
# PHASE 2: Initialize
# ============================================================================
if [ "$CURRENT_PHASE" = "init" ]; then
  echo -e "${BOLD}Phase 2: Initialize${NC}"
  echo ""

  if [ "$RELEASE_EXISTS" = false ]; then
    if run_step "Initialize new release" "./scripts/release/init.sh $VERSION"; then
      RELEASE_EXISTS=true
    fi
  elif [ "$APPSTORE_STATUS" = "rejected" ]; then
    echo "  Previous submission was rejected."
    if run_step "Reset for new build" "./scripts/release/init.sh $VERSION --reset"; then
      APPSTORE_STATUS="pending"
    fi
  elif [ "$APPSTORE_STATUS" = "none" ] || [ "$APPSTORE_STATUS" = "pending" ]; then
    echo "  Release already initialized."
    if prompt "Reset for new build?" "N"; then
      run_step "Reset release" "./scripts/release/init.sh $VERSION --reset"
    fi
  else
    echo "  Release already initialized (App Store: $APPSTORE_STATUS)"
  fi

  CURRENT_PHASE="build"
fi

# ============================================================================
# PHASE 3: Build
# ============================================================================
if [ "$CURRENT_PHASE" = "build" ]; then
  echo ""
  echo -e "${BOLD}Phase 3: Build${NC}"
  echo ""

  # Refresh status
  DMG_STATUS=$(get_status "dmg")
  APPSTORE_STATUS=$(get_status "appstore")

  if [ "$APPSTORE_STATUS" = "built" ]; then
    echo "  App Store already built."
    if prompt "Rebuild?" "N"; then
      run_step "Rebuild" "./scripts/release/build.sh $VERSION"
    fi
  elif [ "$APPSTORE_STATUS" = "pending" ] || [ "$APPSTORE_STATUS" = "none" ]; then
    # Determine build flags
    BUILD_FLAGS=""
    if [ "$DMG_STATUS" = "shipped" ]; then
      BUILD_FLAGS="--skip-dmg"
      echo "  DMG already shipped, will build App Store only."
    fi

    run_step "Build distributions" "./scripts/release/build.sh $VERSION $BUILD_FLAGS"
  else
    echo "  App Store status: $APPSTORE_STATUS (skipping build)"
  fi

  CURRENT_PHASE="qa"
fi

# ============================================================================
# PHASE 4: QA Testing
# ============================================================================
if [ "$CURRENT_PHASE" = "qa" ]; then
  echo ""
  echo -e "${BOLD}Phase 4: QA Testing${NC}"
  echo ""

  # Refresh status
  DMG_STATUS=$(get_status "dmg")
  APPSTORE_STATUS=$(get_status "appstore")

  echo "  Test the builds with a fresh first-run experience."
  echo "  This cleans the database, resets permissions, and launches the app."
  echo ""

  # Test DMG if built
  if [ "$DMG_STATUS" = "built" ] || [ "$DMG_STATUS" = "shipped" ]; then
    if prompt "Test DMG build (fresh state)?"; then
      echo ""
      run_step "Launch DMG for QA" "./scripts/release/test-app.sh $VERSION --dmg"
      echo ""
      echo -e "${YELLOW}  Complete QA testing, then press Enter to continue...${NC}"
      read -r
    fi
  fi

  # Test App Store if built
  if [ "$APPSTORE_STATUS" = "built" ] || [ "$APPSTORE_STATUS" = "submitted" ]; then
    if prompt "Test App Store build (fresh state)?"; then
      echo ""
      run_step "Launch App Store build for QA" "./scripts/release/test-app.sh $VERSION"
      echo ""
      echo -e "${YELLOW}  Complete QA testing, then press Enter to continue...${NC}"
      read -r
    fi
  fi

  CURRENT_PHASE="demo"
fi

# ============================================================================
# PHASE 5: Demo Video (if needed for App Store)
# ============================================================================
if [ "$CURRENT_PHASE" = "demo" ]; then
  echo ""
  echo -e "${BOLD}Phase 5: Demo Video${NC}"
  echo ""

  # Check if demo video exists
  DEMO_VIDEO="$ROOT_DIR/website/review-4a125b1d/demo-video.mp4"

  if [ -f "$DEMO_VIDEO" ]; then
    echo "  Demo video exists: $DEMO_VIDEO"
    if prompt "Re-record demo?" "N"; then
      run_step "Record demo video" "./scripts/release/demo-recording.sh"
    fi
  else
    echo "  No demo video found."
    if prompt "Record demo video now?"; then
      run_step "Record demo video" "./scripts/release/demo-recording.sh"
    else
      echo ""
      echo -e "${YELLOW}  Tip: Run demo-recording.sh later before uploading${NC}"
    fi
  fi

  CURRENT_PHASE="upload"
fi

# ============================================================================
# PHASE 6: Upload to App Store Connect
# ============================================================================
if [ "$CURRENT_PHASE" = "upload" ]; then
  echo ""
  echo -e "${BOLD}Phase 6: Upload to App Store Connect${NC}"
  echo ""

  APPSTORE_STATUS=$(get_status "appstore")

  if [ "$APPSTORE_STATUS" = "submitted" ]; then
    echo "  Already submitted (build $BUILD_NUM)"
  elif [ "$APPSTORE_STATUS" = "built" ]; then
    # Check for pkg
    PKG_PATH="$ROOT_DIR/build/appstore/Contextify.pkg"
    if [ ! -f "$PKG_PATH" ]; then
      echo -e "${RED}  No .pkg found. Run export-pkg first.${NC}"
      if run_step "Export .pkg" "bash scripts/xc.sh export-pkg"; then
        :
      fi
    fi

    if [ -f "$PKG_PATH" ]; then
      if run_step "Upload to App Store Connect" "bash scripts/xc.sh upload"; then
        echo ""
        echo -e "${GREEN}  Upload complete!${NC}"
        echo ""
        echo "  Next: Submit for review in App Store Connect"
        echo "  https://appstoreconnect.apple.com"
        echo ""

        if prompt "Mark as submitted?"; then
          BUILD_NUM=$(get_build_number)
          run_step "Record submission" "./scripts/release/mark-submitted.sh $VERSION --build $BUILD_NUM"
        fi
      fi
    fi
  else
    echo "  App Store status: $APPSTORE_STATUS"
    echo "  Need to build first."
  fi

  CURRENT_PHASE="review"
fi

# ============================================================================
# PHASE 7: Wait for Review
# ============================================================================
if [ "$CURRENT_PHASE" = "review" ]; then
  echo ""
  echo -e "${BOLD}Phase 7: App Store Review${NC}"
  echo ""

  APPSTORE_STATUS=$(get_status "appstore")
  BUILD_NUM=$(get_build_number)

  if [ "$APPSTORE_STATUS" = "submitted" ]; then
    echo "  Build $BUILD_NUM is awaiting Apple review."
    echo ""
    echo "  What's the review outcome?"
    echo "    [A] Approved"
    echo "    [R] Rejected"
    echo "    [W] Still waiting"
    echo ""
    echo -n "  Choice: "
    read -r choice

    case "$choice" in
      [Aa])
        run_step "Mark as approved" "./scripts/release/mark-shipped.sh $VERSION --appstore --build $BUILD_NUM"
        CURRENT_PHASE="ship"
        ;;
      [Rr])
        run_step "Record rejection" "./scripts/release/mark-rejected.sh $VERSION --interactive"
        echo ""
        echo -e "${YELLOW}  To fix and retry:${NC}"
        echo "    ./scripts/release/run.sh $VERSION --from init"
        exit 0
        ;;
      [Ww]|*)
        echo ""
        echo "  Check back later. Run:"
        echo "    ./scripts/release/run.sh $VERSION --from review"
        exit 0
        ;;
    esac
  elif [ "$APPSTORE_STATUS" = "approved" ]; then
    echo "  Already approved!"
    CURRENT_PHASE="ship"
  elif [ "$APPSTORE_STATUS" = "rejected" ]; then
    echo "  Previous build was rejected."
    echo ""
    echo "  To fix and retry:"
    echo "    ./scripts/release/run.sh $VERSION --from init"
    exit 0
  else
    echo "  App Store status: $APPSTORE_STATUS"
    echo "  Need to submit first."
  fi
fi

# ============================================================================
# PHASE 8: Ship DMG
# ============================================================================
if [ "$CURRENT_PHASE" = "ship" ]; then
  echo ""
  echo -e "${BOLD}Phase 8: Ship DMG${NC}"
  echo ""

  DMG_STATUS=$(get_status "dmg")

  if [ "$DMG_STATUS" = "shipped" ]; then
    echo "  DMG already shipped."
  elif [ "$DMG_STATUS" = "built" ]; then
    echo "  DMG is built and ready to ship."
    echo ""
    echo "  Before shipping:"
    echo "    1. Update appcast.xml with new version"
    echo "    2. Deploy to website"
    echo ""

    if prompt "Mark DMG as shipped?"; then
      run_step "Mark DMG shipped" "./scripts/release/mark-shipped.sh $VERSION --dmg"
    fi
  elif [ "$DMG_STATUS" = "skipped" ]; then
    echo "  DMG was skipped for this release."
  else
    echo "  DMG status: $DMG_STATUS"
  fi
fi

# ============================================================================
# COMPLETE
# ============================================================================
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}Release Workflow Complete${NC}                                    ${GREEN}║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Final status
echo "Final Status:"
./scripts/release/status.sh "$VERSION" 2>/dev/null | grep -E "^\s+(DMG|App Store):" | head -4 || true
echo ""
echo "Run './scripts/release/status.sh $VERSION' for full details."
echo ""
