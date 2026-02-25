#!/usr/bin/env bash
# CI Signing Test Script
# Tests the GitHub Actions workflows to verify code signing works correctly
#
# Usage: ./scripts/release/test-ci-signing.sh

set -euo pipefail

REPO="banagale/contextify"
WORKFLOW="on-demand-build.yml"

echo ""
echo "🔍 CI Signing Test Script"
echo "=========================="
echo ""

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) not found."
    echo ""
    echo "Install it with:"
    echo "  macOS: brew install gh"
    echo "  Linux: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
    echo ""
    exit 1
fi

# Check authentication
if ! gh auth status &> /dev/null; then
    echo "❌ Not authenticated with GitHub."
    echo ""
    echo "Run: gh auth login"
    echo ""
    exit 1
fi

echo "✅ GitHub CLI authenticated"
echo ""

# Show current workflow status
echo "📊 Recent workflow runs:"
echo ""
gh run list --workflow="$WORKFLOW" --limit 5 --json conclusion,createdAt,displayTitle,status,url \
    --template '{{range .}}{{printf "%-12s" .status}} {{.displayTitle}} ({{timeago .createdAt}})
{{.url}}
{{end}}'

echo ""
echo "───────────────────────────────────────────────────────────"
echo ""

# Offer to trigger new build
read -p "🚀 Trigger a new Debug build? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping build trigger."
    echo ""
    echo "To manually trigger:"
    echo "  gh workflow run $WORKFLOW -f configuration=Debug"
    echo ""
    exit 0
fi

# Trigger the workflow
echo ""
echo "Triggering workflow..."
if gh workflow run "$WORKFLOW" -f configuration=Debug -f skip_launch=true; then
    echo "✅ Workflow triggered successfully!"
    echo ""

    # Wait a moment for the run to register
    sleep 3

    echo "📺 Starting live monitor..."
    echo ""

    # Watch the build
    gh run watch

    # After completion, show the result
    echo ""
    echo "───────────────────────────────────────────────────────────"
    echo ""
    echo "📋 Build completed. Checking for signing issues..."
    echo ""

    # Get the most recent run
    RUN_ID=$(gh run list --workflow="$WORKFLOW" --limit 1 --json databaseId --jq '.[0].databaseId')

    # Check logs for signing-related errors
    echo "Searching for signing/certificate errors in logs..."
    if gh run view "$RUN_ID" --log | grep -iE "sign|certificate|identity" > /tmp/signing-output.txt; then
        echo ""
        echo "🔍 Found signing-related log entries:"
        echo ""
        cat /tmp/signing-output.txt | head -20
        echo ""
        if [[ $(wc -l < /tmp/signing-output.txt) -gt 20 ]]; then
            echo "... ($(wc -l < /tmp/signing-output.txt) total lines, see /tmp/signing-output.txt for full output)"
        fi
    else
        echo "✅ No signing errors found in logs"
    fi

    echo ""
    echo "───────────────────────────────────────────────────────────"
    echo ""
    echo "📖 View full logs:"
    echo "   gh run view $RUN_ID --log"
    echo ""
    echo "🌐 View in browser:"
    gh run view "$RUN_ID" --web
else
    echo "❌ Failed to trigger workflow"
    exit 1
fi
