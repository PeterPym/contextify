# Architecture & Key Components

This document provides detailed information about Contextify's architecture and key components.

**For high-level overview:** See `build/notes/technical-reference/system-architecture-overview.md`
- Explains component roles (Coordinator vs Orchestrator vs Monitor)
- Data model hierarchy (Projects → Transcripts → Entries → Summaries)
- Initialization flow and common confusion points

---

## Database Layer (SQL Backend)

- **Current Schema Version: v26** (see DatabaseSchema.swift for migration history)

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
- SQL schema definitions and versioned migrations (v1-v26)
- **v8-v9**: project_visits table, unread query indices
- **v10-v11**: assistant_usage_pending staging, FK hardening
- **v12-v13**: Epoch timestamps (projects.last_viewed_ts, entries.created_ts), optimizations
- **v14-v15**: Request ID normalization, index cleanup
- **v16**: GROUP BY index for unread queries
- **v17-v20**: Schema fixes, file migration, orphaned project tracking
- **v21**: database_access_metadata table
- **v22**: Strategy constraint fix (transcript_metadata.generation_strategy)
- **v23**: Active transcript follow (project_follow_policy table)

**TranscriptWatcher** (`app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`):
- File system monitoring for real-time transcript updates

**Models** (`app/Sources/ContextifyCore/Database/Models.swift`):
- Codable/Sendable database models (Project, Transcript, Entry, TimelineCache, AssistantUsage, etc.)

**ProjectVisitsRepository** (`app/Sources/ContextifyCore/Database/ProjectVisitsRepository.swift`):
- Unread tracking and visit timestamps per project

### Documentation

- Usage guide: `app/Sources/ContextifyCore/Database/README.md`
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

**StatusBar** (`Contextify/Contextify/StatusBarView.swift`, `StatusBarViewModel.swift`):
- Aggregates both LLM queues for unified monitoring
- Shows processing status, pending counts, ETAs, and errors

**TimelineModels** (`Contextify/Contextify/TimelineModels.swift`):
- Timeline-specific data models (TimelineEntry, CacheKey, Disposition)

**TimelineState** (`ConversationMonitor.swift`):
- Observable state container for timeline entries, derived cache index, and revision tracking

### Documentation

- **⭐ LLM Architecture Overview:** `build/docs/architecture/llm-processing.md` (start here)
- Timeline cache + LLM: `build/docs/components/timeline-cache.md`
- State management: `build/docs/architecture/conversation-monitor-state.md`
- Status bar: Shipped (see original design in `build/docs/archive/feature-specs/status-bar.md`)

---

## Core Components (Project Context)

**HUDViewModel** (`app/Sources/ContextifyCore/HUDCore.swift:370-1032`):
- Main `@Observable` `@MainActor` view model
- Manages:
  - Project root detection (environment → persisted → CWD → existing)
  - Git repository discovery and branch monitoring via file watchers
  - File/URL ingestion with Markdown artifact generation
  - Session and checkpoint management
  - Security-scoped bookmarks for sandboxed access

**GitRepositoryResolver** (`app/Sources/ContextifyCore/HUDCore.swift:142-368`):
- Git repository detection
- Finds `.git` root, parses HEAD (handles detached state, worktrees)
- Executes `git rev-parse` with timeout/fallback

**HUDPreferences** (`app/Sources/ContextifyCore/HUDCore.swift:13-126`):
- Manages UserDefaults with suite fallback
- Stores project root path and security-scoped bookmarks

---

## Startup Coordination (as of 2025-11-05)

**IMPORTANT:** All project identity flows through `StartupCoordinator.shared` for deterministic startup sequencing.

**StartupCoordinator** (`app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`):
- Orchestrates deterministic startup sequencing for project identity pipeline
- Provides single source of truth via `ActiveProjectContext`
- Ensures project exists in database before monitoring starts

**ActiveProjectContext** (`app/Sources/ContextifyCore/Models/ActiveProjectContext.swift`):
- Immutable value type representing active project identity
- Contains stable project ID (primary key), filesystem path (metadata), display name, git branch, and security-scoped bookmark

### Key Principles

- `ActiveProjectContext.id` is the **stable primary identity** - use for all database queries
- `ActiveProjectContext.path` is **metadata only** - do not use for lookups
- Coordinator owns `getOrCreateProject()` database calls
- All subsystems receive context via typed `AsyncStream` (not NotificationCenter)

### DO

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

### DON'T

```swift
// Query HUDViewModel for path (stale, race-prone)
let path = HUDViewModel.shared.projectRootURL

// Call getOrCreateProject directly (coordinator owns this)
let projectId = try orchestrator.getOrCreateProject(...)

// Use NotificationCenter for startup (timing-dependent)
NotificationCenter.default.addObserver(forName: .projectRootDidChange ...)
```

### Architecture

- **Startup Order:** `ContextifyApp.init()` starts coordinator → `ProjectSwitcherState.start()` subscribes to updates → `ContentView.task` waits for `ready()` → Timeline starts with stable project ID
- **Documentation:** `build/docs/architecture/startup-coordinator.md`
- **Implementation:** Shipped in commit 531ac70 (see original plan in `build/docs/archive/feature-specs/startup-coordinator.md`)

---

## UI Layer

**ContentView** (`Contextify/Contextify/ContentView.swift`):
- Main UI with header (project/branch display, "Set Project Root" button), URL entry field, drop zone, controls (New Session, Checkpoint, Reveal Outputs), and toast notifications

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

**IngestDropZone** (`Contextify/Contextify/IngestDropZone.swift`):
- Drag-and-drop target for files, uses SwiftUI `onDrop` with completion handlers and main actor marshaling

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

**TranscriptMetadataOrchestrator** (`Contextify/Contextify/TranscriptMetadataOrchestrator.swift`):
- Coordinates LLM-based metadata generation for transcripts (titles, descriptions, topics)

**SidecarMetadataStore** (`Contextify/Contextify/SidecarMetadataStore.swift`):
- JSON sidecar file persistence for transcript metadata

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
- Format spec: `build/docs/specifications/claude-code-format.md`
