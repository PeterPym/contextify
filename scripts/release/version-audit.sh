#!/bin/bash
#
# version-audit.sh - Query and compare versions across all distribution channels
#
# Verifies that published binaries are consistent across:
# - GitHub Releases (DMG)
# - GitHub Releases (Linux CLI)
# - Sparkle appcast (auto-updates)
# - App Store (manual check note)
#
# CRITICAL: The published DMG MUST match what Sparkle uses for updates.
# This script verifies URL consistency between GitHub releases and appcast.xml.
#
# Usage:
#   ./scripts/release/version-audit.sh [OPTIONS]
#
# Options:
#   --json          Output as JSON
#   --quiet         Only output if inconsistencies found
#   --no-color      Disable colored output
#   --help          Show this help
#
# Exit codes:
#   0 - All versions consistent
#   1 - Inconsistencies found (requires attention)
#   2 - Error fetching data
#
# Examples:
#   ./scripts/release/version-audit.sh
#   ./scripts/release/version-audit.sh --json
#   ./scripts/release/version-audit.sh --quiet  # CI/cron usage
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
GITHUB_REPO="PeterPym/contextify"
APPCAST_URL="https://contextify.sh/appcast.xml"
APPSTORE_ID="6753190666"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Options
JSON_OUTPUT=false
QUIET=false
NO_COLOR=false

usage() {
  sed -n '2,32p' "$0" | sed 's/^# //' | sed 's/^#//'
  exit 0
}

error() {
  if [ "$NO_COLOR" = true ]; then
    echo "Error: $1" >&2
  else
    echo -e "${RED}Error:${NC} $1" >&2
  fi
}

warn() {
  if [ "$QUIET" = false ]; then
    if [ "$NO_COLOR" = true ]; then
      echo "Warning: $1"
    else
      echo -e "${YELLOW}Warning:${NC} $1"
    fi
  fi
}

info() {
  if [ "$QUIET" = false ]; then
    if [ "$NO_COLOR" = true ]; then
      echo "$1"
    else
      echo -e "${BLUE}$1${NC}"
    fi
  fi
}

success() {
  if [ "$QUIET" = false ]; then
    if [ "$NO_COLOR" = true ]; then
      echo "[OK] $1"
    else
      echo -e "${GREEN}[OK]${NC} $1"
    fi
  fi
}

fail() {
  if [ "$NO_COLOR" = true ]; then
    echo "[FAIL] $1"
  else
    echo -e "${RED}[FAIL]${NC} $1"
  fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --quiet)
      QUIET=true
      shift
      ;;
    --no-color)
      NO_COLOR=true
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      error "Unknown option: $1"
      echo "Use --help for usage"
      exit 2
      ;;
  esac
done

# Initialize results
GITHUB_DMG_VERSION=""
GITHUB_DMG_BUILD=""
GITHUB_DMG_URL=""
GITHUB_LINUX_VERSION=""
SPARKLE_VERSION=""
SPARKLE_BUILD=""
SPARKLE_URL=""
APPSTORE_VERSION=""
APPSTORE_NOTE=""
ISSUES=()

# Fetch GitHub release info
info "Fetching GitHub releases..."
GITHUB_RESPONSE=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>&1) || {
  error "Failed to fetch GitHub releases"
  exit 2
}

# Check for API error
if echo "$GITHUB_RESPONSE" | grep -q '"message"'; then
  MSG=$(echo "$GITHUB_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message','Unknown error'))")
  error "GitHub API error: $MSG"
  exit 2
fi

# Parse GitHub release
GITHUB_TAG=$(echo "$GITHUB_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || echo "")
if [ -n "$GITHUB_TAG" ]; then
  GITHUB_DMG_VERSION="${GITHUB_TAG#v}"  # Strip 'v' prefix
fi

# Find DMG asset
GITHUB_DMG_URL=$(echo "$GITHUB_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'].endswith('.dmg'):
        print(asset['browser_download_url'])
        break
" 2>/dev/null || echo "")

# Find Linux assets
GITHUB_LINUX_X86=$(echo "$GITHUB_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if 'linux' in asset['name'].lower() and 'x86' in asset['name'].lower():
        print(asset['browser_download_url'])
        break
" 2>/dev/null || echo "")

GITHUB_LINUX_ARM=$(echo "$GITHUB_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if 'linux' in asset['name'].lower() and 'arm' in asset['name'].lower():
        print(asset['browser_download_url'])
        break
" 2>/dev/null || echo "")

if [ -n "$GITHUB_LINUX_X86" ] || [ -n "$GITHUB_LINUX_ARM" ]; then
  GITHUB_LINUX_VERSION="$GITHUB_DMG_VERSION"
fi

# Fetch Sparkle appcast
info "Fetching Sparkle appcast..."
APPCAST_RESPONSE=$(curl -s "$APPCAST_URL" 2>&1) || {
  warn "Failed to fetch Sparkle appcast"
  APPCAST_RESPONSE=""
}

if [ -n "$APPCAST_RESPONSE" ]; then
  # Parse latest item from appcast (first <item> block)
  SPARKLE_VERSION=$(echo "$APPCAST_RESPONSE" | python3 -c "
import sys
import xml.etree.ElementTree as ET

content = sys.stdin.read()
try:
    # Define namespace
    ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
    root = ET.fromstring(content)
    items = root.findall('.//item')
    if items:
        item = items[0]  # First item is newest
        version = item.find('sparkle:shortVersionString', ns)
        if version is not None:
            print(version.text)
except Exception as e:
    pass
" 2>/dev/null || echo "")

  SPARKLE_BUILD=$(echo "$APPCAST_RESPONSE" | python3 -c "
import sys
import xml.etree.ElementTree as ET

content = sys.stdin.read()
try:
    ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
    root = ET.fromstring(content)
    items = root.findall('.//item')
    if items:
        item = items[0]
        build = item.find('sparkle:version', ns)
        if build is not None:
            print(build.text)
except Exception as e:
    pass
" 2>/dev/null || echo "")

  SPARKLE_URL=$(echo "$APPCAST_RESPONSE" | python3 -c "
import sys
import xml.etree.ElementTree as ET

content = sys.stdin.read()
try:
    ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
    root = ET.fromstring(content)
    items = root.findall('.//item')
    if items:
        item = items[0]
        enclosure = item.find('enclosure')
        if enclosure is not None:
            print(enclosure.get('url', ''))
except Exception as e:
    pass
" 2>/dev/null || echo "")
fi

# App Store version check (requires manual verification)
# Note: Automated App Store version checking requires App Store Connect API
# which needs authentication. For now, we note it requires manual check.
APPSTORE_NOTE="Manual check required (App Store Connect or apps.apple.com)"

# Try to get App Store version from local manifest for reference
LOCAL_APPSTORE_VERSION=""
if [ -f "$REPO_ROOT/releases/manifest.json" ]; then
  LOCAL_APPSTORE_VERSION=$(python3 -c "
import json
with open('$REPO_ROOT/releases/manifest.json') as f:
    data = json.load(f)
    releases = data.get('releases', {})
    # Find latest approved App Store version
    for ver in sorted(releases.keys(), reverse=True):
        info = releases[ver]
        appstore = info.get('appstore', {})
        if appstore.get('status') in ['approved', 'shipped']:
            print(ver)
            break
" 2>/dev/null || echo "")
fi

# Perform integrity checks
INTEGRITY_OK=true

# Check 1: GitHub DMG URL matches Sparkle URL
if [ -n "$GITHUB_DMG_URL" ] && [ -n "$SPARKLE_URL" ]; then
  if [ "$GITHUB_DMG_URL" = "$SPARKLE_URL" ]; then
    CHECK1_OK=true
  else
    CHECK1_OK=false
    INTEGRITY_OK=false
    ISSUES+=("GitHub DMG URL does not match Sparkle appcast URL")
  fi
else
  CHECK1_OK="unknown"
  if [ -z "$GITHUB_DMG_URL" ]; then
    ISSUES+=("No DMG found in GitHub release")
  fi
  if [ -z "$SPARKLE_URL" ]; then
    ISSUES+=("Could not parse Sparkle appcast URL")
  fi
fi

# Check 2: Version numbers match
if [ -n "$GITHUB_DMG_VERSION" ] && [ -n "$SPARKLE_VERSION" ]; then
  if [ "$GITHUB_DMG_VERSION" = "$SPARKLE_VERSION" ]; then
    CHECK2_OK=true
  else
    CHECK2_OK=false
    INTEGRITY_OK=false
    ISSUES+=("GitHub version ($GITHUB_DMG_VERSION) does not match Sparkle version ($SPARKLE_VERSION)")
  fi
else
  CHECK2_OK="unknown"
fi

# Check 3: Linux version matches DMG version (if Linux exists)
if [ -n "$GITHUB_LINUX_VERSION" ] && [ -n "$GITHUB_DMG_VERSION" ]; then
  if [ "$GITHUB_LINUX_VERSION" = "$GITHUB_DMG_VERSION" ]; then
    CHECK3_OK=true
  else
    CHECK3_OK=false
    INTEGRITY_OK=false
    ISSUES+=("Linux CLI version does not match DMG version")
  fi
else
  CHECK3_OK="n/a"
fi

# Output
if [ "$JSON_OUTPUT" = true ]; then
  # JSON output
  cat <<EOF
{
  "audit_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "channels": {
    "github_dmg": {
      "version": "${GITHUB_DMG_VERSION:-null}",
      "url": "${GITHUB_DMG_URL:-null}"
    },
    "github_linux": {
      "version": "${GITHUB_LINUX_VERSION:-null}",
      "x86_64_url": "${GITHUB_LINUX_X86:-null}",
      "arm64_url": "${GITHUB_LINUX_ARM:-null}"
    },
    "sparkle": {
      "version": "${SPARKLE_VERSION:-null}",
      "build": "${SPARKLE_BUILD:-null}",
      "url": "${SPARKLE_URL:-null}"
    },
    "appstore": {
      "version": "${LOCAL_APPSTORE_VERSION:-null}",
      "note": "$APPSTORE_NOTE"
    }
  },
  "integrity": {
    "all_ok": $INTEGRITY_OK,
    "checks": {
      "github_sparkle_url_match": "$CHECK1_OK",
      "github_sparkle_version_match": "$CHECK2_OK",
      "linux_dmg_version_match": "$CHECK3_OK"
    },
    "issues": [$(if [ ${#ISSUES[@]} -gt 0 ]; then printf '"%s",' "${ISSUES[@]}" | sed 's/,$//'; fi)]
  }
}
EOF
elif [ "$QUIET" = true ] && [ "$INTEGRITY_OK" = true ]; then
  # Quiet mode with no issues - suppress output entirely
  :
else
  # Human-readable output
  echo ""
  if [ "$NO_COLOR" = true ]; then
    echo "Contextify Version Audit"
    echo "========================"
  else
    echo -e "${BOLD}Contextify Version Audit${NC}"
    echo "========================"
  fi
  echo ""
  echo "Audit time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo ""

  # Version table
  printf "%-16s %-10s %-8s %s\n" "Channel" "Version" "Build" "Source"
  printf "%-16s %-10s %-8s %s\n" "---------------" "-------" "-----" "------"

  # App Store (local manifest reference)
  if [ -n "$LOCAL_APPSTORE_VERSION" ]; then
    printf "%-16s %-10s %-8s %s\n" "App Store*" "$LOCAL_APPSTORE_VERSION" "-" "local manifest (verify in ASC)"
  else
    printf "%-16s %-10s %-8s %s\n" "App Store" "-" "-" "$APPSTORE_NOTE"
  fi

  # GitHub DMG
  if [ -n "$GITHUB_DMG_VERSION" ]; then
    printf "%-16s %-10s %-8s %s\n" "GitHub DMG" "$GITHUB_DMG_VERSION" "-" "github.com/${GITHUB_REPO}"
  else
    printf "%-16s %-10s %-8s %s\n" "GitHub DMG" "-" "-" "not found"
  fi

  # Sparkle
  if [ -n "$SPARKLE_VERSION" ]; then
    printf "%-16s %-10s %-8s %s\n" "Sparkle" "$SPARKLE_VERSION" "${SPARKLE_BUILD:-?}" "contextify.sh/appcast.xml"
  else
    printf "%-16s %-10s %-8s %s\n" "Sparkle" "-" "-" "fetch failed"
  fi

  # Linux CLI
  if [ -n "$GITHUB_LINUX_VERSION" ]; then
    printf "%-16s %-10s %-8s %s\n" "Linux CLI" "$GITHUB_LINUX_VERSION" "-" "github.com/${GITHUB_REPO}"
  else
    printf "%-16s %-10s %-8s %s\n" "Linux CLI" "-" "-" "not in release"
  fi

  echo ""

  # Integrity checks
  if [ "$NO_COLOR" = true ]; then
    echo "Integrity Checks:"
  else
    echo -e "${BOLD}Integrity Checks:${NC}"
  fi

  # Check 1: URL match
  if [ "$CHECK1_OK" = true ]; then
    success "GitHub DMG URL matches Sparkle appcast URL"
  elif [ "$CHECK1_OK" = false ]; then
    fail "GitHub DMG URL does NOT match Sparkle appcast URL"
    echo "    GitHub:  $GITHUB_DMG_URL"
    echo "    Sparkle: $SPARKLE_URL"
  else
    warn "Could not verify URL match (missing data)"
  fi

  # Check 2: Version match
  if [ "$CHECK2_OK" = true ]; then
    success "GitHub and Sparkle versions match ($GITHUB_DMG_VERSION)"
  elif [ "$CHECK2_OK" = false ]; then
    fail "Version mismatch: GitHub=$GITHUB_DMG_VERSION, Sparkle=$SPARKLE_VERSION"
  else
    warn "Could not verify version match (missing data)"
  fi

  # Check 3: Linux version match
  if [ "$CHECK3_OK" = true ]; then
    success "Linux CLI version matches DMG version"
  elif [ "$CHECK3_OK" = false ]; then
    fail "Linux CLI version does not match DMG version"
  elif [ "$CHECK3_OK" = "n/a" ]; then
    info "Linux CLI: Not included in this release"
  fi

  echo ""

  # Summary
  if [ "$INTEGRITY_OK" = true ]; then
    if [ "$NO_COLOR" = true ]; then
      echo "Status: All checks passed"
    else
      echo -e "${GREEN}${BOLD}Status: All checks passed${NC}"
    fi
  else
    if [ "$NO_COLOR" = true ]; then
      echo "Status: INCONSISTENCIES FOUND"
      echo ""
      echo "Issues requiring attention:"
    else
      echo -e "${RED}${BOLD}Status: INCONSISTENCIES FOUND${NC}"
      echo ""
      echo -e "${YELLOW}Issues requiring attention:${NC}"
    fi
    for issue in "${ISSUES[@]}"; do
      echo "  - $issue"
    done
    echo ""
    echo "See releases/WORKFLOW.md for the binary integrity requirement."
  fi
  echo ""

  # Note about App Store
  if [ "$NO_COLOR" = true ]; then
    echo "Note: App Store version requires manual verification in App Store Connect"
  else
    echo -e "${CYAN}Note:${NC} App Store version requires manual verification in App Store Connect"
  fi
  echo "      or via: ./scripts/release/poll-appstore-status.sh"
  echo ""
fi

# Exit code
if [ "$INTEGRITY_OK" = true ]; then
  exit 0
else
  exit 1
fi
