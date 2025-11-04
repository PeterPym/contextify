# Repository Guidelines

DO NOT attribute work to Claude or Codex in commit messages, or as a co-author.
 
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

### Database Layer (SQL Backend)
- **Current Schema Version: v21** (see DatabaseSchema.swift for migration history)
- **Recent Migrations:**
  - **v12-v13**: Epoch timestamps (projects.last_viewed_ts, entries.created_ts)
  - **v14**: Request ID normalization (empty → entry_id fallback)
  - **v15**: Index cleanup and optimization
  - **v16**: GROUP BY index for unread queries (idx_entries_unread_join)
  - **v17-v20**: Schema fixes, file migration, orphaned project tracking
  - **v21**: Database access metadata for multi-machine conflict detection
- **TranscriptOrchestrator** (`app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`): High-level coordinator for all database operations. Provides async API for projects, transcripts, entries, timeline cache, and assistant usage reconciliation.
- **DatabaseManager** (`app/Sources/ContextifyCore/Database/DatabaseManager.swift`): Singleton managing GRDB connection pool, migrations, WAL mode, and custom database locations. Supports bookmark-based access for sandboxed builds.
- **DatabaseMigration** (`app/Sources/ContextifyCore/Database/DatabaseMigration.swift`): Safe database file migration between locations. Handles disk space checks, atomic copies, and validation.
- **DatabaseAccessMetadata** (`app/Sources/ContextifyCore/Database/DatabaseAccessMetadata.swift`): Multi-machine access tracking and conflict detection. Warns users of concurrent access issues.
- **HooverEngine** (`app/Sources/ContextifyCore/Database/HooverEngine.swift`): Streaming transcript ingestion engine. Processes JSONL files incrementally with crash-safe checkpointing. CTE-based FK-safe assistant_usage inserts with O(N+M) JOIN reconciliation.
- **Repositories** (`app/Sources/ContextifyCore/Database/Repositories.swift`): Type-safe GRDB repositories (ProjectRepository, TranscriptRepository, EntryRepository, TimelineCacheRepository, ProjectVisitsRepository).
- **DatabaseSchema** (`app/Sources/ContextifyCore/Database/DatabaseSchema.swift`): SQL schema definitions and versioned migrations (v1-v21).
  - **v8-v9**: project_visits table, unread query indices
  - **v10-v11**: assistant_usage_pending staging, FK hardening
  - **v12-v13**: Epoch timestamps (projects.last_viewed_ts, entries.created_ts), optimizations
  - **v14-v15**: Request ID normalization, index cleanup
  - **v16**: GROUP BY index for unread queries
  - **v17-v20**: Schema fixes, file migration, orphaned project tracking
  - **v21**: database_access_metadata table
- **TranscriptWatcher** (`app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`): File system monitoring for real-time transcript updates.
- **Models** (`app/Sources/ContextifyCore/Database/Models.swift`): Codable/Sendable database models (Project, Transcript, Entry, TimelineCache, AssistantUsage, etc.).
- **ProjectVisitsRepository** (`app/Sources/ContextifyCore/Database/ProjectVisitsRepository.swift`): Unread tracking and visit timestamps per project.
- **Documentation**:
  - Usage guide: `app/Sources/ContextifyCore/Database/README.md`
  - Architecture: `build/notes/technical-reference/sql-backend-architecture.md`
  - Custom location feature: `build/notes/feature-specs/custom-database-location/spec.md`

### LLM Processing & Timeline Integration
Contextify uses **two independent LLM processing queues** for content generation (both using Apple Intelligence/FoundationLLM on macOS 26+):

1. **Timeline Summary Generation** - Entry-level summaries (present/past forms)
2. **Transcript Metadata Generation** - Document-level titles, descriptions, topics

**Key Components:**
- **ConversationMonitor** (`Contextify/Contextify/ConversationMonitor.swift`): Main `@Observable` `@MainActor` component for timeline display. Manages TimelineState, visible entries, and session filtering. Integrates with SQL backend via TranscriptOrchestrator.
- **TimelineCacheMissGenerator** (`Contextify/Contextify/TimelineCacheMissGenerator.swift`): Queue #1 - Batched FIFO processing for timeline entry summaries. Generates present/past forms with batching and rate limiting.
- **TranscriptMetadataOrchestrator** (`Contextify/Contextify/TranscriptMetadataOrchestrator.swift`): Queue #2 - Concurrent task processing for transcript titles/descriptions/topics. Includes circuit breaker and SQL caching.
- **FoundationLLM** (`Contextify/Contextify/FoundationLLM.swift`): Shared integration with Apple's LanguageModel/FoundationModels. **Requires macOS 26.0+**. On older macOS, systems fall back to heuristics (no LLM).
- **StatusBar** (`Contextify/Contextify/StatusBarView.swift`, `StatusBarViewModel.swift`): Aggregates both LLM queues for unified monitoring. Shows processing status, pending counts, ETAs, and errors.
- **TimelineModels** (`Contextify/Contextify/TimelineModels.swift`): Timeline-specific data models (TimelineEntry, CacheKey, Disposition).
- **TimelineState** (`ConversationMonitor.swift`): Observable state container for timeline entries, derived cache index, and revision tracking.
- **Documentation**:
  - **⭐ LLM Architecture Overview:** `build/notes/technical-reference/llm-processing-architecture.md` (start here)
  - Timeline cache + LLM: `build/notes/technical-reference/timeline-cache-llm-architecture.md`
  - State management: `build/notes/technical-reference/conversation-monitor-state-architecture.md`
  - Status bar spec: `build/notes/feature-specs/status-bar/spec-final.md`

### Core Components (Project Context)
- **HUDViewModel** (`app/Sources/ContextifyCore/HUDCore.swift:370-1032`): Main `@Observable` `@MainActor` view model. Manages:
  - Project root detection (environment → persisted → CWD → existing)
  - Git repository discovery and branch monitoring via file watchers
  - File/URL ingestion with Markdown artifact generation
  - Session and checkpoint management
  - Security-scoped bookmarks for sandboxed access

- **GitRepositoryResolver** (`app/Sources/ContextifyCore/HUDCore.swift:142-368`): Git repository detection. Finds `.git` root, parses HEAD (handles detached state, worktrees), and executes `git rev-parse` with timeout/fallback.

- **HUDPreferences** (`app/Sources/ContextifyCore/HUDCore.swift:13-126`): Manages UserDefaults with suite fallback. Stores project root path and security-scoped bookmarks.

### UI Layer
- **ContentView** (`Contextify/Contextify/ContentView.swift`): Main UI with header (project/branch display, "Set Project Root" button), URL entry field, drop zone, controls (New Session, Checkpoint, Reveal Outputs), and toast notifications.
- **ConversationTimelineView** (`Contextify/Contextify/ConversationTimelineView.swift`): Timeline display UI with session filtering and real-time updates.
- **TimelineEntryRow** (`Contextify/Contextify/TimelineEntryRow.swift`): Individual timeline entry row component.
- **TranscriptInventoryView** (`Contextify/Contextify/TranscriptInventoryView.swift`): UI for browsing and switching between transcript sessions.
- **IngestDropZone** (`Contextify/Contextify/IngestDropZone.swift`): Drag-and-drop target for files, uses SwiftUI `onDrop` with completion handlers and main actor marshaling.

### Supporting Components
- **WindowTitleWriter** (`Contextify/Contextify/WindowTitleWriter.swift`): Updates window title to show current project name.
- **SystemInfo** (`Contextify/Contextify/SystemInfo.swift`): System information utilities (machine ID, support email).

> **Note:** iTerm2/terminal integration (ITerm2Bridge, ComposeWindowManager, GlobalHotkeyManager) was removed in commit 35ce380 for App Store compliance. See `build/notes/future-features.md` "Removed Features" section for re-implementation guidance if needed.

### Transcript Parsing & Metadata
- **TranscriptParsers** (`app/Sources/ContextifyCore/Database/TranscriptParsers.swift`): JSONL parsers for Claude Code and Codex CLI formats. Used by HooverEngine during ingestion (JSONL → DB).
- **ConversationMonitor**: Consumes parsed entries from SQL; **does not parse JSONL**.
- **IMPORTANT:** For all transcript parsing, format differences, and JSON structure details, **ALWAYS consult** `build/notes/archive/technical-briefing-local-history-claude-code-codex.md`
  - Documents Claude Code vs Codex JSONL format differences (lines 118-131)
  - Record type taxonomy and field shapes (lines 47-115)
  - Parsing strategies for both formats (lines 177-192)
  - Content block types: Claude Code uses `text`, Codex uses `input_text`/`output_text`
  - Message structure: Claude Code has top-level `uuid`/`type`, Codex wraps in `payload.type:"message"`
- **ConversationSources** (`Contextify/Contextify/ConversationSources.swift`): Provider-specific session discovery (Claude Code, Codex CLI)
- **TranscriptMetadataOrchestrator** (`Contextify/Contextify/TranscriptMetadataOrchestrator.swift`): Coordinates LLM-based metadata generation for transcripts (titles, descriptions, topics).
- **SidecarMetadataStore** (`Contextify/Contextify/SidecarMetadataStore.swift`): JSON sidecar file persistence for transcript metadata.

## Build, Test, and Development Commands

**Primary build script:** `bash scripts/xc.sh build` (auto-detects Xcode-beta if installed)

### Building on Linux / Non-macOS Environments

**For Claude Code Web users and Linux environments:**

Since Contextify is a macOS-only project requiring Xcode, builds from Linux environments must use **on-demand GitHub Actions** with macOS runners. The build script (`scripts/xc.sh`) automatically detects non-macOS environments and guides you through the process.

**Quick Start:**

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

**For detailed debugging workflows:** See `scripts/QUICK-REFERENCE.md` and `scripts/LOG-CAPTURE-README.md`

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

**Design specs:** `build/notes/design-reference/` (color scheme, typography, patterns)
**Color scheme:** `build/notes/design-reference/color-scheme.md` | Implementation: `TimelineEntryRow.swift:192-206`

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

**Detailed reference:** See `build/notes/technical-reference/logging-preferences.md` for comprehensive guidelines, code examples, and anti-patterns.

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

**Key Document:** `build/notes/technical-reference/claude-code-transcript-format.md` contains:
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
