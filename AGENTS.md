# Repository Guidelines

## ⚠️ CRITICAL RULES (Read First)

### Attribution
**NEVER** attribute work to AI/Claude/Codex in commits, co-authors, or comments.

### Commit Strategy
**ALWAYS** create atomic commits - one logical change per commit.
- Multiple related features? → Multiple commits
- Implementation plan has phases/PRs? → Separate commit per phase
- Before committing, ask: "Could this be split into smaller logical units?"

### Destructive Operations
**NEVER** run `git restore`, `git reset --hard`, `git clean`, or delete tracked files without:
1. Creating a backup branch first
2. Getting explicit user approval

---

## Project Overview

Contextify is a macOS SwiftUI HUD for project-centric AI sessions. It ingests dropped files or URLs, creates timestamped Markdown artifacts, provides checkpoints, and monitors Claude Code/Codex CLI conversation timelines with real-time LLM-powered summaries. Built with Swift 6 + SwiftUI on Xcode 16 (macOS 26 SDK, minimum deployment macOS 14/15).

## Target Platform & Tooling
- Xcode: 16+ (set Command Line Tools to Xcode 16).
- SDKs: Base `macOS 26` (Tahoe); min deployment `macOS 14` or `15`.
- Language: Swift 6; Frameworks: SwiftUI, Observation; optional: SwiftData, Core ML.
- Availability: gate Tahoe-only APIs (`@available(macOS 26, *)`) with clear fallbacks.

## Project Structure & Module Organization
- Source lives under `app/` (SwiftUI macOS HUD) and `cli/` (session/automation tools) when added.
- Documentation in `docs/` (e.g., `docs/roadmap/`) and acceptance/run guides per phase.
- Tests in `tests/` mirroring targets (e.g., `app/Tests/`, `cli/tests/`).
- Assets in `assets/` (icons, symbols). Working artifacts in per‑project `docs/sessions/` as described in the roadmap.

Example layout:
```
app/ ContextifyHUD.xcodeproj …
cli/ context/ …
docs/ roadmap/ …
tests/ app/ cli/
assets/ icons/
```

## Architecture & Key Modules

**For high-level system overview:** See `build/notes/technical-reference/system-architecture-overview.md`
- Explains component roles (Coordinator vs Orchestrator vs Monitor)
- Data model hierarchy (Projects → Transcripts → Entries → Summaries)
- Initialization flow and common confusion points

### Database Layer (SQL Backend)
- **Current Schema Version: v23** (see DatabaseSchema.swift for migration history)
- **Recent Migrations:**
  - **v12-v13**: Epoch timestamps (projects.last_viewed_ts, entries.created_ts)
  - **v14**: Request ID normalization (empty → entry_id fallback)
  - **v15**: Index cleanup and optimization
  - **v16**: GROUP BY index for unread queries (idx_entries_unread_join)
  - **v17-v20**: Schema fixes, file migration, orphaned project tracking
  - **v21**: Database access metadata for multi-machine conflict detection
  - **v22**: Strategy constraint fix (transcript_metadata.generation_strategy)
  - **v23**: Active transcript follow (project_follow_policy table)
- **TranscriptOrchestrator** (`app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`): High-level coordinator for all database operations. Provides async API for projects, transcripts, entries, timeline cache, and assistant usage reconciliation.
- **DatabaseManager** (`app/Sources/ContextifyCore/Database/DatabaseManager.swift`): Singleton managing GRDB connection pool, migrations, WAL mode, and custom database locations. Supports bookmark-based access for sandboxed builds.
- **DatabaseMigration** (`app/Sources/ContextifyCore/Database/DatabaseMigration.swift`): Safe database file migration between locations. Handles disk space checks, atomic copies, and validation.
- **DatabaseAccessMetadata** (`app/Sources/ContextifyCore/Database/DatabaseAccessMetadata.swift`): Multi-machine access tracking and conflict detection. Warns users of concurrent access issues.
- **HooverEngine** (`app/Sources/ContextifyCore/Database/HooverEngine.swift`): Streaming transcript ingestion engine. Processes JSONL files incrementally with crash-safe checkpointing. CTE-based FK-safe assistant_usage inserts with O(N+M) JOIN reconciliation.
- **Repositories** (`app/Sources/ContextifyCore/Database/Repositories.swift`): Type-safe GRDB repositories (ProjectRepository, TranscriptRepository, EntryRepository, TimelineCacheRepository, ProjectVisitsRepository).
- **DatabaseSchema** (`app/Sources/ContextifyCore/Database/DatabaseSchema.swift`): SQL schema definitions and versioned migrations (v1-v23).
  - **v8-v9**: project_visits table, unread query indices
  - **v10-v11**: assistant_usage_pending staging, FK hardening
  - **v12-v13**: Epoch timestamps (projects.last_viewed_ts, entries.created_ts), optimizations
  - **v14-v15**: Request ID normalization, index cleanup
  - **v16**: GROUP BY index for unread queries
  - **v17-v20**: Schema fixes, file migration, orphaned project tracking
  - **v21**: database_access_metadata table
  - **v22**: Strategy constraint fix (transcript_metadata.generation_strategy)
  - **v23**: Active transcript follow (project_follow_policy table)
- **TranscriptWatcher** (`app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`): File system monitoring for real-time transcript updates.
- **Models** (`app/Sources/ContextifyCore/Database/Models.swift`): Codable/Sendable database models (Project, Transcript, Entry, TimelineCache, AssistantUsage, etc.).
- **ProjectVisitsRepository** (`app/Sources/ContextifyCore/Database/ProjectVisitsRepository.swift`): Unread tracking and visit timestamps per project.
- **Documentation**:
  - Usage guide: `app/Sources/ContextifyCore/Database/README.md`
  - Architecture: `build/docs/architecture/sql-backend.md`
  - Database migration: `build/docs/components/database-migration.md`
  - Custom location feature: Shipped (see Settings > Database tab)

### LLM Processing & Timeline Integration
Contextify uses **two independent LLM processing queues** for content generation (both using Apple Intelligence/FoundationLLM on macOS 26+):

1. **Timeline Summary Generation** - Entry-level summaries (present/past forms)
2. **Transcript Metadata Generation** - Document-level titles, descriptions, topics

**Key Components:**
- **ConversationMonitor** (`Contextify/Contextify/ConversationMonitor.swift`): Main `@Observable` `@MainActor` component for timeline display. Manages TimelineState, visible entries, and session filtering. Integrates with SQL backend via TranscriptOrchestrator.
- **TimelineCacheMissGenerator** (`Contextify/Contextify/TimelineCacheMissGenerator.swift`): Queue #1 - LIFO processing for timeline entry summaries. Generates present/past forms with viewport-based pruning and overload protection.
- **TranscriptMetadataOrchestrator** (`Contextify/Contextify/TranscriptMetadataOrchestrator.swift`): Queue #2 - LIFO queue with viewport-aware pruning for transcript titles/descriptions/topics. Sequential processing with circuit breaker and SQL caching.
- **FoundationLLM** (`Contextify/Contextify/FoundationLLM.swift`): Shared integration with Apple's LanguageModel/FoundationModels. **Requires macOS 26.0+**. On older macOS, systems fall back to heuristics (no LLM).
- **StatusBar** (`Contextify/Contextify/StatusBarView.swift`, `StatusBarViewModel.swift`): Aggregates both LLM queues for unified monitoring. Shows processing status, pending counts, ETAs, and errors.
- **TimelineModels** (`Contextify/Contextify/TimelineModels.swift`): Timeline-specific data models (TimelineEntry, CacheKey, Disposition).
- **TimelineState** (`ConversationMonitor.swift`): Observable state container for timeline entries, derived cache index, and revision tracking.
- **Documentation**:
  - **⭐ LLM Architecture Overview:** `build/docs/architecture/llm-processing.md` (start here)
  - Timeline cache + LLM: `build/docs/components/timeline-cache.md`
  - State management: `build/docs/architecture/conversation-monitor-state.md`
  - Status bar: Shipped (see original design in `build/docs/archive/feature-specs/status-bar.md`)

### Core Components (Project Context)
- **HUDViewModel** (`app/Sources/ContextifyCore/HUDCore.swift:370-1032`): Main `@Observable` `@MainActor` view model. Manages:
  - Project root detection (environment → persisted → CWD → existing)
  - Git repository discovery and branch monitoring via file watchers
  - File/URL ingestion with Markdown artifact generation
  - Session and checkpoint management
  - Security-scoped bookmarks for sandboxed access

- **GitRepositoryResolver** (`app/Sources/ContextifyCore/HUDCore.swift:142-368`): Git repository detection. Finds `.git` root, parses HEAD (handles detached state, worktrees), and executes `git rev-parse` with timeout/fallback.

- **HUDPreferences** (`app/Sources/ContextifyCore/HUDCore.swift:13-126`): Manages UserDefaults with suite fallback. Stores project root path and security-scoped bookmarks.

### Startup Coordination (as of 2025-11-05)

**IMPORTANT:** All project identity flows through `StartupCoordinator.shared` for deterministic startup sequencing.

- **StartupCoordinator** (`app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`): Orchestrates deterministic startup sequencing for project identity pipeline. Provides single source of truth via `ActiveProjectContext` and ensures project exists in database before monitoring starts.

- **ActiveProjectContext** (`app/Sources/ContextifyCore/Models/ActiveProjectContext.swift`): Immutable value type representing active project identity. Contains stable project ID (primary key), filesystem path (metadata), display name, git branch, and security-scoped bookmark.

**Key Principles:**
- `ActiveProjectContext.id` is the **stable primary identity** - use for all database queries
- `ActiveProjectContext.path` is **metadata only** - do not use for lookups
- Coordinator owns `getOrCreateProject()` database calls
- All subsystems receive context via typed `AsyncStream` (not NotificationCenter)

**DO:**
```swift
// Subscribe to coordinator updates
for await context in StartupCoordinator.shared.updates {
    self.activeProjectId = context.id
    await refreshData()
}

// Wait for initial context
let context = try await StartupCoordinator.shared.ready()
await monitor.startMonitoring(projectId: context.id)

// User-initiated switch
try await StartupCoordinator.shared.switchProject(to: newPath)
```

**DON'T:**
```swift
// Query HUDViewModel for path (stale, race-prone)
let path = HUDViewModel.shared.projectRootURL

// Call getOrCreateProject directly (coordinator owns this)
let projectId = try orchestrator.getOrCreateProject(...)

// Use NotificationCenter for startup (timing-dependent)
NotificationCenter.default.addObserver(forName: .projectRootDidChange ...)
```

**Architecture:**
- **Startup Order:** `ContextifyApp.init()` starts coordinator → `ProjectSwitcherState.start()` subscribes to updates → `ContentView.task` waits for `ready()` → Timeline starts with stable project ID
- **Documentation:** `build/docs/architecture/startup-coordinator.md`
- **Implementation:** Shipped in commit 531ac70 (see original plan in `build/docs/archive/feature-specs/startup-coordinator.md`)

### UI Layer
- **ContentView** (`Contextify/Contextify/ContentView.swift`): Main UI with header (project/branch display, "Set Project Root" button), URL entry field, drop zone, controls (New Session, Checkpoint, Reveal Outputs), and toast notifications.
- **ConversationTimelineView** (`Contextify/Contextify/ConversationTimelineView.swift`): Timeline display UI with session filtering and real-time updates.
- **TimelineEntryRow** (`Contextify/Contextify/TimelineEntryRow.swift`): Individual timeline entry row component.
- **TranscriptInventoryView** (`Contextify/Contextify/TranscriptInventoryView.swift`): UI for browsing and switching between transcript sessions.
- **ProjectSwitcherView** (`Contextify/Contextify/ProjectSwitcherView.swift`): Multi-project tab navigation bar with drag-drop reordering, unread badges, and keyboard shortcuts.
- **ProjectSwitcherState** (`Contextify/Contextify/ProjectSwitcherState.swift`): `@Observable` state management for project list, active project, and unread counts.
- **IngestDropZone** (`Contextify/Contextify/IngestDropZone.swift`): Drag-and-drop target for files, uses SwiftUI `onDrop` with completion handlers and main actor marshaling.
- **Documentation**:
  - Project switcher architecture: `build/docs/architecture/project-switcher.md`
  - Active session policy: `build/docs/components/active-session-policy.md`

### Supporting Components
- **WindowTitleWriter** (`Contextify/Contextify/WindowTitleWriter.swift`): Updates window title to show current project name.
- **SystemInfo** (`Contextify/Contextify/SystemInfo.swift`): System information utilities (machine ID, support email).

> **Note:** iTerm2/terminal integration (ITerm2Bridge, ComposeWindowManager, GlobalHotkeyManager) was removed in commit 35ce380 for App Store compliance. See `build/notes/future-features.md` "Removed Features" section for re-implementation guidance if needed.

### Transcript Parsing & Metadata
- **TranscriptParsers** (`app/Sources/ContextifyCore/Database/TranscriptParsers.swift`): JSONL parsers for Claude Code and Codex CLI formats. Used by HooverEngine during ingestion (JSONL → DB).
- **ConversationMonitor**: Consumes parsed entries from SQL; **does not parse JSONL**.
- **IMPORTANT:** For all transcript parsing, format differences, and JSON structure details, **ALWAYS consult** `build/docs/archive/completed-work/technical-briefing-local-history-claude-code-codex.md`
  - Documents Claude Code vs Codex JSONL format differences (lines 118-131)
  - Record type taxonomy and field shapes (lines 47-115)
  - Parsing strategies for both formats (lines 177-192)
  - Content block types: Claude Code uses `text`, Codex uses `input_text`/`output_text`
  - Message structure: Claude Code has top-level `uuid`/`type`, Codex wraps in `payload.type:"message"`
- **ConversationSources** (`Contextify/Contextify/ConversationSources.swift`): Provider-specific session discovery (Claude Code, Codex CLI)
- **TranscriptMetadataOrchestrator** (`Contextify/Contextify/TranscriptMetadataOrchestrator.swift`): Coordinates LLM-based metadata generation for transcripts (titles, descriptions, topics).
- **SidecarMetadataStore** (`Contextify/Contextify/SidecarMetadataStore.swift`): JSON sidecar file persistence for transcript metadata.

### Transcript Corruption (Claude Code Web)
**Issue:** Claude Code Web "teleport" feature can corrupt transcripts, causing API 400 errors when resuming sessions.

**Common symptoms:**
- `API Error 400: unexpected tool_use_id found in tool_result blocks`
- Session works in web but fails in CLI after teleport
- Orphaned tool_result blocks, stop_reason mismatches, broken parent chains

**Detection & Repair:**
```bash
# Analyze transcript (no changes)
python3 scripts/transcript-repair/repair_transcript.py <transcript> --dry-run

# Repair transcript (creates .backup)
python3 scripts/transcript-repair/repair_transcript.py <transcript>
```

**Documentation:**
- Full guide: `build/docs/operations/transcript-corruption-detection.md`
- Script README: `scripts/transcript-repair/README.md`
- Format spec: `build/docs/specifications/claude-code-format.md`

## Build, Test, and Development Commands

**Primary build script:** `bash scripts/xc.sh build` (auto-detects Xcode-beta if installed)

### Building on Linux / Non-macOS Environments

**For Claude Code Web users and Linux environments:**

Since Contextify is a macOS-only project requiring Xcode, builds from Linux environments must use **on-demand GitHub Actions** with macOS runners.

#### Recommended: Use the Trigger Script (No gh CLI needed!)

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

#### Alternative: Using gh CLI

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

**Viewing Build Results:**

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

### macOS Build Commands

Common commands:
- Build and run: `make build` or `bash scripts/xc.sh build`
- Build and run with developer mode: `bash scripts/xc.sh --dev build` (enables test buttons)
- Build only (no launch): `CTX_NO_RUN=1 bash scripts/xc.sh build` (for CI/verification)
- Test: `make test` or `bash scripts/xc.sh test`
- Clean: `make clean` (removes DerivedData)
- Full setup with hooks: `make setup`

**Note:** Build commands launch the app by default. Use `CTX_NO_RUN=1` to skip launching.

**First-run QA testing (CLI-only toolkit):**
- **Complete guide:** `build/docs/testing/first-run-qa-guide.md`
- Seed demo fixtures: `bash scripts/xc.sh seed-demo`
- DMG first-run (unsandboxed): `bash scripts/xc.sh --dist=dmg Debug cleanrun`
- App Store first-run (sandboxed): `bash scripts/xc.sh --dist=appstore Debug cleanrun`
- Reset permissions only: `bash scripts/xc.sh reset-perms`
- Reset app state only: `bash scripts/xc.sh reset-state`
- Reset all (perms + state): `bash scripts/xc.sh reset-all`
- Stream app logs: `bash scripts/xc.sh logs`
- **Distribution modes:**
  - `--dist=dmg` (default): Unsandboxed build, fast path for testing
  - `--dist=appstore`: Sandboxed build, requires permission grants
- **Use cases:**
  - Test onboarding flow (Permissions → Discovery → Indexing → Auto-dismiss)
  - Verify TCC permission handling (gated vs ungated locations)
  - Test security-scoped bookmarks (App Store builds)
  - Reproducible testing with demo fixtures (<10s runs)

**Log capture for debugging:**
- Capture last 5 min: `make logs` → `/tmp/contextify-recent.log`
- Stream live: `make logs-live` → `/tmp/contextify-live.log`
- Build + capture: `make debug` → `build/logs/runtime/contextify-YYYYMMDD-HHMMSS.log`

**Database management:**
- ⚠️  **IMPORTANT:** ALWAYS use `scripts/db_manager.sh` for database operations
- ⚠️  **NEVER** delete database files manually with `rm` while app is running
- Database location: `~/Library/Application Support/Contextify/contextify.db` (default)
  - **Custom locations supported** via Settings > Database tab
  - Supports Dropbox, iCloud Drive, or any user-selected directory
  - Migration preserves all data (copies db, wal, shm files)
  - Multi-machine conflict detection warns of concurrent access
- Clean database (creates backup): `make clean-db` or `./scripts/db_manager.sh clean`
- Create backup: `make db-backup` or `./scripts/db_manager.sh backup`
- Restore latest: `make db-restore` or `./scripts/db_manager.sh restore latest`
- List backups: `make db-list` or `./scripts/db_manager.sh list`
- Re-ingest transcript: `./scripts/db_manager.sh reingest <transcript-id>` (resets checkpoint and re-parses JSONL file)
- Backups stored in: `build/db-backups/`
- **Agent rule:** ALWAYS ask user for approval before cleaning database

**For detailed debugging workflows:** See `scripts/logging/README.md` (primary debugging toolkit) and `scripts/QUICK-REFERENCE.md`

**Diagnostics HTTP API (DEBUG builds only):**
- API runs on `http://localhost:17329` when app is running
- Endpoints:
  - `GET /health` - Check if API is responding
  - `GET /diagnostics` - Full diagnostic snapshot (project state, watcher, hoover, timeline, issues)
  - `GET /timeline/recent?count=N` - Recent N entries (default 10)
  - `GET /timeline/latest` - Most recent entry
- Helper script: `./scripts/timeline_api.sh status|latest|recent|watch`
- Entry fields: `role` (user/assistant), `present_summary`, `content`, `timestamp`, `is_generating`, `is_error`
- Use for debugging timeline state, hoover lag, LLM generation issues

**Release workflow (macOS only):**
- Build Release configuration: `make build-release` or `bash scripts/xc.sh Release build`
- Sign and create DMG: `make sign-dmg` (production) or `make sign-dmg-no-notarize` (testing)
- Full release automation: `make release` (interactive workflow)
- Preview release: `make release-dry-run` (shows what would happen)
- ⚠️  **IMPORTANT:** Default `make build` uses **Debug** configuration. Always use `make build-release` for distribution!
- **Detailed guide:** See `scripts/RELEASE.md` for complete release documentation

**Build output:** `.derived/Build/Products/Debug/Contextify.app` (Debug) or `.derived/Build/Products/Release/Contextify.app` (Release)

- Logs/Results: script writes logs to `build/logs/` and result bundles to `build/ResultBundles/`. Use these for error triage; builds fail fast on non-zero.
- Direct (beta): `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Contextify/Contextify.xcodeproj -scheme Contextify -destination 'platform=macOS' build`
- Xcode GUI: open `Contextify/Contextify.xcodeproj`, scheme `Contextify`, Run on "My Mac"

## Git Hooks (Pre-commit Build Guard)
- Enable hooks: `git config core.hooksPath .githooks`
- Behavior: when files under `Contextify/` are staged, the pre-commit hook runs `scripts/xc.sh build` (using Xcode‑beta if present). If the build fails, the commit is blocked; check logs under `build/logs/` and `.xcresult` under `build/ResultBundles/`.

## Coding Style & Naming Conventions
- Swift: 2‑space indent; follow Swift API Design Guidelines. Types `UpperCamelCase`, methods/vars `lowerCamelCase`.
- Concurrency (Swift 6): use async/await, structured `Task`s, `@MainActor` for UI, `Sendable` where crossing threads; avoid detached tasks.
- State: prefer Observation (`@Observable`) or `@StateObject` ViewModels; keep Views declarative and side‑effect‑free.
- Availability: isolate new APIs behind small adapters; `#available(macOS 26, *)` guards with working fallbacks.
- Python (if present): Black (line length 88), isort, flake8; snake_case for functions/vars, PascalCase for classes.
- File/dir names: kebab‑case for non‑code folders (e.g., `docs/sessions/active/`).
- Keep modules small; separate UI (Views), state (ViewModels), and services.

## UI/UX Design Guidelines

**Design specs:** `build/docs/design/` (color scheme, typography, patterns)
**Color scheme:** `build/docs/design/color-scheme.md` | Implementation: `TimelineEntryRow.swift:192-206`

## Logging Guidelines

**Framework:** Use `OSLog` with `Logger(subsystem: "dev.contextify", category: "CategoryName")`

**Two-Phase Approach:**
1. **Development:** Use `.info` generously to track execution flow; `.debug` for verbose details
2. **Pre-merge:** Move routine operations to `.debug`; keep `.info` only for significant state changes

**Level Usage:**
- `.debug` - Normal operation, success paths (hidden with `TYPE Info` filter)
- `.info` - Significant state changes (e.g., "Watching transcript: [file]", session switches)
- `.warning` - Retries, fallbacks, recoverable issues (e.g., "LLM retry 2/3")
- `.error` - Failures requiring intervention (parse errors, missing files)
- `.fault` - Use `assertionFailure()` instead

**Special Cases:**
- Retry logic: first attempt `.debug`, retries 1+ use `.warning`
- Initialization: key steps `.info`, routine sub-steps `.debug`
- Emojis: use sparingly in development; remove before merge (except error indicators)

Configure Xcode console with `TYPE Info` filter to hide debug logs in production.

**Detailed reference:** See `build/docs/guides/logging-best-practices.md` for comprehensive guidelines, code examples, and anti-patterns.

## Debugging Workflows

**Primary resource:** `scripts/logging/README.md` - Complete debugging toolkit with automated test harnesses

When encountering bugs or issues:

1. **Choose debugging pattern** based on symptom:
   - **Feature not appearing in UI** → Pipeline Completeness Check (`scripts/logging/monitor-pipeline-check.sh`)
   - **Need to verify bug fix** → Automated Test Harness (`scripts/logging/monitor-automated-test.sh`)
   - **App slow/laggy** → Gap Analysis (`scripts/logging/monitor-interactive.sh` + `analyze-gaps.sh`)
   - **Exploring unknown issue** → Interactive Monitoring (`scripts/logging/monitor-interactive.sh`)

2. **Prefer automated approaches** that generate pass/fail reports without human interpretation

3. **See full documentation:** `scripts/logging/README.md` contains:
   - Quick dispatch table (symptom → script)
   - 5 debugging patterns with usage examples
   - Self-validating test harness templates
   - LLM-optimized workflow guidance

**Additional debugging resources:**
- Log capture: `scripts/QUICK-REFERENCE.md`, `scripts/LOG-CAPTURE-README.md`
- Logging conventions: `build/docs/guides/logging-best-practices.md`
- Debugging case study: `build/notes/research/debugging-setup-2025-11-08.md`

## Testing Guidelines
- **XCTest** (or Swift Testing) under `ContextifyTests/` for app modules
- Key test files:
  - `GitDetectionTests.swift`: Git resolution, worktree handling, HEAD parsing
  - `ContextifyTests.swift`: HUD view model tests
  - `TestHelpers.swift`: Shared test utilities
- Use `pytest` for CLI utilities under `cli/tests/` with `test_*.py` files (if present)
- Prefer fast, deterministic tests; include minimal fixtures under `tests/fixtures/`
- Target: tests for every feature; smoke tests for HUD launch and file ingest

## Project Setup Recommendation
- Preferred (interactive): create a new macOS App (SwiftUI) in Xcode 16, name `ContextifyHUD`, Base SDK `macOS 26`, min `macOS 14/15`. This ensures correct signing, targets, previews, and SDK selection. After creation, we add Views/ViewModels and tests via PRs.
- Alternative (sample‑based): start from an Apple SwiftUI macOS sample that demonstrates drag & drop or `DocumentGroup`, then replace the root view with our HUD and keep the project settings. Avoid iOS‑only samples.
- Avoid: generating `.xcodeproj` by hand in CI; Xcode manages capabilities and schemes more reliably.

## Persistence & Project Root Resolution

**Startup precedence (init):**
1. Security-scoped bookmark (sandboxed)
2. Persisted path from UserDefaults
3. Falls back to no project

**Runtime update precedence (`updateGitInfo`):**
1. `CONTEXTIFY_PROJECT_ROOT` environment variable
2. Persisted path (if bookmark or saved path exists)
3. Current working directory (CWD)
4. Existing project root (if already set)

**Backward compatibility:** Out of scope. Remove legacy migrations; assume clean builds with no user data.

## Git Monitoring

- Uses file watchers on `.git/HEAD`, resolved ref file (e.g., `.git/refs/heads/main`), and `.git/packed-refs`
- Sandboxed: parses HEAD directly (no git subprocess)
- Non-sandboxed: runs `git rev-parse --abbrev-ref HEAD` with 2s timeout, falls back to HEAD parsing
- Handles worktrees (`.git` file with `gitdir:` pointer)
- Debounces events (150ms) and re-arms watchers on file deletion/rename

## File Output Structure

- Outputs: `~/Contextify/outputs` (or `$CONTEXTIFY_OUTPUTS_DIR` if set; `Application Support/Contextify/outputs` in sandbox)
- Ingested files copied to `outputs/ingest/` with timestamp prefix
- Artifacts: `outputs/{timestamp}.md` (file/URL metadata)
- Checkpoints: `outputs/checkpoints/checkpoint-{session}-{timestamp}.md`

## Database Location Discovery

**IMPORTANT:** Users can customize the database location via Settings > Database tab. ALWAYS check for custom location before querying the database.

**Location precedence:**
1. **Custom location** (if set by user): Check UserDefaults for custom path, or query the running app
2. **Default location**: `~/Library/Application Support/Contextify/contextify.db`
3. **Sandboxed container** (if sandbox enabled): `~/Library/Containers/PeterPym.Contextify*/Data/Library/Application Support/Contextify/contextify.db`

**How to find the active database:**
```bash
# Method 1: Check UserDefaults for custom location (RECOMMENDED)
CUSTOM_DIR=$(defaults read dev.contextify dev.contextify.customDatabaseLocation 2>/dev/null)
if [ -n "$CUSTOM_DIR" ]; then
  DB_PATH="$CUSTOM_DIR/contextify.db"
  echo "Custom location: $DB_PATH"
else
  echo "Default location: ~/Library/Application Support/Contextify/contextify.db"
  DB_PATH="$HOME/Library/Application Support/Contextify/contextify.db"
fi

# Method 2: Find all databases and use most recently modified
find ~/Library -name "contextify.db" -type f 2>/dev/null -exec ls -lt {} + | head -1

# Method 3: Check all common locations
find ~/Library/Application\ Support/Contextify -name "contextify.db" 2>/dev/null
find ~/Library/Containers -name "contextify.db" 2>/dev/null
find ~/Library/CloudStorage -name "contextify.db" 2>/dev/null  # Dropbox/iCloud
```

**Common custom locations:**
- Dropbox: `~/Library/CloudStorage/Dropbox/*/contextify.db`
- iCloud Drive: `~/Library/Mobile Documents/com~apple~CloudDocs/*/contextify.db`
- External drive: `/Volumes/*/contextify.db`

**Note:** When users change database locations, the old database file remains in place (not deleted). Always use the most recently modified database file.

## Quickstart For Agents
- Ensure Xcode 16 (or Xcode-beta) is installed and selected by the script (it auto-detects)
- Build once: `bash scripts/xc.sh build`
- If CLI fails, verify: `xcodebuild -version` and `xcode-select -p` (set `DEVELOPER_DIR` or use Xcode GUI)
- **Database location:** Always check for custom database location (see "Database Location Discovery" above)
- Keep PRs small; rely on CI (macOS build workflow) to validate changes
- Never run destructive git commands (e.g., `git restore`, `reset --hard`, `clean`) on a teammate's work without first creating a backup branch or patch; preserve in-progress changes at all costs
- NEVER delete or clean tracked files without a backup branch/patch that has been coordinated with the user

## Commit & Pull Request Guidelines
- Commits: Conventional Commits (e.g., `feat(hud): add drop target`, `fix(cli): checkpoint writes timestamp`).
- Scope small, descriptive commits; prefer present tense, imperative mood.
- Keep commits atomic—each commit should represent a single logical change; never bundle unrelated edits.
- Do not attribute work to Codex (or other agents) in commit messages, PR descriptions, or change logs; keep authorship human-focused.
- PRs: clear summary, linked issues, screenshots/GIFs for UI, reproduction or acceptance steps, and notes on risks.
- Require passing checks and reviewer approval before merge; rebase onto `main`.

## Security & Configuration Tips
- Default to no network access unless explicitly enabled; avoid committing secrets.
- Session data belongs under `<project>/docs/sessions/` and may be versioned; do not store sensitive user data there.
- Log minimally with timestamps; exclude local paths or tokens.

## Transcript Analysis Workflow (For Agents)

When working with Claude Code transcript files, **ALWAYS classify first** before analyzing structure:

### Classification Scripts

**Simple (fast):**
```bash
./scripts/classify_transcript.sh <transcript-id-or-file-path>
```
Returns: `"conversational"` | `"metadata-only"` | `"empty"`

**Detailed (multi-dimensional):**
```bash
./scripts/classify_transcript_detailed.sh <transcript-id-or-file-path>
```
Returns: Primary classification + 4 dimensional axes (conversation, metadata, content_flags, state)

### Agent Workflow

**Step 1: Classify**
```bash
./scripts/classify_transcript.sh A31F3D0A-4820-41AB-8121-0C81AC8533C4
```

**Step 2: Read Relevant Documentation**

| Classification | Read These Sections | Parser Fields |
|---------------|---------------------|---------------|
| **conversational** | `claude-code-transcript-format.md` §1-2 (User/Assistant Messages) | `uuid`, `timestamp`, `type`, `message` |
| **metadata-only** | `claude-code-transcript-format.md` §3-5 (File-History, Summary, System) | `messageId`, `snapshot`, `trackedFileBackups` |
| **empty** | (no further analysis) | (none) |

**Step 3: Reference Implementation**
- Parser: `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`
- Database: `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`

**Key Document:** `build/docs/specifications/claude-code-format.md` contains:
- Complete field specifications for all record types
- Transcript Classification Guide (§ at end)
- Field Reference by Classification table
- Content block types and structures

**DO NOT** guess at transcript structure - classify first, then read the appropriate section.

## Project File Locations

- Main project: `Contextify/Contextify.xcodeproj`
- Source: `Contextify/Contextify/*.swift`, `app/Sources/ContextifyCore/*.swift`
- Tests: `Contextify/ContextifyTests/*.swift`, `Contextify/ContextifyUITests/*.swift`
- Scripts: `scripts/xc.sh`, `scripts/classify_transcript.sh`, `scripts/db_manager.sh`
- Hooks: `.githooks/pre-commit`

## Useful References (Apple)
- SwiftUI `onDrop`: https://developer.apple.com/documentation/swiftui/view/ondrop(of:isTargeted:perform/)
- Transferable (modern data): https://developer.apple.com/documentation/coretransferable/transferable
- MenuBarExtra: https://developer.apple.com/documentation/swiftui/menubarextra
- DocumentGroup: https://developer.apple.com/documentation/swiftui/documentgroup
- Testing (Swift Testing/XCTest): https://developer.apple.com/documentation/testing
