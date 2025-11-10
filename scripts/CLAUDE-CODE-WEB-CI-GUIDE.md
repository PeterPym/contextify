# Triggering CI Builds from Claude Code on the Web

This guide explains how to trigger GitHub Actions CI builds directly from Claude Code web sessions.

## Quick Start

### One-Time Setup (5 minutes)

1. **Create a GitHub Personal Access Token:**

   Visit: https://github.com/settings/tokens/new

   - **Name:** "Claude Code CI Trigger"
   - **Expiration:** 90 days (recommended)
   - **Scopes:**
     - ✅ `repo` (full repository access)
     - ✅ `workflow` (trigger workflows)

   Click "Generate token" and copy the token (starts with `ghp_`)

2. **Add Token to Claude Code Environment:**

   In Claude Code on the web:
   - Click your current environment name
   - Click the settings icon (⚙️)
   - Under "Environment variables", add:
     ```
     GITHUB_TOKEN=ghp_your_token_here
     ```
   - Click "Save"

3. **Verify Setup:**

   The SessionStart hook will automatically run when you start a new session and confirm the token is available.

### Triggering Builds

Once setup is complete, you can trigger CI builds from any Claude Code web session:

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

**Note:** The script automatically uses your **current git branch** by default. This is usually what you want when testing your changes!

The script will:
- ✅ Use the `GITHUB_TOKEN` from your environment
- ✅ Trigger the GitHub Actions workflow on your current branch (or specified branch)
- ✅ Return the run ID and URL for monitoring

## How It Works

### Automatic Setup

When you start a Claude Code web session, the SessionStart hook (`scripts/setup-ci-tools.sh`) automatically:

1. ✅ Detects it's running in a remote environment (`CLAUDE_CODE_REMOTE=true`)
2. ✅ Checks for `GITHUB_TOKEN` in environment variables
3. ✅ Makes CI trigger scripts executable
4. ✅ Displays usage instructions

### Authentication

The `trigger-ci-build.sh` script uses the GitHub REST API with your token:

```bash
POST /repos/banagale/contextify/actions/workflows/on-demand-build.yml/dispatches
Authorization: Bearer $GITHUB_TOKEN
```

This doesn't require:
- ❌ gh CLI installation
- ❌ OAuth device flow
- ❌ SSH keys
- ❌ Additional dependencies

Just curl + your token = working CI trigger!

## Network Access Requirements

The trigger script needs access to:
- ✅ `api.github.com` (already in default allowlist)

**Network policy:** Works with default "Limited" network access - no custom configuration needed!

## Example Workflow

### Scenario: Fix a Bug from Claude Code Web

1. **Start session** on [claude.ai/code](https://claude.ai/code)
2. **Make your changes** with Claude's help
3. **Trigger CI build** to verify:
   ```bash
   ./scripts/trigger-ci-build.sh Debug feature/my-fix
   ```
4. **Monitor build** via the returned URL
5. **Create PR** when CI passes

### Scenario: Parallel Testing

Test multiple branches simultaneously:

```bash
# Trigger builds on multiple branches
./scripts/trigger-ci-build.sh Debug feature/ui-redesign
./scripts/trigger-ci-build.sh Debug feature/api-optimization
./scripts/trigger-ci-build.sh Debug feature/database-migration

# All three builds run in parallel
```

## Environment Variables Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `GITHUB_TOKEN` | ✅ Yes | Personal access token with `repo` and `workflow` scopes |
| `CLAUDE_CODE_REMOTE` | Auto-set | Set to `"true"` in remote environments |
| `CLAUDE_PROJECT_DIR` | Auto-set | Path to project root in remote session |

## Security Best Practices

### Token Management

1. **Use short-lived tokens** (30-90 days)
2. **Rotate regularly** - create new token when expiring
3. **Revoke unused tokens** at https://github.com/settings/tokens
4. **Don't share tokens** - each developer gets their own

### Token Scopes

Only grant the **minimum required scopes**:
- ✅ `repo` - Needed to trigger workflows in private repos
- ✅ `workflow` - Needed to dispatch workflow events
- ❌ Don't add admin scopes unless absolutely necessary

### Environment Configuration

Claude Code environment variables are:
- 🔒 Stored securely by Anthropic
- 🔒 Not visible in session transcripts
- 🔒 Only accessible to your sessions

## Troubleshooting

### "GITHUB_TOKEN not set in environment"

**Solution:**
1. Click environment selector in Claude Code
2. Click settings (⚙️) next to environment name
3. Add environment variable:
   ```
   GITHUB_TOKEN=ghp_your_token_here
   ```
4. Start a new session (existing sessions won't pick up the change)

### "401 Authentication failed"

**Causes:**
- Token expired
- Token missing required scopes
- Token revoked

**Solution:**
1. Create new token: https://github.com/settings/tokens/new
2. Update environment variable with new token
3. Start new Claude Code session

### "404 Workflow not found"

**Causes:**
- Branch doesn't exist
- Workflow file not on target branch

**Solution:**
```bash
# Check available branches in Claude Code session
git branch -r | grep feature

# Trigger on verified branch
./scripts/trigger-ci-build.sh Debug origin/feature/my-branch
```

### Script shows "Local environment detected"

**Expected!** The SessionStart hook (`setup-ci-tools.sh`) only runs setup in remote environments. On local machines, you don't need this setup - use gh CLI or the token file approach instead.

## Comparison: Claude Code Web vs Local

| Feature | Claude Code Web | Local Terminal |
|---------|-----------------|----------------|
| **Authentication** | Environment variable | Token file or gh CLI |
| **Setup** | SessionStart hook | One-time `setup-github-token.sh` |
| **Network** | Via proxy (allowlist) | Direct |
| **Dependencies** | Auto-installed | Manual or gh CLI |
| **Use Case** | Quick tasks, parallel work | Long sessions, full IDE |

## Advanced Usage

### Custom Workflow Inputs

Modify `trigger-ci-build.sh` to pass additional inputs:

```bash
# Line 85-86, add custom inputs to JSON payload:
-d "{\"ref\":\"$BRANCH\",\"inputs\":{
  \"configuration\":\"$CONFIG\",
  \"skip_launch\":\"true\",
  \"enable_dev_mode\":\"true\"
}}"
```

### Checking Build Status

Use the GitHub API to monitor build status:

```bash
# Get run ID from trigger script output
RUN_ID=19214484236

# Check status
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/banagale/contextify/actions/runs/$RUN_ID \
  | grep '"status"\|"conclusion"'
```

### Downloading Build Logs

Download complete build logs (including compilation errors) as a ZIP archive:

```bash
# Get run ID from trigger script output or GitHub Actions UI
RUN_ID=19217497540

# Download logs ZIP file
curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -o build-logs-${RUN_ID}.zip \
  https://api.github.com/repos/banagale/contextify/actions/runs/${RUN_ID}/logs

# Extract logs
unzip build-logs-${RUN_ID}.zip

# Search for Swift compilation errors
grep -h "error:" *.txt | grep -i "\.swift"
```

**Note:** All three headers are required:
- `Accept: application/vnd.github+json` - Request GitHub's JSON API format
- `Authorization: Bearer $GITHUB_TOKEN` - Authenticate with your token
- `X-GitHub-Api-Version: 2022-11-28` - Specify API version for compatibility

The downloaded ZIP contains:
- `0_build.txt` - Main build job logs with compilation output
- Other job logs if applicable

**Tip:** Use this to debug build failures when the GitHub UI is not accessible or you need to process logs programmatically.

### Trigger from Python

If you prefer Python:

```python
import os
import requests

token = os.environ['GITHUB_TOKEN']
headers = {
    'Authorization': f'Bearer {token}',
    'Accept': 'application/vnd.github+json'
}

response = requests.post(
    'https://api.github.com/repos/banagale/contextify/actions/workflows/on-demand-build.yml/dispatches',
    headers=headers,
    json={
        'ref': 'main',
        'inputs': {
            'configuration': 'Debug',
            'skip_launch': 'true'
        }
    }
)

if response.status_code == 204:
    print('✅ Workflow triggered successfully!')
else:
    print(f'❌ Failed: {response.status_code}')
    print(response.text)
```

## Environment Setup Details

### SessionStart Hook Configuration

**File:** `.claude/settings.json`

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/scripts/setup-ci-tools.sh"
          }
        ]
      }
    ]
  }
}
```

This runs automatically when Claude Code web sessions start.

### Hook Script Details

**File:** `scripts/setup-ci-tools.sh`

What it does:
1. ✅ Checks `CLAUDE_CODE_REMOTE` (only runs in web sessions)
2. ✅ Verifies `GITHUB_TOKEN` exists in environment
3. ✅ Makes trigger scripts executable
4. ✅ Displays helpful usage instructions

## Migration Guide

### From gh CLI to Environment Variable

If you're used to using gh CLI locally:

**Local (gh CLI):**
```bash
gh workflow run on-demand-build.yml -f configuration=Debug
gh run watch
```

**Claude Code Web (API):**
```bash
./scripts/trigger-ci-build.sh Debug
# Open returned URL in browser to watch
```

### From Manual API Calls

If you're currently using curl commands:

**Before:**
```bash
curl -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/banagale/contextify/actions/workflows/on-demand-build.yml/dispatches \
  -d '{"ref":"main","inputs":{"configuration":"Debug"}}'
```

**After:**
```bash
./scripts/trigger-ci-build.sh Debug main
```

Much simpler!

## Related Documentation

- **CI Trigger Guide:** `scripts/CI-TRIGGER-README.md` (comprehensive Linux guide)
- **Investigation Report:** `build/notes/technical-reference/ci-signing-investigation.md`
- **Claude Code Hooks:** https://docs.claude.com/en/hooks
- **GitHub API Reference:** https://docs.github.com/en/rest/actions/workflows

## Support

### Common Questions

**Q: Do I need to install anything?**
A: No! Everything is already available in the Claude Code universal image (curl, bash, git).

**Q: Will this work with private repositories?**
A: Yes, as long as your `GITHUB_TOKEN` has access to the repository.

**Q: Can I trigger workflows in other repositories?**
A: Yes, modify the `REPO_OWNER` and `REPO_NAME` variables in `trigger-ci-build.sh`.

**Q: How do I rotate my token?**
A: Create a new token, update the environment variable in Claude Code settings, and revoke the old token.

**Q: Is this secure?**
A: Yes. Tokens are stored in Claude Code's secure environment variable system and only accessible to your sessions.

---

**Last Updated:** 2025-11-08
**Requirements:** Claude Code on the web (Pro/Max users)
**Dependencies:** None (uses universal image)
