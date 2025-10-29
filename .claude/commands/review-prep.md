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
  fi
fi

# Generate timestamp for filename
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT="/tmp/review-${BASE//\//-}-to-${HEAD_REF//\//-}-${TIMESTAMP}.md"

# Get current branch name
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")

# Generate the review package
{
  echo "# Code Review Package"
  echo ""
  echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
  echo "**Branch:** $CURRENT_BRANCH"
  echo "**Range:** \`$RANGE\`"
  echo ""

  # Summary stats
  echo "## Summary"
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

    while IFS= read -r file; do
      if [ -f "$file" ]; then
        echo ""
        echo "### \`$file\`"
        echo ""

        # Detect language for syntax highlighting
        EXT="${file##*.}"
        case "$EXT" in
          swift) LANG="swift" ;;
          py) LANG="python" ;;
          js) LANG="javascript" ;;
          ts) LANG="typescript" ;;
          md) LANG="markdown" ;;
          json) LANG="json" ;;
          yml|yaml) LANG="yaml" ;;
          sh) LANG="bash" ;;
          *) LANG="" ;;
        esac

        echo "\`\`\`${LANG}"
        cat "$file"
        echo '```'
        echo ""
      else
        echo ""
        echo "### \`$file\` *(deleted)*"
        echo ""
      fi
    done <<< "$CHANGED_FILES"
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

} > "$OUTPUT"

echo "✅ Review package written to: $OUTPUT"
echo ""
echo "📊 Stats:"
wc -l "$OUTPUT" | awk '{print "   Lines: " $1}'
du -h "$OUTPUT" | awk '{print "   Size: " $1}'
echo ""
echo "📋 To copy to clipboard:"
echo "   macOS: cat \"$OUTPUT\" | pbcopy"
echo "   Linux: cat \"$OUTPUT\" | xclip -selection clipboard"
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

- The script generates a markdown file with full file contents (after changes)
- The diff section shows the exact changes
- File is saved to `/tmp/review-{base}-to-{head}-{timestamp}.md`
- The script is idempotent and safe to run multiple times
