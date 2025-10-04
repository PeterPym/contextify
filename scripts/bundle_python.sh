#!/bin/bash
# Bundle Python dependencies for inclusion in macOS app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUNDLE_DIR="$PROJECT_ROOT/Resources/Python"

echo "🐍 Bundling Python dependencies for Contextify..."
echo ""
echo "Bundle directory: $BUNDLE_DIR"
echo ""

# Clean previous bundle
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/lib/python/site-packages"

# Install iterm2 module into bundle directory
echo "📦 Installing iterm2 module..."
pip3 install --target "$BUNDLE_DIR/lib/python/site-packages" iterm2

echo ""
echo "✅ Python dependencies bundled successfully!"
echo ""
echo "Contents:"
ls -lh "$BUNDLE_DIR/lib/python/site-packages/"
echo ""
echo "Size: $(du -sh "$BUNDLE_DIR" | cut -f1)"
