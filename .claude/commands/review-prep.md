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

# Check for uncommitted changes to code files (ignoring .md and .sh)
UNCOMMITTED=$(git status --porcelain | grep -vE '\.(md|sh)$' || true)
if [ -n "$UNCOMMITTED" ]; then
  echo "❌ Error: You have uncommitted changes to code files."
  echo ""
  echo "Changes (excluding .md and .sh files):"
  echo "$UNCOMMITTED"
  echo ""
  echo "💡 Please commit your changes before generating a review package:"
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

# Get list of code files (exclude .md and .sh)
CODE_FILES=$(git diff "${RANGE_STAT}" --name-only | grep -vE '\.(md|sh)$')

# Common header function
write_header() {
  local title="$1"

  # For diff files, include the review prompt
  if [ "$title" = "Diff Only" ]; then
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
  echo "## Commit Summary"
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
