#!/bin/bash
# Cross-Platform Change Detection Script
#
# Detects when changes require a Linux CLI release.
# Used for release automation and pre-commit checks.
#
# Exit codes:
#   0 = Changes detected that affect Linux CLI
#   1 = No relevant changes (Linux release not needed)
#   2 = Error
#
# Usage:
#   ./scripts/cross-platform-change-detect.sh [BASE_REF] [HEAD_REF]
#
# Examples:
#   ./scripts/cross-platform-change-detect.sh          # Compare HEAD to main
#   ./scripts/cross-platform-change-detect.sh v1.0.0   # Compare HEAD to tag
#   ./scripts/cross-platform-change-detect.sh abc123 def456  # Compare commits

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Determine comparison range
BASE_REF="${1:-$(git -C "$PROJECT_ROOT" merge-base origin/main HEAD 2>/dev/null || echo "origin/main")}"
HEAD_REF="${2:-HEAD}"

# Files that affect the Linux CLI build
# These paths mirror the linuxSources list in Package.swift
LINUX_RELEVANT_PATHS=(
  # Platform abstractions
  "app/Sources/ContextifyCore/Platform/"

  # Database layer
  "app/Sources/ContextifyCore/Database/DatabaseSchema.swift"
  "app/Sources/ContextifyCore/Database/KeyGeneration.swift"
  "app/Sources/ContextifyCore/Database/Models.swift"
  "app/Sources/ContextifyCore/Database/PathNormalizer.swift"

  # Discovery
  "app/Sources/ContextifyCore/Discovery/"

  # Core types
  "app/Sources/ContextifyCore/Clock.swift"
  "app/Sources/ContextifyCore/ContextifyConfig.swift"
  "app/Sources/ContextifyCore/LoggingConfig.swift"
  "app/Sources/ContextifyCore/ProjectIdentity.swift"
  "app/Sources/ContextifyCore/Projects/ProjectModels.swift"
  "app/Sources/ContextifyCore/Projects/TranscriptAccessProvider.swift"
  "app/Sources/ContextifyCore/Projects/TranscriptProviderID.swift"

  # CLI sources
  "Sources/ContextifyIngestionCLI/"

  # Package configuration
  "Package.swift"
  "Package.resolved"

  # CI workflow
  ".github/workflows/linux-build.yml"

  # Docker build scripts
  "scripts/docker-linux-build.sh"
)

# Get list of changed files
CHANGED_FILES=$(git -C "$PROJECT_ROOT" diff --name-only "$BASE_REF" "$HEAD_REF" 2>/dev/null)

if [ -z "$CHANGED_FILES" ]; then
  echo "No changes between $BASE_REF and $HEAD_REF"
  exit 1
fi

# Check if any changed files match Linux-relevant paths
LINUX_CHANGES=""
for path in "${LINUX_RELEVANT_PATHS[@]}"; do
  # Use grep to check if any changed files start with this path
  MATCHES=$(echo "$CHANGED_FILES" | grep -E "^${path}" 2>/dev/null || true)
  if [ -n "$MATCHES" ]; then
    LINUX_CHANGES="${LINUX_CHANGES}${MATCHES}"$'\n'
  fi
done

if [ -z "$LINUX_CHANGES" ]; then
  echo "No Linux-relevant changes between $BASE_REF and $HEAD_REF"
  exit 1
fi

# Remove duplicate blank lines and trailing whitespace
LINUX_CHANGES=$(echo "$LINUX_CHANGES" | sed '/^$/d' | sort -u)

echo "Linux CLI changes detected ($BASE_REF..$HEAD_REF):"
echo "$LINUX_CHANGES"
echo ""
echo "Count: $(echo "$LINUX_CHANGES" | wc -l | tr -d ' ') files"
exit 0
