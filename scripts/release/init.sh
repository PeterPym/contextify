#!/bin/bash
# Initialize or reset a release directory
# Usage: ./scripts/release/init.sh X.Y.Z [--reset]
#
# Options:
#   --reset    Reset existing release for new build (preserves notes, increments build)

set -e

VERSION="${1}"
RESET_MODE=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --reset)
      RESET_MODE=true
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "Usage: $0 X.Y.Z [--reset]"
  echo "Example: $0 1.0.1"
  echo "Example: $0 1.0.0 --reset  # Reset for new build"
  exit 1
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

  # Extract existing notes and build number from release.json
  if [ -f "$RELEASE_DIR/release.json" ]; then
    EXISTING_NOTES=$(python3 -c "import json; f=open('$RELEASE_DIR/release.json'); d=json.load(f); print(json.dumps(d.get('notes', [])))" 2>/dev/null || echo "[]")
    EXISTING_BUILD=$(python3 -c "import json; f=open('$RELEASE_DIR/release.json'); d=json.load(f); print(d.get('phases',{}).get('build',{}).get('appstore',{}).get('build_number') or 0)" 2>/dev/null || echo "0")
    NEW_BUILD=$((EXISTING_BUILD + 1))
  else
    EXISTING_NOTES="[]"
    NEW_BUILD=1
  fi

  echo "  Preserving ${#EXISTING_NOTES} notes"
  echo "  Incrementing build: $EXISTING_BUILD -> $NEW_BUILD"

else
  echo "Initializing release v${VERSION}..."
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

# Create release.json
cat > "$RELEASE_DIR/release.json" << EOF
{
  "\$schema": "../schemas/release.schema.json",
  "version": "${VERSION}",
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
      "status": "pending",
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
      "status": "pending",
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

if [ "$RESET_MODE" = true ]; then
  echo "Release v${VERSION} reset for build ${NEW_BUILD}"
else
  echo "Release v${VERSION} initialized at: $RELEASE_DIR"
fi

echo ""
echo "Next steps:"
echo "  1. Review checklists in $RELEASE_DIR/checklists/"
echo "  2. Start with 01-pre-release.md"
echo "  3. Update release.json as you progress"
