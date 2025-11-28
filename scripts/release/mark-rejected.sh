#!/bin/bash
# ============================================================================
# mark-rejected.sh - Record App Store rejection
# ============================================================================
#
# Purpose:
#   Records when Apple has rejected an App Store submission. Captures the
#   rejection guideline and reason for tracking. After fixing, use init.sh
#   --reset to prepare for a new build attempt.
#
# Usage:
#   ./scripts/release/mark-rejected.sh X.Y.Z [OPTIONS]
#
# Options:
#   --guideline "2.1"   Apple guideline number (e.g., "2.1", "4.2.3")
#   --reason "..."      Rejection reason text
#   --date DATE         Override date (default: today, format: YYYY-MM-DD)
#   --interactive       Prompt for guideline and reason interactively
#   --dry-run           Show what would change without writing
#
# State Changes:
#   - releases/vX.Y.Z/release.json: submission.status = "rejected", rejection details
#   - releases/manifest.json: appstore.status = "rejected", rejection_reason
#
# Prerequisites:
#   - Release directory exists
#   - Build has been submitted
#
# Exit Codes:
#   0 - Success
#   1 - Error (missing version, missing details without --interactive)
#
# Examples:
#   ./scripts/release/mark-rejected.sh 1.0.0 --interactive
#   ./scripts/release/mark-rejected.sh 1.0.0 --guideline "2.1" --reason "Needs demo video"
#   ./scripts/release/mark-rejected.sh 1.0.0 --guideline "4.0" --reason "Crashes on launch"
#
# After rejection:
#   1. Fix the issues
#   2. Run: ./scripts/release/init.sh X.Y.Z --reset
#   3. Rebuild and resubmit
# ============================================================================

set -e

# Parse arguments
VERSION=""
GUIDELINE=""
REASON=""
DATE=$(date +%Y-%m-%d)
INTERACTIVE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --guideline)
      GUIDELINE="$2"
      shift 2
      ;;
    --guideline=*)
      GUIDELINE="${1#*=}"
      shift
      ;;
    --reason)
      REASON="$2"
      shift 2
      ;;
    --reason=*)
      REASON="${1#*=}"
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
    --interactive)
      INTERACTIVE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      head -38 "$0" | tail -36 | sed 's/^# //' | sed 's/^#//'
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
  echo "Usage: $0 X.Y.Z [--guideline \"2.1\" --reason \"...\"] [--interactive]"
  echo "Use --help for more options"
  exit 1
fi

# Interactive mode
if [ "$INTERACTIVE" = true ]; then
  echo "Recording App Store rejection for v$VERSION"
  echo ""

  if [ -z "$GUIDELINE" ]; then
    echo "Common guidelines:"
    echo "  2.1    - App Completeness (demo account, missing features)"
    echo "  2.3    - Accurate Metadata (screenshots, description)"
    echo "  4.0    - Design (crashes, bugs)"
    echo "  4.2    - Minimum Functionality"
    echo "  5.1.1  - Data Collection and Storage"
    echo ""
    read -p "Guideline number: " GUIDELINE
  fi

  if [ -z "$REASON" ]; then
    echo ""
    read -p "Rejection reason: " REASON
  fi

  echo ""
fi

# Validate we have the required info
if [ -z "$GUIDELINE" ] || [ -z "$REASON" ]; then
  echo "Error: Guideline and reason required"
  echo "Use --interactive for prompts, or provide:"
  echo "  --guideline \"2.1\" --reason \"Needs demo video\""
  exit 1
fi

MANIFEST="releases/manifest.json"
RELEASE_JSON="releases/v${VERSION}/release.json"

if [ ! -f "$MANIFEST" ]; then
  echo "Error: $MANIFEST not found"
  exit 1
fi

# Source guards and run soft check (warns but doesn't block)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/scripts/release/lib/guards.sh"

check_can_reject "$VERSION"

echo "Recording App Store rejection:"
echo "  Version:    $VERSION"
echo "  Date:       $DATE"
echo "  Guideline:  $GUIDELINE"
echo "  Reason:     $REASON"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "[dry-run] Would update $MANIFEST and $RELEASE_JSON"
  exit 0
fi

# Escape reason for JSON
REASON_ESCAPED=$(echo "$REASON" | sed 's/"/\\"/g' | sed "s/'/\\'/g")

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
    print('Warning: Release $VERSION not found in manifest')
    exit(1)

release = data['releases']['$VERSION']

# Update App Store status
release['appstore']['status'] = 'rejected'
release['appstore']['rejection_reason'] = 'Guideline $GUIDELINE - $REASON_ESCAPED'

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
data['phases']['submission']['status'] = 'rejected'
data['phases']['submission']['rejection'] = {
    'date': '$DATE',
    'guideline': '$GUIDELINE',
    'reason': '''$REASON_ESCAPED'''
}

# Add note
data['notes'].append({
    'date': str(date.today()),
    'author': 'apple',
    'note': f'Rejected - Guideline $GUIDELINE: $REASON_ESCAPED'
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

echo ""
echo "Next steps:"
echo "  1. Fix the issues mentioned in the rejection"
echo "  2. Reset for new build:  ./scripts/release/init.sh $VERSION --reset"
echo "  3. Rebuild:              ./scripts/release/build.sh $VERSION"
echo "  4. Upload:               bash scripts/xc.sh upload"
echo "  5. Submit:               ./scripts/release/mark-submitted.sh $VERSION --build N"
