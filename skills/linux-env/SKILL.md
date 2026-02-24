---
name: linux-env
description: Set up and manage Docker-based Linux testing environment for Contextify CLI testing. Use when user says "linux env", "linux testing", "test in linux", "docker linux", "/linux-env", or needs to test CLI in Linux container.
---

# Linux Environment for CLI Testing

Set up and manage a Docker-based Linux environment for testing Contextify CLI and Claude Code integration.

## Trigger Phrases

- "/linux-env"
- "/linux-env status"
- "/linux-env --state deps-ready"
- "clean linux qa env"
- "linux testing environment"
- "test in linux"
- "set up linux env"

## Primary Use Case: Clean Linux QA Environment

When user asks for "clean linux qa env" or similar:

### Step 1: Destroy any existing container

"Clean" means fresh - no confirmation needed.

```bash
docker stop contextify-qa 2>/dev/null; docker rm contextify-qa 2>/dev/null
```

### Step 2: Create fresh container and install deps

Bring environment to `deps-ready` state (container + curl installed).

### Step 3: Present the install command

**Target output:**
```
Linux QA environment ready.

Enter the container (as non-root user):
  docker exec -it -u testuser contextify-qa bash

Install Contextify (copy this line):
  curl -fsSL https://contextify.sh/install.sh | sh
```

This tests that install.sh works without root privileges (installs to ~/.local/bin).

## CRITICAL: Architecture Rules

**On ARM Mac (M1/M2/M3):**
- **arm64**: Build and test LOCALLY with native Colima arm64 profile (~12 min builds)
- **x86_64**: ALWAYS use GitHub CI - NEVER build x86_64 locally on ARM Mac

Local x86_64 builds on ARM Mac are unreliable (Rosetta/QEMU issues, crashes, wrong binaries).
Use `/linux-ci-trigger` or `gh workflow run linux-build.yml -f architecture=x86_64` instead.

## Arguments

Parse arguments from the command:
- `status` - Show current environment state (default if no args)
- `--state=<target>` - Bring environment to specified state
- `--arch=arm64` - Target architecture (default: arm64 on ARM Mac)
- `--cleanup` - Stop container and optionally Colima

**Note:** `--arch=x86_64` is intentionally not supported for local testing. Use CI for x86_64.

Target states (in order):
1. `container-ready` - Colima running, Ubuntu container available
2. `deps-ready` - curl and prerequisites installed for install.sh
3. `cli-installed` - Claude Code CLI installed in container
4. `contextify-installed` - Contextify CLI installed via install.sh
5. `auth-complete` - Claude Code authenticated
6. `fixtures-loaded` - Test fixtures installed
7. `active-session` - Ready for live testing

Examples:
```
/linux-env                          # Show status
/linux-env status                   # Show status
/linux-env --state container-ready  # Start Colima and container
/linux-env --state deps-ready       # Install curl and prerequisites
/linux-env --state contextify-installed  # Full setup including Contextify
/linux-env --arch=arm64             # Use arm64 (warn: slow)
/linux-env --cleanup                # Stop container
```

## End States

Each state builds on the previous. Request a state to bring the environment up to that point.

| State | Description |
|-------|-------------|
| container-ready | Colima + Ubuntu container running |
| deps-ready | curl, ca-certificates installed |
| cli-installed | Claude Code CLI installed via npm |
| contextify-installed | Contextify CLI installed via install.sh |
| auth-complete | Claude authenticated (interactive) |
| fixtures-loaded | Test transcripts installed |
| active-session | Container ready for live testing |

## Workflow

### Step 1: Check Current State

```bash
# Check Colima status and architecture
colima status 2>/dev/null && colima list

# Check Docker context (CRITICAL - determines which VM handles commands)
docker context show
docker context ls

# Check for running container
docker ps --filter "name=contextify-qa" --format "{{.Names}}"
```

Report current state to user before proceeding.

### Step 2: Architecture Selection

**Default: arm64** (native on ARM Mac, fast and reliable)

On ARM Mac, ONLY use arm64 for local Docker testing. x86_64 local builds are unreliable.

```bash
# Check current Colima architecture
colima list  # ARCH column shows current

# Start arm64 Colima (if not running)
colima start --profile arm64 --arch aarch64 --vm-type vz
docker context use colima-arm64
```

**NEVER switch to x86_64 locally.** If you need x86_64 binaries, use GitHub CI:
```bash
gh workflow run linux-build.yml --repo banagale/contextify -f architecture=x86_64
```

**IMPORTANT:** Always ask user before any Colima operations - they disrupt running containers.

### Step 3: Container Ready State

Start Colima if needed, then start Ubuntu container with non-root user:

```bash
# Start arm64 Colima (if not running)
colima start --profile arm64 --arch aarch64 --vm-type vz

# Verify Docker context points to arm64 Colima
docker context use colima-arm64

# Start persistent Ubuntu container with --init (prevents zombie processes)
docker run -d --name contextify-qa \
  --init \
  --platform linux/arm64 \
  ubuntu:22.04 \
  sleep infinity

# Create non-root user (tests that install.sh doesn't require root)
docker exec contextify-qa bash -c '
  useradd -m -s /bin/bash testuser
'

# Verify container is running
docker ps --filter "name=contextify-qa"
```

### Step 4: Deps Ready State (NEW)

Install curl and prerequisites so install.sh can run:

```bash
docker exec contextify-qa bash -c '
  apt-get update -qq
  apt-get install -y curl ca-certificates -qq

  # Verify curl is available
  curl --version
'
```

This state prepares the container for the one-line install command.

### Step 5: CLI Installed State

Install Claude Code CLI:

```bash
docker exec contextify-qa bash -c '
  # Install Node.js 20.x (required for Claude Code)
  apt-get install -y gnupg -qq
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
  apt-get update -qq
  apt-get install -y nodejs -qq

  # Install Claude Code CLI
  npm install -g @anthropic-ai/claude-code

  # Verify installation
  claude --version
'
```

Report Claude CLI version when complete.

### Step 6: Contextify Installed State (NEW)

Install Contextify CLI using the official installer (as non-root user):

```bash
docker exec -u testuser contextify-qa bash -c '
  # One-line install from contextify.sh (same as website)
  curl -fsSL https://contextify.sh/install.sh | sh

  # Verify installation
  ~/.local/bin/contextify --version
'
```

This tests that install.sh works without root privileges.

### Step 7: Auth Complete State

Authentication requires interactive user input (opens browser on host).

```bash
# Start auth flow - this will print a URL (as non-root user)
docker exec -it -u testuser contextify-qa claude auth login
```

**Guide user through:**
1. Copy the URL printed in terminal
2. Open URL in browser on host machine
3. Complete Anthropic login
4. CLI will show "Authentication successful"

**Note:** Container auth is separate from host auth. Each container needs its own authentication.

### Step 8: Fixtures Loaded State

Install test transcript fixtures for CLI testing (as non-root user):

```bash
docker exec -u testuser contextify-qa bash -c '
  mkdir -p ~/.claude/projects/test-project/sessions

  # Create minimal test transcript
  cat > ~/.claude/projects/test-project/sessions/test-session-001.jsonl << "EOF"
{"type":"summary","timestamp":"2026-01-19T12:00:00Z","summary":"Test fixture session for CLI validation"}
{"type":"message","timestamp":"2026-01-19T12:00:01Z","role":"user","content":"Hello, this is a test"}
{"type":"message","timestamp":"2026-01-19T12:00:02Z","role":"assistant","content":"Hello! I am a test fixture response."}
EOF

  echo "Test fixtures installed at ~/.claude/"
  ls -la ~/.claude/projects/test-project/sessions/
'
```

### Step 9: Active Session State

Container is ready for live Claude Code sessions:

```bash
# Start interactive shell in container (as non-root user)
docker exec -it -u testuser contextify-qa bash

# Inside container, user can:
# - Run claude commands
# - Test contextify / contextify-query commands
# - Generate real transcripts
# - Test Total Recall skill
```

## Quick Commands

**Default: Get ready for QA testing**
```
/linux-env
```
or
```
clean linux qa env
```

This brings the environment to `deps-ready` and outputs:
```
Linux QA environment ready.

Enter the container (as non-root user):
  docker exec -it -u testuser contextify-qa bash

Install Contextify (copy this line):
  curl -fsSL https://contextify.sh/install.sh | sh
```

**The install command** (same as https://contextify.sh/platforms/linux/):
```bash
curl -fsSL https://contextify.sh/install.sh | sh
```

**Enter the container (as non-root user):**
```bash
docker exec -it -u testuser contextify-qa bash
```

## Cleanup

Offer cleanup when work is complete:

```bash
# Stop and remove container (preserves Colima)
docker stop contextify-qa && docker rm contextify-qa

# Full cleanup (only if user confirms):
docker stop contextify-qa && docker rm contextify-qa
colima stop
```

**Container lifecycle:** Leave running by default. Offer cleanup when user indicates work is complete.

## Status Reporting

When showing status, report:

1. **Colima**: Running/Stopped, Architecture (x86_64/aarch64)
2. **Docker Context**: Current context and whether it matches Colima
3. **Container**: Running/Stopped/Not exists
4. **Deps**: curl available/not available
5. **Claude CLI**: Installed/Not installed, Version
6. **Contextify CLI**: Installed/Not installed, Version
7. **Auth**: Authenticated/Not authenticated
8. **Fixtures**: Present/Not present

Example output:
```
Linux Environment Status:
  Colima: Running (x86_64)
  Docker Context: colima (correct)
  Container: Running (contextify-qa)
  Deps: curl available
  Claude CLI: v2.1.12
  Contextify CLI: v1.2.0
  Auth: Not authenticated
  Fixtures: Not loaded

Current state: contextify-installed
Next state: auth-complete (requires interactive auth)
```

## Architecture Considerations

**arm64 (default, required for local testing on ARM Mac):**
- Native on ARM Mac - fast and reliable
- Requires: `colima start --profile arm64 --arch aarch64 --vm-type vz`
- Use `docker context use colima-arm64`

**x86_64 (CI ONLY - never build locally on ARM Mac):**
- Local x86_64 builds on ARM Mac are unreliable (Rosetta issues, crashes, wrong binaries)
- ALWAYS use GitHub CI for x86_64: `gh workflow run linux-build.yml -f architecture=x86_64`
- CI has native x86_64 runners that build correctly in ~10 min

**CRITICAL:** On ARM Mac, only use arm64 Colima profile for local work. Never switch to x86_64.

```bash
# Verify you're using arm64
docker run --rm ubuntu:22.04 uname -m
# Must show: aarch64
```

## Troubleshooting

### Container won't start
```bash
# Check Colima is running
colima status

# Check Docker daemon
docker info

# Check context
docker context ls  # * shows active
docker context use colima
```

### Wrong architecture in container
```bash
# Check actual architecture
docker exec contextify-qa uname -m

# If wrong, need to switch Colima (user confirmation first)
colima stop
colima delete
colima start --arch x86_64 --vm-type vz --vz-rosetta
```

### Claude auth fails
- Ensure container has internet: `docker exec contextify-qa ping -c1 google.com`
- Check Node.js version: `docker exec contextify-qa node --version` (need 18+)
- Try auth again: `docker exec -it contextify-qa claude auth login`

### install.sh fails
- Ensure curl is installed: `docker exec contextify-qa which curl`
- Check network: `docker exec contextify-qa curl -I https://contextify.sh`
- Run with deps-ready state first: `/linux-env --state deps-ready`

### macOS tar includes `._*` resource fork files
When copying files from macOS into a Linux container via `tar`, macOS tar includes AppleDouble (`._*`) resource fork files by default. This doubles the file count and confuses transcript discovery.

**Fix:** Always set `COPYFILE_DISABLE=1` when creating tarballs on macOS:
```bash
COPYFILE_DISABLE=1 tar -czf archive.tar.gz -C ~/path files/
```

Or when piping from `find`:
```bash
COPYFILE_DISABLE=1 find .claude/projects -name "*.jsonl" | COPYFILE_DISABLE=1 tar -czf /tmp/transcripts.tar.gz -T -
```

### "Illegal instruction" during builds
Colima is using QEMU instead of Rosetta. Recreate with `--vz-rosetta` flag.

## Related

- `/linux-ci-trigger` - Trigger CI builds instead of local Docker
- `build/docs/guides/local-linux-builds.md` - Build-specific commands
- https://contextify.sh/platforms/linux/ - User-facing install docs
