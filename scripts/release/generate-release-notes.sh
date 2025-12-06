#!/bin/bash
#
# generate-release-notes.sh - LLM-powered release notes (app-only)
#
# Generates user-focused release notes by analyzing git history with an LLM.
# Only includes changes to app code paths (configured in releases/config/app-paths.txt).
#
# Usage:
#   ./scripts/release/generate-release-notes.sh <version> [OPTIONS]
#
# Options:
#   --from <ref>       Base ref (default: previous tag)
#   --include-diff     Include full diff in LLM context
#   --allow-empty      Don't fail if no app changes
#   --dry-run          Show what would be generated
#
# Examples:
#   ./scripts/release/generate-release-notes.sh 1.0.1
#   ./scripts/release/generate-release-notes.sh 1.0.1 --from v1.0.0
#   ./scripts/release/generate-release-notes.sh 1.0.1 --include-diff
#
# Output:
#   releases/vX.Y.Z/assets/changelog.llm.md - Raw LLM draft
#
# Next steps after running:
#   1. Review and edit the LLM draft
#   2. Save final version as changelog.final.md
#   3. Update CHANGELOG.md with the final content
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo -e "${RED}Error:${NC} Version required"
    echo "Usage: $0 <version> [--from <ref>] [--include-diff] [--allow-empty] [--dry-run]"
    exit 1
fi
shift

FROM_REF=""
INCLUDE_DIFF=false
ALLOW_EMPTY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --from) FROM_REF="$2"; shift 2 ;;
        --include-diff) INCLUDE_DIFF=true; shift ;;
        --allow-empty) ALLOW_EMPTY=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            head -35 "$0" | tail -30 | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *) echo -e "${RED}Error:${NC} Unknown option: $1"; exit 1 ;;
    esac
done

# Load app paths
APP_PATHS_FILE="$REPO_ROOT/releases/config/app-paths.txt"
APP_PATHS=()

if [[ -f "$APP_PATHS_FILE" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        APP_PATHS+=("$line")
    done < "$APP_PATHS_FILE"
else
    echo -e "${RED}Error:${NC} App paths config not found: $APP_PATHS_FILE"
    exit 1
fi

if [[ ${#APP_PATHS[@]} -eq 0 ]]; then
    echo -e "${RED}Error:${NC} No app paths configured in $APP_PATHS_FILE"
    exit 1
fi

echo -e "${BLUE}App paths:${NC} ${APP_PATHS[*]}"

# Auto-detect from ref if not specified
if [[ -z "$FROM_REF" ]]; then
    FROM_REF=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [[ -z "$FROM_REF" ]]; then
        echo -e "${RED}Error:${NC} No previous tag found. Use --from to specify base ref."
        exit 1
    fi
fi

echo -e "${BLUE}Generating release notes for ${GREEN}$VERSION${NC} (from ${YELLOW}$FROM_REF${NC})..."

# Gather app-only context
cd "$REPO_ROOT"
COMMITS=$(git log "$FROM_REF"..HEAD --oneline --no-merges -- "${APP_PATHS[@]}" 2>/dev/null || echo "")
DIFF_STAT=$(git diff "$FROM_REF"..HEAD --stat -- "${APP_PATHS[@]}" 2>/dev/null || echo "")

# Check for empty
if [[ -z "$COMMITS" ]]; then
    echo ""
    echo -e "${YELLOW}No app changes between $FROM_REF and HEAD.${NC}"
    echo "(Non-app paths like website/docs are excluded from changelog.)"
    if [[ "$ALLOW_EMPTY" == "true" ]]; then
        exit 0
    else
        echo ""
        echo "Use --allow-empty to suppress this error, or check your --from ref."
        exit 1
    fi
fi

# Count commits
COMMIT_COUNT=$(echo "$COMMITS" | wc -l | tr -d ' ')
echo -e "${GREEN}Found $COMMIT_COUNT app commits${NC}"

# Optional full diff
DIFF_FULL=""
if [[ "$INCLUDE_DIFF" == "true" ]]; then
    DIFF_FULL=$(git diff "$FROM_REF"..HEAD -- "${APP_PATHS[@]}" 2>/dev/null || echo "")
    # Truncate if too large (>100KB)
    if [[ ${#DIFF_FULL} -gt 100000 ]]; then
        DIFF_FULL="${DIFF_FULL:0:100000}

[... truncated, full diff too large ...]"
        echo -e "${YELLOW}Note: Full diff truncated (>100KB)${NC}"
    fi
fi

# Create prompt
PROMPT="Generate release notes for Contextify version $VERSION.

## Context

Contextify is a macOS menu bar app that monitors Claude Code and Codex CLI conversations, providing real-time LLM-powered summaries in a timeline view.

**Important:** These commits and diffs are already filtered to app-only paths. Website, documentation, and marketing changes exist but are out of scope for this changelog and must not be mentioned.

## Commits since $FROM_REF

$COMMITS

## Files changed

$DIFF_STAT"

# Add full diff if included
if [[ -n "$DIFF_FULL" ]]; then
    PROMPT="$PROMPT

## Full diff

$DIFF_FULL"
fi

# Add instructions
PROMPT="$PROMPT

## Instructions

1. Generate app-focused release notes following Keep a Changelog conventions
2. Categories: Added, Changed, Fixed, Removed (only include categories with content)
3. Focus on user-visible behavior and benefits
4. Be concise - one line per change, grouped logically
5. Skip internal refactoring unless it affects users
6. Do NOT mention website, docs, or marketing changes

## Output format

Return ONLY the Markdown content for this version's entry:

### Added
- Feature description

### Fixed
- Bug fix description

Do not include the version header - I will add that."

# Create output directory
ASSETS_DIR="$REPO_ROOT/releases/v$VERSION/assets"
mkdir -p "$ASSETS_DIR"

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo -e "${BLUE}=== DRY RUN ===${NC}"
    echo "Would generate release notes with this context:"
    echo ""
    echo "  Commits: $COMMIT_COUNT"
    echo "  Files changed: $(echo "$DIFF_STAT" | tail -1 | tr -d ' ')"
    echo "  Include diff: $INCLUDE_DIFF"
    echo "  Output: $ASSETS_DIR/changelog.llm.md"
    echo ""
    echo "Prompt preview (first 500 chars):"
    echo "---"
    echo "${PROMPT:0:500}..."
    exit 0
fi

# Generate via Claude CLI
if command -v claude &> /dev/null; then
    echo ""
    echo -e "${BLUE}Generating via Claude CLI...${NC}"

    # Save prompt for reference
    echo "$PROMPT" > "$ASSETS_DIR/prompt.txt"

    RESULT=$(echo "$PROMPT" | claude --print 2>&1)

    # Save raw output
    echo "$RESULT" > "$ASSETS_DIR/changelog.llm.md"
    echo ""
    echo -e "${GREEN}Saved to:${NC} $ASSETS_DIR/changelog.llm.md"
    echo ""
    echo -e "${BLUE}=== Generated Release Notes ===${NC}"
    echo ""
    cat "$ASSETS_DIR/changelog.llm.md"
    echo ""
    echo -e "${BLUE}=== Next Steps ===${NC}"
    echo "1. Review and edit: $ASSETS_DIR/changelog.llm.md"
    echo "2. Save final version as: $ASSETS_DIR/changelog.final.md"
    echo "3. Update CHANGELOG.md with the final content"
    echo "4. Generate HTML for Sparkle: website/release-notes/$VERSION.html"
    echo "5. Update App Store release notes: appstore-metadata/fastlane/metadata/en-US/release_notes.txt"
else
    # Save prompt for manual use
    echo "$PROMPT" > "$ASSETS_DIR/prompt.txt"
    echo ""
    echo -e "${YELLOW}Claude CLI not found.${NC}"
    echo "Prompt saved to: $ASSETS_DIR/prompt.txt"
    echo ""
    echo "To generate release notes:"
    echo "1. Copy the prompt to your preferred LLM"
    echo "2. Save output to: $ASSETS_DIR/changelog.llm.md"
    echo ""
    echo "Or install Claude CLI: npm install -g @anthropic-ai/claude-cli"
fi
