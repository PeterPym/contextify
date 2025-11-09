#!/usr/bin/env bash
# Trigger GitHub Actions workflow from any environment (including Linux without gh CLI)
#
# Usage:
#   ./scripts/trigger-ci-build.sh [Debug|Release] [branch]
#
# Examples:
#   ./scripts/trigger-ci-build.sh Debug
#   ./scripts/trigger-ci-build.sh Release main
#   GITHUB_TOKEN=ghp_xxx ./scripts/trigger-ci-build.sh Debug

set -euo pipefail

REPO_OWNER="banagale"
REPO_NAME="contextify"
WORKFLOW_FILE="on-demand-build.yml"

# Configuration
CONFIG="${1:-Debug}"
# Default to current branch if available, otherwise main
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
BRANCH="${2:-${CURRENT_BRANCH:-main}}"

# GitHub token from environment or keyring
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

echo ""
echo "🚀 Trigger GitHub Actions Build"
echo "================================"
echo ""
echo "Repository: $REPO_OWNER/$REPO_NAME"
echo "Workflow:   $WORKFLOW_FILE"
echo "Branch:     $BRANCH"
echo "Config:     $CONFIG"
echo ""

# If no token in environment, try to get it from various sources
if [[ -z "$GITHUB_TOKEN" ]]; then
  # Try token file (created by setup-github-token.sh)
  TOKEN_FILE="$HOME/.config/contextify/github-token"
  if [[ -f "$TOKEN_FILE" ]]; then
    echo "📋 Using token from $TOKEN_FILE..."
    GITHUB_TOKEN=$(cat "$TOKEN_FILE")
  fi

  # Try gh CLI
  if [[ -z "$GITHUB_TOKEN" ]] && command -v gh &> /dev/null && gh auth status &> /dev/null; then
    echo "📋 Using token from gh CLI..."
    GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
  fi

  # Try macOS keychain (if available)
  if [[ -z "$GITHUB_TOKEN" ]] && command -v security &> /dev/null; then
    echo "🔑 Attempting to read token from macOS keychain..."
    GITHUB_TOKEN=$(security find-internet-password -s github.com -a "$REPO_OWNER" -w 2>/dev/null || echo "")
  fi
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "❌ No GitHub token found."
  echo ""
  echo "Options:"
  echo ""
  echo "1. Set GITHUB_TOKEN environment variable:"
  echo "   export GITHUB_TOKEN=ghp_your_token_here"
  echo "   ./scripts/trigger-ci-build.sh"
  echo ""
  echo "2. Create a Personal Access Token:"
  echo "   https://github.com/settings/tokens/new"
  echo "   Required scopes: repo, workflow"
  echo ""
  echo "3. Authenticate with gh CLI:"
  echo "   gh auth login"
  echo ""
  exit 1
fi

# Validate token format
if [[ ! "$GITHUB_TOKEN" =~ ^(ghp_|github_pat_) ]]; then
  echo "⚠️  Warning: Token doesn't look like a valid GitHub token"
  echo "   Expected format: ghp_... or github_pat_..."
  echo ""
fi

# Trigger workflow via GitHub API
echo "🔄 Triggering workflow..."
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/workflows/$WORKFLOW_FILE/dispatches" \
  -d "{\"ref\":\"$BRANCH\",\"inputs\":{\"configuration\":\"$CONFIG\",\"skip_launch\":\"true\"}}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | head -n -1 2>/dev/null || echo "$RESPONSE" | sed '$d')

echo "HTTP Status: $HTTP_CODE"

if [[ "$HTTP_CODE" == "204" ]]; then
  echo "✅ Workflow triggered successfully!"
  echo ""
  echo "🔗 View workflow runs:"
  echo "   https://github.com/$REPO_OWNER/$REPO_NAME/actions/workflows/$WORKFLOW_FILE"
  echo ""

  # Wait a moment for the run to register
  echo "⏳ Waiting for run to register..."
  sleep 5

  # Try to get the run ID
  echo ""
  echo "📊 Fetching latest run..."
  RUNS=$(curl -s \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/workflows/$WORKFLOW_FILE/runs?per_page=1&branch=$BRANCH")

  RUN_ID=$(echo "$RUNS" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')
  RUN_URL=$(echo "$RUNS" | grep -o '"html_url": "[^"]*"' | head -1 | cut -d'"' -f4)

  if [[ -n "$RUN_ID" && -n "$RUN_URL" ]]; then
    echo "✅ Run ID: $RUN_ID"
    echo "🌐 $RUN_URL"
    echo ""

    # Poll for completion
    echo "⏳ Monitoring build progress (Ctrl+C to stop watching)..."
    echo ""

    POLL_INTERVAL=10
    ELAPSED=0
    MAX_WAIT=1800  # 30 minutes max

    while [[ $ELAPSED -lt $MAX_WAIT ]]; do
      sleep $POLL_INTERVAL
      ELAPSED=$((ELAPSED + POLL_INTERVAL))

      # Get run status
      RUN_STATUS=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runs/$RUN_ID")

      STATUS=$(echo "$RUN_STATUS" | grep -o '"status": "[^"]*"' | head -1 | cut -d'"' -f4)
      CONCLUSION=$(echo "$RUN_STATUS" | grep -o '"conclusion": "[^"]*"' | head -1 | cut -d'"' -f4)

      if [[ "$STATUS" == "completed" ]]; then
        echo ""
        echo "═══════════════════════════════════════"
        if [[ "$CONCLUSION" == "success" ]]; then
          echo "✅ Build SUCCEEDED in ${ELAPSED}s"
        elif [[ "$CONCLUSION" == "failure" ]]; then
          echo "❌ Build FAILED in ${ELAPSED}s"
        else
          echo "⚠️  Build completed with status: $CONCLUSION"
        fi
        echo "═══════════════════════════════════════"
        echo ""
        echo "🔗 View results: $RUN_URL"
        echo ""

        # Exit with appropriate code
        if [[ "$CONCLUSION" == "success" ]]; then
          exit 0
        else
          exit 1
        fi
      fi

      # Show progress
      printf "\r⏳ Status: %-15s | Elapsed: %3ds" "$STATUS" "$ELAPSED"
    done

    # Timeout
    echo ""
    echo ""
    echo "⏰ Timeout after ${MAX_WAIT}s - build still running"
    echo "🔗 View status: $RUN_URL"
    exit 2
  else
    echo "⚠️  Could not fetch run details. Check the URL above."
    exit 1
  fi
else
  echo "❌ Failed to trigger workflow"
  echo ""
  echo "Response:"
  echo "$BODY" | head -20
  echo ""

  # Common errors
  if [[ "$HTTP_CODE" == "401" ]]; then
    echo "💡 Authentication failed. Check your token:"
    echo "   - Is it expired?"
    echo "   - Does it have 'repo' and 'workflow' scopes?"
    echo "   - Create new: https://github.com/settings/tokens/new"
  elif [[ "$HTTP_CODE" == "404" ]]; then
    echo "💡 Workflow not found. Check:"
    echo "   - Repository: $REPO_OWNER/$REPO_NAME"
    echo "   - Workflow file: $WORKFLOW_FILE"
    echo "   - Branch: $BRANCH"
  elif [[ "$HTTP_CODE" == "422" ]]; then
    echo "💡 Invalid request. Check:"
    echo "   - Branch '$BRANCH' exists"
    echo "   - Workflow inputs are correct"
  fi

  exit 1
fi
