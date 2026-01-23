#!/bin/bash
#
# check-dmg-consistency.sh - Verify macOS DMG download infrastructure is consistent
#
# Checks that these three sources agree:
#   1. website/macos-version (what /go/dmg and install.sh use)
#   2. website/appcast.xml (what Sparkle auto-updater uses)
#   3. GitHub release assets (what users actually download)
#
# Run this:
#   - Before deploying the website
#   - After uploading a DMG to GitHub
#   - After editing appcast.xml or macos-version
#
# Usage:
#   ./scripts/release/check-dmg-consistency.sh [OPTIONS]
#
# Options:
#   --strict    Exit 1 on any mismatch (default: warn only for appcast lag)
#   --quiet     Only output on failure
#   --help      Show this help
#
# Exit codes:
#   0 - All consistent
#   1 - Critical inconsistency (macos-version points to missing DMG)
#   2 - Error fetching data
#   3 - Appcast behind macos-version (warning unless --strict)
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
GITHUB_REPO="PeterPym/contextify"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

# Options
STRICT=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --strict) STRICT=true; shift ;;
    --quiet) QUIET=true; shift ;;
    --help|-h) sed -n '2,28p' "$0" | sed 's/^# //' | sed 's/^#//'; exit 0 ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

info() { [ "$QUIET" = false ] && echo -e "$1" || true; }
ok() { [ "$QUIET" = false ] && echo -e "${GREEN}[OK]${NC} $1" || true; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

EXIT_CODE=0

info ""
info "${BOLD}DMG Download Consistency Check${NC}"
info "==============================="
info ""

# 1. Read website/macos-version
MACOS_VERSION_FILE="$REPO_ROOT/website/macos-version"
if [ ! -f "$MACOS_VERSION_FILE" ]; then
  fail "website/macos-version file not found"
  exit 2
fi
MACOS_VERSION=$(tr -d '\r\n' < "$MACOS_VERSION_FILE")
if [ -z "$MACOS_VERSION" ]; then
  fail "website/macos-version is empty"
  exit 2
fi
info "macos-version file: ${BOLD}$MACOS_VERSION${NC}"

# 2. Parse appcast.xml for latest version
APPCAST_FILE="$REPO_ROOT/website/appcast.xml"
if [ ! -f "$APPCAST_FILE" ]; then
  fail "website/appcast.xml not found"
  exit 2
fi
APPCAST_VERSION=$(python3 -c "
import xml.etree.ElementTree as ET
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
root = ET.parse('$APPCAST_FILE').getroot()
items = root.findall('.//item')
if items:
    v = items[0].find('sparkle:shortVersionString', ns)
    if v is not None: print(v.text)
" 2>/dev/null || echo "")

APPCAST_URL=$(python3 -c "
import xml.etree.ElementTree as ET
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
root = ET.parse('$APPCAST_FILE').getroot()
items = root.findall('.//item')
if items:
    enc = items[0].find('enclosure')
    if enc is not None: print(enc.get('url', ''))
" 2>/dev/null || echo "")

if [ -z "$APPCAST_VERSION" ]; then
  fail "Could not parse version from appcast.xml"
  exit 2
fi
info "appcast.xml latest: ${BOLD}$APPCAST_VERSION${NC}"

# 3. Check GitHub for DMG existence
DMG_NAME="Contextify-${MACOS_VERSION}.dmg"
DMG_URL="https://github.com/$GITHUB_REPO/releases/download/v${MACOS_VERSION}/${DMG_NAME}"
info "Expected DMG URL:   ${DMG_URL}"
info ""

# Use curl to check if the DMG exists (GitHub returns 302 for valid assets, 404 for missing)
HTTP_STATUS=$(curl -sI -o /dev/null -w "%{http_code}" "$DMG_URL" 2>/dev/null || echo "000")

# Check 1: DMG exists on GitHub
if [ "$HTTP_STATUS" = "302" ] || [ "$HTTP_STATUS" = "200" ]; then
  ok "DMG exists on GitHub (v$MACOS_VERSION)"
else
  fail "DMG NOT FOUND on GitHub: $DMG_NAME (HTTP $HTTP_STATUS)"
  echo "    URL: $DMG_URL"
  echo ""
  echo "    Either:"
  echo "      - The DMG hasn't been uploaded to GitHub yet"
  echo "      - website/macos-version is set to a version that doesn't have a DMG"
  EXIT_CODE=1
fi

# Check 2: macos-version matches appcast
if [ "$MACOS_VERSION" = "$APPCAST_VERSION" ]; then
  ok "macos-version matches appcast.xml ($MACOS_VERSION)"
else
  # Appcast lagging behind is a warning (updated during release process)
  # macos-version ahead of GitHub DMG is the critical failure (Check 1)
  if [ "$STRICT" = true ]; then
    fail "macos-version ($MACOS_VERSION) does not match appcast.xml ($APPCAST_VERSION)"
    EXIT_CODE=1
  else
    warn "macos-version ($MACOS_VERSION) ahead of appcast.xml ($APPCAST_VERSION)"
    echo "    This is OK if appcast will be updated as part of the release."
    echo "    Use --strict to treat this as an error."
    [ $EXIT_CODE -eq 0 ] && EXIT_CODE=3
  fi
fi

# Check 3: appcast URL matches expected pattern
EXPECTED_APPCAST_URL="https://github.com/$GITHUB_REPO/releases/download/v${APPCAST_VERSION}/Contextify-${APPCAST_VERSION}.dmg"
if [ "$APPCAST_URL" = "$EXPECTED_APPCAST_URL" ]; then
  ok "Appcast download URL follows expected pattern"
else
  warn "Appcast URL doesn't match expected pattern"
  echo "    Expected: $EXPECTED_APPCAST_URL"
  echo "    Got:      $APPCAST_URL"
  [ $EXIT_CODE -eq 0 ] && EXIT_CODE=3
fi

info ""

# Summary
if [ $EXIT_CODE -eq 0 ]; then
  info "${GREEN}${BOLD}All checks passed.${NC} Download infrastructure is consistent."
elif [ $EXIT_CODE -eq 3 ]; then
  info "${YELLOW}${BOLD}Warnings found.${NC} Non-critical mismatches (appcast may be updating)."
else
  info "${RED}${BOLD}CRITICAL: Download link is broken.${NC}"
  echo "  Users clicking 'Download DMG' on the website will get a 404."
  echo "  Fix: Upload the DMG to GitHub or update website/macos-version."
fi
info ""

exit $EXIT_CODE
