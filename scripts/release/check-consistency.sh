#!/bin/bash
# ============================================================================
# check-consistency.sh - Check consistency between release state files
# ============================================================================
#
# Purpose:
#   Validates that manifest.json, release.json, and filesystem artifacts
#   are consistent with each other. Reports any discrepancies.
#
# Usage:
#   ./scripts/release/check-consistency.sh [VERSION]
#
# Options:
#   VERSION    Check specific version only (optional)
#
# Exit Codes:
#   0 - No issues found
#   N - Number of issues found
#
# Examples:
#   ./scripts/release/check-consistency.sh        # Check all releases
#   ./scripts/release/check-consistency.sh 1.0.0  # Check v1.0.0 only
# ============================================================================

set -e

MANIFEST="releases/manifest.json"
ISSUES=0
CHECK_VERSION="$1"

if [ ! -f "$MANIFEST" ]; then
    echo "Error: $MANIFEST not found"
    exit 1
fi

echo "Checking release state consistency..."
echo ""

for release_dir in releases/v*/; do
    version=$(basename "$release_dir" | sed 's/^v//')
    release_json="$release_dir/release.json"

    # Skip if checking specific version and this isn't it
    if [ -n "$CHECK_VERSION" ] && [ "$version" != "$CHECK_VERSION" ]; then
        continue
    fi

    echo "Checking v$version..."

    if [ ! -f "$release_json" ]; then
        echo "  Warning: No release.json found"
        ((ISSUES++)) || true
        continue
    fi

    # Compare build numbers
    manifest_build=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$version',{}).get('appstore',{}).get('build_number', 'N/A'))" 2>/dev/null || echo "N/A")
    release_build=$(python3 -c "import json; d=json.load(open('$release_json')); print(d.get('phases',{}).get('build',{}).get('appstore',{}).get('build_number', 'N/A'))" 2>/dev/null || echo "N/A")

    if [ "$manifest_build" != "$release_build" ]; then
        echo "  Issue: Build number mismatch"
        echo "    manifest.json: $manifest_build"
        echo "    release.json:  $release_build"
        ((ISSUES++)) || true
    fi

    # Check DMG artifact matches claimed state
    manifest_dmg=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$version',{}).get('dmg',{}).get('status', 'pending'))" 2>/dev/null || echo "pending")
    dmg_path="build/archives/v${version}/dmg/Contextify-${version}.dmg"

    if [ "$manifest_dmg" = "shipped" ] || [ "$manifest_dmg" = "built" ]; then
        if [ ! -f "$dmg_path" ]; then
            echo "  Issue: DMG marked '$manifest_dmg' but archive missing"
            echo "    Expected: $dmg_path"
            ((ISSUES++)) || true
        else
            echo "  OK: DMG archive exists"
        fi
    fi

    # Check App Store archive matches claimed state
    manifest_as=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$version',{}).get('appstore',{}).get('status', 'pending'))" 2>/dev/null || echo "pending")
    archive_path="build/archives/v${version}/appstore/Contextify.xcarchive"

    if [ "$manifest_as" = "submitted" ] || [ "$manifest_as" = "approved" ] || [ "$manifest_as" = "built" ]; then
        if [ ! -d "$archive_path" ]; then
            echo "  Issue: App Store marked '$manifest_as' but archive missing"
            echo "    Expected: $archive_path"
            ((ISSUES++)) || true
        else
            echo "  OK: App Store archive exists"
        fi
    fi

    # Check for legacy 'complete' status
    if [ "$manifest_dmg" = "complete" ]; then
        echo "  Issue: Legacy DMG status 'complete' should be 'shipped'"
        echo "    Run: ./scripts/release/normalize-statuses.sh"
        ((ISSUES++)) || true
    fi

    echo ""
done

echo "=========================================="
if [ "$ISSUES" -eq 0 ]; then
    echo "OK: No consistency issues found"
else
    echo "Found $ISSUES issue(s)"
    echo ""
    echo "To fix:"
    echo "  - Build number mismatch: Run init.sh --reset to sync"
    echo "  - Missing archives: Run build.sh to rebuild"
    echo "  - Legacy status: Run normalize-statuses.sh"
fi

exit $ISSUES
