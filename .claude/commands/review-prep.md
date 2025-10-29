---
description: Generate a comprehensive review package with diffs and full file contents for LLM feedback
---

I need you to create a review package for the git commit range provided by the user.

## Instructions

1. **Parse the commit range from the user's message:**
   - If one hash provided (e.g., "abc123"): use range `abc123..HEAD`
   - If two hashes provided (e.g., "abc123 def456"): use range `abc123..def456`
   - If no hash provided: use `main..HEAD` (or `master..HEAD` as fallback)

2. **Run this shell script to generate the review package:**

```bash
#!/bin/bash
set -e

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
  fi
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

# Get list of code files (exclude .md and .sh)
CODE_FILES=$(git diff "${RANGE_STAT}" --name-only | grep -vE '\.(md|sh)$')

# Common header function
write_header() {
  echo "# Code Review: $1"
  echo ""
  echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
  echo "**Branch:** $CURRENT_BRANCH"
  echo "**Range:** \`$RANGE\` (\`${BASE_SHORT}..${HEAD_SHORT}\`)"
  echo ""
  echo "## Summary"
  echo ""
  echo "### Commits"
  echo ""
  git log "$RANGE" --reverse --format="- \`%h\` %s (%an, %ar)"
  echo ""
  echo "### Files Changed (code only, excluding .md and .sh)"
  echo ""
  echo '```'
  git diff "${RANGE_STAT}" --stat | grep -vE '\.(md|sh) '
  echo '```'
  echo ""
}

if [ -n "$CODE_FILES" ]; then
  # Generate DIFF file (lightweight - just changes)
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
  {
    write_header "Full Files"

    echo "---"
    echo ""
    echo "## Changed Files (Full Content)"
    echo ""
    echo "**Note:** This file contains complete file contents. For just the diff, see:"
    echo "\`$(basename "$OUTPUT_DIFF")\`"
    echo ""

    echo "$CODE_FILES" | while IFS= read -r file; do
      if [ -f "$file" ]; then
        echo ""
        echo "### \`$file\`"
        echo ""

        EXT="${file##*.}"
        case "$EXT" in
          swift) LANG="swift" ;;
          py) LANG="python" ;;
          js) LANG="javascript" ;;
          ts) LANG="typescript" ;;
          json) LANG="json" ;;
          yml|yaml) LANG="yaml" ;;
          *) LANG="" ;;
        esac

        echo "\`\`\`${LANG}"
        cat "$file"
        echo '```'
        echo ""
      fi
    done
  } > "$OUTPUT_FILES"

  echo "✅ Review packages generated:"
  echo ""
  echo "📄 DIFF (lightweight - recommended for review):"
  echo "   File: $OUTPUT_DIFF"
  wc -l "$OUTPUT_DIFF" | awk '{print "   Lines: " $1}'
  du -h "$OUTPUT_DIFF" | awk '{print "   Size: " $1}'
  echo ""
  echo "📚 FULL FILES (complete contents - use as reference):"
  echo "   File: $OUTPUT_FILES"
  wc -l "$OUTPUT_FILES" | awk '{print "   Lines: " $1}'
  du -h "$OUTPUT_FILES" | awk '{print "   Size: " $1}'
  echo ""
  echo "📋 Copy diff to clipboard: cat \"$OUTPUT_DIFF\" | pbcopy"
else
  echo "No code files changed (only documentation/scripts)."
fi
```

3. **After running the script, ask the user:**
   - Would you like me to generate a summary of what this changeset represents?
   - Should I analyze the changes and provide context for review?

4. **If the user wants a summary:**
   - Read the generated markdown file from `/tmp/`
   - Analyze the commits and diffs
   - Prepend a "Context for Review" section with:
     - High-level description of what changed
     - Why these changes were made (inferred from commit messages and code)
     - Key areas to focus on during review
     - Potential concerns or questions for the reviewer

## Usage Examples

User says: `/review-prep abc123`
→ Creates review package for commits from abc123 to HEAD

User says: `/review-prep abc123 def456`
→ Creates review package for commits from abc123 to def456

User says: `/review-prep`
→ Creates review package for commits from main to HEAD

## Notes

- The script generates a markdown file with:
  - List of all commits
  - Statistics of changed files
  - Full file contents (final state after all changes)
  - Detailed diff showing exact line-by-line changes
- **Excluded from review**: `*.md` and `*.sh` files (documentation and scripts)
- **Included**: All code files (Swift, Python, JSON, YAML, etc.)
- Output: `/tmp/review-{base}-to-{head}-{timestamp}.md`
- The diff shows squashed/net changes across all commits (not individual commit diffs)
