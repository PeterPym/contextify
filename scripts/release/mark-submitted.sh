#!/bin/bash
# ============================================================================
# mark-submitted.sh - Record App Store submission
# ============================================================================
#
# Purpose:
#   Records when a build has been submitted to App Store Connect for review.
#   This is called after uploading via `xc.sh upload` and submitting in
#   App Store Connect.
#
# Usage:
#   ./scripts/release/mark-submitted.sh X.Y.Z [OPTIONS]
#
# Options:
#   --build N      Build number submitted (required)
#   --date DATE    Override date (default: today, format: YYYY-MM-DD)
#   --force        Bypass precondition checks
#   --dry-run      Show what would change without writing
#
# State Changes:
#   - releases/vX.Y.Z/release.json: submission.status = "submitted"
#   - releases/manifest.json: appstore.status = "submitted"
#
# Prerequisites:
#   - Release directory exists
#   - Build has been uploaded to App Store Connect
#
# Exit Codes:
#   0 - Success
#   1 - Error (missing version, missing build number)
#
# Examples:
#   ./scripts/release/mark-submitted.sh 1.0.0 --build 8
#   ./scripts/release/mark-submitted.sh 1.0.0 --build 8 --date 2025-11-28
# ============================================================================

set -e

# Parse arguments
VERSION=""
BUILD_NUM=""
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
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
      TIMESTAMP="${DATE}T12:00:00Z"
      shift 2
      ;;
    --date=*)
      DATE="${1#*=}"
      TIMESTAMP="${DATE}T12:00:00Z"
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
      head -30 "$0" | tail -28 | sed 's/^# //' | sed 's/^#//'
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

if [ -z "$VERSION" ]; then
  echo "Usage: $0 X.Y.Z --build N [OPTIONS]"
  echo "Use --help for more options"
  exit 1
fi

if [ -z "$BUILD_NUM" ]; then
  echo "Error: Build number required (--build N)"
  exit 1
fi

MANIFEST="releases/manifest.json"
RELEASE_JSON="releases/v${VERSION}/release.json"

if [ ! -f "$MANIFEST" ]; then
  echo "Error: $MANIFEST not found"
  exit 1
fi

# Source guards and run precondition checks
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/scripts/release/lib/guards.sh"

if [ "$FORCE" != true ]; then
  if ! check_can_submit "$VERSION"; then
    echo "Use --force to override"
    exit 1
  fi
fi

echo "Recording App Store submission:"
echo "  Version:    $VERSION"
echo "  Build:      $BUILD_NUM"
echo "  Date:       $DATE"
echo "  Timestamp:  $TIMESTAMP"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "[dry-run] Would update $MANIFEST and $RELEASE_JSON"
  exit 0
fi

# Update manifest.json
python3 << EOF
import json
import sys

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
    print('Warning: Release $VERSION not found in manifest, creating entry')
    data.setdefault('releases', {})['$VERSION'] = {
        'created': '$DATE',
        'status': 'in_progress',
        'dmg': {},
        'appstore': {}
    }

release = data['releases']['$VERSION']

# Update App Store status
release['appstore']['status'] = 'submitted'
release['appstore']['build_number'] = int('$BUILD_NUM')
release['appstore']['submitted_at'] = '$TIMESTAMP'

with open('$MANIFEST', 'w') as f:
    json.dump(data, f, indent=2)

print('Updated manifest.json')
EOF

# Update release.json
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

# Update submission phase
data['phases']['submission']['status'] = 'submitted'
data['phases']['submission']['submitted_at'] = '$TIMESTAMP'

# Update build info
data['phases']['build']['appstore']['build_number'] = int('$BUILD_NUM')
data['phases']['build']['appstore']['uploaded'] = True

# Add note
force_note = ' (guard bypassed)' if '$FORCE' == 'true' else ''
data['notes'].append({
    'date': str(date.today()),
    'author': 'system',
    'note': f'Submitted build $BUILD_NUM to App Store Connect{force_note}'
})

with open('$RELEASE_JSON', 'w') as f:
    json.dump(data, f, indent=2)

print('Updated release.json')
EOF
else
  echo "Warning: $RELEASE_JSON not found, skipping"
fi

# Show new status
echo ""
./scripts/release/status.sh "$VERSION"
