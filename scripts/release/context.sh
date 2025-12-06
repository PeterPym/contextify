#!/bin/bash
# ============================================================================
# context.sh - Show current release context for session awareness
# ============================================================================
#
# Purpose:
#   Provides a quick summary of release state for Claude Code sessions.
#   Shows active release, targeting, next action, and any outstanding marketing.
#
# Usage:
#   ./scripts/release/context.sh
#
# Output:
#   - Active release (highest semver among in_progress)
#   - Target channels
#   - Current phase and next action
#   - Previous release status and any incomplete work
#
# Examples:
#   ./scripts/release/context.sh
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
DIM='\033[2m'

MANIFEST="releases/manifest.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source guards for helper functions
source "$ROOT_DIR/scripts/release/lib/guards.sh"

if [ ! -f "$MANIFEST" ]; then
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Release Context${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "No releases initialized."
    echo ""
    echo -e "${DIM}./scripts/release/init.sh X.Y.Z --dmg|--appstore|--both${NC}"
    exit 0
fi

# Get release data via Python
CONTEXT=$(python3 << 'PYEOF'
import json
import sys

try:
    with open('releases/manifest.json', 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f"ERROR:{e}")
    sys.exit(1)

releases = data.get('releases', {})
if not releases:
    print("NO_RELEASES")
    sys.exit(0)

# Find active release (highest semver among in_progress)
active = None
active_ver = None
for ver, info in releases.items():
    if info.get('status') == 'in_progress':
        if active_ver is None or tuple(map(int, ver.split('.'))) > tuple(map(int, active_ver.split('.'))):
            active_ver = ver
            active = info

# Find previous (highest complete)
previous = None
previous_ver = None
for ver, info in releases.items():
    if info.get('status') == 'complete':
        if previous_ver is None or tuple(map(int, ver.split('.'))) > tuple(map(int, previous_ver.split('.'))):
            previous_ver = ver
            previous = info

# Output format: key=value lines
if active:
    tc = active.get('target_channels', ['dmg', 'appstore'])
    dmg = active.get('dmg', {})
    appstore = active.get('appstore', {})
    print(f"ACTIVE_VER={active_ver}")
    print(f"ACTIVE_TARGETS={','.join(tc)}")
    print(f"ACTIVE_DMG_STATUS={dmg.get('status', 'pending')}")
    print(f"ACTIVE_AS_STATUS={appstore.get('status', 'pending')}")
    print(f"ACTIVE_AS_BUILD={appstore.get('build_number', '?')}")
    print(f"ACTIVE_DMG_TARGETED={'true' if 'dmg' in tc else 'false'}")
    print(f"ACTIVE_AS_TARGETED={'true' if 'appstore' in tc else 'false'}")

if previous:
    tc = previous.get('target_channels', ['dmg', 'appstore'])
    dmg = previous.get('dmg', {})
    appstore = previous.get('appstore', {})
    print(f"PREV_VER={previous_ver}")
    print(f"PREV_TARGETS={','.join(tc)}")
    print(f"PREV_DMG_STATUS={dmg.get('status', 'unknown')}")
    print(f"PREV_AS_STATUS={appstore.get('status', 'unknown')}")
    print(f"PREV_AS_BUILD={appstore.get('build_number', '?')}")

# Check for incomplete marketing on shipped releases
# Actually verify by reading phase status from release.json
import os

for ver, info in sorted(releases.items(), key=lambda x: tuple(map(int, x[0].split('.'))), reverse=True):
    dmg = info.get('dmg', {})
    appstore = info.get('appstore', {})
    tc = info.get('target_channels', ['dmg', 'appstore'])

    dmg_done = dmg.get('status') in ['shipped', 'skipped'] or 'dmg' not in tc
    as_done = appstore.get('status') in ['approved', 'skipped'] or 'appstore' not in tc

    if dmg_done and as_done and info.get('status') != 'complete':
        # Channels are shipped but release not complete - check what's actually pending
        release_json_path = f'releases/v{ver}/release.json'
        if os.path.exists(release_json_path):
            try:
                with open(release_json_path, 'r') as rf:
                    release_data = json.load(rf)
                phases = release_data.get('phases', {})
                marketing = phases.get('marketing', {}).get('status', 'pending')
                post_release = phases.get('post_release', {}).get('status', 'pending')

                # Only report as marketing pending if actually pending
                if marketing != 'complete' or post_release != 'complete':
                    print(f"MARKETING_VER={ver}")
                    print(f"MARKETING_TARGETS={','.join(tc)}")
                    print(f"MARKETING_STATUS={marketing}")
                    print(f"POST_RELEASE_STATUS={post_release}")
                    break
            except:
                # Fallback to heuristic if can't read release.json
                print(f"MARKETING_VER={ver}")
                print(f"MARKETING_TARGETS={','.join(tc)}")
                break
PYEOF
)

# Parse output
eval "$CONTEXT" 2>/dev/null || true

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Release Context${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Show active release
if [ -n "$ACTIVE_VER" ]; then
    echo -e "${GREEN}Active: v${ACTIVE_VER}${NC} (${ACTIVE_TARGETS/,/, })"

    # Determine current phase
    if [ "$ACTIVE_DMG_TARGETED" = "true" ] && [ "$ACTIVE_DMG_STATUS" = "pending" ]; then
        echo -e "  Phase:  ${YELLOW}build (pending)${NC}"
        echo "  Next:   ./scripts/release/build.sh $ACTIVE_VER"
    elif [ "$ACTIVE_AS_TARGETED" = "true" ] && [ "$ACTIVE_AS_STATUS" = "pending" ]; then
        echo -e "  Phase:  ${YELLOW}build (pending)${NC}"
        echo "  Next:   ./scripts/release/build.sh $ACTIVE_VER"
    elif [ "$ACTIVE_DMG_TARGETED" = "true" ] && [ "$ACTIVE_DMG_STATUS" = "built" ]; then
        echo -e "  Phase:  ${YELLOW}deploy (dmg built)${NC}"
        echo "  Next:   ./scripts/release/mark-shipped.sh $ACTIVE_VER --dmg"
    elif [ "$ACTIVE_AS_TARGETED" = "true" ] && [ "$ACTIVE_AS_STATUS" = "built" ]; then
        echo -e "  Phase:  ${YELLOW}submission (built)${NC}"
        echo "  Next:   bash scripts/xc.sh upload"
        echo "          ./scripts/release/mark-submitted.sh $ACTIVE_VER --build $ACTIVE_AS_BUILD"
    elif [ "$ACTIVE_AS_TARGETED" = "true" ] && [ "$ACTIVE_AS_STATUS" = "submitted" ]; then
        echo -e "  Phase:  ${YELLOW}review (submitted)${NC}"
        echo "  Next:   Waiting for Apple..."
        echo "          If approved: ./scripts/release/mark-shipped.sh $ACTIVE_VER --appstore --build $ACTIVE_AS_BUILD"
    elif [ "$ACTIVE_AS_TARGETED" = "true" ] && [ "$ACTIVE_AS_STATUS" = "rejected" ]; then
        echo -e "  Phase:  ${RED}rejected${NC}"
        echo "  Next:   ./scripts/release/init.sh $ACTIVE_VER --reset"
    else
        # Check if all targeted channels are done
        DMG_DONE=true
        AS_DONE=true
        [ "$ACTIVE_DMG_TARGETED" = "true" ] && [ "$ACTIVE_DMG_STATUS" != "shipped" ] && DMG_DONE=false
        [ "$ACTIVE_AS_TARGETED" = "true" ] && [ "$ACTIVE_AS_STATUS" != "approved" ] && AS_DONE=false

        if [ "$DMG_DONE" = true ] && [ "$AS_DONE" = true ]; then
            echo -e "  Phase:  ${GREEN}shipped (marketing pending)${NC}"
            echo "  Next:   Complete Phase 5: releases/v${ACTIVE_VER}/checklists/05-marketing.md"
        else
            echo -e "  Phase:  ${YELLOW}in progress${NC}"
        fi
    fi
    echo ""
fi

# Show previous release with incomplete marketing
if [ -n "$MARKETING_VER" ] && [ "$MARKETING_VER" != "$ACTIVE_VER" ]; then
    echo -e "${YELLOW}Marketing pending: v${MARKETING_VER}${NC} (${MARKETING_TARGETS/,/, })"
    echo "  Complete: releases/v${MARKETING_VER}/checklists/05-marketing.md"
    echo ""
fi

# Show what's in production
echo -e "${DIM}In production:${NC}"
python3 << 'PYEOF'
import json
try:
    with open('releases/manifest.json', 'r') as f:
        data = json.load(f)

    dmg_prod = None
    as_prod = None

    for ver, info in sorted(data.get('releases', {}).items(), key=lambda x: tuple(map(int, x[0].split('.'))), reverse=True):
        dmg = info.get('dmg', {})
        appstore = info.get('appstore', {})
        tc = info.get('target_channels', ['dmg', 'appstore'])

        if not dmg_prod and 'dmg' in tc and dmg.get('status') == 'shipped':
            dmg_prod = (ver, dmg)
        if not as_prod and 'appstore' in tc and appstore.get('status') == 'approved':
            as_prod = (ver, appstore)

        if dmg_prod and as_prod:
            break

    if dmg_prod:
        print(f"  DMG:       v{dmg_prod[0]}")
    else:
        print(f"  DMG:       (none shipped)")

    if as_prod:
        print(f"  App Store: v{as_prod[0]} build {as_prod[1].get('build_number', '?')}")
    else:
        print(f"  App Store: (none approved)")
except:
    print("  (unable to determine)")
PYEOF

echo ""
echo -e "${DIM}───────────────────────────────────────────────────────────────${NC}"
echo -e "${DIM}./scripts/release/status.sh <version> for details${NC}"
echo ""
