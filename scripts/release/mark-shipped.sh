#!/bin/bash
# ============================================================================
# mark-shipped.sh - Mark a release as shipped to production
# ============================================================================
#
# Purpose:
#   Records when a release distribution (DMG or App Store) has been shipped
#   or approved for production. Updates both tracking files consistently.
#
# Usage:
#   ./scripts/release/mark-shipped.sh X.Y.Z --dmg|--appstore|--linux [OPTIONS]
#
# Options:
#   --dmg          Mark DMG as shipped
#   --appstore     Mark App Store as approved/shipped
#   --linux        Mark Linux as shipped (creates GitHub Release)
#   --build N      Specify build number (App Store)
#   --date DATE    Override date (default: today, format: YYYY-MM-DD)
#   --skipped      Mark as skipped (not shipped)
#   --force        Bypass precondition checks
#   --dry-run      Show what would change without writing
#
# State Changes:
#   - releases/vX.Y.Z/release.json: submission.status updated
#   - releases/manifest.json: dmg/appstore status and dates updated
#
# Prerequisites:
#   - Release directory exists
#   - Build has been completed
#
# Exit Codes:
#   0 - Success
#   1 - Error (missing version, missing channel, file not found)
#
# Examples:
#   ./scripts/release/mark-shipped.sh 1.0.0 --dmg
#   ./scripts/release/mark-shipped.sh 1.0.0 --appstore --build 5
#   ./scripts/release/mark-shipped.sh 1.0.0 --dmg --skipped
#   ./scripts/release/mark-shipped.sh 1.0.0 --appstore --date 2025-11-28
# ============================================================================

set -e

# Parse arguments
VERSION=""
CHANNEL=""
BUILD_NUM=""
DATE=$(date +%Y-%m-%d)
SKIPPED=false
FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      CHANNEL="dmg"
      shift
      ;;
    --appstore)
      CHANNEL="appstore"
      shift
      ;;
    --linux)
      CHANNEL="linux"
      shift
      ;;
    --build)
      BUILD_NUM="$2"
      shift 2
      ;;
    --build=*)
      BUILD_NUM="${1#*=}"
      shift
      ;;
    --date)
      DATE="$2"
      shift 2
      ;;
    --date=*)
      DATE="${1#*=}"
      shift
      ;;
    --skipped)
      SKIPPED=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      head -20 "$0" | tail -18 | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [ -z "$VERSION" ]; then
        VERSION="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$VERSION" ] || [ -z "$CHANNEL" ]; then
  echo "Usage: $0 X.Y.Z --dmg|--appstore [OPTIONS]"
  echo "Use --help for more options"
  exit 1
fi

MANIFEST="releases/manifest.json"

if [ ! -f "$MANIFEST" ]; then
  echo "Error: $MANIFEST not found"
  exit 1
fi

# Determine status
if [ "$SKIPPED" = true ]; then
  STATUS="skipped"
else
  if [ "$CHANNEL" = "dmg" ] || [ "$CHANNEL" = "linux" ]; then
    STATUS="shipped"
  else
    STATUS="approved"
  fi
fi

# Source guards and run precondition checks
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/scripts/release/lib/guards.sh"

if [ "$SKIPPED" = false ] && [ "$FORCE" != true ]; then
  if [ "$CHANNEL" = "dmg" ]; then
    if ! check_can_ship_dmg "$VERSION"; then
      echo "Use --force to override"
      exit 1
    fi
  elif [ "$CHANNEL" = "appstore" ]; then
    if ! check_can_ship_appstore "$VERSION"; then
      echo "Use --force to override"
      exit 1
    fi
  elif [ "$CHANNEL" = "linux" ]; then
    if ! check_can_ship_linux "$VERSION"; then
      echo "Use --force to override"
      exit 1
    fi
  fi
fi

echo "Marking release as shipped:"
echo "  Version:  $VERSION"
echo "  Channel:  $CHANNEL"
echo "  Status:   $STATUS"
echo "  Date:     $DATE"
[ -n "$BUILD_NUM" ] && echo "  Build:    $BUILD_NUM"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "[dry-run] Would update $MANIFEST"
  exit 0
fi

# Update manifest.json
python3 << EOF
import json
import sys
from datetime import date

try:
    with open('$MANIFEST', 'r') as f:
        data = json.load(f)
except json.JSONDecodeError as e:
    print(f"Error: $MANIFEST is invalid JSON: {e}", file=sys.stderr)
    print("  Run: ./scripts/release/check-consistency.sh", file=sys.stderr)
    sys.exit(1)
except FileNotFoundError:
    print("Error: $MANIFEST not found", file=sys.stderr)
    sys.exit(1)

# Ensure release exists
if '$VERSION' not in data.get('releases', {}):
    data.setdefault('releases', {})['$VERSION'] = {
        'created': '$DATE',
        'status': 'in_progress',
        'dmg': {},
        'appstore': {}
    }

release = data['releases']['$VERSION']

if '$CHANNEL' == 'dmg':
    release['dmg']['status'] = '$STATUS'
    if '$STATUS' == 'shipped':
        release['dmg']['released_at'] = '$DATE'
    elif '$STATUS' == 'skipped':
        release['dmg']['skipped_at'] = '$DATE'
elif '$CHANNEL' == 'appstore':
    release['appstore']['status'] = '$STATUS'
    if '$STATUS' == 'approved':
        release['appstore']['approved_at'] = '$DATE'
    elif '$STATUS' == 'skipped':
        release['appstore']['skipped_at'] = '$DATE'
    if '$BUILD_NUM':
        release['appstore']['build_number'] = int('$BUILD_NUM')
elif '$CHANNEL' == 'linux':
    if 'linux' not in release:
        release['linux'] = {}
    release['linux']['status'] = '$STATUS'
    if '$STATUS' == 'shipped':
        release['linux']['shipped_at'] = '$DATE'
    elif '$STATUS' == 'skipped':
        release['linux']['skipped_at'] = '$DATE'

# Update overall status if all targeted channels complete
target_channels = release.get('target_channels', ['dmg', 'appstore'])
dmg_done = 'dmg' not in target_channels or release.get('dmg', {}).get('status') in ['shipped', 'skipped']
as_done = 'appstore' not in target_channels or release.get('appstore', {}).get('status') in ['approved', 'skipped']
linux_done = 'linux' not in target_channels or release.get('linux', {}).get('status') in ['shipped', 'skipped']
if dmg_done and as_done and linux_done:
    release['status'] = 'complete'

# Update current_version if this is a shipped (not skipped) status
# current_version represents "latest version shipped to any channel"
if '$STATUS' in ['shipped', 'approved']:
    current = data.get('current_version')
    if current is None:
        data['current_version'] = '$VERSION'
    else:
        # Compare versions: set if this version is >= current
        def parse_version(v):
            try:
                return tuple(int(x) for x in v.split('.'))
            except:
                return (0, 0, 0)
        if parse_version('$VERSION') >= parse_version(current):
            data['current_version'] = '$VERSION'

with open('$MANIFEST', 'w') as f:
    json.dump(data, f, indent=2)

print('Updated $MANIFEST')
EOF

# Update release.json
RELEASE_JSON="releases/v${VERSION}/release.json"
if [ -f "$RELEASE_JSON" ]; then
  python3 << EOF
import json
import sys
from datetime import date

try:
    with open('$RELEASE_JSON', 'r') as f:
        data = json.load(f)
except json.JSONDecodeError as e:
    print(f"Error: $RELEASE_JSON is invalid JSON: {e}", file=sys.stderr)
    print("  Run: ./scripts/release/check-consistency.sh", file=sys.stderr)
    sys.exit(1)

data['updated'] = str(date.today())

# Update submission phase status
if '$STATUS' == 'approved':
    data['phases']['submission']['status'] = 'approved'
    data['phases']['submission']['approved_at'] = '$DATE'
elif '$STATUS' == 'shipped':
    if '$CHANNEL' == 'dmg':
        # For DMG, mark build phase as complete
        data['phases']['build']['dmg']['shipped'] = True
        data['phases']['build']['dmg']['shipped_at'] = '$DATE'
    elif '$CHANNEL' == 'linux':
        # For Linux, mark as shipped
        data['phases']['build']['linux']['shipped'] = True
        data['phases']['build']['linux']['shipped_at'] = '$DATE'
elif '$STATUS' == 'skipped':
    if '$CHANNEL' == 'appstore':
        data['phases']['submission']['status'] = 'skipped'
    elif '$CHANNEL' == 'dmg':
        data['phases']['build']['dmg']['skipped'] = True
    elif '$CHANNEL' == 'linux':
        data['phases']['build']['linux']['skipped'] = True

# Add note
force_note = ' (guard bypassed)' if '$FORCE' == 'true' else ''
data['notes'].append({
    'date': str(date.today()),
    'author': 'system',
    'note': f'$CHANNEL marked as $STATUS{force_note}'
})

with open('$RELEASE_JSON', 'w') as f:
    json.dump(data, f, indent=2)

print('Updated release.json')
EOF
fi

# Create GitHub Release for Linux
if [ "$CHANNEL" = "linux" ] && [ "$STATUS" = "shipped" ] && [ "$DRY_RUN" = false ]; then
  echo ""
  echo "Creating GitHub Release for Linux..."

  ARCHIVE_DIR="$ROOT_DIR/build/archives/v${VERSION}/linux"
  X86_ARTIFACT="$ARCHIVE_DIR/contextify-linux-x86_64.tar.gz"
  ARM64_ARTIFACT="$ARCHIVE_DIR/contextify-linux-arm64.tar.gz"

  # Generate .sha256 sidecar files for installer verification
  echo "  Generating checksums..."
  for artifact in "$X86_ARTIFACT" "$ARM64_ARTIFACT"; do
    if [ -f "$artifact" ]; then
      basename=$(basename "$artifact")
      sha256=$(shasum -a 256 "$artifact" | cut -d' ' -f1)
      echo "$sha256  $basename" > "${artifact}.sha256"
      echo "  SHA256($basename) = $sha256"
    fi
  done

  X86_SHA="${X86_ARTIFACT}.sha256"
  ARM64_SHA="${ARM64_ARTIFACT}.sha256"

  # Check if release already exists
  if gh release view "v${VERSION}" &>/dev/null; then
    echo "  GitHub Release v${VERSION} already exists, uploading Linux artifacts..."
    # Upload artifacts to existing release (tarballs + checksums)
    gh release upload "v${VERSION}" "$X86_ARTIFACT" "$ARM64_ARTIFACT" "$X86_SHA" "$ARM64_SHA" --clobber
  else
    echo "  Creating new GitHub Release v${VERSION}..."
    # Create release with Linux artifacts + checksums
    gh release create "v${VERSION}" \
      --title "v${VERSION}" \
      --notes "## Contextify v${VERSION}

### Downloads

**macOS:**
- DMG: Download from [contextify.sh](https://contextify.sh)
- App Store: [Mac App Store](https://apps.apple.com/app/contextify/id6753190666)

**Linux CLI (contextify-ingest):**
\`\`\`bash
# x86_64
curl -fsSL https://github.com/banagale/contextify/releases/download/v${VERSION}/contextify-linux-x86_64.tar.gz | tar xz
sudo mv contextify-ingest /usr/local/bin/

# arm64
curl -fsSL https://github.com/banagale/contextify/releases/download/v${VERSION}/contextify-linux-arm64.tar.gz | tar xz
sudo mv contextify-ingest /usr/local/bin/
\`\`\`

### Usage
\`\`\`bash
contextify-ingest ingest --db ~/contextify.db
contextify-ingest verify --db ~/contextify.db
\`\`\`
" \
      "$X86_ARTIFACT" "$ARM64_ARTIFACT" "$X86_SHA" "$ARM64_SHA"
  fi

  # Update release.json with GitHub Release URL
  RELEASE_URL=$(gh release view "v${VERSION}" --json url -q '.url')
  if [ -n "$RELEASE_URL" ]; then
    python3 << EOF
import json
with open('$RELEASE_JSON', 'r') as f:
    data = json.load(f)
data['phases']['build']['linux']['github_release_url'] = '$RELEASE_URL'
with open('$RELEASE_JSON', 'w') as f:
    json.dump(data, f, indent=2)
EOF
    echo "  GitHub Release URL: $RELEASE_URL"
  fi

  echo "  GitHub Release created/updated successfully"
fi

# Show new status
echo ""
./scripts/release/status.sh "$VERSION"
