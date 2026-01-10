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
#   ./scripts/release/init.sh X.Y.Z (--dmg | --appstore | --linux | --both | --all | --reset)
#
# Options:
#   --dmg       Target DMG channel only
#   --appstore  Target App Store channel only
#   --linux     Target Linux channel only
#   --both      Target both DMG and App Store channels (no Linux)
#   --all       Target all channels (DMG, App Store, Linux)
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
TARGET_LINUX=false

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
    --linux)
      TARGET_LINUX=true
      ;;
    --both)
      TARGET_DMG=true
      TARGET_APPSTORE=true
      ;;
    --all)
      TARGET_DMG=true
      TARGET_APPSTORE=true
      TARGET_LINUX=true
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "Usage: $0 X.Y.Z (--dmg | --appstore | --linux | --both | --all | --reset)"
  echo ""
  echo "For new releases:"
  echo "  $0 1.0.1 --dmg       # DMG only"
  echo "  $0 1.0.2 --appstore  # App Store only"
  echo "  $0 1.0.3 --linux     # Linux CLI only"
  echo "  $0 1.1.0 --both      # DMG + App Store (no Linux)"
  echo "  $0 1.1.0 --all       # DMG + App Store + Linux"
  echo ""
  echo "For existing releases:"
  echo "  $0 1.0.0 --reset     # Reset for new build"
  exit 1
fi

# Validate mutually exclusive options
# --reset cannot be combined with targeting flags
if [ "$RESET_MODE" = true ]; then
  if [ "$TARGET_DMG" = true ] || [ "$TARGET_APPSTORE" = true ] || [ "$TARGET_LINUX" = true ]; then
    echo "Error: --reset cannot be combined with --dmg, --appstore, --linux, --both, or --all"
    echo ""
    echo "  --reset preserves existing target_channels and only regenerates checklists."
    echo "  If you need to change channel targeting, create a new version instead."
    exit 1
  fi
fi

# Determine if any targeting option was provided
# We need exactly one "targeting intent": a single channel, --both, --all, or --reset
TARGETING_PROVIDED=false
if [ "$TARGET_DMG" = true ] || [ "$TARGET_APPSTORE" = true ] || [ "$TARGET_LINUX" = true ] || [ "$RESET_MODE" = true ]; then
  TARGETING_PROVIDED=true
fi

# Enforce that some option was provided
if [ "$TARGETING_PROVIDED" = false ]; then
  echo "Error: One of --dmg, --appstore, --linux, --both, --all, or --reset is required"
  echo ""
  echo "Usage: $0 X.Y.Z (--dmg | --appstore | --linux | --both | --all | --reset)"
  exit 1
fi

# Build target_channels array string for JSON
# Build array dynamically based on flags
CHANNELS_ARRAY=()
[ "$TARGET_DMG" = true ] && CHANNELS_ARRAY+=("dmg")
[ "$TARGET_APPSTORE" = true ] && CHANNELS_ARRAY+=("appstore")
[ "$TARGET_LINUX" = true ] && CHANNELS_ARRAY+=("linux")

# Convert to JSON array and display string
if [ ${#CHANNELS_ARRAY[@]} -gt 0 ]; then
  # Build JSON array with proper quoting
  TARGET_CHANNELS=$(printf '%s\n' "${CHANNELS_ARRAY[@]}" | jq -R . | jq -s .)
  TARGET_CHANNELS_DISPLAY=$(IFS=', '; echo "${CHANNELS_ARRAY[*]}")
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
    # Set TARGET_DMG, TARGET_APPSTORE, and TARGET_LINUX based on preserved target_channels
    TARGET_DMG=$(python3 -c "import json; tc=$TARGET_CHANNELS; print('true' if 'dmg' in tc else 'false')" 2>/dev/null || echo "true")
    TARGET_APPSTORE=$(python3 -c "import json; tc=$TARGET_CHANNELS; print('true' if 'appstore' in tc else 'false')" 2>/dev/null || echo "true")
    TARGET_LINUX=$(python3 -c "import json; tc=$TARGET_CHANNELS; print('true' if 'linux' in tc else 'false')" 2>/dev/null || echo "false")
  else
    EXISTING_NOTES="[]"
    NOTES_COUNT=0
    NEW_BUILD=1
    # Default to all channels if no release.json exists
    TARGET_CHANNELS='["dmg", "appstore", "linux"]'
    TARGET_CHANNELS_DISPLAY="dmg, appstore, linux"
    TARGET_DMG=true
    TARGET_APPSTORE=true
    TARGET_LINUX=true
  fi

  echo "  Preserving $NOTES_COUNT notes"
  echo "  Preserving target_channels: $TARGET_CHANNELS_DISPLAY"

  # Only update Xcode build number if App Store is targeted
  # DMG-only releases don't need build number bumps
  PBXPROJ="$ROOT_DIR/Contextify/Contextify.xcodeproj/project.pbxproj"
  if [ "$TARGET_APPSTORE" = "true" ]; then
    echo "  Incrementing build: $EXISTING_BUILD -> $NEW_BUILD"
    if [ -f "$PBXPROJ" ]; then
      sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"
      echo "  Updated Xcode CURRENT_PROJECT_VERSION to $NEW_BUILD"
    fi
  else
    echo "  Build number: n/a (DMG-only release)"
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

# Process checklist template with conditional markers
# Usage: process_checklist_template <template> <output> <dmg_targeted> <appstore_targeted>
#
# Supported conditions:
#   <!-- IF:dmg -->...<!-- ENDIF:dmg -->           - included when DMG is targeted
#   <!-- IF:appstore -->...<!-- ENDIF:appstore --> - included when App Store is targeted
#   <!-- IF:dmgonly -->...<!-- ENDIF:dmgonly -->   - included when DMG-only (no App Store)
#
process_checklist_template() {
  local template="$1"
  local output="$2"
  local dmg_targeted="$3"
  local appstore_targeted="$4"

  # Derive dmgonly condition
  local dmgonly="false"
  if [ "$dmg_targeted" = "true" ] && [ "$appstore_targeted" != "true" ]; then
    dmgonly="true"
  fi

  local content
  content="$(cat "$template")"

  # Remove non-targeted channel sections using Python for reliable multiline handling
  content="$(printf '%s' "$content" | python3 -c "
import sys, re
text = sys.stdin.read()

dmg_targeted = '$dmg_targeted' == 'true'
appstore_targeted = '$appstore_targeted' == 'true'
dmgonly = '$dmgonly' == 'true'

# Remove IF:dmg blocks if DMG not targeted
if not dmg_targeted:
    text = re.sub(r'<!-- IF:dmg -->\n?.*?<!-- ENDIF:dmg -->\n?', '', text, flags=re.DOTALL)

# Remove IF:appstore blocks if App Store not targeted
if not appstore_targeted:
    text = re.sub(r'<!-- IF:appstore -->\n?.*?<!-- ENDIF:appstore -->\n?', '', text, flags=re.DOTALL)

# Remove IF:dmgonly blocks if not DMG-only
if not dmgonly:
    text = re.sub(r'<!-- IF:dmgonly -->\n?.*?<!-- ENDIF:dmgonly -->\n?', '', text, flags=re.DOTALL)

# Strip remaining marker comments (for conditions that passed)
text = re.sub(r'<!-- (?:END)?IF:(?:dmg|appstore|dmgonly) -->\n?', '', text)

print(text, end='')
")"

  # Replace version placeholder
  content="$(printf '%s' "$content" | sed "s/{version}/${VERSION}/g")"

  # Clean up extra blank lines
  content="$(printf '%s' "$content" | cat -s)"

  printf '%s\n' "$content" > "$output"
}

# Copy checklist templates with conditional processing
# Use stub templates for non-targeted phases
for template in releases/templates/checklists/*.md; do
  filename=$(basename "$template")

  # Skip .dmg-only.md files - they're only used as alternates
  if [[ "$filename" == *.dmg-only.md ]]; then
    continue
  fi

  # For DMG-only releases, use stub templates for App Store phases
  if [ "$TARGET_APPSTORE" != "true" ]; then
    case "$filename" in
      03-review-materials.md)
        template="releases/templates/checklists/03-review-materials.dmg-only.md"
        ;;
      04-submission.md)
        template="releases/templates/checklists/04-submission.dmg-only.md"
        ;;
    esac
  fi

  # Process template with conditionals
  process_checklist_template "$template" "$RELEASE_DIR/checklists/$filename" "$TARGET_DMG" "$TARGET_APPSTORE"
done

# Get current commit
CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "null")

# Build notes array - add reset note if resetting
if [ "$RESET_MODE" = true ]; then
  # Use appropriate wording based on targeting
  if [ "$TARGET_APPSTORE" = "true" ]; then
    RESET_NOTE="{\"date\": \"$(date +%Y-%m-%d)\", \"author\": \"system\", \"note\": \"Reset for build $NEW_BUILD from commit ${CURRENT_COMMIT:0:8}\"}"
  else
    RESET_NOTE="{\"date\": \"$(date +%Y-%m-%d)\", \"author\": \"system\", \"note\": \"Reset from commit ${CURRENT_COMMIT:0:8}\"}"
  fi
  # Append reset note to existing notes
  NOTES_JSON=$(python3 -c "
import json
notes = $EXISTING_NOTES
notes.append($RESET_NOTE)
print(json.dumps(notes, indent=4))
" 2>/dev/null || echo "[{\"date\": \"$(date +%Y-%m-%d)\", \"author\": \"system\", \"note\": \"Reset\"}]")
else
  NOTES_JSON="[
    {
      \"date\": \"$(date +%Y-%m-%d)\",
      \"author\": \"system\",
      \"note\": \"Release initialized\"
    }
  ]"
fi

# Determine phase statuses and build number based on targeting
# DMG-only releases don't need review_materials or submission phases
if [ "$TARGET_APPSTORE" = "true" ]; then
  REVIEW_MATERIALS_STATUS="pending"
  SUBMISSION_STATUS="pending"
  APPSTORE_BUILD_NUMBER="${NEW_BUILD}"
else
  REVIEW_MATERIALS_STATUS="complete"
  SUBMISSION_STATUS="complete"
  APPSTORE_BUILD_NUMBER="null"  # Not targeted, no build number needed
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
        "build_number": ${APPSTORE_BUILD_NUMBER},
        "exported": false,
        "uploaded": false,
        "upload_receipt": null
      },
      "linux": {
        "built": false,
        "shipped": false,
        "shipped_at": null,
        "github_release_url": null,
        "x86_64": {
          "built": false,
          "path": null,
          "sha256": null,
          "size_bytes": null
        },
        "arm64": {
          "built": false,
          "path": null,
          "sha256": null,
          "size_bytes": null
        }
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

# Build target description for README
if [ "$TARGET_DMG" = "true" ] && [ "$TARGET_APPSTORE" = "true" ]; then
  TARGET_DESC="Both (DMG + App Store)"
  PHASE3_STATUS="Pending"
  PHASE4_STATUS="Pending"
elif [ "$TARGET_DMG" = "true" ]; then
  TARGET_DESC="DMG only"
  PHASE3_STATUS="Complete (n/a - DMG only)"
  PHASE4_STATUS="Complete (n/a - DMG only)"
else
  TARGET_DESC="App Store only"
  PHASE3_STATUS="Pending"
  PHASE4_STATUS="Pending"
fi

# Create/update README
cat > "$RELEASE_DIR/README.md" << EOF
# Release v${VERSION}

**Created:** $(date +%Y-%m-%d)
**Status:** In Progress
**Build:** ${NEW_BUILD}
**Targeting:** ${TARGET_DESC}

## Quick Status

| Phase | Status |
|-------|--------|
| 1. Pre-Release | Pending |
| 2. Build | Pending |
| 3. Review Materials | ${PHASE3_STATUS} |
| 4. Submission | ${PHASE4_STATUS} |
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
    # Reset mode: only bump build number, preserve target_channels AND channel statuses
    # Per v3 plan: "preserve existing channel statuses, only regenerate checklists"
    if '$VERSION' in data['releases']:
        # Only update appstore build number if appstore is targeted
        if 'appstore' in data['releases']['$VERSION'].get('target_channels', ['dmg', 'appstore']):
            data['releases']['$VERSION']['appstore']['build_number'] = $NEW_BUILD
            # Only clear rejection state if currently rejected (allows retry)
            if data['releases']['$VERSION']['appstore'].get('status') == 'rejected':
                data['releases']['$VERSION']['appstore']['status'] = 'pending'
                if 'rejection_reason' in data['releases']['$VERSION']['appstore']:
                    del data['releases']['$VERSION']['appstore']['rejection_reason']
            # Do NOT reset submitted/built/approved statuses - preserve them
else:
    # New release: create entry with target_channels
    target_channels = $TARGET_CHANNELS

    # Set channel statuses based on targeting
    dmg_status = 'pending' if 'dmg' in target_channels else 'skipped'
    appstore_status = 'pending' if 'appstore' in target_channels else 'skipped'
    linux_status = 'pending' if 'linux' in target_channels else 'skipped'

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
        'linux': {
            'status': linux_status
        },
        'marketing': {
            'changelog_published': False,
            'announcement_posted': False
        }
    }
    # NOTE: Do NOT update current_version here - it represents "latest shipped"
    # and should only be updated by mark-shipped.sh when a release goes live

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
