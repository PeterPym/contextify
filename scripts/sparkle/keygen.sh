#!/usr/bin/env bash
#
# sparkle-keygen.sh - Generate EdDSA keys for Sparkle updates
#
# This script generates the EdDSA key pair needed for signing Sparkle updates.
# Run once during initial setup. The public key goes in Info-DMG.plist,
# the private key is stored in the macOS Keychain (and optionally exported for CI).
#
# Usage:
#   ./scripts/sparkle-keygen.sh          # Generate new key pair
#   ./scripts/sparkle-keygen.sh export   # Export private key for CI
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Check if Sparkle binaries are available
find_sparkle_bin() {
  # Try Xcode SPM artifacts first (preferred - actual binaries)
  # DMG builds use .derived-dmg
  if [[ -f "$PROJECT_ROOT/.derived-dmg/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys" ]]; then
    echo "$PROJECT_ROOT/.derived-dmg/SourcePackages/artifacts/sparkle/Sparkle/bin"
    return
  fi

  # Try DerivedData (after Xcode build)
  local derived_sparkle
  derived_sparkle=$(find "$PROJECT_ROOT/.derived-dmg" -path "*/artifacts/*/bin/generate_keys" -type f 2>/dev/null | head -1)
  if [[ -n "$derived_sparkle" ]]; then
    echo "$(dirname "$derived_sparkle")"
    return
  fi

  # Try SPM checkouts
  if [[ -f "$PROJECT_ROOT/.build/checkouts/Sparkle/bin/generate_keys" ]]; then
    echo "$PROJECT_ROOT/.build/checkouts/Sparkle/bin"
    return
  fi

  # Try homebrew
  local brew_sparkle="/opt/homebrew/Caskroom/sparkle"
  if [[ -d "$brew_sparkle" ]]; then
    local version
    version=$(ls -1 "$brew_sparkle" | sort -V | tail -1)
    if [[ -f "$brew_sparkle/$version/bin/generate_keys" ]]; then
      echo "$brew_sparkle/$version/bin"
      return
    fi
  fi

  echo ""
}

SPARKLE_BIN=$(find_sparkle_bin)

if [[ -z "$SPARKLE_BIN" ]]; then
  echo "Error: Sparkle binaries not found."
  echo ""
  echo "Options to install:"
  echo "  1. Build the DMG scheme first: bash scripts/xc.sh --dist=dmg build"
  echo "  2. Install via Homebrew: brew install --cask sparkle"
  echo "  3. Download from: https://github.com/sparkle-project/Sparkle/releases"
  echo ""
  exit 1
fi

echo "Using Sparkle binaries from: $SPARKLE_BIN"
echo ""

if [[ "${1:-}" == "export" ]]; then
  echo "Exporting private key for CI..."
  echo ""
  echo "This will export the private key from your Keychain to a file."
  echo "Store this securely and add to GitHub Secrets as SPARKLE_PRIVATE_KEY (base64 encoded)."
  echo ""

  EXPORT_PATH="$HOME/sparkle_private_key.txt"
  "$SPARKLE_BIN/generate_keys" -x "$EXPORT_PATH"

  echo ""
  echo "Private key exported to: $EXPORT_PATH"
  echo ""
  echo "To add to GitHub Secrets:"
  echo "  1. base64 -i $EXPORT_PATH | pbcopy"
  echo "  2. Go to: Settings > Secrets > Actions > New repository secret"
  echo "  3. Name: SPARKLE_PRIVATE_KEY"
  echo "  4. Value: (paste from clipboard)"
  echo ""
  echo "IMPORTANT: Delete $EXPORT_PATH after adding to GitHub Secrets!"
  echo ""
else
  echo "Generating new EdDSA key pair..."
  echo ""
  echo "The private key will be stored in your macOS Keychain."
  echo "The public key will be displayed below - add it to Info-DMG.plist as SUPublicEDKey."
  echo ""

  "$SPARKLE_BIN/generate_keys"

  echo ""
  echo "Next steps:"
  echo "  1. Copy the public key above"
  echo "  2. Edit Contextify/Info-DMG.plist"
  echo "  3. Replace REPLACE_WITH_PUBLIC_KEY with the public key"
  echo ""
  echo "To export the private key for CI, run:"
  echo "  ./scripts/sparkle-keygen.sh export"
  echo ""
fi
