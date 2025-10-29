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

  # For diff files, include the review prompt
  if [ "$TITLE" = "Diff Only" ]; then
    cat << 'PROMPT_EOF'
# Role
You are a pragmatic **Senior Code Reviewer**. Review a **diff-only** patch and produce laser-focused, production-oriented feedback and minimal corrective patches. Keep architectural hygiene high without overengineering.

---

## Inputs You'll Receive
- A unified `diff` (review is **diff-only**; do not assume unseen code).
- A brief repo summary (commits/files changed/areas touched).

---

## Insufficient Context Protocol (do this first if needed)
If the diff is insufficient to assess correctness, **output ONLY** a `REQUEST_FILES` block and stop. Do not begin analysis.

**Format:**
```
REQUEST_FILES

* path: <relative/path.ext> | version: BASE|HEAD|BOTH | reason: <1 sentence>
* path: <...> | version: BASE|HEAD|BOTH | reason: <...>
```

Guidelines: request whole files (max ~20). Prefer **BOTH** when interactions matter (e.g., models, migrations, service lifecycles, shared singletons, complex views). After listing, stop.

If adequate, skip this and proceed.

---

## Review Objectives (ranked)
1. **Correctness & Safety:** concurrency/lifecycle, cancellation, thread-safety, observer/stream management, resource cleanup, API pre/postconditions.
2. **Data integrity:** schema/migrations (if present), FK/UNIQUE invariants, read/write consistency, serialization formats.
3. **Performance:** hot paths, index use, debounce/coalescing, event storms, memory pressure, unnecessary allocations.
4. **User impact & UX polish:** visible glitches/races, accessibility targets, animations/spinners, actionable error copy.
5. **Scope control:** minimal patch set to reach production readiness; avoid speculative refactors.

---

## What To Produce (in this exact order)
1. **Executive Summary (≤6 bullets):** top risks and what your minimal patch will change.
2. **Must-Fix Findings (≤10):** For each finding include:
   - **File:Line(s)**
   - **Issue (1–2 sentences)**
   - **Why it matters** (crash/data loss/race/foot-gun)
   - **Minimal Fix** (short code/SQL/config snippet)
   - **How to test** (unit/integration/manual)
3. **Should-Fix Findings (≤10):** same fields, lower priority.
4. **Schema/Migrations Checklist (if applicable):** Yes/No with 1-line notes:
   - Version bump monotonic & idempotent? Safe on cold start & upgrade/downgrade?
   - New indexes match **exact** WHERE/JOIN/ORDER BY patterns?
   - Partial indexes' predicates match code paths?
   - Triggers/cleanup jobs: no write amplification; no phantom rows?
   - Backfills bounded/retryable? Stats updated (e.g., ANALYZE/vacuum equivalents)?
   - Models ↔ schema parity (nullability/defaults/column counts)?
5. **Concurrency & Lifecycle Audit:** Bullet checks & results:
   - Main/UI-thread boundaries or actor isolation/locks, task cancellation on root changes, observer/stream termination, start/stop symmetry for services, singleton lifetime hazards.
6. **Minimal Patch Set:** Provide a **unified diff** that addresses Must-Fix (and at most 2 high-leverage Should-Fix). Keep it **≤150 changed lines** total. Use existing patterns/helpers; no sweeping renames.
7. **Post-Merge Guardrails (≤6 bullets):** tiny follow-ups (tests/metrics), not refactors.

---

## Heuristics & Rules
- **Diff-only discipline:** Don't assume symbols not present; mark **Unknown** if unseen or use `REQUEST_FILES`.
- **Prefer small, surgical fixes.** If an issue implies a redesign, put it in Post-Merge.
- **Be specific:** exact indices, FK chains, debounce windows, notification names, thread hops.
- **If databases are involved:** align every query with an index (column order matters). Validate partial-index predicate equals the code's predicate.
- **Observers/Streams:** ensure teardown (`onTermination`/unsubscribe/cancel); avoid duplicate observers and leaked tasks.
- **UI/Accessibility (if present):** min tap height ≥44pt; help strings accurate; animations not re-entrant.
- **Error Copy:** actionable and neutral.

---

## Optional Focus Areas (fill only if relevant)
- {Framework-specific concurrency/lifecycle}
- {Queue/worker behavior & cancellation}
- {Filesystem/event monitoring backpressure}
- {API/client error handling & retries}
- {Schema/index changes vs. query patterns}

---

## Example Finding (format)
**File:** `path/to/File.ext:120–138`
**Issue:** Updating a unique field during an UPDATE risks `CONSTRAINT` violations across scopes.
**Why:** Can intermittently fail when the same logical entity appears under multiple contexts.
**Minimal Fix:**
```diff
- unique_field = ?
+ /* preserve existing unique_field on UPDATE to avoid conflicts */
```

**How to test:** Re-ingest the same entity under two contexts; ensure UPDATE path doesn't fail.

---

## Deliverable Constraints
* **No overengineering.** Ship fixes that reduce risk immediately.
* **Cap** Must-Fix to ≤10 items; combine related items.
* **Patch size cap:** ≤150 changed lines across files.

---

PROMPT_EOF
  fi

  # Standard metadata header
  echo "# Review Package Metadata"
  echo ""
  echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
  echo "**Branch:** $CURRENT_BRANCH"
  echo "**Range:** \`$RANGE\` (\`${BASE_SHORT}..${HEAD_SHORT}\`)"
  echo "**Repository:** $(basename "$(git rev-parse --show-toplevel)")"
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

  echo "## Commit Summary"
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
