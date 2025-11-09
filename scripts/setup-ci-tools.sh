#!/bin/bash
# Setup CI tools for Claude Code remote environments
# This hook runs automatically when starting a Claude Code web session

set -euo pipefail

# Only run in remote environments (Claude Code on the web)
if [ "$CLAUDE_CODE_REMOTE" != "true" ]; then
  echo "Local environment detected - skipping CI tool setup"
  exit 0
fi

echo "🌐 Setting up CI tools for Claude Code remote environment..."

# Check if curl is available (should be in universal image)
if ! command -v curl &> /dev/null; then
  echo "❌ curl not found - cannot proceed"
  exit 1
fi

# GitHub token should be set as environment variable in Claude Code settings
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "⚠️  GITHUB_TOKEN not set in environment"
  echo "   To trigger CI builds, add GITHUB_TOKEN to your environment settings:"
  echo "   1. Click environment selector"
  echo "   2. Click settings (gear icon)"
  echo "   3. Add environment variable: GITHUB_TOKEN=ghp_your_token_here"
  echo ""
  echo "   You can create a token at: https://github.com/settings/tokens/new"
  echo "   Required scopes: repo, workflow"
  echo ""
  echo "Continuing without CI trigger capability..."
else
  echo "✅ GITHUB_TOKEN found in environment"

  # Validate token format
  if [[ ! "$GITHUB_TOKEN" =~ ^(ghp_|github_pat_) ]]; then
    echo "⚠️  Warning: Token format looks unusual (expected ghp_* or github_pat_*)"
  fi
fi

# Check if jq is available for JSON parsing (useful for API responses)
if command -v jq &> /dev/null; then
  echo "✅ jq available for JSON parsing"
else
  echo "ℹ️  jq not available (optional, but helpful for parsing API responses)"
fi

# Make CI trigger scripts executable
chmod +x "$CLAUDE_PROJECT_DIR"/scripts/trigger-ci-build.sh 2>/dev/null || true
chmod +x "$CLAUDE_PROJECT_DIR"/scripts/setup-github-token.sh 2>/dev/null || true

echo "✅ CI tools setup complete"
echo ""
echo "💡 To trigger a CI build from this remote session:"
echo "   ./scripts/trigger-ci-build.sh Debug"
echo "   ./scripts/trigger-ci-build.sh Release main"
echo ""

exit 0
