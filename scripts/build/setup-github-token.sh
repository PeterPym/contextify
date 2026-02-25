#!/usr/bin/env bash
# Setup GitHub Personal Access Token for CI automation
#
# Usage: ./scripts/build/setup-github-token.sh

set -euo pipefail

echo ""
echo "🔑 GitHub Token Setup"
echo "===================="
echo ""
echo "This script will help you set up a GitHub Personal Access Token"
echo "for triggering CI builds without gh CLI."
echo ""

# Check if token already exists
TOKEN_FILE="$HOME/.config/contextify/github-token"
if [[ -f "$TOKEN_FILE" ]]; then
  echo "⚠️  Token file already exists: $TOKEN_FILE"
  read -p "Do you want to replace it? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "To create a Personal Access Token:"
echo "1. Go to: https://github.com/settings/tokens/new"
echo "2. Give it a descriptive name (e.g., 'Contextify CI')"
echo "3. Set expiration (recommend: 90 days)"
echo "4. Select scopes:"
echo "   ✓ repo (all)"
echo "   ✓ workflow"
echo "5. Click 'Generate token'"
echo "6. Copy the token (ghp_...)"
echo ""
echo "Press Enter to open the token creation page in your browser..."
read -r

if command -v open &> /dev/null; then
  open "https://github.com/settings/tokens/new?scopes=repo,workflow&description=Contextify%20CI"
elif command -v xdg-open &> /dev/null; then
  xdg-open "https://github.com/settings/tokens/new?scopes=repo,workflow&description=Contextify%20CI"
else
  echo "Please open this URL manually:"
  echo "https://github.com/settings/tokens/new?scopes=repo,workflow&description=Contextify%20CI"
fi

echo ""
read -p "Paste your token (ghp_...): " -s TOKEN
echo ""

if [[ -z "$TOKEN" ]]; then
  echo "❌ No token provided."
  exit 1
fi

if [[ ! "$TOKEN" =~ ^(ghp_|github_pat_) ]]; then
  echo "⚠️  Warning: Token doesn't look like a valid GitHub token"
  echo "   Expected format: ghp_... or github_pat_..."
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Create directory if it doesn't exist
mkdir -p "$(dirname "$TOKEN_FILE")"

# Save token with restrictive permissions
echo "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

echo "✅ Token saved to: $TOKEN_FILE"
echo ""
echo "🔒 File permissions: 600 (owner read/write only)"
echo ""
echo "To use the token with trigger-ci-build.sh:"
echo "  export GITHUB_TOKEN=\$(cat $TOKEN_FILE)"
echo "  ./scripts/build/trigger-ci-build.sh Debug"
echo ""
echo "Or add to your shell profile (~/.bashrc or ~/.zshrc):"
echo "  export GITHUB_TOKEN=\$(cat $TOKEN_FILE)"
echo ""
echo "✅ Setup complete!"
