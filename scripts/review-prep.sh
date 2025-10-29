#!/bin/bash
#
# review-prep.sh - Generate comprehensive review package for git commit ranges
#
# Usage:
#   ./scripts/review-prep.sh              # main..HEAD
#   ./scripts/review-prep.sh abc123       # abc123..HEAD
#   ./scripts/review-prep.sh abc123 def456  # abc123..def456
#

set -e

# Show help
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  cat << 'EOF'
review-prep.sh - Generate comprehensive review package for git commit ranges

USAGE:
  ./scripts/review-prep.sh [BASE] [HEAD]

EXAMPLES:
  ./scripts/review-prep.sh              # Compare main..HEAD
  ./scripts/review-prep.sh abc123       # Compare abc123..HEAD
  ./scripts/review-prep.sh abc123 def456  # Compare abc123..def456
  ./scripts/review-prep.sh main feature/branch  # Compare main..feature/branch

OUTPUT:
  Creates a markdown file in /tmp/ with:
  - Commit summary and stats
  - Full file contents (after changes)
  - Detailed diff of all changes
  - Ready for LLM code review

OPTIONS:
  -h, --help    Show this help message

EOF
  exit 0
fi

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
if [ -z "$1" ]; then
  # No arguments - use main..HEAD
  BASE="main"
  HEAD_REF="HEAD"
  RANGE="main..HEAD"
  RANGE_STAT="main...HEAD"
elif [ -z "$2" ]; then
  # One argument - use it as base
  BASE="$1"
  HEAD_REF="HEAD"
  RANGE="$1..HEAD"
  RANGE_STAT="$1...HEAD"
else
  # Two arguments - use as range
  BASE="$1"
  HEAD_REF="$2"
  RANGE="$1..$2"
  RANGE_STAT="$1...$2"
fi

# Check if base exists, fallback to master if main doesn't exist
if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  if [ "$BASE" = "main" ] && git rev-parse --verify master >/dev/null 2>&1; then
    BASE="master"
    RANGE="master..HEAD"
    RANGE_STAT="master...HEAD"
    echo -e "${YELLOW}Note: 'main' not found, using 'master' instead${NC}"
  else
    echo "Error: Base ref '$BASE' not found"
    exit 1
  fi
fi

# Verify HEAD_REF exists
if ! git rev-parse --verify "$HEAD_REF" >/dev/null 2>&1; then
  echo "Error: Head ref '$HEAD_REF' not found"
  exit 1
fi

# Generate timestamp for filename
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT="/tmp/review-${BASE//\//-}-to-${HEAD_REF//\//-}-${TIMESTAMP}.md"

# Get current branch name
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")

echo -e "${BLUE}Generating review package...${NC}"
echo -e "  Range: ${GREEN}$RANGE${NC}"
echo -e "  Output: ${GREEN}$OUTPUT${NC}"
echo ""

# Generate the review package
{
  echo "# Code Review Package"
  echo ""
  echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
  echo "**Branch:** $CURRENT_BRANCH"
  echo "**Range:** \`$RANGE\`"
  echo "**Repository:** $(basename "$(git rev-parse --show-toplevel)")"
  echo ""

  # Summary stats
  echo "## Summary"
  echo ""

  # Commit count
  COMMIT_COUNT=$(git rev-list --count "$RANGE" 2>/dev/null || echo "0")
  echo "**Commits:** $COMMIT_COUNT"

  # File stats
  FILES_CHANGED=$(git diff "$RANGE_STAT" --numstat 2>/dev/null | wc -l | tr -d ' ')
  INSERTIONS=$(git diff "$RANGE_STAT" --numstat 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
  DELETIONS=$(git diff "$RANGE_STAT" --numstat 2>/dev/null | awk '{sum+=$2} END {print sum}' || echo "0")

  echo "**Files Changed:** $FILES_CHANGED"
  echo "**Insertions:** +$INSERTIONS"
  echo "**Deletions:** -$DELETIONS"
  echo ""

  echo "### Commits"
  echo ""
  git log "$RANGE" --reverse --format="- \`%h\` %s (%an, %ar)" 2>/dev/null || echo "No commits found"
  echo ""

  echo "### Files Changed"
  echo ""
  echo '```'
  git diff "$RANGE_STAT" --stat 2>/dev/null || echo "No changes found"
  echo '```'
  echo ""

  # Get list of changed files
  CHANGED_FILES=$(git diff "$RANGE_STAT" --name-only 2>/dev/null)

  if [ -n "$CHANGED_FILES" ]; then
    echo "---"
    echo ""
    echo "## Changed Files (Full Content - After Changes)"
    echo ""
    echo "These files show the **current state** after all changes in the range."
    echo ""
    echo "> **Note:** This includes complete file contents for context. The diff section below shows the exact changes."
    echo ""

    FILE_COUNT=0
    while IFS= read -r file; do
      if [ -f "$file" ]; then
        ((FILE_COUNT++))
        echo ""
        echo "### [$FILE_COUNT] \`$file\`"
        echo ""

        # Detect language for syntax highlighting
        EXT="${file##*.}"
        case "$EXT" in
          swift) LANG="swift" ;;
          py) LANG="python" ;;
          js) LANG="javascript" ;;
          ts) LANG="typescript" ;;
          tsx) LANG="typescript" ;;
          jsx) LANG="javascript" ;;
          md) LANG="markdown" ;;
          json) LANG="json" ;;
          yml|yaml) LANG="yaml" ;;
          sh) LANG="bash" ;;
          rb) LANG="ruby" ;;
          go) LANG="go" ;;
          rs) LANG="rust" ;;
          c|h) LANG="c" ;;
          cpp|hpp|cc) LANG="cpp" ;;
          java) LANG="java" ;;
          sql) LANG="sql" ;;
          *) LANG="" ;;
        esac

        # Add file metadata
        LINE_COUNT=$(wc -l < "$file" | tr -d ' ')
        echo "<details>"
        echo "<summary>File info: $LINE_COUNT lines</summary>"
        echo ""
        echo "**Path:** \`$file\`  "
        echo "**Lines:** $LINE_COUNT  "
        echo "**Type:** ${LANG:-text}"
        echo ""
        echo "</details>"
        echo ""

        echo "\`\`\`${LANG}"
        cat "$file"
        echo '```'
        echo ""
      else
        echo ""
        echo "### \`$file\` *(deleted)*"
        echo ""
        echo "This file was deleted in this changeset."
        echo ""
      fi
    done <<< "$CHANGED_FILES"

    echo ""
    echo "---"
    echo ""
    echo "_Total files with content: $FILE_COUNT_"
    echo ""
  fi

  echo "---"
  echo ""
  echo "## Detailed Diff"
  echo ""
  echo "This shows the exact changes made in the commit range."
  echo ""
  echo '```diff'
  git diff "$RANGE_STAT" 2>/dev/null || echo "No diff available"
  echo '```'
  echo ""

  echo "---"
  echo ""
  echo "## Context for LLM Review"
  echo ""
  echo "> **Instructions for LLM reviewer:**"
  echo "> - Review the complete files above for full context"
  echo "> - Focus on the diff section for specific changes"
  echo "> - Consider architectural implications, not just code correctness"
  echo "> - Look for: patterns, conventions, error handling, integration issues"
  echo ""

} > "$OUTPUT"

# Print success message
echo -e "${GREEN}✅ Review package generated successfully!${NC}"
echo ""
echo -e "${BLUE}📊 Package Stats:${NC}"
LINES=$(wc -l < "$OUTPUT" | tr -d ' ')
SIZE=$(du -h "$OUTPUT" | awk '{print $1}')
echo "   Lines: $LINES"
echo "   Size: $SIZE"
echo "   Location: $OUTPUT"
echo ""
echo -e "${BLUE}📋 Quick Actions:${NC}"
echo "   View: cat \"$OUTPUT\""
echo "   Edit: \$EDITOR \"$OUTPUT\""
if command -v pbcopy >/dev/null 2>&1; then
  echo "   Copy (macOS): cat \"$OUTPUT\" | pbcopy"
fi
if command -v xclip >/dev/null 2>&1; then
  echo "   Copy (Linux): cat \"$OUTPUT\" | xclip -selection clipboard"
fi
echo ""
echo -e "${BLUE}🤖 For LLM Review:${NC}"
echo "   \"Please review the changes in $OUTPUT for:"
echo "   - Architectural concerns"
echo "   - Code quality and patterns"
echo "   - Potential bugs or edge cases"
echo "   - Integration with existing code\""
echo ""
