---
name: wt-sync
description: Bidirectional worktree sync - pull from main AND push to main, plus companion repo health check. Project-level override that wraps the global wt-sync skill and adds contextify-cloud repo status verification.
---

# Worktree Sync (Contextify Project Override)

This is a project-level override of the global `/wt-sync` skill. It adds a companion repo health check for the `contextify-cloud` repository after the standard worktree sync.

## Behavior

**Step 1: Run the standard wt-sync**

Follow the global `~/.claude/skills/wt-sync/SKILL.md` instructions exactly (validate environment, check preconditions, execute sync, report results, surface untracked warnings).

**Step 2: Companion repo health check**

After the standard sync completes (whether syncing current or all worktrees), check the `contextify-cloud` companion repo:

```bash
CLOUD_REPO="$HOME/code/projects/contextify-cloud"

# 1. Check if repo exists
if [ ! -d "$CLOUD_REPO/.git" ]; then
  echo "WARNING: contextify-cloud repo not found at $CLOUD_REPO"
  # Skip remaining checks
fi

# 2. Check current branch
CLOUD_BRANCH=$(git -C "$CLOUD_REPO" branch --show-current)

# 3. Check for uncommitted changes
CLOUD_DIRTY=$(git -C "$CLOUD_REPO" status --porcelain)

# 4. Check sync with origin/main
git -C "$CLOUD_REPO" fetch origin --quiet 2>/dev/null
CLOUD_BEHIND=$(git -C "$CLOUD_REPO" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
CLOUD_AHEAD=$(git -C "$CLOUD_REPO" rev-list --count origin/main..HEAD 2>/dev/null || echo "?")
```

**Step 3: Report companion status**

Append a section to the sync report:

```markdown
### Companion Repo: contextify-cloud

| Property | Value |
|----------|-------|
| Path | ~/code/projects/contextify-cloud |
| Branch | {CLOUD_BRANCH} |
| Status | {clean / dirty} |
| vs origin/main | {behind N / ahead N / in sync} |
```

**Warning conditions** (surface prominently):

- **Not on main:** "contextify-cloud is on branch `{branch}`, not `main`. This may be leftover from a feature branch."
- **Dirty working tree:** "contextify-cloud has uncommitted changes ({N} files modified)."
- **Behind origin/main:** "contextify-cloud is {N} commits behind origin/main. Run `git -C ~/code/projects/contextify-cloud pull` to update."
- **Ahead of origin/main:** "contextify-cloud is {N} commits ahead of origin/main. These changes have not been pushed."

**Clean state** (brief, non-alarming):
- "contextify-cloud: on main, in sync, clean."

## Why This Override Exists

The contextify-cloud repo does not have worktrees (see ct-406). When working on cross-repo features (e.g., device flow auth touches both CLI and server), the cloud repo can drift out of sync or be left on a feature branch. This check ensures agents and users are aware of the companion repo's state during routine sync operations.

## Trigger Phrases

Same as the global skill:
- "/wt-sync", "sync worktree", "sync worktrees", "update from main", "pull main", "push to main", "sync all", "wt-sync"

## Arguments

Same as the global skill:
- (none) = sync all worktrees
- `current` = sync current worktree only
- `--dry-run` = preview without changes
- `push` = push-focused sync
