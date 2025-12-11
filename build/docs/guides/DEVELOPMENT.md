# Development Guide

Complete build, test, and development commands for Contextify.

## Architecture Note

**Lazy Loading:** Contextify uses lazy loading architecture for 10-35x faster startup.
**Key Components:** AppStateOrchestrator, LightweightDiscoveryService, FastPathIngestionCoordinator
**See:** `build/docs/architecture/COMPONENTS.md` for architecture details

## Quick Reference

**Primary build script:** `bash scripts/xc.sh build` (auto-detects Xcode-beta if installed)

Common commands:
- Build and run: `make build` or `bash scripts/xc.sh build`
- Build and run with developer mode: `bash scripts/xc.sh --dev build` (enables test buttons)
- Build only (no launch): `CTX_NO_RUN=1 bash scripts/xc.sh build` (for CI/verification)
- Test: `make test` or `bash scripts/xc.sh test`
- Clean: `make clean` (removes DerivedData)
- Full setup with hooks: `make setup`

**Note:** Build commands launch the app by default. Use `CTX_NO_RUN=1` to skip launching.

## Build Locations

Contextify has two build workflows with different output locations:

### Dev/QA Builds (Scratch)

```bash
bash scripts/xc.sh --dist=appstore dev-archive
```

**Output:** `build/Contextify.xcarchive`

Use for:
- Testing code changes
- Debugging issues
- Quick iteration
- Pre-release QA

These builds are **overwritten** each time you run the command.

### Release Builds (Official)

```bash
./scripts/release/build.sh X.Y.Z
```

**Output:** `build/archives/v{VERSION}/appstore/Contextify.xcarchive`

Use for:
- App Store submission
- Demo video recording
- Final QA before release
- Preserving build artifacts

These builds are **versioned and preserved** for audit trail.

### Why Two Locations?

- **Dev builds** are disposable - you might build 10 times while fixing a bug
- **Release builds** are artifacts - the exact binary submitted to Apple
- Scripts like `demo-recording.sh` only use release builds to ensure demo matches submission

## Building on Linux / Non-macOS Environments

**For Claude Code Web users and Linux environments:**

Since Contextify is a macOS-only project requiring Xcode, builds from Linux environments must use **on-demand GitHub Actions** with macOS runners.

### Recommended: Use the Trigger Script (No gh CLI needed!)

The easiest way to build from Claude Code Web or Linux:

```bash
# Trigger build on your current branch and wait for results
./scripts/trigger-ci-build.sh Debug

# Or explicitly specify a branch
./scripts/trigger-ci-build.sh Debug feature/my-branch
```

**What it does:**
- ✅ Triggers GitHub Actions on your current branch (or specified branch)
- ✅ Waits for build completion (polls every 10s)
- ✅ Reports success/failure with clear output
- ✅ No gh CLI or additional tools required
- ✅ Works in Claude Code Web, generic Linux, or macOS

**Setup (one-time):**
- Ensure `GITHUB_TOKEN` is set in your environment (Claude Code Web: add in environment settings)
- See `scripts/CLAUDE-CODE-WEB-CI-GUIDE.md` for detailed setup

### Alternative: Using gh CLI

1. **Auto-trigger from Linux** (if you have GitHub CLI):
   ```bash
   bash scripts/xc.sh build
   # Follow the interactive prompts to trigger CI
   ```

2. **Manual trigger with gh CLI**:
   ```bash
   # Trigger a Debug build
   gh workflow run on-demand-build.yml -f configuration=Debug

   # Trigger a Release build
   gh workflow run on-demand-build.yml -f configuration=Release

   # Trigger and watch in real-time
   gh workflow run on-demand-build.yml -f configuration=Debug && gh run watch
   ```

3. **Manual trigger via GitHub web UI**:
   - Navigate to: Actions → "On-Demand Build" → Run workflow
   - Select configuration (Debug/Release) and options
   - Click "Run workflow"

### Viewing Build Results

After triggering a build, you can:

1. **Watch in real-time** (gh CLI required):
   ```bash
   gh run watch
   ```

2. **View on GitHub**:
   ```bash
   # Open the workflow runs page
   gh workflow view on-demand-build.yml --web
   ```

3. **Download build artifacts**:
   ```bash
   # List recent runs
   gh run list --workflow=on-demand-build.yml

   # Download artifacts from the latest run
   gh run download
   ```

**Build Artifacts Include:**

- `build-output.log`: Complete build output
- `logs/`: Detailed build logs from scripts/xc.sh
- `xcresult/`: Xcode result bundles (can be opened in Xcode on macOS for detailed analysis)
- `BUILD-SUMMARY.txt`: Summary of build configuration and status

**Workflow Features:**

- **Inputs**: Choose Debug/Release, enable dev mode, skip app launch
- **Fast caching**: SwiftPM packages cached for faster builds
- **Readable logs**: Structured output with clear success/failure indicators
- **Artifacts**: All logs and result bundles uploaded (retained for 7 days)
- **On-demand only**: Workflow does NOT run on push/PR (use `macos-build.yml` for that)

**Setup Requirements:**

1. **GitHub CLI (recommended)**: Install from https://cli.github.com/
   ```bash
   # Authenticate with GitHub
   gh auth login
   ```

2. **Repository access**: Ensure you have push access to trigger workflows

**Troubleshooting:**

- **"workflow not found"**: Ensure the workflow file is in the `main` branch (workflow_dispatch requires this)
- **Authentication errors**: Run `gh auth status` to check your GitHub authentication
- **Build failures**: Download the `xcresult` bundle and open it in Xcode on macOS for detailed diagnostics

**Technical Details:**

- **Runner**: `macos-15` (macOS Sequoia)
- **Xcode**: Latest stable version on GitHub runners
- **Timeout**: 30 minutes per build
- **Cost**: macOS runners use GitHub Actions minutes (10x multiplier vs Linux)

**Workflow File:** `.github/workflows/on-demand-build.yml`

---

## macOS Build Commands

### Build Targets

**DMG builds (`--dist=dmg`, default):**
- Unsandboxed build for development/testing
- Direct filesystem access, no permission prompts
- Fast iteration cycle

**App Store builds (`--dist=appstore`):**
- Sandboxed build with security-scoped bookmarks
- Requires TCC permission grants for transcript access
- Must use `accessProvider.withAccess()` for file I/O

### Common Commands

- Build and run: `make build` or `bash scripts/xc.sh build`
- Build and run with developer mode: `bash scripts/xc.sh --dev build` (enables test buttons)
- Build only (no launch): `CTX_NO_RUN=1 bash scripts/xc.sh build` (for CI/verification)
- Test: `make test` or `bash scripts/xc.sh test`
- Clean: `make clean` (removes DerivedData)
- Full setup with hooks: `make setup`

**Note:** Build commands launch the app by default. Use `CTX_NO_RUN=1` to skip launching.

### First-Run QA Testing (CLI-only toolkit)

**Complete guide:** `build/docs/testing/first-run-qa-guide.md`

Commands:
- Seed demo fixtures: `bash scripts/xc.sh seed-demo`
- DMG first-run (unsandboxed): `bash scripts/xc.sh --dist=dmg Debug cleanrun`
- App Store first-run (sandboxed): `bash scripts/xc.sh --dist=appstore Debug cleanrun`
- Reset permissions only: `bash scripts/xc.sh reset-perms`
- Reset app state only: `bash scripts/xc.sh reset-state`
- Reset all (perms + state): `bash scripts/xc.sh reset-all`
- Stream app logs: `bash scripts/xc.sh logs`

**Distribution modes:**
- `--dist=dmg` (default): Unsandboxed build, fast path for testing
- `--dist=appstore`: Sandboxed build, requires permission grants

**Use cases:**
- Test onboarding flow (Permissions → Discovery → Indexing → Auto-dismiss)
- Verify TCC permission handling (gated vs ungated locations)
- Test security-scoped bookmarks (App Store builds)
- Reproducible testing with demo fixtures (<10s runs)

### Log Capture for Debugging

- Capture last 5 min: `make logs` → `/tmp/contextify-recent.log`
- Stream live: `make logs-live` → `/tmp/contextify-live.log`
- Build + capture: `make debug` → `build/logs/runtime/contextify-YYYYMMDD-HHMMSS.log`

**For detailed debugging workflows:** See `scripts/logging/README.md` (primary debugging toolkit) and `scripts/QUICK-REFERENCE.md`

### Quick-Discovery Logs (Phase 2)

Quick-discovery runs at app launch to identify the project with newest transcript activity before full discovery begins.

**Log tags to monitor:**
- `[QUICK-DISCOVERY-START]` - Scan begins
- `[QUICK-DISCOVERY]` - Found N Claude/Codex directories
- `[QUICK-DISCOVERY-SCAN]` - Per-project scan details
- `[QUICK-DISCOVERY-DONE]` - Scan complete with duration (target: <500ms)
- `[QUICK-DISCOVERY-SWITCH]` - Project switch triggered
- `[QUICK-DISCOVERY-ERROR]` - Scan failed (graceful fallback to full discovery)

**Troubleshooting:**
- **Slow scan (>2s):** Check for network shares in `~/.claude/projects` or `~/.codex/sessions`
- **Wrong project on launch:** Check `[QUICK-DISCOVERY-DONE]` to verify correct project identified
- **No switch triggered:** Current project already has newest activity (expected behavior)
- **Switch failed:** Check `[QUICK-DISCOVERY-SWITCH] ❌` error message, likely DB or path issue

**Example logs:**
```
[QUICK-DISCOVERY-START] Scanning for newest transcript
[QUICK-DISCOVERY] Found 17 Claude project directories
[QUICK-DISCOVERY] Found 142 Codex transcript files
[QUICK-DISCOVERY] Found 8 unique Codex projects
[QUICK-DISCOVERY-DONE] Newest: contextify mtime=2025-11-17 16:49:56 (duration: 234ms)
[QUICK-DISCOVERY-SWITCH] Switching from /Users/rob/old-project to /Users/rob/contextify
[COORD-START] User-initiated switch to project: /Users/rob/contextify
[COORD-END] Switched to: contextify (id: 8F78...) in 0.045s
[QUICK-DISCOVERY-SWITCH] ✅ Switch complete
```

## Database Management

⚠️  **IMPORTANT:** ALWAYS use `scripts/db_manager.sh` for database operations
⚠️  **NEVER** delete database files manually with `rm` while app is running

**Database location:** `~/Library/Application Support/Contextify/contextify.db` (default)
- **Custom locations supported** via Settings > Database tab
- Supports Dropbox, iCloud Drive, or any user-selected directory
- Migration preserves all data (copies db, wal, shm files)
- Multi-machine conflict detection warns of concurrent access

**Commands:**
- Clean database (creates backup): `make clean-db` or `./scripts/db_manager.sh clean`
- Create backup: `make db-backup` or `./scripts/db_manager.sh backup`
- Restore latest: `make db-restore` or `./scripts/db_manager.sh restore latest`
- List backups: `make db-list` or `./scripts/db_manager.sh list`
- Re-ingest transcript: `./scripts/db_manager.sh reingest <transcript-id>` (resets checkpoint and re-parses JSONL file)

**Backups stored in:** `build/db-backups/`

**Agent rule:** ALWAYS ask user for approval before cleaning database

**For database location discovery:** See `build/docs/operations/DATABASE-LOCATIONS.md`

## Release Workflow (macOS only)

- Build Release configuration: `make build-release` or `bash scripts/xc.sh Release build`
- Sign and create DMG: `make sign-dmg` (production) or `make sign-dmg-no-notarize` (testing)
- Full release automation: `make release` (interactive workflow)
- Preview release: `make release-dry-run` (shows what would happen)

⚠️  **IMPORTANT:** Default `make build` uses **Debug** configuration. Always use `make build-release` for distribution!

**Detailed guide:** See `scripts/RELEASE.md` for complete release documentation

## Build Output

**DMG Debug build:** `.derived-dmg/Build/Products/Debug/Contextify.app`
**DMG Release build:** `.derived-dmg/Build/Products/Release/Contextify.app`
**App Store build:** `.derived-appstore/Build/Products/Debug/Contextify AppStore.app`

**Logs/Results:** script writes logs to `build/logs/` and result bundles to `build/ResultBundles/`. Use these for error triage; builds fail fast on non-zero.

**Direct (beta):**
```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Contextify/Contextify.xcodeproj -scheme Contextify -destination 'platform=macOS' build
```

**Xcode GUI:** Open `Contextify/Contextify.xcodeproj`, scheme `Contextify`, Run on "My Mac"
