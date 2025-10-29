# Review Prep Tools

Tools for generating comprehensive code review packages with full file contents and diffs for LLM feedback.

## Overview

These tools solve a common problem: when asking LLMs for code review feedback, providing just a patch/diff lacks context. This generates a **hybrid package** with:

1. **Full file contents** (current state after changes) - for complete context
2. **Detailed diff** - to highlight exact changes
3. **Commit summary** - to understand the progression
4. **Metadata** - file counts, line counts, language detection

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

Both methods generate a markdown file in `/tmp/` with this structure:

```markdown
# Code Review Package

**Generated:** 2025-10-28 22:39:23
**Branch:** feature/my-changes
**Range:** `main..HEAD`

## Summary
- Commit count, file stats, insertions/deletions
- List of commits with authors and timestamps
- File change statistics

## Changed Files (Full Content - After Changes)
- Complete file contents for each changed file
- Syntax highlighting based on file extension
- Collapsible file metadata (line count, type)

## Detailed Diff
- Traditional git diff output
- Shows exact line-by-line changes

## Context for LLM Review
- Instructions for the reviewer
- Suggested focus areas
```

## Example Output

```
✅ Review package generated successfully!

📊 Package Stats:
   Lines: 9720
   Size: 348K
   Location: /tmp/review-main-to-HEAD-20251028-223923.md

📋 Quick Actions:
   View: cat "/tmp/review-main-to-HEAD-20251028-223923.md"
   Copy (macOS): cat "/tmp/review-main-to-HEAD-20251028-223923.md" | pbcopy

🤖 For LLM Review:
   "Please review the changes in /tmp/review-main-to-HEAD-20251028-223923.md for:
   - Architectural concerns
   - Code quality and patterns
   - Potential bugs or edge cases
   - Integration with existing code"
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

### Solution: Full Files + Diff

The hybrid approach provides:
1. **Complete files** - understand architecture and patterns
2. **Diff highlighting** - focus attention on changes
3. **Commit history** - understand evolution of changes
4. **Ready to paste** - immediately usable in LLM chats

## File Size Considerations

- **Small changes** (1-5 files): Usually < 50KB, fits easily in context
- **Medium changes** (5-15 files): 50-200KB, still manageable
- **Large changes** (15+ files): 200KB+, consider splitting review

The script shows file size in output so you can judge if it's too large for your LLM's context window.

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
