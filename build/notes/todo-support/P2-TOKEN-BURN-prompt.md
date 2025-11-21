---
todo_id: P2-TOKEN-BURN
title: Review and Catalog Token Burn Branches
type: prompt
date: 2025-11-19
status: active
description: Agent prompt for reviewing and cataloging branches created during token burn session
---

# Task: Review and Catalog Token Burn Branches (Swift Repository)

## Context

During a token burn session on the night of Nov 18-19, 2025, I created multiple branches with speculative code, documentation, marketing plans, and experimental features. These branches need to be reviewed and cataloged rather than immediately merged.

## Your Task

1. **Fetch and examine all remote branches** created in the last 24-48 hours
2. **Categorize each branch** by content type and review priority
3. **Create a reference document** listing all branches with details
4. **Add appropriate tasks to TODO.md** for future review
5. **DO NOT merge branches automatically** - code needs manual review first

## Instructions

### Step 1: Fetch and List Recent Branches

```bash
git fetch --all
git branch -r --sort=-committerdate | head -20
```

Examine branches that start with `claude/` or were created Nov 18-19, 2025.

### Step 2: Categorize Each Branch

For each branch, determine:

**Content Type:**
- **Code** - Implementation, features, bug fixes, refactoring
- **Documentation** - README updates, guides, inline docs
- **Marketing** - Marketing plans, pitch decks, strategy docs
- **Research** - Explorations, spikes, proof-of-concepts
- **Configuration** - Build scripts, CI/CD, project setup
- **Mixed** - Combination of the above

**Review Priority:**
- **High** - Ready for integration, small/safe changes, critical fixes
- **Medium** - Needs code review, moderate complexity, non-critical
- **Low** - Experimental, may be outdated, speculative

**Action Required:**
- **Integrate** - Merge into main (after review)
- **Document** - Extract to documentation/guides
- **TODO** - Add specific task to TODO.md
- **Archive** - Keep branch but no immediate action
- **Discard** - Can be deleted

### Step 3: Create Reference Document

Create a file: `docs/TOKEN_BURN_BRANCHES_2025-11-18.md`

Format:

```markdown
# Token Burn Branches - Nov 18-19, 2025

Created: 2025-11-19
Status: Pending Review

## Summary

- Total branches: [N]
- Code branches: [N]
- Documentation branches: [N]
- Marketing/Strategy: [N]
- Research/Experimental: [N]

## High Priority Review

### [Branch Name]
- **Type:** Code
- **Description:** [What the branch contains]
- **Files changed:** [N files, major changes]
- **Status:** Needs code review
- **Action:** Integrate after review
- **Notes:** [Any important context]
- **Commits:** [1-2 key commit messages]

[Repeat for each high priority branch]

## Medium Priority Review

[Same format as above]

## Low Priority / Experimental

[Same format as above]

## Branches by Category

### Code Implementation
- `branch-name-1` - [brief description]
- `branch-name-2` - [brief description]

### Documentation
- `branch-name-3` - [brief description]

### Marketing & Strategy
- `branch-name-4` - [brief description]

### Research & Experiments
- `branch-name-5` - [brief description]

## Recommended Actions

1. [Specific action for high priority items]
2. [Specific action for medium priority items]
3. [Decision needed on experimental branches]

## Next Steps

- [ ] Review high priority branches by [date]
- [ ] Code review session for implementation branches
- [ ] Extract documentation to appropriate locations
- [ ] Decide: integrate marketing plans into project docs or separate repo?
- [ ] Archive or delete experimental branches after review
```

### Step 4: Update TODO.md

Add a new high priority section:

```markdown
- [ ] **Review token burn branches (Nov 18-19, 2025)**
  - See `docs/TOKEN_BURN_BRANCHES_2025-11-18.md` for complete catalog
  - [ ] Review [N] high priority branches
  - [ ] Code review [N] implementation branches
  - [ ] Extract documentation from [N] branches
  - [ ] Review marketing/strategy plans
  - [ ] Decision: integrate, document, or archive each branch
```

### Step 5: Handle Special Cases

**If you find:**

- **Marketing plans** → Add note: "Consider moving to project docs or separate marketing repo"
- **Completed features** → Add note: "Test thoroughly before merge"
- **Breaking changes** → Add warning: "BREAKING: requires migration plan"
- **Duplicate work** → Add note: "Check if superseded by other work"
- **Experimental APIs** → Add note: "Requires architecture review"

## What NOT To Do

- ❌ Do not automatically merge any branches
- ❌ Do not delete branches without documenting them first
- ❌ Do not consolidate code without review (unlike the content-only repo)
- ❌ Do not make assumptions about code correctness
- ❌ Do not integrate breaking changes without migration plan

## What TO Do

- ✅ Create comprehensive reference document
- ✅ Categorize by type and priority
- ✅ Add specific TODO items for each branch
- ✅ Flag branches that need code review
- ✅ Extract non-code content (docs, marketing) to appropriate locations
- ✅ Identify dependencies between branches
- ✅ Note any conflicts or overlapping work

## Output Format

When complete, provide:

1. **Summary statistics** (X branches, Y code, Z docs, etc.)
2. **Path to reference document** (`docs/TOKEN_BURN_BRANCHES_2025-11-18.md`)
3. **Updated TODO.md** with review tasks
4. **Recommendations** for immediate next steps
5. **Warnings** about any risky/breaking changes

## Example Output

```
✅ Branch Analysis Complete

Summary:
- 12 branches analyzed
- 7 code implementation branches
- 3 documentation branches
- 2 marketing/strategy branches
- 0 branches merged (all require review)

Created:
- docs/TOKEN_BURN_BRANCHES_2025-11-18.md

Updated:
- TODO.md (added review tasks)

High Priority Actions:
1. Review `claude/feature-xyz` - Small bug fix, ready for merge
2. Review `claude/api-refactor` - Breaking changes, needs migration plan
3. Extract marketing plan from `claude/go-to-market-strategy`

Warnings:
- Branch `claude/api-v2` contains breaking changes
- Branch `claude/database-migration` conflicts with recent main changes
```

## Questions to Consider

As you analyze, consider:

1. Are there duplicate or conflicting branches?
2. Do any branches depend on each other?
3. Are there marketing/strategy docs that should be extracted?
4. Are there completed features that are ready to merge?
5. Are there experiments that can be archived?
6. Are there docs that should be integrated into main documentation?

## Final Notes

- **Be thorough** - Don't miss any branches
- **Be specific** - Provide actionable information for each branch
- **Be cautious** - When in doubt, flag for manual review
- **Be organized** - Clear categorization helps future review

Take your time and create a comprehensive reference that will be useful for manual review later.
