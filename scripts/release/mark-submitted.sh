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

for arg in "$@"; do
  case $arg in
    --build)
      shift
      ;;
    --build=*)
      BUILD_NUM="${arg#*=}"
      ;;
    --date)
      shift
      ;;
    --date=*)
      DATE="${arg#*=}"
      TIMESTAMP="${DATE}T12:00:00Z"
      ;;
    --force)
      FORCE=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --help|-h)
      head -30 "$0" | tail -28 | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    -*)
      # Skip flags
      ;;
    *)
      if [ -z "$VERSION" ]; then
        VERSION="$arg"
      elif [ -z "$BUILD_NUM" ] && [[ "$arg" =~ ^[0-9]+$ ]]; then
        BUILD_NUM="$arg"
      fi
      ;;
  esac
done

# Handle --build N format
args=("$@")
for i in "${!args[@]}"; do
  if [ "${args[$i]}" = "--build" ] && [ -n "${args[$((i+1))]}" ]; then
    BUILD_NUM="${args[$((i+1))]}"
  fi
  if [ "${args[$i]}" = "--date" ] && [ -n "${args[$((i+1))]}" ]; then
    DATE="${args[$((i+1))]}"
    TIMESTAMP="${DATE}T12:00:00Z"
  fi
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

with open('$MANIFEST', 'r') as f:
    data = json.load(f)

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
from datetime import date

with open('$RELEASE_JSON', 'r') as f:
    data = json.load(f)

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
