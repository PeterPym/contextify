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
review-prep.sh - Generate review packages for git commit ranges

USAGE:
  ./scripts/review-prep.sh [BASE] [HEAD]

EXAMPLES:
  ./scripts/review-prep.sh              # Compare main..HEAD
  ./scripts/review-prep.sh abc123       # Compare abc123..HEAD
  ./scripts/review-prep.sh abc123 def456  # Compare abc123..def456
  ./scripts/review-prep.sh main feature/branch  # Compare main..feature/branch

OUTPUT:
  Creates TWO markdown files in /tmp/:

  1. *-diff-*.md (LIGHTWEIGHT - recommended for review)
     - Commit summary and stats
     - Detailed diff of all changes
     - ~30KB typical size

  2. *-files-*.md (COMPLETE - use as reference)
     - Commit summary and stats
     - Full file contents (after changes)
     - ~500KB typical size

  Files excluded: *.md (markdown) and *.sh (shell scripts)
  Focus on: Code files (Swift, Python, JSON, etc.)

OPTIONS:
  -h, --help    Show this help message

NAMING:
  Files are named: review-{branch14}-{type}-{base}..{head}-{date}.md
  Branch name truncated to 14 chars for Finder visibility
  Example: review-feature-un-diff-7f95849..e869957-20251029.md

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
  BASE="main"
  HEAD_REF="HEAD"
elif [ -z "$2" ]; then
  BASE="$1"
  HEAD_REF="HEAD"
else
  BASE="$1"
  HEAD_REF="$2"
fi

# Check if base exists, fallback to master if main doesn't exist
if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  if [ "$BASE" = "main" ] && git rev-parse --verify master >/dev/null 2>&1; then
    BASE="master"
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

# Check for uncommitted changes to code files (ignoring .md and .sh)
UNCOMMITTED=$(git status --porcelain | grep -vE '\.(md|sh)$' || true)
if [ -n "$UNCOMMITTED" ]; then
  echo -e "${YELLOW}❌ Error: You have uncommitted changes to code files.${NC}"
  echo ""
  echo "Changes (excluding .md and .sh files):"
  echo "$UNCOMMITTED"
  echo ""
  echo -e "${BLUE}💡 Please commit your changes before generating a review package:${NC}"
  echo "   git add <files>"
  echo "   git commit -m \"your message\""
  echo ""
  exit 1
fi

RANGE="${BASE}..${HEAD_REF}"
RANGE_STAT="${BASE}...${HEAD_REF}"
DATE=$(date +%Y%m%d)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
BASE_SHORT=$(git rev-parse --short "$BASE" 2>/dev/null || echo "${BASE:0:7}")
HEAD_SHORT=$(git rev-parse --short "$HEAD_REF" 2>/dev/null || echo "HEAD")

# Generate filenames (truncate branch to 14 chars for Finder visibility)
BRANCH_CLEAN=$(echo "$CURRENT_BRANCH" | tr '/' '-' | cut -c1-14)
OUTPUT_DIFF="/tmp/review-${BRANCH_CLEAN}-diff-${BASE_SHORT}..${HEAD_SHORT}-${DATE}.md"
OUTPUT_FILES="/tmp/review-${BRANCH_CLEAN}-files-${BASE_SHORT}..${HEAD_SHORT}-${DATE}.md"

echo -e "${BLUE}Generating review packages...${NC}"
echo -e "  Range: ${GREEN}$RANGE${NC} (${BASE_SHORT}..${HEAD_SHORT})"
echo -e "  Branch: ${GREEN}$CURRENT_BRANCH${NC}"
echo ""

# Get list of code files (exclude .md and .sh)
CODE_FILES=$(git diff "${RANGE_STAT}" --name-only | grep -vE '\.(md|sh)$')

if [ -z "$CODE_FILES" ]; then
  echo -e "${YELLOW}No code files changed (only documentation/scripts).${NC}"
  exit 0
fi

# Common header function
write_header() {
  local TITLE="$1"
  echo "# Code Review: $TITLE"
  echo ""
  echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
  echo "**Branch:** $CURRENT_BRANCH"
  echo "**Range:** \`$RANGE\` (\`${BASE_SHORT}..${HEAD_SHORT}\`)"
  echo "**Repository:** $(basename "$(git rev-parse --show-toplevel)")"
  echo ""
  echo "## Summary"
  echo ""

  # Commit count
  COMMIT_COUNT=$(git rev-list --count "$RANGE" 2>/dev/null || echo "0")
  echo "**Commits:** $COMMIT_COUNT"

  # File stats (code files only)
  CODE_FILE_COUNT=$(echo "$CODE_FILES" | wc -l | tr -d ' ')
  INSERTIONS=$(git diff "$RANGE_STAT" -- $CODE_FILES 2>/dev/null | grep -c "^+" | tr -d ' ' || echo "0")
  DELETIONS=$(git diff "$RANGE_STAT" -- $CODE_FILES 2>/dev/null | grep -c "^-" | tr -d ' ' || echo "0")

  echo "**Code Files Changed:** $CODE_FILE_COUNT (excluding .md and .sh)"
  echo "**Lines Changed:** +$INSERTIONS / -$DELETIONS (approximate)"
  echo ""

  echo "### Commits"
  echo ""
  git log "$RANGE" --reverse --format="- \`%h\` %s (%an, %ar)"
  echo ""

  echo "### Files Changed (code only)"
  echo ""
  echo '```'
  git diff "${RANGE_STAT}" --stat | grep -vE '\.(md|sh) '
  echo '```'
  echo ""
}

# Generate DIFF file (lightweight - just changes)
echo -e "${BLUE}📄 Generating diff file...${NC}"
{
  write_header "Diff Only"

  echo "---"
  echo ""
  echo "## Detailed Diff"
  echo ""
  echo "**Note:** This file contains only the diff. For full file contents, see:"
  echo "\`$(basename "$OUTPUT_FILES")\`"
  echo ""
  echo '```diff'

  FILE_LIST=$(echo "$CODE_FILES" | tr '\n' ' ')
  git diff "${RANGE_STAT}" -- $FILE_LIST

  echo '```'
  echo ""
} > "$OUTPUT_DIFF"

# Generate FILES file (complete - full contents)
echo -e "${BLUE}📚 Generating full files...${NC}"
{
  write_header "Full Files"

  echo "---"
  echo ""
  echo "## Changed Files (Full Content)"
  echo ""
  echo "**Note:** This file contains complete file contents. For just the diff, see:"
  echo "\`$(basename "$OUTPUT_DIFF")\`"
  echo ""
  echo "> These files show the **current state** after all changes in the range."
  echo ""

  FILE_COUNT=0
  echo "$CODE_FILES" | while IFS= read -r file; do
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
        json) LANG="json" ;;
        yml|yaml) LANG="yaml" ;;
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
    fi
  done
} > "$OUTPUT_FILES"

# Print success message
echo ""
echo -e "${GREEN}✅ Review packages generated successfully!${NC}"
echo ""
echo -e "${BLUE}📄 DIFF FILE (lightweight - recommended for review):${NC}"
echo "   File: $OUTPUT_DIFF"
DIFF_LINES=$(wc -l < "$OUTPUT_DIFF" | tr -d ' ')
DIFF_SIZE=$(du -h "$OUTPUT_DIFF" | awk '{print $1}')
echo "   Lines: $DIFF_LINES"
echo "   Size: $DIFF_SIZE"
echo ""
echo -e "${BLUE}📚 FULL FILES (complete contents - use as reference):${NC}"
echo "   File: $OUTPUT_FILES"
FILES_LINES=$(wc -l < "$OUTPUT_FILES" | tr -d ' ')
FILES_SIZE=$(du -h "$OUTPUT_FILES" | awk '{print $1}')
echo "   Lines: $FILES_LINES"
echo "   Size: $FILES_SIZE"
echo ""
echo -e "${BLUE}📋 Quick Actions:${NC}"
echo "   View diff: cat \"$OUTPUT_DIFF\""
echo "   View files: cat \"$OUTPUT_FILES\""
if command -v pbcopy >/dev/null 2>&1; then
  echo "   Copy diff (macOS): cat \"$OUTPUT_DIFF\" | pbcopy"
fi
if command -v xclip >/dev/null 2>&1; then
  echo "   Copy diff (Linux): cat \"$OUTPUT_DIFF\" | xclip -selection clipboard"
fi
echo ""
echo -e "${BLUE}🤖 For LLM Review:${NC}"
echo "   Start with: $OUTPUT_DIFF"
echo "   Reference: $OUTPUT_FILES (if you need full context)"
echo ""
