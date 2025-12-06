#!/bin/bash
# ============================================================================
# guards.sh - Minimal precondition checks for release scripts
# ============================================================================
#
# Purpose:
#   Provides precondition checks to prevent invalid state transitions.
#   Canonical source for channel status: manifest.json
#   Canonical source for artifacts: filesystem
#
# Usage:
#   Source this file after setting ROOT_DIR:
#     ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
#     source "$ROOT_DIR/scripts/release/lib/guards.sh"
#
# Functions:
#   get_target_channels VERSION         - Get target channels from manifest.json
#   is_channel_targeted VERSION CHANNEL - Check if channel is targeted
#   get_channel_status VERSION CHANNEL  - Get current status from manifest.json
#   artifact_exists VERSION TYPE        - Check if artifact exists on filesystem
#   check_can_ship_dmg VERSION          - Precondition for mark-shipped.sh --dmg
#   check_can_ship_appstore VERSION     - Precondition for mark-shipped.sh --appstore
#   check_can_submit VERSION            - Precondition for mark-submitted.sh
#   check_can_reject VERSION            - Soft check for mark-rejected.sh
#   check_reset_safety VERSION          - Warnings for init.sh --reset
# ============================================================================

# Note: ROOT_DIR must be set by caller before sourcing
if [ -z "$ROOT_DIR" ]; then
    echo "Error: ROOT_DIR must be set before sourcing guards.sh" >&2
    exit 1
fi

MANIFEST="${ROOT_DIR}/releases/manifest.json"

# Get target channels from manifest.json
# Returns space-separated channel names (e.g., "dmg" or "appstore" or "dmg appstore")
# Defaults to "dmg appstore" if target_channels is missing (backward compat)
get_target_channels() {
    local version="$1"

    python3 -c "
import json
try:
    with open('$MANIFEST') as f:
        data = json.load(f)
    release = data.get('releases', {}).get('$version', {})
    channels = release.get('target_channels')
    if not channels:
        print('dmg appstore')  # backward compat
    else:
        print(' '.join(sorted(channels)))
except Exception:
    print('dmg appstore')
" 2>/dev/null
}

# Check if a channel is targeted for a version
# Returns 0 if targeted, 1 if not
is_channel_targeted() {
    local version="$1"
    local channel="$2"
    local targets
    targets="$(get_target_channels "$version")"
    [[ " $targets " == *" $channel "* ]]
}

# Get channel status from manifest.json
# Treats legacy "complete" as "shipped"/"approved" for compatibility
# Returns "pending" if version not in manifest (with warning)
get_channel_status() {
    local version="$1"
    local channel="$2"

    local result
    result=$(python3 -c "
import json
import sys
try:
    with open('$MANIFEST') as f:
        data = json.load(f)
    release = data.get('releases', {}).get('$version')
    if release is None:
        print('__MISSING__')
    else:
        status = release.get('$channel', {}).get('status', 'pending')
        # Legacy compatibility
        if status == 'complete':
            status = 'shipped' if '$channel' == 'dmg' else 'approved'
        print(status)
except Exception:
    print('__ERROR__')
" 2>/dev/null)

    case "$result" in
        __MISSING__)
            echo "Warning: v$version not in manifest.json, treating '$channel' as 'pending'" >&2
            echo "pending"
            ;;
        __ERROR__|"")
            echo "pending"
            ;;
        *)
            echo "$result"
            ;;
    esac
}

# Check if artifact exists
artifact_exists() {
    local version="$1"
    local type="$2"

    case "$type" in
        dmg)
            [ -f "${ROOT_DIR}/build/archives/v${version}/dmg/Contextify-${version}.dmg" ]
            ;;
        archive)
            [ -d "${ROOT_DIR}/build/archives/v${version}/appstore/Contextify.xcarchive" ]
            ;;
        pkg)
            [ -f "${ROOT_DIR}/build/archives/v${version}/appstore/Contextify-${version}.pkg" ]
            ;;
        *)
            return 1
            ;;
    esac
}

# Precondition check for mark-shipped.sh --dmg
check_can_ship_dmg() {
    local version="$1"

    # Must target DMG channel
    if ! is_channel_targeted "$version" dmg; then
        echo "Error: v$version does not target the DMG channel" >&2
        echo "  target_channels: $(get_target_channels "$version")" >&2
        return 1
    fi

    local status=$(get_channel_status "$version" "dmg")

    # Already shipped - allow idempotent re-run
    if [ "$status" = "shipped" ]; then
        echo "Note: DMG already marked as shipped (idempotent re-run)" >&2
        return 0
    fi

    # Must be built (or pending with artifacts from legacy flow)
    if [ "$status" != "built" ] && [ "$status" != "pending" ]; then
        echo "Error: Cannot ship DMG - status is '$status'" >&2
        return 1
    fi

    # Must have artifact
    if ! artifact_exists "$version" dmg; then
        echo "Error: DMG archive not found" >&2
        echo "  Expected: build/archives/v${version}/dmg/Contextify-${version}.dmg" >&2
        echo "  Run: ./scripts/release/build.sh $version" >&2
        return 1
    fi

    return 0
}

# Precondition check for mark-shipped.sh --appstore
check_can_ship_appstore() {
    local version="$1"

    # Must target App Store channel
    if ! is_channel_targeted "$version" appstore; then
        echo "Error: v$version does not target the App Store channel" >&2
        echo "  target_channels: $(get_target_channels "$version")" >&2
        return 1
    fi

    local status=$(get_channel_status "$version" "appstore")

    # Already approved - allow idempotent re-run
    if [ "$status" = "approved" ]; then
        echo "Note: App Store already marked as approved (idempotent re-run)" >&2
        return 0
    fi

    # Must be submitted (approved comes after review)
    if [ "$status" != "submitted" ]; then
        echo "Error: Cannot mark App Store approved - status is '$status', expected 'submitted'" >&2
        return 1
    fi

    return 0
}

# Precondition check for mark-submitted.sh
check_can_submit() {
    local version="$1"

    # Must target App Store channel
    if ! is_channel_targeted "$version" appstore; then
        echo "Error: v$version does not target the App Store" >&2
        echo "  target_channels: $(get_target_channels "$version")" >&2
        return 1
    fi

    local status=$(get_channel_status "$version" "appstore")

    # Already submitted - allow idempotent re-run
    if [ "$status" = "submitted" ]; then
        echo "Note: Already marked as submitted (idempotent re-run)" >&2
        return 0
    fi

    # Must be built
    if [ "$status" != "built" ] && [ "$status" != "pending" ]; then
        echo "Error: Cannot submit - status is '$status'" >&2
        return 1
    fi

    # Must have archive
    if ! artifact_exists "$version" archive; then
        echo "Error: App Store archive not found" >&2
        echo "  Expected: build/archives/v${version}/appstore/Contextify.xcarchive" >&2
        echo "  Run: ./scripts/release/build.sh $version" >&2
        return 1
    fi

    return 0
}

# Precondition check for mark-rejected.sh
check_can_reject() {
    local version="$1"

    # Must target App Store channel
    if ! is_channel_targeted "$version" appstore; then
        echo "Error: v$version does not target the App Store" >&2
        echo "  target_channels: $(get_target_channels "$version")" >&2
        return 1
    fi

    local status=$(get_channel_status "$version" "appstore")

    # Must be submitted
    if [ "$status" != "submitted" ]; then
        echo "Warning: Marking rejected but status is '$status', expected 'submitted'" >&2
        # Don't block - if Apple rejected it, we want to record that
    fi

    return 0
}

# Warning for init.sh --reset when already shipped
check_reset_safety() {
    local version="$1"
    local dmg_status=$(get_channel_status "$version" "dmg")
    local as_status=$(get_channel_status "$version" "appstore")

    if [ "$dmg_status" = "shipped" ]; then
        echo "Warning: DMG v${version} is already shipped" >&2
        echo "  Reset will only affect App Store submission" >&2
    fi

    if [ "$as_status" = "approved" ]; then
        echo "Warning: App Store v${version} is already approved" >&2
        echo "  Consider starting a new version instead" >&2
    fi

    return 0
}
