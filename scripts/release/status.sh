#!/bin/bash
# Show release status with filtering options
#
# Usage: ./scripts/release/status.sh [OPTIONS] [VERSION]
#
# Options:
#   --shipped      Show only releases that shipped to production
#   --active       Show releases needing work (in progress, rejected, etc.)
#   --dmg          Filter to DMG channel only
#   --appstore     Filter to App Store channel only
#   --all          Show all releases (default when no version specified)
#   --json         Output as JSON
#   --help         Show this help
#
# Examples:
#   ./scripts/release/status.sh                    # Summary of all releases
#   ./scripts/release/status.sh 1.0.0              # Details for v1.0.0
#   ./scripts/release/status.sh --shipped          # What's in production?
#   ./scripts/release/status.sh --shipped --dmg    # DMG releases in production
#   ./scripts/release/status.sh --active           # What needs work?
#   ./scripts/release/status.sh --appstore         # App Store status for all versions

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
VERSION=""
FILTER_SHIPPED=false
FILTER_ACTIVE=false
FILTER_DMG=false
FILTER_APPSTORE=false
SHOW_ALL=false
OUTPUT_JSON=false

for arg in "$@"; do
  case $arg in
    --shipped)
      FILTER_SHIPPED=true
      ;;
    --active)
      FILTER_ACTIVE=true
      ;;
    --dmg)
      FILTER_DMG=true
      ;;
    --appstore)
      FILTER_APPSTORE=true
      ;;
    --all)
      SHOW_ALL=true
      ;;
    --json)
      OUTPUT_JSON=true
      ;;
    --help|-h)
      head -25 "$0" | tail -23 | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    -*)
      echo "Unknown option: $arg"
      echo "Use --help for usage"
      exit 1
      ;;
    *)
      VERSION="$arg"
      ;;
  esac
done

MANIFEST="releases/manifest.json"

# Helper: get value from JSON (simple grep-based)
json_value() {
  local file="$1"
  local key="$2"
  grep "\"$key\"" "$file" 2>/dev/null | head -1 | sed 's/.*: *"//' | sed 's/".*//'
}

# Helper: print status with color
print_status() {
  local status="$1"
  case "$status" in
    shipped|complete|approved)
      echo -e "${GREEN}$status${NC}"
      ;;
    pending|in_progress|submitted)
      echo -e "${YELLOW}$status${NC}"
      ;;
    rejected|failed|skipped)
      echo -e "${RED}$status${NC}"
      ;;
    *)
      echo "$status"
      ;;
  esac
}

# Show specific version details
show_version_details() {
  local ver="$1"
  local release_dir="releases/v${ver}"
  local release_json="$release_dir/release.json"

  if [ ! -d "$release_dir" ]; then
    echo -e "${RED}Release v${ver} not found${NC}"
    return 1
  fi

  echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  Release v${ver}${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
  echo ""

  if [ -f "$release_json" ]; then
    # Git info
    local tag=$(json_value "$release_json" "tag")
    local commit=$(json_value "$release_json" "commit")
    echo "Git:"
    echo "  Tag:    ${tag:-not set}"
    echo "  Commit: ${commit:0:8}"
    echo ""

    # Build info
    local build_num=$(grep -A10 '"appstore"' "$release_json" | grep '"build_number"' | head -1 | grep -o '[0-9]*')
    echo "Build: ${build_num:-unknown}"
    echo ""

    # Phase status
    echo "Phases:"
    for phase in pre_release build review_materials submission marketing post_release; do
      local status=$(grep -A2 "\"$phase\":" "$release_json" | grep '"status"' | head -1 | sed 's/.*: *"//' | sed 's/".*//')
      local phase_display=$(echo "$phase" | sed 's/_/ /g')
      printf "  %-18s " "$phase_display:"
      print_status "${status:-unknown}"
    done
    echo ""

    # Channel status (from manifest if available)
    if [ -f "$MANIFEST" ]; then
      echo "Channels:"

      # DMG status
      if [ "$FILTER_APPSTORE" = false ]; then
        local dmg_status=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$ver',{}).get('dmg',{}).get('status','unknown'))" 2>/dev/null || echo "unknown")
        local dmg_date=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$ver',{}).get('dmg',{}).get('released_at',''))" 2>/dev/null || echo "")
        printf "  %-10s " "DMG:"
        print_status "$dmg_status"
        [ -n "$dmg_date" ] && echo "             Released: $dmg_date"
      fi

      # App Store status
      if [ "$FILTER_DMG" = false ]; then
        local as_status=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$ver',{}).get('appstore',{}).get('status','unknown'))" 2>/dev/null || echo "unknown")
        local as_build=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$ver',{}).get('appstore',{}).get('build_number',''))" 2>/dev/null || echo "")
        local as_date=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$ver',{}).get('appstore',{}).get('approved_at') or d.get('releases',{}).get('$ver',{}).get('appstore',{}).get('submitted_at',''))" 2>/dev/null || echo "")
        printf "  %-10s " "App Store:"
        print_status "$as_status"
        [ -n "$as_build" ] && echo "             Build: $as_build"
        [ -n "$as_date" ] && echo "             Date: $as_date"
      fi
    fi
    echo ""

    # Recent notes
    echo "Recent Notes:"
    grep '"note":' "$release_json" | tail -3 | while read line; do
      note=$(echo "$line" | sed 's/.*"note": *"//' | sed 's/".*$//')
      echo "  - $note"
    done
    echo ""

    # Checklists
    echo "Checklists:"
    for checklist in "$release_dir/checklists/"*.md; do
      if [ -f "$checklist" ]; then
        local name=$(basename "$checklist")
        local total=$(grep -c "^\- \[" "$checklist" 2>/dev/null || echo "0")
        local done=$(grep -c "^\- \[x\]" "$checklist" 2>/dev/null || echo "0")
        printf "  %-28s %s/%s\n" "$name" "$done" "$total"
      fi
    done

    # Suggested next action
    echo ""
    echo "Suggested next action:"
    local dmg_status=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$ver',{}).get('dmg',{}).get('status','pending'))" 2>/dev/null || echo "pending")
    local as_status=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$ver',{}).get('appstore',{}).get('status','pending'))" 2>/dev/null || echo "pending")
    local as_build=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$ver',{}).get('appstore',{}).get('build_number','?'))" 2>/dev/null || echo "?")

    if [ "$dmg_status" = "pending" ] && [ "$as_status" = "pending" ]; then
      echo "  -> Build: ./scripts/release/build.sh $ver"
    elif [ "$dmg_status" = "built" ]; then
      echo "  -> Ship DMG: ./scripts/release/mark-shipped.sh $ver --dmg"
    fi

    if [ "$as_status" = "built" ]; then
      echo "  -> Upload: bash scripts/xc.sh upload"
      echo "  -> Then: ./scripts/release/mark-submitted.sh $ver --build $as_build"
    elif [ "$as_status" = "submitted" ]; then
      echo "  -> Waiting for Apple review..."
      echo "  -> If approved: ./scripts/release/mark-shipped.sh $ver --appstore --build $as_build"
      echo "  -> If rejected: ./scripts/release/mark-rejected.sh $ver --interactive"
    elif [ "$as_status" = "rejected" ]; then
      echo "  -> Fix issues, then: ./scripts/release/init.sh $ver --reset"
    elif [ "$dmg_status" = "shipped" ] && [ "$as_status" = "approved" ]; then
      echo "  -> Release complete!"
    fi
  else
    echo "No release.json found"
  fi
}

# Show summary of all releases
show_summary() {
  echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  Contextify Release Status${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
  echo ""

  if [ ! -f "$MANIFEST" ]; then
    echo "No manifest.json found."
    echo "Initialize a release with: ./scripts/release/init.sh X.Y.Z"
    return
  fi

  # Current version
  local current=$(json_value "$MANIFEST" "current_version")
  echo "Current Version: $current"
  echo ""

  # Table header
  echo "Releases:"
  echo "─────────────────────────────────────────────────────────────────"
  printf "  %-10s %-12s %-12s %-10s %s\n" "VERSION" "DMG" "APP STORE" "BUILD" "NOTES"
  echo "─────────────────────────────────────────────────────────────────"

  # List all releases from manifest
  python3 << 'PYEOF'
import json
import sys

try:
    with open('releases/manifest.json', 'r') as f:
        data = json.load(f)
except:
    sys.exit(0)

filter_shipped = '${FILTER_SHIPPED}' == 'true'
filter_active = '${FILTER_ACTIVE}' == 'true'
filter_dmg = '${FILTER_DMG}' == 'true'
filter_appstore = '${FILTER_APPSTORE}' == 'true'

for ver, info in sorted(data.get('releases', {}).items(), reverse=True):
    dmg = info.get('dmg', {})
    appstore = info.get('appstore', {})

    dmg_status = dmg.get('status', 'unknown')
    as_status = appstore.get('status', 'unknown')
    build_num = appstore.get('build_number', '-')

    # Apply filters
    if filter_shipped:
        dmg_shipped = dmg_status in ['shipped', 'complete']
        as_shipped = as_status in ['approved', 'shipped']
        if filter_dmg and not dmg_shipped:
            continue
        if filter_appstore and not as_shipped:
            continue
        if not filter_dmg and not filter_appstore and not (dmg_shipped or as_shipped):
            continue

    if filter_active:
        # Active = needs work (not shipped/complete/approved)
        dmg_active = dmg_status in ['pending', 'in_progress', 'building', 'rejected', 'unknown']
        as_active = as_status in ['pending', 'in_progress', 'submitted', 'in_review', 'rejected', 'unknown']
        if filter_dmg and not dmg_active:
            continue
        if filter_appstore and not as_active:
            continue
        if not filter_dmg and not filter_appstore and not (dmg_active or as_active):
            continue

    # Get note snippet
    note = ''
    if as_status == 'rejected':
        note = appstore.get('rejection_reason', '')[:30]

    # Print row
    if not filter_appstore:
        dmg_display = dmg_status
    else:
        dmg_display = '-'

    if not filter_dmg:
        as_display = as_status
    else:
        as_display = '-'

    print(f"  {ver:<10} {dmg_display:<12} {as_display:<12} {build_num:<10} {note}")
PYEOF

  echo "─────────────────────────────────────────────────────────────────"
  echo ""

  # What's in production
  if [ "$FILTER_SHIPPED" = false ] && [ "$FILTER_ACTIVE" = false ]; then
    echo -e "${GREEN}In Production:${NC}"
    python3 << 'PYEOF'
import json
try:
    with open('releases/manifest.json', 'r') as f:
        data = json.load(f)

    for ver, info in sorted(data.get('releases', {}).items(), reverse=True):
        dmg = info.get('dmg', {})
        appstore = info.get('appstore', {})

        if dmg.get('status') in ['shipped', 'complete']:
            print(f"  DMG:       v{ver} (released {dmg.get('released_at', 'unknown')})")
            break

    for ver, info in sorted(data.get('releases', {}).items(), reverse=True):
        appstore = info.get('appstore', {})
        if appstore.get('status') in ['approved', 'shipped']:
            print(f"  App Store: v{ver} build {appstore.get('build_number', '?')} (approved {appstore.get('approved_at', 'unknown')})")
            break
except Exception as e:
    print(f"  (unable to determine: {e})")
PYEOF
    echo ""
  fi
}

# Main
if [ -n "$VERSION" ]; then
  show_version_details "$VERSION"
else
  show_summary
fi

# Show helpful commands
echo "Commands:"
echo "  ./scripts/release/status.sh <version>     # Details for specific version"
echo "  ./scripts/release/status.sh --shipped     # What's in production"
echo "  ./scripts/release/status.sh --active      # What needs work"
echo "  ./scripts/release/init.sh X.Y.Z           # Start new release"
echo "  ./scripts/release/init.sh X.Y.Z --reset   # Reset for new build"
echo "  ./scripts/release/build.sh X.Y.Z          # Build both distributions"
echo ""
