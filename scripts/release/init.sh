#!/bin/bash
# ============================================================================
# init.sh - Initialize or reset a release directory
# ============================================================================
#
# Purpose:
#   Creates a new release directory structure with tracking files, or resets
#   an existing release for a new build attempt (preserving history).
#
# Usage:
#   ./scripts/release/init.sh X.Y.Z (--dmg | --appstore | --both | --reset)
#
# Options:
#   --dmg       Target DMG channel only
#   --appstore  Target App Store channel only
#   --both      Target both DMG and App Store channels
#   --reset     Reset existing release for new build (preserves notes, target_channels)
#
# Note: Exactly one option is required.
#   - For new releases: use --dmg, --appstore, or --both
#   - For existing releases: use --reset to regenerate checklists
#
# State Changes:
#   - releases/vX.Y.Z/release.json: Created (new) or reset (--reset)
#   - releases/vX.Y.Z/README.md: Created or updated
#   - releases/vX.Y.Z/checklists/: Created from templates
#   - releases/manifest.json: Entry created (new) or build_number updated (--reset)
#   - Contextify.xcodeproj: CURRENT_PROJECT_VERSION updated (--reset only)
#
# Prerequisites:
#   - For new release: No existing releases/vX.Y.Z directory
#   - For reset: Existing releases/vX.Y.Z directory with release.json
#
# Exit Codes:
#   0 - Success
#   1 - Error (missing version, directory exists without --reset)
#
# Examples:
#   ./scripts/release/init.sh 1.0.0 --dmg       # DMG-only release
#   ./scripts/release/init.sh 1.0.1 --appstore  # App Store-only release
#   ./scripts/release/init.sh 1.1.0 --both      # Both channels
#   ./scripts/release/init.sh 1.0.0 --reset     # Reset for new build attempt
# ============================================================================

set -e

VERSION="${1}"
RESET_MODE=false
TARGET_DMG=false
TARGET_APPSTORE=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --reset)
      RESET_MODE=true
      ;;
    --dmg)
      TARGET_DMG=true
      ;;
    --appstore)
      TARGET_APPSTORE=true
      ;;
    --both)
      TARGET_DMG=true
      TARGET_APPSTORE=true
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "Usage: $0 X.Y.Z (--dmg | --appstore | --both | --reset)"
  echo ""
  echo "For new releases:"
  echo "  $0 1.0.1 --dmg       # DMG only"
  echo "  $0 1.0.2 --appstore  # App Store only"
  echo "  $0 1.1.0 --both      # Both channels"
  echo ""
  echo "For existing releases:"
  echo "  $0 1.0.0 --reset     # Reset for new build"
  exit 1
fi

# Validate mutually exclusive options
OPT_COUNT=0
[ "$RESET_MODE" = true ] && OPT_COUNT=$((OPT_COUNT + 1))
[ "$TARGET_DMG" = true ] && [ "$TARGET_APPSTORE" = false ] && OPT_COUNT=$((OPT_COUNT + 1))
[ "$TARGET_APPSTORE" = true ] && [ "$TARGET_DMG" = false ] && OPT_COUNT=$((OPT_COUNT + 1))
[ "$TARGET_DMG" = true ] && [ "$TARGET_APPSTORE" = true ] && OPT_COUNT=$((OPT_COUNT + 1))

# If no targeting option provided
if [ "$TARGET_DMG" = false ] && [ "$TARGET_APPSTORE" = false ] && [ "$RESET_MODE" = false ]; then
  echo "Error: Must specify one of --dmg, --appstore, --both, or --reset"
  echo ""
  echo "Usage: $0 X.Y.Z (--dmg | --appstore | --both | --reset)"
  exit 1
fi

# Build target_channels array string for JSON
if [ "$TARGET_DMG" = true ] && [ "$TARGET_APPSTORE" = true ]; then
  TARGET_CHANNELS='["dmg", "appstore"]'
  TARGET_CHANNELS_DISPLAY="dmg, appstore"
elif [ "$TARGET_DMG" = true ]; then
  TARGET_CHANNELS='["dmg"]'
  TARGET_CHANNELS_DISPLAY="dmg"
elif [ "$TARGET_APPSTORE" = true ]; then
  TARGET_CHANNELS='["appstore"]'
  TARGET_CHANNELS_DISPLAY="appstore"
fi

RELEASE_DIR="releases/v${VERSION}"

# Handle existing directory
if [ -d "$RELEASE_DIR" ]; then
  if [ "$RESET_MODE" = false ]; then
    echo "Error: Release directory already exists: $RELEASE_DIR"
    echo "Use --reset to reset for a new build (preserves notes)"
    exit 1
  fi

  echo "Resetting release v${VERSION} for new build..."

  # Source guards and check reset safety
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  source "$ROOT_DIR/scripts/release/lib/guards.sh"
  check_reset_safety "$VERSION"

  # Extract existing notes, build number, and target_channels from release.json
  if [ -f "$RELEASE_DIR/release.json" ]; then
    EXISTING_NOTES=$(python3 -c "import json; f=open('$RELEASE_DIR/release.json'); d=json.load(f); print(json.dumps(d.get('notes', [])))" 2>/dev/null || echo "[]")
    NOTES_COUNT=$(python3 -c "import json; f=open('$RELEASE_DIR/release.json'); d=json.load(f); print(len(d.get('notes', [])))" 2>/dev/null || echo "0")
    EXISTING_BUILD=$(python3 -c "import json; f=open('$RELEASE_DIR/release.json'); d=json.load(f); print(d.get('phases',{}).get('build',{}).get('appstore',{}).get('build_number') or 0)" 2>/dev/null || echo "0")
    NEW_BUILD=$((EXISTING_BUILD + 1))
    # Preserve target_channels from existing release
    TARGET_CHANNELS=$(python3 -c "import json; f=open('$RELEASE_DIR/release.json'); d=json.load(f); tc=d.get('target_channels', ['dmg','appstore']); print(json.dumps(tc))" 2>/dev/null || echo '["dmg", "appstore"]')
    TARGET_CHANNELS_DISPLAY=$(python3 -c "import json; tc=$TARGET_CHANNELS; print(', '.join(tc))" 2>/dev/null || echo "dmg, appstore")
    # Set TARGET_DMG and TARGET_APPSTORE based on preserved target_channels
    TARGET_DMG=$(python3 -c "import json; tc=$TARGET_CHANNELS; print('true' if 'dmg' in tc else 'false')" 2>/dev/null || echo "true")
    TARGET_APPSTORE=$(python3 -c "import json; tc=$TARGET_CHANNELS; print('true' if 'appstore' in tc else 'false')" 2>/dev/null || echo "true")
  else
    EXISTING_NOTES="[]"
    NOTES_COUNT=0
    NEW_BUILD=1
    # Default to both channels if no release.json exists
    TARGET_CHANNELS='["dmg", "appstore"]'
    TARGET_CHANNELS_DISPLAY="dmg, appstore"
    TARGET_DMG=true
    TARGET_APPSTORE=true
  fi

  echo "  Preserving $NOTES_COUNT notes"
  echo "  Preserving target_channels: $TARGET_CHANNELS_DISPLAY"
  echo "  Incrementing build: $EXISTING_BUILD -> $NEW_BUILD"

  # Update Xcode project build number
  PBXPROJ="$ROOT_DIR/Contextify/Contextify.xcodeproj/project.pbxproj"
  if [ -f "$PBXPROJ" ]; then
    sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"
    echo "  Updated Xcode CURRENT_PROJECT_VERSION to $NEW_BUILD"
  fi

else
  echo "Initializing release v${VERSION}..."
  echo "  Target channels: $TARGET_CHANNELS_DISPLAY"
  EXISTING_NOTES="[]"
  NEW_BUILD=1

  # Create directory structure
  mkdir -p "$RELEASE_DIR/checklists"
  mkdir -p "$RELEASE_DIR/artifacts"
  mkdir -p "$RELEASE_DIR/logs"
  mkdir -p "$RELEASE_DIR/assets"
fi

# Copy checklist templates and replace version placeholder
for template in releases/templates/checklists/*.md; do
  filename=$(basename "$template")
  sed "s/{version}/${VERSION}/g" "$template" > "$RELEASE_DIR/checklists/$filename"
done

# Get current commit
CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "null")

# Build notes array - add reset note if resetting
if [ "$RESET_MODE" = true ]; then
  RESET_NOTE="{\"date\": \"$(date +%Y-%m-%d)\", \"author\": \"system\", \"note\": \"Reset for build $NEW_BUILD from commit ${CURRENT_COMMIT:0:8}\"}"
  # Append reset note to existing notes
  NOTES_JSON=$(python3 -c "
import json
notes = $EXISTING_NOTES
notes.append($RESET_NOTE)
print(json.dumps(notes, indent=4))
" 2>/dev/null || echo "[{\"date\": \"$(date +%Y-%m-%d)\", \"author\": \"system\", \"note\": \"Reset for build $NEW_BUILD\"}]")
else
  NOTES_JSON="[
    {
      \"date\": \"$(date +%Y-%m-%d)\",
      \"author\": \"system\",
      \"note\": \"Release initialized\"
    }
  ]"
fi

# Determine phase statuses based on targeting
# DMG-only releases don't need review_materials or submission phases
if [ "$TARGET_APPSTORE" = "true" ]; then
  REVIEW_MATERIALS_STATUS="pending"
  SUBMISSION_STATUS="pending"
else
  REVIEW_MATERIALS_STATUS="complete"
  SUBMISSION_STATUS="complete"
fi

# Create release.json
cat > "$RELEASE_DIR/release.json" << EOF
{
  "\$schema": "../schemas/release.schema.json",
  "version": "${VERSION}",
  "target_channels": ${TARGET_CHANNELS},
  "created": "$(date +%Y-%m-%d)",
  "updated": "$(date +%Y-%m-%d)",

  "git": {
    "tag": "v${VERSION}",
    "commit": "${CURRENT_COMMIT}",
    "branch": "main"
  },

  "phases": {
    "pre_release": {
      "status": "pending",
      "completed_at": null,
      "validation": {
        "tests_passed": null,
        "test_count": null,
        "warnings": null,
        "working_directory_clean": null
      }
    },

    "build": {
      "status": "pending",
      "dmg": {
        "built": false,
        "path": null,
        "sha256": null,
        "size_bytes": null,
        "signed": false,
        "notarized": false,
        "sparkle_signature": null
      },
      "appstore": {
        "archived": false,
        "archive_path": null,
        "build_number": ${NEW_BUILD},
        "exported": false,
        "uploaded": false,
        "upload_receipt": null
      }
    },

    "review_materials": {
      "status": "${REVIEW_MATERIALS_STATUS}",
      "demo_video": {
        "recorded": false,
        "path": null,
        "deployed": false
      },
      "sample_data": {
        "generated": false,
        "path": null,
        "deployed": false
      }
    },

    "submission": {
      "status": "${SUBMISSION_STATUS}",
      "submitted_at": null,
      "rejection": null,
      "resubmission": null
    },

    "marketing": {
      "status": "pending",
      "changelog": {
        "written": false,
        "published": false
      },
      "announcements": {
        "twitter": false,
        "mastodon": false,
        "hacker_news": false,
        "product_hunt": false
      }
    },

    "post_release": {
      "status": "pending",
      "documentation_updated": false,
      "support_faq_updated": false,
      "monitoring_enabled": false
    }
  },

  "notes": ${NOTES_JSON}
}
EOF

# Create/update README
cat > "$RELEASE_DIR/README.md" << EOF
# Release v${VERSION}

**Created:** $(date +%Y-%m-%d)
**Status:** In Progress
**Build:** ${NEW_BUILD}

## Quick Status

| Phase | Status |
|-------|--------|
| 1. Pre-Release | Pending |
| 2. Build | Pending |
| 3. Review Materials | Pending |
| 4. Submission | Pending |
| 5. Marketing | Pending |
| 6. Post-Release | Pending |

## Checklists

- [\`01-pre-release.md\`](checklists/01-pre-release.md)
- [\`02-build.md\`](checklists/02-build.md)
- [\`03-review-materials.md\`](checklists/03-review-materials.md)
- [\`04-submission.md\`](checklists/04-submission.md)
- [\`05-marketing.md\`](checklists/05-marketing.md)
- [\`06-post-release.md\`](checklists/06-post-release.md)

## Files

- \`release.json\` - Complete release state
- \`checklists/\` - Phase checklists
- \`artifacts/\` - Build artifact references
- \`logs/\` - Validation outputs
- \`assets/\` - Screenshots, receipts

## Commands

\`\`\`bash
# Check status
./scripts/release/status.sh ${VERSION}

# Validate pre-release
./scripts/release/validate-pre-release.sh ${VERSION}

# Reset for new build (preserves notes)
./scripts/release/init.sh ${VERSION} --reset
\`\`\`
EOF

# Update manifest.json
MANIFEST="releases/manifest.json"
if [ -f "$MANIFEST" ]; then
  python3 << EOF
import json
from datetime import date

with open('$MANIFEST', 'r') as f:
    data = json.load(f)

# Ensure releases dict exists
data.setdefault('releases', {})

if '$RESET_MODE' == 'true':
    # Reset mode: just update build number, preserve target_channels
    if '$VERSION' in data['releases']:
        # Only reset appstore build number if appstore is targeted
        if 'appstore' in data['releases']['$VERSION'].get('target_channels', ['dmg', 'appstore']):
            data['releases']['$VERSION']['appstore']['build_number'] = $NEW_BUILD
            if data['releases']['$VERSION']['appstore'].get('status') not in ['approved', 'skipped']:
                data['releases']['$VERSION']['appstore']['status'] = 'pending'
            # Clear any rejection state when rebuilding
            if 'rejection_reason' in data['releases']['$VERSION']['appstore']:
                del data['releases']['$VERSION']['appstore']['rejection_reason']
else:
    # New release: create entry with target_channels
    target_channels = $TARGET_CHANNELS

    # Set channel statuses based on targeting
    dmg_status = 'pending' if 'dmg' in target_channels else 'skipped'
    appstore_status = 'pending' if 'appstore' in target_channels else 'skipped'

    data['releases']['$VERSION'] = {
        'created': str(date.today()),
        'status': 'in_progress',
        'target_channels': target_channels,
        'git_tag': 'v$VERSION',
        'git_commit': '$CURRENT_COMMIT',
        'dmg': {
            'status': dmg_status
        },
        'appstore': {
            'status': appstore_status,
            'build_number': $NEW_BUILD
        },
        'marketing': {
            'changelog_published': False,
            'announcement_posted': False
        }
    }
    # Update current_version
    data['current_version'] = '$VERSION'

with open('$MANIFEST', 'w') as f:
    json.dump(data, f, indent=2)

print('Updated manifest.json')
EOF
else
  echo "Warning: manifest.json not found, skipping"
fi

if [ "$RESET_MODE" = true ]; then
  echo "Release v${VERSION} reset for build ${NEW_BUILD}"
else
  echo "Release v${VERSION} initialized at: $RELEASE_DIR"
fi

echo ""
echo "Next steps:"
echo "  1. Validate pre-release:  ./scripts/release/validate-pre-release.sh ${VERSION}"
echo "  2. Build both dists:      ./scripts/release/build.sh ${VERSION}"
echo "  3. Follow checklists in:  $RELEASE_DIR/checklists/"
