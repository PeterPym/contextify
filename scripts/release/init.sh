#!/bin/bash
# Initialize a new release directory from templates
# Usage: ./scripts/release/init.sh X.Y.Z

set -e

VERSION="${1}"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 X.Y.Z"
  echo "Example: $0 1.0.1"
  exit 1
fi

RELEASE_DIR="releases/v${VERSION}"

if [ -d "$RELEASE_DIR" ]; then
  echo "Error: Release directory already exists: $RELEASE_DIR"
  exit 1
fi

echo "Initializing release v${VERSION}..."

# Create directory structure
mkdir -p "$RELEASE_DIR/checklists"
mkdir -p "$RELEASE_DIR/artifacts"
mkdir -p "$RELEASE_DIR/logs"
mkdir -p "$RELEASE_DIR/assets"

# Copy checklist templates and replace version placeholder
for template in releases/templates/checklists/*.md; do
  filename=$(basename "$template")
  sed "s/{version}/${VERSION}/g" "$template" > "$RELEASE_DIR/checklists/$filename"
done

# Create release.json
cat > "$RELEASE_DIR/release.json" << EOF
{
  "\$schema": "../schemas/release.schema.json",
  "version": "${VERSION}",
  "created": "$(date +%Y-%m-%d)",
  "updated": "$(date +%Y-%m-%d)",

  "git": {
    "tag": "v${VERSION}",
    "commit": null,
    "branch": "main"
  },

  "phases": {
    "pre_release": {
      "status": "not_started",
      "completed_at": null,
      "validation": {
        "tests_passed": null,
        "test_count": null,
        "warnings": null,
        "working_directory_clean": null
      }
    },

    "build": {
      "status": "not_started",
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
        "build_number": null,
        "exported": false,
        "uploaded": false,
        "upload_receipt": null
      }
    },

    "review_materials": {
      "status": "not_started",
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
      "status": "not_started",
      "submitted_at": null,
      "rejection": null,
      "resubmission": null
    },

    "marketing": {
      "status": "not_started",
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
      "status": "not_started",
      "documentation_updated": false,
      "support_faq_updated": false,
      "monitoring_enabled": false
    }
  },

  "notes": [
    {
      "date": "$(date +%Y-%m-%d)",
      "author": "system",
      "note": "Release initialized"
    }
  ]
}
EOF

# Create README
cat > "$RELEASE_DIR/README.md" << EOF
# Release v${VERSION}

**Created:** $(date +%Y-%m-%d)
**Status:** In Progress

## Quick Status

| Phase | Status |
|-------|--------|
| 1. Pre-Release | Not Started |
| 2. Build | Not Started |
| 3. Review Materials | Not Started |
| 4. Submission | Not Started |
| 5. Marketing | Not Started |
| 6. Post-Release | Not Started |

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
\`\`\`
EOF

echo "Release v${VERSION} initialized at: $RELEASE_DIR"
echo ""
echo "Next steps:"
echo "  1. Review checklists in $RELEASE_DIR/checklists/"
echo "  2. Start with 01-pre-release.md"
echo "  3. Update release.json as you progress"
