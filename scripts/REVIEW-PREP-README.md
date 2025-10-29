# Review Prep Tools

Tools for generating comprehensive code review packages for LLM feedback.

## Overview

These tools solve a common problem: when asking LLMs for code review feedback, providing just a patch/diff lacks context. This generates **TWO separate packages**:

### 1. Diff Package (Lightweight - Recommended)
- Commit summary and stats
- Detailed diff showing exact changes
- ~30KB typical size
- **Best for:** Code review, focusing on what changed

### 2. Full Files Package (Complete - Reference)
- Commit summary and stats
- Complete file contents (current state after changes)
- ~500KB typical size
- **Best for:** Understanding context, architecture review

**What's Included:** Code files only (Swift, Python, JSON, etc.)
**What's Excluded:** Documentation (*.md) and scripts (*.sh)

## Two Ways to Use

### 1. Claude Code Slash Command (Recommended)

Use directly in your Claude Code session:

```
/review-prep                    # Compare main..HEAD
/review-prep abc123             # Compare abc123..HEAD
/review-prep abc123 def456      # Compare abc123..def456
```

**Benefits:**
- Integrated into your workflow
- Can ask Claude to generate a summary/context section
- Natural conversation flow

**Location:** `.claude/commands/review-prep.md`

---

### 2. Standalone Shell Script

Run directly from command line:

```bash
./scripts/review-prep.sh                    # Compare main..HEAD
./scripts/review-prep.sh abc123             # Compare abc123..HEAD
./scripts/review-prep.sh abc123 def456      # Compare abc123..def456
./scripts/review-prep.sh main feature/foo   # Compare branches
```

**Benefits:**
- Works without Claude Code
- Faster for repeated use
- Can pipe/redirect output
- Shows colorized progress

**Location:** `scripts/review-prep.sh`

---

## Output Format

Both methods generate **TWO markdown files** in `/tmp/`:

### File Naming

```
review-{branch14}-diff-{base}..{head}-{date}.md
review-{branch14}-files-{base}..{head}-{date}.md
```

**Note:** Branch name is truncated to 14 characters so that `-diff` and `-files` are visible in Finder's list view.

Example (from `feature/unread-badges-refactor` branch):
```
/tmp/review-feature-un-diff-7f95849..e869957-20251029.md
/tmp/review-feature-un-files-7f95849..e869957-20251029.md
```

### Diff File Structure

```markdown
# Code Review: Diff Only

**Generated:** 2025-10-29 12:00:00
**Branch:** feature/my-changes
**Range:** `7f95849..HEAD`

## Summary
- Commit count and file stats (code only)
- List of commits with authors/timestamps
- File change statistics

## Detailed Diff
- Traditional git diff output
- Shows exact line-by-line changes
- Excludes .md and .sh files
```

### Full Files Structure

```markdown
# Code Review: Full Files

(Same header as diff file)

## Changed Files (Full Content)
- Complete file contents for each changed file
- Syntax highlighting based on file extension
- Collapsible file metadata (line count, type)
- Excludes .md and .sh files
```

## Example Output

```
✅ Review packages generated successfully!

📄 DIFF FILE (lightweight - recommended for review):
   File: /tmp/review-main-7f95849..HEAD-diff-20251029.md
   Lines: 3012
   Size: 28K

📚 FULL FILES (complete contents - use as reference):
   File: /tmp/review-main-7f95849..HEAD-files-20251029.md
   Lines: 11890
   Size: 496K

📋 Quick Actions:
   View diff: cat "/tmp/review-main-7f95849..HEAD-diff-20251029.md"
   Copy diff (macOS): cat "/tmp/review-main-7f95849..HEAD-diff-20251029.md" | pbcopy

🤖 For LLM Review:
   Start with: /tmp/review-main-7f95849..HEAD-diff-20251029.md
   Reference: /tmp/review-main-7f95849..HEAD-files-20251029.md (if you need full context)
```

## Typical Workflow

### With Claude Code

1. Make your changes and commit them
2. In Claude Code chat: `/review-prep main`
3. Script runs and generates package
4. Ask: "Can you summarize what changed and add review context?"
5. Claude reads the file, adds summary section
6. Share the enhanced package with reviewers or use for self-review

### Standalone Script

1. Make your changes and commit them
2. Run: `./scripts/review-prep.sh main`
3. Copy the output file path
4. In your LLM of choice: "Please review [paste file path]"
5. Or copy to clipboard and paste into chat

## Advanced Usage

### Compare Specific Commits

```bash
# Compare two specific commits
./scripts/review-prep.sh abc123 def456

# Compare branch to specific commit
./scripts/review-prep.sh v1.2.3 HEAD

# Compare two branches
./scripts/review-prep.sh main feature/new-feature
```

### Integration with Other Tools

```bash
# Auto-copy to clipboard after generation
./scripts/review-prep.sh main && cat /tmp/review-*.md | tail -1 | pbcopy

# Open in editor immediately
./scripts/review-prep.sh main && code "$(ls -t /tmp/review-*.md | head -1)"

# Generate and show stats only
./scripts/review-prep.sh main 2>&1 | grep -A5 "Package Stats"
```

## Why This Approach?

### Problem with Diff-Only

```diff
- async func processUpdate() {
+ async func processUpdate() throws {
```

Without surrounding code, the reviewer can't see:
- What errors might be thrown
- How this integrates with calling code
- Whether error handling patterns are consistent
- Impact on other components

### Solution: Two-File Approach

**Diff file** provides focused review:
1. **Exact changes** - line-by-line what changed
2. **Commit context** - why it changed
3. **Lightweight** - fits easily in LLM context (~30KB)
4. **Ready to paste** - immediately usable in LLM chats

**Full files** provide context when needed:
5. **Complete files** - understand architecture and patterns
6. **Reference only** - use when diff isn't clear enough
7. **Larger but useful** - ~500KB, only load if needed

## File Size Considerations

### Diff File (Recommended for Review)
- **Small changes** (1-5 files): ~10-30KB
- **Medium changes** (5-15 files): ~30-100KB
- **Large changes** (15+ files): ~100KB+

### Full Files (Reference Only)
- **Small changes** (1-5 files): ~50-200KB
- **Medium changes** (5-15 files): ~200-500KB
- **Large changes** (15+ files): ~500KB+

**Pro tip:** Start with the diff file. Only load the full files if you need additional context.

The script shows both file sizes so you can choose appropriately for your LLM's context window.

## Tips for Best Results

1. **Commit frequently** - Smaller, focused reviews are better
2. **Use descriptive commit messages** - They appear in the summary
3. **Review before merging** - Generate package and self-review first
4. **Split large changes** - Use commit ranges to review in chunks
5. **Include context in prompts** - Tell the LLM what to focus on

## Troubleshooting

**"Base ref 'main' not found"**
- Your repo uses `master` instead of `main`
- The script auto-detects this, but you can specify explicitly:
  ```bash
  ./scripts/review-prep.sh master
  ```

**"No changes found"**
- The two refs are the same
- Check your commit history: `git log main..HEAD`

**Output too large**
- Review commits in smaller ranges
- Example: `./scripts/review-prep.sh abc123 def456` for a subset

**File not showing in output**
- Only committed files are included
- Stage and commit your changes first

## Future Enhancements

Possible additions:
- Add `--before` flag to show files before changes (currently shows after)
- Add `--summary` flag to automatically generate LLM summary
- Add `--clipboard` flag to auto-copy output
- Add `--format json` for programmatic consumption
- Integration with GitHub PR creation

## See Also

- Git diff documentation: `man git-diff`
- Claude Code slash commands: `.claude/commands/README.md`
- Code review best practices: `docs/code-review-guide.md` (if exists)
