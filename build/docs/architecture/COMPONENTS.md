# Architecture & Key Components

This document provides detailed information about Contextify's architecture and key components, including:
- Component roles (Coordinator vs Orchestrator vs Monitor)
- Data model hierarchy (Projects → Transcripts → Entries → Summaries)
- Initialization flow and common patterns

---

## Performance Summary

**Startup Performance:**
- **Cold start:** <200ms (target) | 187ms (achieved)
- **UI ready:** Immediate after lightweight scan (no ingestion blocking)
- **First project selection:** <1s (JIT ingestion)

**Memory Footprint:**
- **At startup:** 30-50 MB
- **After first project load:** 60-100 MB

**Database Operations:**
- **At startup:** 19 row updates (projects metadata only)

**Lazy Loading:**
- **Discovery:** Stat-only filesystem scan (no JSONL parsing)
- **Ingestion:** On-demand (JIT) when user selects project
- **Background:** Low-priority pre-ingestion of inactive projects

---

## Database Layer (SQL Backend)

- **Current Schema Version: v39** (see DatabaseSchema.swift for migration history)

### Recent Migrations

- **v12-v13**: Epoch timestamps (projects.last_viewed_ts, entries.created_ts)
- **v14**: Request ID normalization (empty → entry_id fallback)
- **v15**: Index cleanup and optimization
- **v16**: GROUP BY index for unread queries (idx_entries_unread_join)
- **v17-v20**: Schema fixes, file migration, orphaned project tracking
- **v21**: Database access metadata for multi-machine conflict detection
- **v22**: Strategy constraint fix (transcript_metadata.generation_strategy)
- **v23**: Active transcript follow (project_follow_policy table)

### Key Components

**TranscriptOrchestrator** (`app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`):
- High-level coordinator for all database operations
- Provides async API for projects, transcripts, entries, timeline cache, and assistant usage reconciliation

**DatabaseManager** (`app/Sources/ContextifyCore/Database/DatabaseManager.swift`):
- Singleton managing GRDB connection pool, migrations, WAL mode, and custom database locations
- Supports bookmark-based access for sandboxed builds

**DatabaseMigration** (`app/Sources/ContextifyCore/Database/DatabaseMigration.swift`):
- Safe database file migration between locations
- Handles disk space checks, atomic copies, and validation

**DatabaseAccessMetadata** (`app/Sources/ContextifyCore/Database/DatabaseAccessMetadata.swift`):
- Multi-machine access tracking and conflict detection
- Warns users of concurrent access issues

**HooverEngine** (`app/Sources/ContextifyCore/Database/HooverEngine.swift`):
- Streaming transcript ingestion engine
- Processes JSONL files incrementally with crash-safe checkpointing
- CTE-based FK-safe assistant_usage inserts with O(N+M) JOIN reconciliation

**Repositories** (`app/Sources/ContextifyCore/Database/Repositories.swift`):
- Type-safe GRDB repositories (ProjectRepository, TranscriptRepository, EntryRepository, TimelineCacheRepository, ProjectVisitsRepository)

**DatabaseSchema** (`app/Sources/ContextifyCore/Database/DatabaseSchema.swift`):
- SQL schema definitions and versioned migrations (v1-v39)
- **v8-v9**: project_visits table, unread query indices
- **v10-v11**: assistant_usage_pending staging, FK hardening
- **v12-v13**: Epoch timestamps (projects.last_viewed_ts, entries.created_ts), optimizations
- **v14-v15**: Request ID normalization, index cleanup
- **v16**: GROUP BY index for unread queries
- **v17-v20**: Schema fixes, file migration, orphaned project tracking
- **v21**: database_access_metadata table
- **v22**: Strategy constraint fix (transcript_metadata.generation_strategy)
- **v23**: Active transcript follow (project_follow_policy table)
- **v27**: queued message tracking (`transcript_entries.is_queued`)
- **v28**: FTS5 search index for conversation search
- **v29**: include summaries in FTS
- **v30**: sidechain ingestion (`transcript_entries.is_sidechain`) + `tool_invocations` table
- **v31**: pending_rehoover for lazy watchers
- **v32**: lazy watcher baseline tracking (`transcripts.known_last_entry_ts`, `known_file_size`, `unread_approx_count`, `unread_approx_confidence`, `unread_approx_updated_at`, `last_activity_detected_at`, `projects.last_activity_detected_at`)
- **v33**: ingestion_runs table for CLI debugging
- **v39**: transcript_tags table (composite PK: transcript_id, tag) for transcript tagging

**TranscriptWatcher** (`app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`):
- File system monitoring for real-time transcript updates
- Uses DispatchSource per-file; started via `ensureProjectWatcher()` at app startup
- Health check recovery restores all watchers if any are missing

**Models** (`app/Sources/ContextifyCore/Database/Models.swift`):
- Codable/Sendable database models (Project, Transcript, Entry, TimelineCache, ToolInvocation, AssistantUsage, etc.)

**ProjectVisitsRepository** (`app/Sources/ContextifyCore/Database/ProjectVisitsRepository.swift`):
- Unread tracking and visit timestamps per project

### Documentation

- Architecture: `build/docs/architecture/sql-backend.md`
- Database migration: `build/docs/components/database-migration.md`
- Custom location feature: Shipped (see Settings > Database tab)

---

## LLM Processing & Timeline Integration

Contextify uses **two independent LLM processing queues** for content generation (both using Apple Intelligence/FoundationLLM on macOS 26+):

1. **Timeline Summary Generation** - Entry-level summaries (present/past forms)
2. **Transcript Metadata Generation** - Document-level titles, descriptions, topics

### Key Components

**ConversationMonitor** (`Contextify/Contextify/ConversationMonitor.swift`):
- Main `@Observable` `@MainActor` component for timeline display
- Manages TimelineState, visible entries, and session filtering
- Integrates with SQL backend via TranscriptOrchestrator
- **Note:** Planned future refactoring into 4 focused components (see architecture-refactoring-analysis.md):
  - ConversationMonitor (400 lines) - Timeline coordination only
  - TimelineLoader (300 lines) - Database queries & pagination
  - WatcherBudgetCoordinator (250 lines) - Watcher lifecycle (extracted)
  - TimelineCacheCoordinator (200 lines) - LLM queue management

**WatcherBudgetCoordinator** (`app/Sources/ContextifyCore/Coordination/WatcherBudgetCoordinator.swift`):
- Single lifecycle authority for transcript watchers
- Implements tiered budget system: HOT (20 transcripts), WARM (10 each), COLD (0)
- Manages LRU tracking for 3 most recently activated projects
- Applies plan → diff → apply algorithm to enforce watcher budgets
- Triggers activation catch-up rehoover for missed changes during COLD state
- Recency-based watching: Only monitors most recent transcripts within projects, not all
- See: [lazy-watchers-architecture.md](lazy-watchers-architecture.md) for detailed diagrams and design rationale

**TimelineCacheMissGenerator** (`Contextify/Contextify/TimelineCacheMissGenerator.swift`):
- Queue #1 - LIFO processing for timeline entry summaries
- Generates present/past forms with viewport-based pruning and overload protection

**TranscriptMetadataOrchestrator** (`Contextify/Contextify/TranscriptMetadataOrchestrator.swift`):
- Queue #2 - LIFO queue with viewport-aware pruning for transcript titles/descriptions/topics
- Sequential processing with circuit breaker and SQL caching

**FoundationLLM** (`Contextify/Contextify/FoundationLLM.swift`):
- Shared integration with Apple's LanguageModel/FoundationModels
- **Requires macOS 26.0+**
- On older macOS, systems fall back to heuristics (no LLM)

**LLMAvailability** (`Contextify/Contextify/LLMAvailability.swift`):
- Centralized availability check (cached per process, computed once at startup)
- Detects Lite Mode for macOS 15 (Sequoia) users
- Gates all LLM queue operations via `LLMAvailability.current.isLiteMode`
- Supports `-simulate-legacy-macos` launch argument for testing
- See `build/docs/architecture/llm-processing.md` for Lite Mode details

**StatusBar** (`Contextify/Contextify/StatusBarView.swift`, `StatusBarViewModel.swift`):
- Aggregates both LLM queues for unified monitoring
- Shows processing status, pending counts, ETAs, and errors

**TimelineModels** (`Contextify/Contextify/TimelineModels.swift`):
- Timeline-specific data models (TimelineEntry, CacheKey, Disposition)

**TimelineState** (`ConversationMonitor.swift`):
- Observable state container for timeline entries, derived cache index, and revision tracking

**Viewport-driven Summaries**
- Entries join the LLM queue once SwiftUI reports ≥25% visibility (`viewportVisibilityThreshold` in `ConversationTimelineView`/`TranscriptInventoryView`), so partial rows still count.
- `InitialViewportStateMachine` keeps the initial snapshot/fallback handshake deterministic, logging `[SUMM-VIEWPORT-ACCEPTED]`, `[SUMM-VIEWPORT-FALLBACK]`, and ticking fallback counters while replaying pending snapshots only once.
- Recent-visible IDs now expire after ~1 s and are removed as soon as they drop out of the reported viewport, allowing pruning to evict scrolled-off rows without waiting for a different UUID set.
- `TimelineCacheMissGenerator.isEntryQueued` guards `queueVisibleGeneratingEntries`, so repeated fallbacks/replays never requeue the same entry, and `SUMM-QUEUE-SKIP` logs highlight the deduplication.

### Documentation

- **⭐ LLM Architecture Overview:** `build/docs/architecture/llm-processing.md` (start here)
- Timeline cache + LLM: `build/docs/components/timeline-cache.md`
- State management: `build/docs/architecture/conversation-monitor-state.md`
- Status bar: Shipped (see original design in `build/docs/archive/feature-specs/status-bar.md`)

---

## Image Handling (Timeline Media)

Contextify extracts and displays images embedded in Claude Code transcript entries. Images are stored as base64-encoded content blocks in JSONL files and extracted on-demand for timeline display.

### Image Content Block Format

Images in Claude Code transcripts use the following JSON structure:

```json
{
  "type": "image",
  "source": {
    "type": "base64",
    "media_type": "image/png",
    "data": "iVBORw0KGgo..."
  }
}
```

### Key Components

**ImageExtractor** (`Contextify/Contextify/ImageExtractor.swift`):
- Actor-based image extraction from Claude Code transcripts
- Extracts base64-encoded images from JSONL content blocks
- Streaming file I/O with 64KB chunks (no full-file loads)
- Cache: FIFO eviction with dual constraints (100 entries, 100MB total)
- In-flight task deduplication prevents redundant file reads
- Sandbox-aware: Uses TranscriptAccessProvider for App Store builds

**Architecture notes:**
- **Lazy loading:** Images extracted on-demand when timeline entries become visible
- **Caching strategy:** Results cached by entry UUID; oversized entries (>100MB) returned but not cached
- **Sandbox access:** All FileManager operations wrapped in `accessProvider.withAccess()` closure
- **Data models:** ExtractedImage (Sendable) contains decoded data; NSImage conversion on MainActor

**UI Components** (`Contextify/Contextify/ImageThumbnailView.swift`):
- **ImageThumbnailRow:** Displays up to 4 thumbnails inline with overflow indicator
- **ImagePreviewPanelController:** Floating NSPanel for Quick Look-style preview
- **ImagePreviewPanelContent:** SwiftUI view with zoom/pan gestures, keyboard navigation (arrow keys, ESC)

**Integration:**
- TimelineEntryRow calls `ImageExtractor.shared.extractImages()` on appearance
- Preview panel opened via `ImagePreviewPanelController.shared.show()`
- Access provider configured in ContextifyApp.swift during startup

### Cache Management

The ImageExtractor maintains a memory-efficient cache with two constraints:
- **Entry limit:** 100 cached results (FIFO eviction)
- **Byte limit:** 100MB total cached data
- **Oversized handling:** Results >100MB are returned to caller but not cached
- **In-flight deduplication:** Multiple requests for the same entry share a single file read

---

## Core Components (Project Context)

**HUDViewModel** (`app/Sources/ContextifyCore/HUDCore.swift#HUDViewModel`):
- Main `@Observable` `@MainActor` view model
- Manages:
  - Project root detection (environment → persisted → CWD → existing)
  - Git repository discovery and branch monitoring via file watchers
  - Session and checkpoint management
  - Security-scoped bookmarks for sandboxed access

**GitRepositoryResolver** (`app/Sources/ContextifyCore/HUDCore.swift#GitRepositoryResolver`):
- Git repository detection
- Finds `.git` root, parses HEAD (handles detached state, worktrees)
- Executes `git rev-parse` with timeout/fallback

**HUDPreferences** (`app/Sources/ContextifyCore/HUDCore.swift#HUDPreferences`):
- Manages UserDefaults with suite fallback
- Stores project root path and security-scoped bookmarks

---

## Application State Coordination

**AppStateOrchestrator** (`app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift`):
- Central coordinator for all app state transitions
- Implements state machine pattern via AppState enum
- Manages lazy loading: JIT (Just-In-Time) ingestion on project selection
- Coordinates background indexing of inactive projects

**AppState** (enum in AppStateOrchestrator.swift):
- `startup` - Initial app launch
- `discovering` - Lightweight filesystem scan in progress
- `idle(projects: [LightweightProject])` - UI ready with project list
- `loading(projectId: String)` - JIT ingestion in progress for selected project
- `active(projectId: String)` - Project fully loaded and timeline ready
- `error(String)` - Error state with user-facing message

**LightweightDiscoveryService** (`app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift`):
- Fast filesystem scanner for project metadata (NO file content reads, NO DB writes)
- Stat-only scanning: uses file modification times as activity proxy
- Goal: <200ms for typical setup (19 projects, 663 transcripts)
- Returns `LightweightProject` structs sorted by last activity
- Actor-based for thread safety

**LightweightProject** (`app/Sources/ContextifyCore/Projects/ProjectModels.swift#LightweightProject`):
- Sendable, lightweight project metadata (no database required)
- Contains: id, path, displayName, transcriptCount, lastActivity, provider, cwd, transcriptFiles
- Used for initial UI display before full ingestion
- Converted to DiscoveredProject by ProjectsViewModel for UI compatibility

**FastPathIngestionCoordinator** (`app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift`):
- JIT ingestion coordinator with bounded 4-worker pool
- Preview subset (active project) gets watchers; completion work uses `startWatching: false`
- Drop-proof lifecycle: check pause before dequeue, requeue on cancellation/failure
- Two lifecycle modes: `pauseBackfill()` (resumable) vs `shutdown()` (terminal)
- Called by AppStateOrchestrator.selectProject()

**ProjectsViewModel** (`Contextify/Contextify/ProjectsViewModel.swift`):
- Observer view model for AppStateOrchestrator state transitions
- Converts state to UI-compatible models (LightweightProject → DiscoveredProject)
- Delegates all actions to AppStateOrchestrator (no direct discovery or ingestion)

### Key Principles

- **AppStateOrchestrator** is the central coordinator - all state flows through it
- **Startup is lightweight** - stat-only scan, NO ingestion (target: <200ms)
- **Ingestion is lazy (JIT)** - projects ingested only when user selects them
- **Background indexing** - inactive projects pre-ingested at low priority
- **State machine pattern** - explicit state transitions with type safety

### Architecture Flow

```
1. App Launch → AppStateOrchestrator.startup()
   - LightweightDiscoveryService.discoverProjectsLightweight() [<200ms]
   - Update projects table metadata ONLY (no transcripts/entries)
   - setState(.idle(projects)) → UI ready

2. User Selects Project → AppStateOrchestrator.selectProject(id:)
   - Cancel background work
   - setState(.loading(projectId))
   - FastPathIngestionCoordinator.ingestProjectJIT(project) [<1s]
   - StartupCoordinator.handleExternalProjectSwitch() [legacy compatibility]
   - setState(.active(projectId))
   - Post .projectDidActivate notification

3. Background (idle) → AppStateOrchestrator.startBackgroundIndexing()
   - Wait 5s after user activity
   - Ingest inactive projects one at a time (low priority)
   - Check Task.isCancelled between projects
   - Post .backgroundIngestProgress notifications
```

### Documentation

- **Architecture overview:** `build/docs/architecture/data-pipeline-architecture.md`
- **Implementation guide:** `build/docs/components/project-discovery-service-implementation.md`

---

## Startup Coordination (Legacy)

**StartupCoordinator** (`app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`):
- Legacy coordinator for backward compatibility with ConversationMonitor and other legacy components
- Receives notifications from AppStateOrchestrator via handleExternalProjectSwitch()
- Publishes ActiveProjectContext updates for legacy subscribers
- **Note:** Planned for refactor/removal when ConversationMonitor is split (see architecture-refactoring-analysis.md)

**ActiveProjectContext** (`app/Sources/ContextifyCore/Models/ActiveProjectContext.swift`):
- Immutable value type representing active project identity
- Contains stable project ID (primary key), filesystem path (metadata), display name, git branch, and security-scoped bookmark

### Integration Pattern

```swift
// New components: Subscribe to AppStateOrchestrator
for await _ in NotificationCenter.default.notifications(named: .appStateDidChange) {
    await updateFromOrchestrator()
}

// Legacy components: Still use StartupCoordinator
for await context in StartupCoordinator.shared.updates() {
    self.activeProjectId = context.id
}
```

### Key Principles

- `ActiveProjectContext.id` is the **stable primary identity** - use for all database queries
- `ActiveProjectContext.path` is **metadata only** - do not use for lookups
- New code should use AppStateOrchestrator directly (not StartupCoordinator)

### Documentation

- **Architecture:** `build/docs/architecture/startup-coordinator.md`
- **Implementation:** `build/docs/components/startup-coordinator-implementation.md`
- **Future refactoring plan:** `build/docs/architecture/architecture-refactoring-analysis.md`

**⚠️ Note:** This section documents legacy behavior. For new development, see "Application State Coordination" above.

---

## UI Layer

**ContentView** (`Contextify/Contextify/ContentView.swift`):
- Main UI with project switcher, project header, timeline view, quick search, and toast notifications

**ConversationTimelineView** (`Contextify/Contextify/ConversationTimelineView.swift`):
- Timeline display UI with session filtering and real-time updates

**TimelineEntryRow** (`Contextify/Contextify/TimelineEntryRow.swift`):
- Individual timeline entry row component

**TranscriptInventoryView** (`Contextify/Contextify/TranscriptInventoryView.swift`):
- UI for browsing and switching between transcript sessions

**ProjectSwitcherView** (`Contextify/Contextify/ProjectSwitcherView.swift`):
- Multi-project tab navigation bar with drag-drop reordering, unread badges, and keyboard shortcuts

**ProjectSwitcherState** (`Contextify/Contextify/ProjectSwitcherState.swift`):
- `@Observable` state management for project list, active project, and unread counts

**ProjectsViewModel** (`Contextify/Contextify/ProjectsViewModel.swift`):
- Observer view model for Projects window
- Observes AppStateOrchestrator state transitions
- Converts LightweightProject → DiscoveredProject for UI display
- Delegates all actions (project selection, refresh) to AppStateOrchestrator

### Documentation

- Project switcher architecture: `build/docs/architecture/project-switcher.md`
- Active session policy: `build/docs/components/active-session-policy.md`

---

## Supporting Components

**WindowTitleWriter** (`Contextify/Contextify/WindowTitleWriter.swift`):
- Updates window title to show current project name

**SystemInfo** (`Contextify/Contextify/SystemInfo.swift`):
- System information utilities (machine ID, support email)

> **Note:** iTerm2/terminal integration (ITerm2Bridge, ComposeWindowManager, GlobalHotkeyManager) was removed in commit 35ce380 for App Store compliance. See `build/notes/future-features.md` "Removed Features" section for re-implementation guidance if needed.

---

## Transcript Parsing & Metadata

**TranscriptParsers** (`app/Sources/ContextifyCore/Database/TranscriptParsers.swift`):
- JSONL parsers for Claude Code and Codex CLI formats
- Used by HooverEngine during ingestion (JSONL → DB)

**ConversationMonitor**:
- Consumes parsed entries from SQL
- **Does not parse JSONL**

**CRITICAL:** For all transcript work (parsing, discovery, permissions), **ALWAYS consult** `build/docs/specifications/transcript-formats.md` FIRST

Key information in transcript-formats.md:
- **Storage locations:** Claude Code (`~/.claude/projects/`) vs Codex (`~/.codex/sessions/YYYY/MM/DD/`)
- **Project discovery:** Claude Code uses directory structure, Codex uses `session_meta.payload.cwd` field
- **Record types:** Complete specifications for all record types in both formats
- **Content blocks:** Claude Code uses `text`, Codex uses `input_text`/`output_text`
- **Message linking:** Claude Code uses `uuid`+`parentUuid`, Codex uses `call_id` for tools
- **Format comparison:** Side-by-side comparison table of all differences

**ConversationSources** (`Contextify/Contextify/ConversationSources.swift`):
- Provider-specific session discovery (Claude Code, Codex CLI)
- **Planned (Phase 0, ct-1043):** The provider abstraction (`TranscriptProviderID`, `DiscoveredProject.Provider`, `TimelineModels.Provider`) will be refactored to support N providers before any new provider is added. The ct-1050 audit identified 12 hardcoded binary provider assumptions across the codebase (database CHECK constraints, binary ternary fallbacks, parallel enum types, hardcoded `claudeRoot`/`codexRoot` access-provider properties) that must be resolved first. See `/tmp/ct-1051-design-spec.md` Phase 0 for the full change list.

**TranscriptMetadataOrchestrator** (`Contextify/Contextify/TranscriptMetadataOrchestrator.swift`):
- Coordinates LLM-based metadata generation for transcripts (titles, descriptions, topics)

---

## Transcript Corruption (Claude Code Web)

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
- Format spec: `build/docs/specifications/claude-code-transcript-format.md`

---

## Platform Abstractions (Cross-Platform Support)

Contextify supports both macOS (full app) and Linux (ingestion CLI). Platform-specific APIs are wrapped in abstraction modules.

**CrossPlatformLogger** (`app/Sources/ContextifyCore/Platform/CrossPlatformLogger.swift`):
- Darwin: Wraps `OSLog.Logger` for system logging
- Linux: Writes to stderr with timestamp/level prefixes

**CrossPlatformCrypto** (`app/Sources/ContextifyCore/Platform/CrossPlatformCrypto.swift`):
- Darwin: Uses `CryptoKit.SHA256`
- Linux: Uses `Crypto.SHA256` from swift-crypto

**CrossPlatformLock** (`app/Sources/ContextifyCore/Platform/CrossPlatformLock.swift`):
- Darwin: Wraps `OSAllocatedUnfairLock<State>`
- Linux: Uses `NSLock` with DEBUG reentrancy detection

**PlatformSandbox** (`app/Sources/ContextifyCore/Platform/PlatformSandbox.swift`):
- Darwin: Detects App Store sandbox
- Linux: Always returns `false`

**IngestionEventSink** (`app/Sources/ContextifyCore/Platform/IngestionEventSink.swift`):
- Protocol for ingestion event reporting (progress, errors, completion)
- CLI implements this with `CLIEventSink` for human/JSONL output

### Documentation

- **Architecture:** `build/docs/architecture/cross-platform-architecture.md`
- **Development patterns:** `build/docs/guides/cross-platform-swift.md`
- **CLI usage:** `Sources/ContextifyIngestionCLI/README.md`
