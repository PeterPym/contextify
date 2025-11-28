#!/bin/bash
# Mark a release as shipped to production
#
# Usage: ./scripts/release/mark-shipped.sh X.Y.Z --dmg|--appstore [OPTIONS]
#
# Options:
#   --dmg          Mark DMG as shipped
#   --appstore     Mark App Store as approved/shipped
#   --build N      Specify build number (App Store)
#   --date DATE    Override date (default: today, format: YYYY-MM-DD)
#   --skipped      Mark as skipped (not shipped)
#   --dry-run      Show what would change without writing
#
# Examples:
#   ./scripts/release/mark-shipped.sh 1.0.0 --dmg
#   ./scripts/release/mark-shipped.sh 1.0.0 --appstore --build 5
#   ./scripts/release/mark-shipped.sh 1.0.0 --dmg --skipped
#   ./scripts/release/mark-shipped.sh 1.0.0 --appstore --date 2025-11-28

set -e

# Parse arguments
VERSION=""
CHANNEL=""
BUILD_NUM=""
DATE=$(date +%Y-%m-%d)
SKIPPED=false
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --dmg)
      CHANNEL="dmg"
      ;;
    --appstore)
      CHANNEL="appstore"
      ;;
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
      ;;
    --skipped)
      SKIPPED=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --help|-h)
      head -20 "$0" | tail -18 | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    -*)
      # Check if next positional is a value
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
  fi
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
  if [ "$CHANNEL" = "dmg" ]; then
    STATUS="shipped"
  else
    STATUS="approved"
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
from datetime import date

with open('$MANIFEST', 'r') as f:
    data = json.load(f)

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
else:
    release['appstore']['status'] = '$STATUS'
    if '$STATUS' == 'approved':
        release['appstore']['approved_at'] = '$DATE'
    elif '$STATUS' == 'skipped':
        release['appstore']['skipped_at'] = '$DATE'
    if '$BUILD_NUM':
        release['appstore']['build_number'] = int('$BUILD_NUM')

# Update overall status if both channels complete
dmg_done = release.get('dmg', {}).get('status') in ['shipped', 'skipped']
as_done = release.get('appstore', {}).get('status') in ['approved', 'skipped']
if dmg_done and as_done:
    release['status'] = 'complete'

with open('$MANIFEST', 'w') as f:
    json.dump(data, f, indent=2)

print('Updated $MANIFEST')
EOF

# Show new status
echo ""
./scripts/release/status.sh "$VERSION"
