# Triggering CI Builds from Linux

This guide explains how to trigger GitHub Actions builds from Linux environments (like Claude Code Web) without installing gh CLI.

## Quick Start

### One-Time Setup (5 minutes)

1. **Create a GitHub Personal Access Token:**

   ```bash
   # Run the setup script
   ./scripts/setup-github-token.sh
   ```

   This will:
   - Open GitHub's token creation page
   - Guide you through creating a token with correct scopes
   - Save it securely to `~/.config/contextify/github-token`

2. **Add to your shell profile (optional but recommended):**

   ```bash
   # Add to ~/.bashrc or ~/.zshrc
   export GITHUB_TOKEN=$(cat ~/.config/contextify/github-token 2>/dev/null)
   ```

   Or for session-only:
   ```bash
   export GITHUB_TOKEN=$(cat ~/.config/contextify/github-token)
   ```

### Triggering Builds

```bash
# Trigger Debug build on current branch (default)
./scripts/trigger-ci-build.sh Debug

# Trigger Release build on current branch
./scripts/trigger-ci-build.sh Release

# Trigger on a specific branch (e.g., main)
./scripts/trigger-ci-build.sh Debug main

# Trigger on any branch explicitly
./scripts/trigger-ci-build.sh Debug feature/my-branch
```

**Note:** The script automatically detects your current git branch. If you want to test your changes, just run `./scripts/trigger-ci-build.sh Debug` without specifying a branch!

The script will:
- ✅ Trigger the GitHub Actions workflow on your current branch (or specified branch)
- ✅ Show the run URL
- ✅ Provide the run ID for monitoring

### Watching Build Progress

After triggering, you can:

**Option 1: Open in browser**
```bash
# The script outputs a URL like:
open https://github.com/banagale/contextify/actions/runs/19214484236
```

**Option 2: Use gh CLI (if available)**
```bash
gh run watch 19214484236
```

**Option 3: Use GitHub API**
```bash
# Check status
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/banagale/contextify/actions/runs/19214484236 \
  | grep '"status"\|"conclusion"'
```

---

## How It Works

### Authentication Methods (in order of preference)

1. **Token file** (recommended for Linux): `~/.config/contextify/github-token`
2. **Environment variable**: `GITHUB_TOKEN=ghp_...`
3. **gh CLI** (if installed and authenticated)
4. **macOS Keychain** (macOS only)

### GitHub API

The script uses GitHub's REST API:

```bash
POST /repos/:owner/:repo/actions/workflows/:workflow_id/dispatches
```

This requires a Personal Access Token with:
- ✅ `repo` scope (full repository access)
- ✅ `workflow` scope (trigger workflows)

---

## Troubleshooting

### "No GitHub token found"

**Solution:**
```bash
# Run the setup script
./scripts/setup-github-token.sh

# Or manually set the token
export GITHUB_TOKEN=ghp_your_token_here
```

### "401 Authentication failed"

**Causes:**
- Token expired
- Token missing required scopes
- Token revoked

**Solution:**
1. Create a new token: https://github.com/settings/tokens/new
2. Select scopes: `repo`, `workflow`
3. Run setup script again: `./scripts/setup-github-token.sh`

### "404 Workflow not found"

**Causes:**
- Branch doesn't exist
- Workflow file not on that branch
- Wrong repository

**Solution:**
```bash
# Check available branches
git branch -r

# Trigger on a different branch
./scripts/trigger-ci-build.sh Debug main
```

### "422 Invalid request"

**Causes:**
- Invalid branch name
- Invalid configuration (must be "Debug" or "Release")

**Solution:**
```bash
# Use exact capitalization
./scripts/trigger-ci-build.sh Debug  # ✅
./scripts/trigger-ci-build.sh debug  # ❌

# Check branch exists
git rev-parse --verify origin/your-branch
```

---

## Security Best Practices

### Token Storage

The token is stored at `~/.config/contextify/github-token` with permissions `600` (owner read/write only).

**DO:**
- ✅ Use short-lived tokens (30-90 days)
- ✅ Keep token file permissions restrictive (`chmod 600`)
- ✅ Add `~/.config/contextify/` to `.gitignore` (already done)
- ✅ Revoke tokens you're no longer using

**DON'T:**
- ❌ Commit tokens to git
- ❌ Share tokens with others
- ❌ Use overly broad scopes
- ❌ Use long-lived tokens (> 90 days)

### Token Rotation

Rotate tokens regularly:

```bash
# 1. Revoke old token
#    Visit: https://github.com/settings/tokens

# 2. Create new token
./scripts/setup-github-token.sh

# 3. Test new token
./scripts/trigger-ci-build.sh Debug
```

---

## Advanced Usage

### Custom Workflow Inputs

Edit `trigger-ci-build.sh` to add custom inputs:

```bash
# Line 85-86, modify the JSON payload:
-d "{\"ref\":\"$BRANCH\",\"inputs\":{
  \"configuration\":\"$CONFIG\",
  \"skip_launch\":\"true\",
  \"enable_dev_mode\":\"false\"  # Add custom input
}}"
```

### Trigger Multiple Builds

```bash
# Trigger builds on multiple branches
for branch in main develop feature/new-ui; do
  ./scripts/trigger-ci-build.sh Debug "$branch"
  sleep 5  # Avoid rate limiting
done
```

### Check Build Status Programmatically

```bash
#!/bin/bash
RUN_ID=$(./scripts/trigger-ci-build.sh Debug | grep "Run ID:" | awk '{print $3}')

while true; do
  STATUS=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
    https://api.github.com/repos/banagale/contextify/actions/runs/$RUN_ID \
    | grep '"status"' | head -1 | cut -d'"' -f4)

  echo "Status: $STATUS"

  if [[ "$STATUS" != "in_progress" && "$STATUS" != "queued" ]]; then
    break
  fi

  sleep 10
done
```

---

## Comparison with gh CLI

| Feature | trigger-ci-build.sh | gh CLI |
|---------|---------------------|--------|
| **Works on Linux** | ✅ Yes | ✅ Yes |
| **No installation** | ✅ Just curl | ❌ Needs binary |
| **Token management** | ✅ File-based | ✅ Keyring |
| **Watch progress** | ❌ No (use API) | ✅ Built-in |
| **Interactive** | ✅ Yes | ✅ Yes |
| **CI-friendly** | ✅ Yes | ✅ Yes |

**Recommendation:**
- Use `trigger-ci-build.sh` on Linux/Claude Code Web
- Use `gh workflow run` when gh CLI is available

---

## Examples

### From Claude Code Web (Linux)

```bash
# First time setup
./scripts/setup-github-token.sh

# Trigger build
./scripts/trigger-ci-build.sh Debug

# Check status via GitHub web UI
# (script outputs the URL)
```

### From macOS Terminal

```bash
# If gh CLI is installed, it automatically uses that token
./scripts/trigger-ci-build.sh Debug

# Or use the same token file approach as Linux
export GITHUB_TOKEN=$(cat ~/.config/contextify/github-token)
./scripts/trigger-ci-build.sh Debug
```

### In CI Pipeline

```bash
# Set token as secret in your CI system
# Then trigger another workflow:
export GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}
./scripts/trigger-ci-build.sh Release main
```

---

## Related Scripts

- `trigger-ci-build.sh` - Main script to trigger builds
- `setup-github-token.sh` - One-time token setup
- `test-ci-signing.sh` - Monitor builds with gh CLI (requires gh)

---

## Further Reading

- [GitHub API: Workflow Dispatches](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event)
- [Creating Personal Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
- [GitHub Actions: workflow_dispatch](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#workflow_dispatch)

---

**Last Updated:** 2025-11-08
