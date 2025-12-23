#!/bin/bash
# ---
# title: Clean Install Reset for QA Testing
# description: Clears all Contextify and CLI state for fresh DMG/CLI install testing
# usage: ./scripts/qa/reset-for-clean-install.sh
# prerequisites: None (handles missing components gracefully)
# ---
#
# This script prepares the system for a clean install test by:
# 1. Quitting Claude Code
# 2. Uninstalling Homebrew contextify-query (if present)
# 3. Clearing Contextify app state (DB, prefs, CLI, bookmarks)
# 4. Clearing Claude Code plugin cache
# 5. Clearing user skills (total-recall and legacy locations)
# 6. Verifying clean state
#
# After running, follow these steps:
# 1. Open dist/Contextify.dmg and install to /Applications
# 2. Launch Contextify
# 3. Go to Settings > CLI > Install CLI
# 4. Quit and relaunch Claude Code
# 5. Type /total-recall to verify skill is active

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Contextify Clean Install Reset ==="
echo ""

# Step 1: Quit Claude Code
echo "1. Quitting Claude Code..."
pkill -9 "Claude Code" 2>/dev/null && echo "   Killed Claude Code" || echo "   Claude Code not running"

# Step 2: Uninstall Homebrew contextify-query (if present)
echo "2. Checking Homebrew installation..."
if command -v brew &>/dev/null && brew list contextify-query &>/dev/null; then
    echo "   Uninstalling Homebrew contextify-query..."
    brew uninstall contextify-query
    echo "   Homebrew package removed"

    # Clean up stale symlinks
    if [ -L /opt/homebrew/bin/contextify-query ]; then
        rm /opt/homebrew/bin/contextify-query
        echo "   Removed stale symlink from /opt/homebrew/bin/"
    fi
    if [ -L /usr/local/bin/contextify-query ]; then
        rm /usr/local/bin/contextify-query 2>/dev/null || true
        echo "   Removed stale symlink from /usr/local/bin/"
    fi
else
    echo "   No Homebrew installation found"
fi

# Also check for stale symlinks even if Homebrew package not installed
if [ -L /opt/homebrew/bin/contextify-query ] && [ ! -e /opt/homebrew/bin/contextify-query ]; then
    rm /opt/homebrew/bin/contextify-query
    echo "   Removed orphaned symlink from /opt/homebrew/bin/"
fi

# Step 3: Clear Contextify app state
echo "3. Clearing Contextify app state..."
cd "$REPO_ROOT"
./scripts/xc.sh reset-state

# Step 4: Clear Claude Code plugin cache for Contextify
echo "4. Clearing Claude Code plugin cache..."
if [ -d ~/.claude/plugins/cache/contextify ]; then
    rm -rf ~/.claude/plugins/cache/contextify/
    echo "   Removed ~/.claude/plugins/cache/contextify/"
else
    echo "   No plugin cache found (already clean)"
fi

# Step 5: Clear user skills (current and legacy locations)
echo "5. Clearing user skills..."
skills_cleared=0

if [ -d ~/.claude/skills/total-recall ]; then
    rm -rf ~/.claude/skills/total-recall/
    echo "   Removed ~/.claude/skills/total-recall/"
    skills_cleared=1
fi

if [ -d ~/.claude/skills/contextify-reinject ]; then
    rm -rf ~/.claude/skills/contextify-reinject/
    echo "   Removed old ~/.claude/skills/contextify-reinject/"
    skills_cleared=1
fi

if [ $skills_cleared -eq 0 ]; then
    echo "   No user skills found (already clean)"
fi

# Step 6: Clear ~/bin CLI shim if present
echo "6. Clearing ~/bin CLI shim..."
if [ -f ~/bin/contextify-query ]; then
    rm ~/bin/contextify-query
    echo "   Removed ~/bin/contextify-query"
else
    echo "   No ~/bin shim found"
fi

# Step 7: Verify clean state
echo ""
echo "=== Verification ==="

errors=0

echo -n "Homebrew package: "
if command -v brew &>/dev/null && brew list contextify-query &>/dev/null 2>&1; then
    echo "FAIL - still installed"
    errors=$((errors + 1))
else
    echo "CLEAN"
fi

echo -n "CLI in PATH: "
if command -v contextify-query &>/dev/null; then
    echo "FAIL - found at $(which contextify-query)"
    errors=$((errors + 1))
else
    echo "CLEAN"
fi

echo -n "Plugin cache: "
if ls ~/.claude/plugins/cache/ 2>/dev/null | grep -q contextify; then
    echo "FAIL - contextify still present"
    errors=$((errors + 1))
else
    echo "CLEAN"
fi

echo -n "User skills: "
if ls ~/.claude/skills/ 2>/dev/null | grep -qE "(total-recall|contextify)"; then
    echo "FAIL - skill still present"
    errors=$((errors + 1))
else
    echo "CLEAN"
fi

echo ""
if [ $errors -gt 0 ]; then
    echo "=== WARNING: $errors items not fully cleaned ==="
    echo "Review above and clean manually if needed."
else
    echo "=== Reset Complete ==="
fi

echo ""
echo "Next steps:"
echo "  1. Open dist/Contextify.dmg and install to /Applications"
echo "  2. Launch Contextify"
echo "  3. Go to Settings > CLI > Install CLI"
echo "  4. Quit and relaunch Claude Code"
echo "  5. Type /total-recall to verify skill is active"
