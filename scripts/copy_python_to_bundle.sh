#!/bin/bash
# Copy bundled Python dependencies into app bundle
# Called as an Xcode build phase

set -e

if [ -z "$BUILT_PRODUCTS_DIR" ] || [ -z "$CONTENTS_FOLDER_PATH" ]; then
    echo "⚠️  Warning: Not running in Xcode build environment"
    echo "   This script should be run as an Xcode build phase"
    exit 0
fi

BUNDLE_RESOURCES="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources"
SOURCE_PYTHON="$PROJECT_DIR/Resources/Python"

echo "📦 Copying bundled Python dependencies to app bundle..."
echo "   Source: $SOURCE_PYTHON"
echo "   Destination: $BUNDLE_RESOURCES/Python"

# Create destination
mkdir -p "$BUNDLE_RESOURCES"

# Copy Python packages
if [ -d "$SOURCE_PYTHON" ]; then
    rsync -a --delete "$SOURCE_PYTHON/" "$BUNDLE_RESOURCES/Python/"
    echo "✅ Copied Python dependencies ($(du -sh "$BUNDLE_RESOURCES/Python" | cut -f1))"
else
    echo "❌ ERROR: Source Python directory not found at $SOURCE_PYTHON"
    echo "   Run: bash scripts/bundle_python.sh"
    exit 1
fi

# Copy Python script
if [ -f "$PROJECT_DIR/scripts/iterm2_reader.py" ]; then
    cp "$PROJECT_DIR/scripts/iterm2_reader.py" "$BUNDLE_RESOURCES/"
    chmod +x "$BUNDLE_RESOURCES/iterm2_reader.py"
    echo "✅ Copied iterm2_reader.py"
else
    echo "❌ ERROR: iterm2_reader.py not found"
    exit 1
fi

echo "✅ Python bundling complete"
