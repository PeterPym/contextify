#!/bin/bash
# ============================================================================
# normalize-statuses.sh - One-time migration to normalize status values
# ============================================================================
#
# Purpose:
#   Normalizes legacy status values in manifest.json to match STATUS-VALUES.md
#   - DMG: 'complete' -> 'shipped'
#   - App Store: 'complete' -> 'approved'
#
# Usage:
#   ./scripts/release/normalize-statuses.sh
#
# State Changes:
#   - releases/manifest.json: Status values normalized
#
# Exit Codes:
#   0 - Success (with or without changes)
# ============================================================================

set -e

MANIFEST="releases/manifest.json"

if [ ! -f "$MANIFEST" ]; then
    echo "Error: $MANIFEST not found"
    exit 1
fi

echo "Normalizing status values in $MANIFEST..."

python3 << 'EOF'
import json

with open('releases/manifest.json', 'r') as f:
    data = json.load(f)

changes = 0

for version, release in data.get('releases', {}).items():
    # Normalize DMG
    dmg = release.get('dmg', {})
    if dmg.get('status') == 'complete':
        dmg['status'] = 'shipped'
        print(f"  {version}: DMG 'complete' -> 'shipped'")
        changes += 1

    # Normalize App Store
    appstore = release.get('appstore', {})
    if appstore.get('status') == 'complete':
        appstore['status'] = 'approved'
        print(f"  {version}: App Store 'complete' -> 'approved'")
        changes += 1

if changes > 0:
    with open('releases/manifest.json', 'w') as f:
        json.dump(data, f, indent=2)
    print(f"\nNormalized {changes} status value(s)")
else:
    print("  No legacy values found")

print("Done.")
EOF
