# Linux/Non-macOS CI Build System

## Overview

This document describes the on-demand CI build system for Contextify, designed to enable Claude Code web users (running in Linux environments) to build the macOS-only project via GitHub Actions.

## Problem Statement

Contextify is a macOS-only SwiftUI application requiring Xcode to build. Claude Code web runs in Linux containers and cannot build macOS projects directly. This creates a workflow gap for web-based AI coding assistants.

## Solution Architecture

### 1. On-Demand GitHub Actions Workflow

**File**: `.github/workflows/on-demand-build.yml`

**Key Features:**
- Manual trigger via `workflow_dispatch` event
- Configurable inputs (Debug/Release, dev mode, skip launch)
- Runs on macOS 15 runners with Xcode
- Uploads comprehensive build artifacts (logs, xcresult bundles)
- Structured output with GitHub Actions summaries
- SwiftPM caching for faster builds
- 30-minute timeout protection

**Inputs:**
- `configuration`: Debug or Release (choice)
- `skip_launch`: Skip app launch after build (boolean, default: true)
- `enable_dev_mode`: Enable developer mode (boolean, default: false)

**Artifacts:**
- `build-output.log`: Complete build output
- `logs/`: Detailed build logs from scripts/xc.sh
- `xcresult/`: Xcode result bundles (7-day retention)
- `BUILD-SUMMARY.txt`: Build metadata summary

### 2. Smart Detection in Build Script

**File**: `scripts/xc.sh`

**Enhanced with:**
- OS detection (checks `uname -s`)
- Helpful error messages for non-macOS platforms
- GitHub CLI integration for auto-triggering
- Interactive prompts (when in terminal)
- Non-interactive fallback (for CI/automation)
- Clear instructions for manual triggering

**User Flow:**
1. User runs `bash scripts/xc.sh build` on Linux
2. Script detects non-macOS OS
3. If `gh` CLI available: offers to trigger CI automatically
4. Otherwise: shows manual trigger instructions
5. Exits with code 1 (preventing silent failures)

### 3. Comprehensive Documentation

**File**: `AGENTS.md` (symlinked as `CLAUDE.md`)

**New Section**: "Building on Linux / Non-macOS Environments"

**Covers:**
- Quick start guides (auto-trigger, manual CLI, web UI)
- Build artifact details
- Workflow features and limitations
- Setup requirements (gh CLI, authentication)
- Troubleshooting common issues
- Technical details (runner specs, costs)

## Triggering Builds with trigger-ci-build.sh (Recommended)

The easiest way to trigger builds from any environment (no gh CLI required):

```bash
# Trigger Debug build on current branch (default)
./scripts/build/trigger-ci-build.sh Debug

# Trigger Release build on current branch
./scripts/build/trigger-ci-build.sh Release

# Trigger on a specific branch
./scripts/build/trigger-ci-build.sh Debug feature/my-branch
```

The script automatically detects your current git branch. It uses the GitHub REST API with a Personal Access Token, so no `gh` CLI is needed.

### One-Time Token Setup

1. **Create a GitHub Personal Access Token** at https://github.com/settings/tokens/new
   - Scopes: `repo` (full repository access), `workflow` (trigger workflows)
   - Recommended expiration: 30-90 days

2. **Store the token** (one of these methods):
   ```bash
   # Option A: Run the setup script
   ./scripts/build/setup-github-token.sh

   # Option B: Set environment variable
   export GITHUB_TOKEN=ghp_your_token_here
   ```

Token is stored at `~/.config/contextify/github-token` with permissions `600` (owner read/write only).

**Authentication priority:** Token file > `GITHUB_TOKEN` env var > gh CLI > macOS Keychain

### Claude Code Web Setup

In Claude Code web sessions, the `SessionStart` hook (`scripts/build/setup-ci-tools.sh`) automatically detects the remote environment and verifies token availability.

1. Click environment selector in Claude Code
2. Click settings next to environment name
3. Add environment variable: `GITHUB_TOKEN=ghp_your_token_here`
4. Start a new session (existing sessions will not pick up the change)

**Hook configuration** (`.claude/settings.json`):
```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "startup",
      "hooks": [{
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/scripts/build/setup-ci-tools.sh"
      }]
    }]
  }
}
```

### Watching Build Progress

After triggering, you can:

```bash
# Open URL from script output in browser
open https://github.com/banagale/contextify/actions/runs/XXXXX

# Use gh CLI (if available)
gh run watch XXXXX

# Check status via API
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/banagale/contextify/actions/runs/XXXXX \
  | grep '"status"\|"conclusion"'
```

### Downloading Build Logs

```bash
RUN_ID=XXXXX
curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -o build-logs-${RUN_ID}.zip \
  https://api.github.com/repos/banagale/contextify/actions/runs/${RUN_ID}/logs

unzip build-logs-${RUN_ID}.zip
grep -h "error:" *.txt | grep -i "\.swift"
```

## Alternative: Using gh CLI

```bash
# Trigger Debug build
gh workflow run on-demand-build.yml -f configuration=Debug

# Trigger Release build
gh workflow run on-demand-build.yml -f configuration=Release

# Trigger and watch
gh workflow run on-demand-build.yml -f configuration=Debug && gh run watch

# Via build script (interactive, auto-detects Linux)
bash scripts/xc.sh build
```

### Viewing Results

```bash
# Watch live
gh run watch

# List recent runs
gh run list --workflow=on-demand-build.yml

# Download artifacts
gh run download

# View in browser
gh workflow view on-demand-build.yml --web
```

## Token Security Best Practices

- Use short-lived tokens (30-90 days)
- Keep token file permissions restrictive (`chmod 600`)
- Revoke tokens you are no longer using
- Do not commit tokens to git or share them
- Rotate tokens regularly: revoke old token, run `./scripts/build/setup-github-token.sh`, test with `./scripts/build/trigger-ci-build.sh Debug`

## Troubleshooting

### "No GitHub token found"

Run `./scripts/build/setup-github-token.sh` or set `export GITHUB_TOKEN=ghp_...`

### "401 Authentication failed"

Token expired, missing required scopes, or revoked. Create a new token with `repo` and `workflow` scopes.

### "404 Workflow not found"

Branch does not exist or workflow file is not on that branch. Check `git branch -r` and try a different branch.

### "422 Invalid request"

Invalid branch name or configuration. Use exact capitalization (`Debug`, not `debug`).

## Design Decisions

### Why workflow_dispatch?

- **On-demand**: No wasteful builds on every push/PR
- **Explicit**: User controls when to spend macOS runner minutes
- **Configurable**: Supports multiple build configurations
- **Accessible**: Can be triggered via CLI, API, or web UI

### Why Separate Workflow?

- **Clarity**: `macos-build.yml` for PR/push, `on-demand-build.yml` for manual
- **Flexibility**: Different inputs and artifact strategies
- **Cost control**: macOS runners are 10x more expensive than Linux
- **Specialization**: Each workflow optimized for its use case

### Why Exit on Linux?

- **Fail-fast**: Prevents confusing errors from missing Xcode
- **Clear guidance**: Shows exact steps to build successfully
- **Non-destructive**: No partial builds or corrupted state
- **Discoverable**: Error message leads to documentation

## Best Practices for Agents

### When to Trigger

- User explicitly requests a build
- After making code changes that need verification
- When build logs/diagnostics are needed
- For testing Release configuration

### What NOT to Do

- Don't trigger on every file save
- Don't trigger multiple builds concurrently
- Don't ignore workflow timeouts (30 min limit)
- Don't forget to download artifacts if build fails

### Cost Awareness

- macOS runners: **10x** cost of Linux runners
- Build typically takes 5-10 minutes
- Artifacts retained for 7 days (automatic cleanup)
- SwiftPM caching reduces subsequent build times

## Testing

### Validation Checklist

- [x] YAML syntax valid (both workflow files)
- [x] Linux detection works in xc.sh
- [x] Error messages clear and actionable
- [x] Documentation comprehensive
- [ ] Workflow triggers successfully on GitHub (requires merge to main)
- [ ] Build succeeds on macOS runner
- [ ] Artifacts uploaded correctly
- [ ] gh CLI integration works

### Manual Testing

After merging to main:

```bash
# Test trigger
gh workflow run on-demand-build.yml -f configuration=Debug

# Watch progress
gh run watch

# Check artifacts
gh run list --workflow=on-demand-build.yml --limit 1
gh run view --log
```

## Future Enhancements

### Potential Improvements

1. **Build matrix**: Test multiple Xcode versions
2. **Test automation**: Run unit tests in workflow
3. **Notification system**: Slack/email on build completion
4. **Build caching**: DerivedData caching for faster builds
5. **PR comments**: Post build results as PR comments
6. **Status badges**: Add build status badge to README
7. **Benchmark tracking**: Track build times over time

### Alternative Approaches Considered

- **Always-on CI**: Rejected due to cost (macOS runners)
- **Container-based Xcode**: Not supported by Apple/GitHub
- **Remote build service**: Too complex for open source project
- **Dual platform**: Would require complete rewrite

## References

- [GitHub Actions workflow_dispatch](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#workflow_dispatch)
- [GitHub CLI manual](https://cli.github.com/manual/)
- [macOS GitHub runners](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners#supported-runners-and-hardware-resources)
- [Xcode build actions](https://github.com/marketplace/actions/mxcl-xcodebuild)

## Maintenance

### Regular Checks

- Monitor runner versions (update `runs-on` when new macOS releases)
- Review artifact retention policy (currently 7 days)
- Check for GitHub Actions deprecations
- Update Xcode version requirements in docs

### Known Limitations

- Requires workflow file in default branch (workflow_dispatch requirement)
- macOS runners slower to provision than Linux (~1-3 min)
- Build artifacts max size: 10 GB per workflow run
- Rate limits apply to workflow triggers (1000 per hour)

---

**Last Updated**: 2026-02-24
**Workflow Version**: 1.0
**Maintained by**: Contextify maintainers

**Note**: This document consolidates content previously in `scripts/CI-TRIGGER-README.md` and `scripts/CLAUDE-CODE-WEB-CI-GUIDE.md`.
