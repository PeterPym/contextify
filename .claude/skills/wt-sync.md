---
name: wt-sync
description: Bidirectional worktree sync - pull from main AND push to main, plus paired repo health check. Project-level override that wraps the global wt-sync skill and checks the matching contextify-cloud worktree status.
---

# Worktree Sync (Contextify Project Override)

This is a project-level override of the global `/wt-sync` skill. It adds a paired repo health check for the **matching** `contextify-cloud` worktree after the standard worktree sync.

## Behavior

**Step 1: Run the standard wt-sync**

Follow the global `~/.claude/skills/wt-sync/SKILL.md` instructions exactly (validate environment, check preconditions, execute sync, report results, surface untracked warnings).

**Step 2: Determine the matching cloud worktree**

The contextify and contextify-cloud repos have mirrored worktrees (wb1-wb4). Always check the **matching** cloud worktree based on the current contextify worktree name.

```bash
# Determine current worktree name from project-config.yaml
CURRENT_WT=$(wt-context.sh --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null)

# Map to the matching cloud worktree
case "$CURRENT_WT" in
  primary) CLOUD_REPO="$HOME/code/projects/contextify-cloud" ;;
  wb*)     CLOUD_REPO="$HOME/code/projects/contextify-cloud-${CURRENT_WT}" ;;
  *)       CLOUD_REPO="$HOME/code/projects/contextify-cloud" ;;
esac
```

**Step 3: Check paired repo health**

```bash
# 1. Check if repo exists
if [ ! -d "$CLOUD_REPO" ]; then
  echo "WARNING: paired cloud worktree not found at $CLOUD_REPO"
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

**Step 4: Report paired repo status**

Append a section to the sync report:

```markdown
### Paired Repo: contextify-cloud ({CURRENT_WT})

| Property | Value |
|----------|-------|
| Path | {CLOUD_REPO} |
| Branch | {CLOUD_BRANCH} |
| Status | {clean / dirty} |
| vs origin/main | {behind N / ahead N / in sync} |
```

**Warning conditions** (surface prominently):

- **Not on landing branch:** "contextify-cloud-{wt} is on branch `{branch}`, not its landing branch. This may be leftover from a feature branch."
- **Dirty working tree:** "contextify-cloud-{wt} has uncommitted changes ({N} files modified)."
- **Behind origin/main:** "contextify-cloud-{wt} is {N} commits behind origin/main. Consider running `cd {CLOUD_REPO} && wt-sync.sh` to update."
- **Ahead of origin/main:** "contextify-cloud-{wt} is {N} commits ahead of origin/main. These changes have not been pushed."

**Clean state** (brief, non-alarming):
- "contextify-cloud-{wt}: on landing branch, in sync, clean."

## Why This Override Exists

The contextify and contextify-cloud repos are paired with mirrored worktrees (wb1-wb4). When working on cross-repo features (e.g., CLI + server changes), the cloud repo can drift out of sync or be left on a feature branch. This check ensures agents and users are aware of the paired worktree's state during routine sync operations. See `paired_repo` in `project-config.yaml`.

## Trigger Phrases

Same as the global skill:
- "/wt-sync", "sync worktree", "sync worktrees", "update from main", "pull main", "push to main", "sync all", "wt-sync"

## Arguments

Same as the global skill:
- (none) = sync all worktrees
- `current` = sync current worktree only
- `--dry-run` = preview without changes
- `push` = push-focused sync
