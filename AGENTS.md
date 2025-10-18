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
- **TranscriptOrchestrator** (`app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`): High-level coordinator for all database operations. Provides async API for projects, transcripts, entries, and timeline cache.
- **DatabaseManager** (`app/Sources/ContextifyCore/Database/DatabaseManager.swift`): Singleton managing GRDB connection pool, migrations, and WAL mode.
- **HooverEngine** (`app/Sources/ContextifyCore/Database/HooverEngine.swift`): Streaming transcript ingestion engine. Processes JSONL files incrementally with crash-safe checkpointing.
- **Repositories** (`app/Sources/ContextifyCore/Database/Repositories.swift`): Type-safe GRDB repositories (ProjectRepository, TranscriptRepository, EntryRepository, TimelineCacheRepository).
- **DatabaseSchema** (`app/Sources/ContextifyCore/Database/DatabaseSchema.swift`): SQL schema definitions and versioned migrations.
- **TranscriptWatcher** (`app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`): File system monitoring for real-time transcript updates.
- **Models** (`app/Sources/ContextifyCore/Database/Models.swift`): Codable/Sendable database models (Project, Transcript, Entry, TimelineCache, etc.).
- **Documentation**:
  - Usage guide: `app/Sources/ContextifyCore/Database/README.md`
  - Architecture: `build/notes/technical-reference/sql-backend-architecture.md`

### Timeline & LLM Integration
- **ConversationMonitor** (`Contextify/Contextify/ConversationMonitor.swift`): Main `@Observable` `@MainActor` component for timeline display. Manages TimelineState, visible entries, and session filtering. Integrates with SQL backend via TranscriptOrchestrator.
- **TimelineCacheMissGenerator** (`Contextify/Contextify/TimelineCacheMissGenerator.swift`): LLM-powered summary generation for cache misses. Uses FoundationLLM (Apple Intelligence) to generate present/past form summaries.
- **FoundationLLM** (`Contextify/Contextify/FoundationLLM.swift`): Integration with Apple's LanguageModel/FoundationModels. **Requires macOS 26.0+**. On older macOS, the system falls back to basic summaries (no LLM).
- **TimelineModels** (`Contextify/Contextify/TimelineModels.swift`): Timeline-specific data models (TimelineEntry, CacheKey, Disposition).
- **TimelineState** (`ConversationMonitor.swift`): Observable state container for timeline entries, derived cache index, and revision tracking.
- **Documentation**:
  - Cache + LLM: `build/notes/technical-reference/timeline-cache-llm-architecture.md`
  - State management: `build/notes/technical-reference/conversation-monitor-state-architecture.md`

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
- **ComposeURLRouter/ComposeWindowManager** (`Contextify/Contextify/ComposeURLRouter.swift`, `ComposeWindowManager.swift`): URL routing and compose window lifecycle (automation support).
- **ITerm2Bridge** (`Contextify/Contextify/ITerm2Bridge.swift`): iTerm2 integration for shell bindings.

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

Common commands:
- Build: `make build` or `bash scripts/xc.sh build`
- Test: `make test` or `bash scripts/xc.sh test`
- Clean: `make clean` (removes DerivedData)
- Full setup with hooks: `make setup`

**Log capture for debugging:**
- Capture last 5 min: `make logs` → `/tmp/contextify-recent.log`
- Stream live: `make logs-live` → `/tmp/contextify-live.log`
- Build + capture: `make debug` → `build/logs/runtime/contextify-YYYYMMDD-HHMMSS.log`
- Clean database: `make clean-db`

**For detailed debugging workflows:** See `scripts/QUICK-REFERENCE.md` and `scripts/LOG-CAPTURE-README.md`

**Build output:** `.derived/Build/Products/Debug/Contextify.app`

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

## Quickstart For Agents
- Ensure Xcode 16 (or Xcode-beta) is installed and selected by the script (it auto-detects)
- Build once: `bash scripts/xc.sh build`
- If CLI fails, verify: `xcodebuild -version` and `xcode-select -p` (set `DEVELOPER_DIR` or use Xcode GUI)
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

## Project File Locations

- Main project: `Contextify/Contextify.xcodeproj`
- Source: `Contextify/Contextify/*.swift`, `app/Sources/ContextifyCore/*.swift`
- Tests: `Contextify/ContextifyTests/*.swift`, `Contextify/ContextifyUITests/*.swift`
- Scripts: `scripts/xc.sh`, `scripts/install-shell-bindings.sh`
- Hooks: `.githooks/pre-commit`

## Useful References (Apple)
- SwiftUI `onDrop`: https://developer.apple.com/documentation/swiftui/view/ondrop(of:isTargeted:perform/)
- Transferable (modern data): https://developer.apple.com/documentation/coretransferable/transferable
- MenuBarExtra: https://developer.apple.com/documentation/swiftui/menubarextra
- DocumentGroup: https://developer.apple.com/documentation/swiftui/documentgroup
- Testing (Swift Testing/XCTest): https://developer.apple.com/documentation/testing
