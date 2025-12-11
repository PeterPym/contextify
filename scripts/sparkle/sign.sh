#!/usr/bin/env bash
#
# sparkle-sign.sh - Sign DMG for Sparkle updates
#
# Signs a DMG file with EdDSA for Sparkle verification.
# Outputs the signature and file size for use in appcast.xml.
#
# Usage:
#   ./scripts/sparkle-sign.sh path/to/Contextify.dmg
#
# For CI (using SPARKLE_PRIVATE_KEY env var):
#   SPARKLE_PRIVATE_KEY=base64_encoded_key ./scripts/sparkle-sign.sh path/to/Contextify.dmg
#

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <dmg-file>"
  echo ""
  echo "Example:"
  echo "  $0 dist/Contextify.dmg"
  echo ""
  exit 1
fi

DMG_PATH="$1"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Error: DMG file not found: $DMG_PATH"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Find Sparkle binaries (same logic as keygen script)
find_sparkle_bin() {
  # Try Xcode SPM artifacts first (preferred - actual binaries)
  # DMG builds use .derived-dmg
  if [[ -f "$PROJECT_ROOT/.derived-dmg/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" ]]; then
    echo "$PROJECT_ROOT/.derived-dmg/SourcePackages/artifacts/sparkle/Sparkle/bin"
    return
  fi

  # Try DerivedData (after Xcode build)
  local derived_sparkle
  derived_sparkle=$(find "$PROJECT_ROOT/.derived-dmg" -path "*/artifacts/*/bin/sign_update" -type f 2>/dev/null | head -1)
  if [[ -n "$derived_sparkle" ]]; then
    echo "$(dirname "$derived_sparkle")"
    return
  fi

  # Try SPM checkouts
  if [[ -f "$PROJECT_ROOT/.build/checkouts/Sparkle/bin/sign_update" ]]; then
    echo "$PROJECT_ROOT/.build/checkouts/Sparkle/bin"
    return
  fi

  # Try homebrew
  local brew_sparkle="/opt/homebrew/Caskroom/sparkle"
  if [[ -d "$brew_sparkle" ]]; then
    local version
    version=$(ls -1 "$brew_sparkle" | sort -V | tail -1)
    if [[ -f "$brew_sparkle/$version/bin/sign_update" ]]; then
      echo "$brew_sparkle/$version/bin"
      return
    fi
  fi

  echo ""
}

SPARKLE_BIN=$(find_sparkle_bin)

if [[ -z "$SPARKLE_BIN" ]]; then
  echo "Error: Sparkle binaries not found."
  echo "Build the DMG scheme first: bash scripts/xc.sh --dist=dmg build"
  exit 1
fi

# Get file size
FILE_SIZE=$(stat -f%z "$DMG_PATH")
echo "DMG size: $FILE_SIZE bytes"
echo ""

# Sign the DMG
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "Using private key from SPARKLE_PRIVATE_KEY environment variable"
  echo ""

  # Decode base64 and pipe to sign_update
  SIGNATURE_OUTPUT=$(echo "$SPARKLE_PRIVATE_KEY" | base64 -d | "$SPARKLE_BIN/sign_update" "$DMG_PATH" --ed-key-file -)
else
  echo "Using private key from macOS Keychain"
  echo ""

  SIGNATURE_OUTPUT=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
fi

echo "Raw output from sign_update:"
echo "$SIGNATURE_OUTPUT"
echo ""

# Extract just the signature value
SIGNATURE=$(echo "$SIGNATURE_OUTPUT" | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/')

if [[ -z "$SIGNATURE" || "$SIGNATURE" == "$SIGNATURE_OUTPUT" ]]; then
  echo "Error: Could not parse signature from output"
  exit 1
fi

echo "============================================="
echo "Appcast XML values:"
echo "============================================="
echo ""
echo "sparkle:edSignature=\"$SIGNATURE\""
echo "length=\"$FILE_SIZE\""
echo ""
echo "============================================="
echo ""
echo "Copy these values to website/appcast.xml"
echo ""
