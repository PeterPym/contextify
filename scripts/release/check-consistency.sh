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

# Check 1: Every manifest version has a release.json
echo "Checking manifest entries have release directories..."
manifest_versions=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(' '.join(d.get('releases', {}).keys()))" 2>/dev/null || echo "")
for version in $manifest_versions; do
    if [ -n "$CHECK_VERSION" ] && [ "$version" != "$CHECK_VERSION" ]; then
        continue
    fi
    release_json="releases/v${version}/release.json"
    if [ ! -f "$release_json" ]; then
        echo "  Issue: Manifest has v$version but no $release_json"
        ((ISSUES++)) || true
    fi
done
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

    # Check target_channels consistency
    target_channels=$(python3 -c "import json; d=json.load(open('$release_json')); tc=d.get('target_channels'); print(' '.join(tc) if tc else '')" 2>/dev/null || echo "")
    manifest_target_channels=$(python3 -c "import json; d=json.load(open('$MANIFEST')); tc=d.get('releases',{}).get('$version',{}).get('target_channels'); print(' '.join(tc) if tc else '')" 2>/dev/null || echo "")

    # Check for missing target_channels (backward compat: treat as both)
    if [ -z "$target_channels" ]; then
        echo "  Warning: No target_channels in release.json (defaulting to both)"
    else
        # Check for invalid channel values
        for channel in $target_channels; do
            if [ "$channel" != "dmg" ] && [ "$channel" != "appstore" ]; then
                echo "  Error: Invalid target_channel '$channel'"
                ((ISSUES++)) || true
            fi
        done
    fi

    # Check manifest and release.json agree on target_channels
    if [ -n "$target_channels" ] && [ -n "$manifest_target_channels" ]; then
        # Sort and compare
        tc_sorted=$(echo $target_channels | tr ' ' '\n' | sort | tr '\n' ' ')
        mtc_sorted=$(echo $manifest_target_channels | tr ' ' '\n' | sort | tr '\n' ' ')
        if [ "$tc_sorted" != "$mtc_sorted" ]; then
            echo "  Issue: target_channels mismatch"
            echo "    release.json:  $target_channels"
            echo "    manifest.json: $manifest_target_channels"
            ((ISSUES++)) || true
        fi
    fi

    # Determine targeting (default to both if missing)
    dmg_targeted=false
    appstore_targeted=false
    if [ -z "$target_channels" ]; then
        dmg_targeted=true
        appstore_targeted=true
    else
        [[ " $target_channels " == *" dmg "* ]] && dmg_targeted=true
        [[ " $target_channels " == *" appstore "* ]] && appstore_targeted=true
    fi

    # Check channel status matches targeting
    manifest_dmg=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$version',{}).get('dmg',{}).get('status', 'pending'))" 2>/dev/null || echo "pending")
    manifest_as=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$version',{}).get('appstore',{}).get('status', 'pending'))" 2>/dev/null || echo "pending")

    if [ "$dmg_targeted" = false ] && [ "$manifest_dmg" != "skipped" ]; then
        echo "  Issue: DMG not targeted but status is '$manifest_dmg', expected 'skipped'"
        ((ISSUES++)) || true
    fi
    if [ "$dmg_targeted" = true ] && [ "$manifest_dmg" = "skipped" ]; then
        echo "  Warning: DMG is targeted but status is 'skipped'"
        # This is a warning, not an error - might be intentional abort
    fi
    if [ "$appstore_targeted" = false ] && [ "$manifest_as" != "skipped" ]; then
        echo "  Issue: App Store not targeted but status is '$manifest_as', expected 'skipped'"
        ((ISSUES++)) || true
    fi
    if [ "$appstore_targeted" = true ] && [ "$manifest_as" = "skipped" ]; then
        echo "  Warning: App Store is targeted but status is 'skipped'"
        # This is a warning, not an error - might be intentional abort
    fi

    # Compare build numbers (only for App Store-targeted releases)
    if [ "$appstore_targeted" = true ]; then
        manifest_build=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$version',{}).get('appstore',{}).get('build_number', 'N/A'))" 2>/dev/null || echo "N/A")
        release_build=$(python3 -c "import json; d=json.load(open('$release_json')); print(d.get('phases',{}).get('build',{}).get('appstore',{}).get('build_number', 'N/A'))" 2>/dev/null || echo "N/A")

        if [ "$manifest_build" != "$release_build" ]; then
            echo "  Issue: Build number mismatch"
            echo "    manifest.json: $manifest_build"
            echo "    release.json:  $release_build"
            ((ISSUES++)) || true
        fi
    fi

    # Check DMG artifact matches claimed state (only if targeted)
    dmg_path="build/archives/v${version}/dmg/Contextify-${version}.dmg"

    if [ "$dmg_targeted" = true ]; then
        if [ "$manifest_dmg" = "shipped" ] || [ "$manifest_dmg" = "built" ]; then
            if [ ! -f "$dmg_path" ]; then
                echo "  Issue: DMG marked '$manifest_dmg' but archive missing"
                echo "    Expected: $dmg_path"
                ((ISSUES++)) || true
            else
                echo "  OK: DMG archive exists"
            fi
        fi
    else
        # Warn if non-targeted channel has artifacts
        if [ -f "$dmg_path" ]; then
            echo "  Warning: DMG not targeted but artifact exists at $dmg_path"
        fi
    fi

    # Check App Store archive matches claimed state (only if targeted)
    archive_path="build/archives/v${version}/appstore/Contextify.xcarchive"

    if [ "$appstore_targeted" = true ]; then
        if [ "$manifest_as" = "submitted" ] || [ "$manifest_as" = "approved" ] || [ "$manifest_as" = "built" ]; then
            if [ ! -d "$archive_path" ]; then
                echo "  Issue: App Store marked '$manifest_as' but archive missing"
                echo "    Expected: $archive_path"
                ((ISSUES++)) || true
            else
                echo "  OK: App Store archive exists"
            fi
        fi
    else
        # Warn if non-targeted channel has artifacts
        if [ -d "$archive_path" ]; then
            echo "  Warning: App Store not targeted but archive exists at $archive_path"
        fi
    fi

    # Check for legacy 'complete' status
    if [ "$manifest_dmg" = "complete" ]; then
        echo "  Issue: Legacy DMG status 'complete' should be 'shipped'"
        echo "    Run: ./scripts/release/normalize-statuses.sh"
        ((ISSUES++)) || true
    fi

    # Check overall release.status sanity
    overall_status=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$version',{}).get('status', 'in_progress'))" 2>/dev/null || echo "in_progress")
    if [ "$overall_status" = "complete" ]; then
        # When complete, DMG should be shipped|skipped and appstore should be approved|skipped
        if [ "$manifest_dmg" != "shipped" ] && [ "$manifest_dmg" != "skipped" ]; then
            echo "  Issue: release.status is 'complete' but DMG is '$manifest_dmg'"
            echo "    Expected: shipped or skipped"
            ((ISSUES++)) || true
        fi
        if [ "$manifest_as" != "approved" ] && [ "$manifest_as" != "skipped" ]; then
            echo "  Issue: release.status is 'complete' but App Store is '$manifest_as'"
            echo "    Expected: approved or skipped"
            ((ISSUES++)) || true
        fi
    fi

    echo ""
done

# Check Xcode build number matches manifest (for current version)
echo "Checking Xcode project build number sync..."
CURRENT_VERSION=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('current_version', ''))" 2>/dev/null || echo "")
if [ -n "$CURRENT_VERSION" ]; then
    if [ -z "$CHECK_VERSION" ] || [ "$CHECK_VERSION" = "$CURRENT_VERSION" ]; then
        MANIFEST_BUILD=$(python3 -c "import json; d=json.load(open('$MANIFEST')); print(d.get('releases',{}).get('$CURRENT_VERSION',{}).get('appstore',{}).get('build_number', 0))" 2>/dev/null || echo "0")
        PBXPROJ="Contextify/Contextify.xcodeproj/project.pbxproj"
        if [ -f "$PBXPROJ" ]; then
            XCODE_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION" "$PBXPROJ" | sed 's/.*= //' | tr -d ';' | tr -d ' ')
            if [ "$MANIFEST_BUILD" != "$XCODE_BUILD" ] && [ "$MANIFEST_BUILD" != "0" ]; then
                echo "  Issue: Build number mismatch for v$CURRENT_VERSION"
                echo "    Manifest:      $MANIFEST_BUILD"
                echo "    Xcode project: $XCODE_BUILD"
                echo "    Fix: ./scripts/release/init.sh $CURRENT_VERSION --reset"
                ((ISSUES++)) || true
            else
                echo "  OK: Build numbers in sync ($XCODE_BUILD)"
            fi
        fi
    fi
fi
echo ""

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
