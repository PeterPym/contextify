# Project Switcher Implementation - Related Files

This document lists all files related to implementing the Project Switcher Navigation Bar feature, including existing files that need modification and new files to be created.

**Updated**: 2025-10-27 - Post Ultrathink + Colleague Review
**Readiness**: 4.0/5 (ready to start Phase 0)
**Status Bar Integration**: StatusBarView, StatusBarViewModel, and QueueStatsProvider patterns exist as reference implementations
**Migration Strategy**: Simplified for pre-production hard cutover (no complex rollback)

**Key Architecture Changes from Ultrathink**:
- FSEvents-first discovery (not polling)
- ProjectActivityMonitor is an **actor** (single watcher owner)
- DB-derived unread counts (no mutable counters)
- project_visits table with `last_viewed_at`, `last_selected_at`, `pinned`
- Privacy/consent dialog for global scanning
- Comprehensive accessibility contract

## Related Files

### New Files (To Be Created)

#### `app/Sources/ContextifyCore/ProjectActivityMonitor.swift` ⭐ ACTOR
**Purpose:** **Actor** that owns all watcher lifecycle. Single source of truth for which projects are being watched. Uses FSEvents for discovery with fallback polling.

**Key Properties**:
- **Actor isolation**: All watcher start/stop/replace serialized through actor
- **Idempotent**: Calling `ensureWatcher(projectId)` twice returns same handle
- **Dictionary-based**: `Dictionary<ProjectID, WatchHandle>` ensures exactly one watcher per project
- **Event stream**: Emits `AsyncStream<ProjectEvent>` for UI consumption

**API Surface**:
```swift
public actor ProjectActivityMonitor {
  public init(orchestrator: TranscriptOrchestrator, discovery: ProjectDiscovery)
  public func startGlobalMonitoring() async throws
  public func stopAll()
  public func ensureWatcher(projectId: String) async throws -> WatchHandle
  public func stopWatcher(projectId: String) async
  public nonisolated func observeProjectEvents() -> AsyncStream<ProjectEvent>
}
```

#### `app/Sources/ContextifyCore/FSEventsMonitor.swift` 🆕
**Purpose:** Wrapper for FSEvents API to monitor transcript roots (`~/.claude/projects/`, `~/.codex/sessions/`). Provides AsyncStream of file system changes with fallback to polling when FSEvents unavailable.

**Responsibilities**:
- Register FSEvents on transcript roots
- Emit change notifications via AsyncStream
- Fall back to 30s polling when FSEvents errors
- Set telemetry flag `fsevents_unavailable` on fallback

#### `app/Sources/ContextifyCore/ProjectIdentity.swift` 🆕
**Purpose:** Reverse path-mangling algorithm and project identity hashing. Converts Claude Code/Codex CLI directory names back to absolute project paths.

**Key Functions**:
```swift
func reverseManglePath(provider: String, directory: URL) throws -> String
func computeProjectID(provider: String, path: String) -> String  // SHA256 hash
func canonicalizePath(_ path: String) throws -> String  // Resolve symlinks
```

**Collision Handling**: Same project across multiple roots → prefer newest `entries.created_at`

#### `app/Sources/ContextifyCore/Database/ProjectVisitsRepository.swift` 🆕
**Purpose:** Repository interface and implementation for `project_visits` table. **DB-derived unread counts** (no mutable counters).

**Schema**:
```sql
CREATE TABLE project_visits (
  project_id TEXT NOT NULL PRIMARY KEY,
  last_viewed_at TEXT,      -- ISO8601Z UTC (NULL = never viewed)
  last_selected_at TEXT,    -- ISO8601Z UTC
  pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0,1)),
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

CREATE INDEX idx_entries_project_created_at ON entries(project_id, created_at);
CREATE INDEX idx_project_visits_last_viewed_at ON project_visits(project_id, last_viewed_at);
```

**Operations**:
- `markViewed(projectId, timestamp)`: Set `last_viewed_at` (UTC ISO8601Z)
- `markSelected(projectId)`: Set `last_selected_at = now()`
- `togglePin(projectId)`: Toggle `pinned` flag
- `getUnreadCounts()`: Execute batch query with LEFT JOIN (index-only plan)

**Unread Query**:
```sql
SELECT COUNT(*) FROM entries e
LEFT JOIN project_visits v ON v.project_id = e.project_id
WHERE e.project_id = ?
  AND (v.last_viewed_at IS NULL OR e.created_at > v.last_viewed_at);
```

**Key Properties**:
- Crash-safe (purely DB-derived from immutable timestamps)
- Clock-skew resistant (uses UTC, never `now()`)
- NULL semantics: `last_viewed_at = NULL` → all entries unread

#### `Contextify/Contextify/ProjectSwitcherState.swift`
**Purpose:** @Observable @MainActor view model that queries all projects with transcripts, subscribes to TranscriptUpdated notifications, maintains unread counts per project, and provides switchToProject() API. Single source of truth for project switcher UI state.

**Architecture Pattern:** Follow StatusBarViewModel pattern (see `StatusBarViewModel.swift` lines 1-132):
- Event-driven with AsyncStream for real-time updates (not polling)
- Proper lifecycle management with start()/stop() methods
- Idempotent start() with guard
- Task cancellation on stop()
- @Observable for SwiftUI integration

#### `Contextify/Contextify/ProjectSwitcherView.swift`
**Purpose:** SwiftUI component rendering horizontal navigation bar with project tabs. Shows project names, active state styling, and unread badges. Handles tap gestures to trigger project switching. Includes ProjectTabView subcomponent for individual tabs.

**Architecture Pattern:** Follow StatusBarView pattern (see `StatusBarView.swift` lines 1-250):
- Use `.task { viewModel.start() }` for lifecycle (no await - method is sync)
- Use `.onDisappear { viewModel.stop() }` for cleanup
- Use `.contentTransition(.opacity)` for smooth state changes
- Use Contextify color scheme (see `build/notes/design-reference/color-scheme.md`)
- Comprehensive accessibility labels with 44pt hit targets

#### `app/Sources/ContextifyCore/Clock.swift` 🆕
**Purpose:** Protocol for deterministic time in tests. Injectable into repositories for timestamp generation.

```swift
public protocol Clock: Sendable {
  func now() -> Date
}

public struct SystemClock: Clock {
  public func now() -> Date { Date() }
}

public struct FixedClock: Clock {
  let fixedDate: Date
  public func now() -> Date { fixedDate }
}
```

#### `app/Sources/ContextifyCore/ConsentManager.swift` 🆕
**Purpose:** Manages user consent for multi-project mode. First-run dialog and preference persistence.

**Preference Key**: `dev.contextify.multiProjectMode.enabled` (default: `false`)

**Dialog Copy**:
```
Enable Multi-Project Monitoring?

Contextify can monitor all projects with
Claude Code or Codex CLI transcripts.

This requires scanning:
• ~/.claude/projects/
• ~/.codex/sessions/

Project paths are stored locally only.
No data is shared externally.

[Disable]  [Enable Multi-Project Mode]
```

### Existing Files (To Be Modified)

#### `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`
**Purpose:** Add `project_visits` table schema. Determine next migration version (v8?).

**Migration v8 (Hard Cutover)**:
```swift
migrator.registerMigration("v8-project-visits") { db in
  // Create table + indices
  try db.execute(sql: """
    CREATE TABLE project_visits (
      project_id TEXT NOT NULL PRIMARY KEY,
      last_viewed_at TEXT,
      last_selected_at TEXT,
      pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0,1)),
      FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
    );
    CREATE INDEX idx_entries_project_created_at ON entries(project_id, created_at);
    CREATE INDEX idx_project_visits_last_viewed_at ON project_visits(project_id, last_viewed_at);
  """)

  // Optional: backfill current project only (others default to NULL = all unread)
  if let currentProjectId = getCurrentProjectId() {
    try db.execute(sql: """
      INSERT INTO project_visits (project_id, last_viewed_at)
      SELECT ?, MIN(created_at) FROM entries WHERE project_id = ?
    """, arguments: [currentProjectId, currentProjectId])
  }
}
```

**Rollback Plan**: Delete `~/Library/Application Support/Contextify/transcripts.db`, restart (fresh DB)

**Verification**: Run `EXPLAIN QUERY PLAN` to confirm index-only scan for unread query.

#### `app/Sources/ContextifyCore/Database/Repositories.swift`
**Purpose:** Add ProjectVisitsRepository protocol and ProjectVisitsRepositoryImpl implementation. Integrate with existing repository pattern used by TranscriptOrchestrator.

#### `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`
**Purpose:** Add methods to expose project visits repository: getUnreadCounts(), updateProjectVisit(), incrementProjectUnread(). Wire up ProjectVisitsRepository in init(). May need to adjust project creation/discovery to automatically initialize project_visits records.

#### `Contextify/Contextify/ConversationMonitor.swift`
**Purpose:** Modify watchForDebouncedTranscriptUpdates() to **branch on projectId** (not filter). Process all project updates; unread counts handled by DB-derived queries (not incremental counters).

**Change**:
```swift
// BEFORE: guard pid == self.currentProjectId else { return }

// AFTER:
if pid == self.currentProjectId {
  // Refresh timeline (existing behavior)
  self.debounceTask?.cancel()
  self.debounceTask = Task {
    try? await Task.sleep(nanoseconds: 150_000_000)
    await self.processIncrementalUpdate()
  }
}
// No else branch needed - unread is DB-derived, updated on next query
```

**Note**: No direct `incrementUnreadCount()` calls. Unread is purely DB-derived from `entries.created_at > last_viewed_at`.

#### `app/Sources/ContextifyCore/HUDCore.swift` (HUDViewModel)
**Purpose:** Add switchToProject(projectPath: String) method that updates projectRootURL, posts ProjectRootChanged notification, and refreshes git info. This will be called by ProjectSwitcherState when user taps a project tab.

#### `Contextify/Contextify/ContentView.swift`
**Purpose:** Add ProjectSwitcherView above existing header in main VStack. Initialize ProjectSwitcherState in app startup and inject into SwiftUI environment. Conditionally show switcher only when allProjects.count > 1.

**Current State:** StatusBarView is already integrated at line 51 (bottom footer). Project switcher will be added to top navigation area, above existing header.

**Integration Pattern:**
```swift
VStack(spacing: 0) {
  // NEW: Project switcher (top)
  if projectSwitcherState.allProjects.count > 1 {
    ProjectSwitcherView()
  }

  // EXISTING: Main content (lines 28-48)
  HStack(spacing: 0) { /* ... */ }

  // EXISTING: Status bar (line 51) - already implemented
  StatusBarView()
}
```

### Reference Files (Existing Patterns from Status Bar Implementation)

#### `Contextify/Contextify/StatusBarView.swift` ✅ IMPLEMENTED
**Purpose:** Reference implementation for SwiftUI component with lifecycle management. Shows pattern for event-driven UI with AsyncStream observation.

**Key Patterns to Follow:**
- `.task(id: identity)` for automatic reconnection when dependencies change (lines 38-42)
- Proper lifecycle: `viewModel.start()` on appear, `viewModel.stop()` on disappear
- Multiple provider aggregation (lines 62-73)
- Contextify color scheme usage (lines 95-100)

#### `Contextify/Contextify/StatusBarViewModel.swift` ✅ IMPLEMENTED
**Purpose:** Reference implementation for @Observable view model with event-driven updates. Shows pattern for AsyncStream consumption, lifecycle management, and state change detection.

**Key Patterns to Follow:**
- Idempotent `start()` with isStarted guard
- `Task { @MainActor [weak self] in ... }` for proper actor isolation
- Change detection before state updates (avoid unnecessary SwiftUI invalidation)
- Proper cleanup in `stop()`

#### `Contextify/Contextify/QueueStatsProvider.swift` ✅ IMPLEMENTED
**Purpose:** Reference implementation for protocol-based provider pattern. Shows how to create testable interfaces for event streams.

**Key Patterns to Follow:**
- Protocol with single AsyncStream method
- Mock providers for testing (MockQueueProvider, EmptyQueueProvider)
- Sendable conformance for actor safety

### Supporting Files (Reference Only)

#### `build/notes/technical-reference/sql-backend-architecture.md`
**Purpose:** Reference documentation for understanding database schema patterns, repository interfaces, and migration strategies used in Contextify.

#### `build/notes/technical-reference/conversation-monitor-state-architecture.md`
**Purpose:** Reference documentation for understanding ConversationMonitor state management, notification patterns, and timeline refresh logic.

#### `Contextify/Contextify/ConversationSources.swift` (DEPRECATED)
**Purpose:** Legacy file-based discovery providers (ClaudeTranscriptProvider, CodexTranscriptProvider). NOW DEAD CODE kept for reference only. New discovery logic will be in ProjectActivityMonitor using database-backed approach, but path parsing logic may be useful reference.

#### `build/notes/feature-specs/status-bar/spec-final.md` ✅ REFERENCE
**Purpose:** Complete specification for status bar implementation. Use as template for project switcher spec formatting and component breakdown.

**Relevant Sections:**
- Component specifications with Implementation code blocks
- Testing strategy (unit, integration, UI tests)
- Performance characteristics
- Edge cases and error handling
- Accessibility guidelines

#### `build/notes/technical-reference/llm-processing-architecture.md` ✅ REFERENCE
**Purpose:** High-level architecture document for aggregating multiple event sources. Shows pattern for monitoring multiple independent systems (timeline + metadata queues).

**Applicable Pattern:** Project switcher will aggregate updates from multiple projects (similar to status bar aggregating multiple LLM queues).

---

## Architecture Alignment

The project switcher follows established Contextify patterns from the recent status bar implementation, with critical enhancements from Ultrathink analysis:

**Shared Patterns**:
1. **Event-Driven Architecture**: AsyncStream for real-time updates (FSEvents + notifications, not polling)
2. **Observable ViewModels**: @MainActor @Observable with proper lifecycle (start/stop)
3. **Protocol Abstraction**: Provider protocols for testability (`QueueStatsProvider`, `ProjectDiscovery`)
4. **Actor Isolation**: Single owner per domain (StatusBar uses actors, ProjectActivityMonitor is an actor)
5. **Lifecycle Management**: Idempotent start(), explicit stop(), task cancellation
6. **SwiftUI Integration**: `.task/.onDisappear` for view lifecycle
7. **Color Scheme**: Contextify colors from `build/notes/design-reference/color-scheme.md`

**Differences**:
- **Status bar**: Aggregates LLM queue stats (bottom footer, read-only monitoring)
- **Project switcher**: Aggregates project states (top navigation, interactive switching)
- **Concurrency**: Status bar uses actors for LLM queues; project switcher uses **ProjectActivityMonitor actor** for watchers
- **Storage**: Status bar uses in-memory state; project switcher uses **SQL** (`project_visits` table)

**New Patterns from Ultrathink**:
- **DB-derived state**: Unread counts computed from immutable timestamps (not mutable counters)
- **FSEvents-first**: Primary discovery mechanism with fallback polling
- **Privacy/consent**: User opt-in for global scanning
- **Accessibility contract**: Keyboard shortcuts (Cmd+1…9), VoiceOver labels, 44pt hit targets

## Must-Fix Before Build (Gap List)

Per Ultrathink analysis + colleague review, these gaps **must be resolved** before starting implementation:

1. **Reverse path-mangle spec** (`ProjectIdentity.swift`): Complete algorithm with test fixtures for both Claude Code and Codex CLI formats + collision policy *(Phase 0)*
2. **Watcher provider API** (`ProjectWatcherProvider` protocol): Define lifecycle, error surface, backoff strategy *(Phase 0-1)*
3. **Migration v8**: Hard cutover with optional current project backfill; simple rollback (delete DB) *(Phase 0)*
4. **Transaction boundaries**: GRDB write blocks for concurrent unread updates *(Phase 2)*
5. **Cancellation pattern**: Timeline refresh cancellation on rapid switching *(Phase 5)*
6. **Performance budget**: Document max CPU % during idle (≤2%), max FS ops/sec (<10) *(Phase 4)*
7. **Startup selection policy**: Last selected vs. most active in last N hours; tie-breaking logic *(Phase 0)*
8. **Error handling surface**: Toast vs. HUD vs. silent logs for watcher failures *(Phase 0)*
9. **FSEvents probe**: Verify non-sandboxed environment; test FSEvents on transcript roots *(Phase 1)*
10. **Index verification**: Run `EXPLAIN QUERY PLAN` on unread query; confirm index-only scan *(Phase 2)*

## Validation Requirements

### Unit Tests
- `testUnreadForNeverVisited_isAllEntries`: NULL `last_viewed_at` → count = all entries
- `testUnreadIndexPlan_isIndexOnly`: Verify `idx_entries_project_created_at` used
- `testMarkViewed_updatesTimestamp`: Update `last_viewed_at`, verify unread = 0
- `testClockSkew`: Entry after `last_viewed_at` → unread = 1
- `testReverseMangle_claudeCode`: Reverse-mangle Claude Code directory names
- `testReverseMangle_collision`: Same project across multiple roots → same `project_id`

### Actor/Concurrency Tests
- `testIdempotentWatcherStart`: Double-start → same handle, count = 1
- `testRapidSwitchCancellation`: 20× switch → no leaked tasks after 60s

### Integration Tests
- `testEndToEnd_unreadBadgeUpdate`: 3 projects → file events → badges update within 300ms
- `testFSEventsFailure_fallbackPolling`: FSEvents unavailable → fallback engaged, telemetry flag set

### Performance Tests
- `testIdleCPU`: Monitor 10 projects → ≤2% CPU over 60s
- `testBurstEvents`: 200 events across 10 projects → process in ≤2s, ≤10 DB transactions

---

## File Contents

### Existing Files


#### `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`

```swift
import Foundation
import GRDB

/// SQLite schema for Contextify transcript storage
/// Based on sql-implementation-plan-05.md and sql-integration-plan-v2.md
///
/// Time Unit Convention:
/// - Standard timestamps (created_at, updated_at, generated_at, timestamp, last_modified): Unix seconds (Int)
/// - High-precision timestamps (mtime_ms, latency_ms, etc): Unix milliseconds (Int64)
/// - Rationale: Seconds provide sufficient precision for most operations, milliseconds used where needed
/// - Future: Consider migrating all timestamps to milliseconds for consistency
enum DatabaseSchema {
  static let version = 7

  /// Create migrator for schema evolution
  static func createMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()

    // v1: Base schema (all tables and indexes)
    migrator.registerMigration("v1_base") { db in
      try createBaseSchema(db)
    }

    // v2: Window fields for fast cache joins
    migrator.registerMigration("v2_window_sha") { db in
      try db.alter(table: "transcript_entries") { t in
        t.add(column: "prev1_id", .text)
        t.add(column: "prev2_id", .text)
        t.add(column: "window_sha256", .text)
      }
    }

    // v2: Resume checkpoint for correct window state across restarts
    migrator.registerMigration("v2_resume_checkpoint") { db in
      try db.alter(table: "transcripts") { t in
        t.add(column: "last_processed_entry_id", .text)
      }

      // Best-effort backfill: set to last chronological entry per transcript
      let tids = try String.fetchAll(db, sql: "SELECT id FROM transcripts")
      for tid in tids {
        if let lastId = try String.fetchOne(
          db,
          sql: """
            SELECT id FROM transcript_entries
            WHERE transcript_id = ?
            ORDER BY timestamp DESC, id DESC
            LIMIT 1
          """,
          arguments: [tid]
        ) {
          try db.execute(
            sql: "UPDATE transcripts SET last_processed_entry_id = ? WHERE id = ?",
            arguments: [lastId, tid]
          )
        }
      }
    }

    // v2: Backfill window fields for existing data
    migrator.registerMigration("v2_window_sha_backfill") { db in
      let tids = try String.fetchAll(db, sql: "SELECT id FROM transcripts")
      for tid in tids {
        let rows = try Row.fetchAll(db, sql: """
          SELECT id
          FROM transcript_entries
          WHERE transcript_id = ?
          ORDER BY timestamp ASC, id ASC
        """, arguments: [tid])

        var prev2: String? = nil
        var prev1: String? = nil
        for r in rows {
          let id: String = r["id"]
          let win = SHA256Utils.computeWindowSHA256(prev2: prev2, prev1: prev1)
          try db.execute(
            sql: """
              UPDATE transcript_entries
              SET prev2_id = ?, prev1_id = ?, window_sha256 = ?
              WHERE id = ?
            """,
            arguments: [prev2, prev1, win, id]
          )
          prev2 = prev1
          prev1 = id
        }
      }

      // Create covering index AFTER backfill to avoid costly index maintenance
      // Includes (timestamp, created_at, id) to match feed query ORDER BY for consistent sorting
      try db.create(
        index: "idx_entries_feed_cover",
        on: "transcript_entries",
        columns: [
          "project_id",
          "timestamp",   // Primary sort key
          "created_at",  // Secondary sort key for tie-breaking
          "id",          // Tertiary sort key for stable ordering
          "content_sha256",
          "window_sha256",
          "kind",
          "is_completion",
          "session_id"
        ],
        ifNotExists: true,
        condition: "display_in_timeline = 1"
      )

      // Run ANALYZE to update statistics after bulk operations
      try db.execute(sql: "ANALYZE")
    }

    // v3: Path normalization and freshness tracking for transcript inventory (pure DDL)
    // Backfill happens during discovery/upsert, not in migration
    migrator.registerMigration("v3_transcript_identity") { db in
      // Check if columns already exist (safe for re-running)
      let tableInfo = try Row.fetchAll(db, sql: "PRAGMA table_info(transcripts)")
      let columnNames = Set(tableInfo.map { $0["name"] as! String })

      // Add columns only if they don't exist
      if !columnNames.contains("normalized_path") {
        try db.execute(sql: "ALTER TABLE transcripts ADD COLUMN normalized_path TEXT")
      }
      if !columnNames.contains("path_hash") {
        try db.execute(sql: "ALTER TABLE transcripts ADD COLUMN path_hash TEXT")
      }
      if !columnNames.contains("content_length") {
        try db.execute(sql: "ALTER TABLE transcripts ADD COLUMN content_length INTEGER")
      }
      if !columnNames.contains("mtime_ms") {
        try db.execute(sql: "ALTER TABLE transcripts ADD COLUMN mtime_ms INTEGER")
      }
      if !columnNames.contains("content_sha256") {
        try db.execute(sql: "ALTER TABLE transcripts ADD COLUMN content_sha256 TEXT")
      }

      // Backfill mtime_ms from legacy mtime_ns if present (only for databases that had the old column)
      if columnNames.contains("mtime_ns") {
        try db.execute(sql: """
          UPDATE transcripts
          SET mtime_ms = mtime_ns / 1000000
          WHERE mtime_ns IS NOT NULL AND mtime_ms IS NULL
        """)
      }

      // Create transcript_metadata table
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS transcript_metadata (
          transcript_id TEXT PRIMARY KEY NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
          project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          description TEXT NOT NULL,
          topics TEXT NOT NULL CHECK(json_valid(topics)),
          confidence REAL NOT NULL,
          may_contain_hallucinations INTEGER NOT NULL DEFAULT 0,
          needs_review INTEGER NOT NULL DEFAULT 0,
          generated_at INTEGER NOT NULL,
          model TEXT NOT NULL,
          prompt_version INTEGER NOT NULL,
          generator_version INTEGER NOT NULL,
          transcript_sha256 TEXT NOT NULL,
          message_count INTEGER NOT NULL,
          strategy TEXT NOT NULL,
          llm_calls INTEGER NOT NULL,
          latency_ms INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      """)

      // Create indexes for transcript_metadata
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_transcript_id ON transcript_metadata(transcript_id)
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_project ON transcript_metadata(project_id)
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_generated_at ON transcript_metadata(generated_at DESC)
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_needs_review ON transcript_metadata(needs_review, generated_at DESC)
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_sha ON transcript_metadata(transcript_sha256)
      """)

      // Create entry indexes for cursor-based pagination (critical for performance)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_cursor
        ON transcript_entries(project_id, timestamp, created_at, id)
        WHERE display_in_timeline = 1
      """)

      // Create identity indexes immediately (don't require backfill)
      try db.execute(sql: """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_tr_provider_session
        ON transcripts(provider, provider_session_id)
        WHERE provider_session_id IS NOT NULL AND provider_session_id <> ''
      """)
      try db.execute(sql: """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_tr_provider_path_hash
        ON transcripts(provider, path_hash)
        WHERE (provider_session_id IS NULL OR provider_session_id = '')
          AND path_hash IS NOT NULL
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tr_mtime_ms ON transcripts(mtime_ms)
      """)
    }

    // v4: RAG embeddings storage
    migrator.registerMigration("v4_embeddings") { db in
      // Check if columns already exist (safe for re-running)
      let tableInfo = try Row.fetchAll(db, sql: "PRAGMA table_info(transcript_entries)")
      let columnNames = Set(tableInfo.map { $0["name"] as! String })

      // Add embedding columns only if they don't exist
      if !columnNames.contains("embedding") {
        try db.execute(sql: "ALTER TABLE transcript_entries ADD COLUMN embedding BLOB")
      }
      if !columnNames.contains("embedding_version") {
        try db.execute(sql: "ALTER TABLE transcript_entries ADD COLUMN embedding_version INTEGER DEFAULT 1")
      }
      if !columnNames.contains("embedding_generated_at") {
        try db.execute(sql: "ALTER TABLE transcript_entries ADD COLUMN embedding_generated_at INTEGER")
      }

      // Create index for efficient queries on embedding presence
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_embedding_version
        ON transcript_entries(embedding_version)
      """)
    }

    // v5: Backfill path_hash for transcript identity and deduplicate
    migrator.registerMigration("v5_path_hash_backfill_dedup") { db in
      // Step 1: Backfill path_hash for rows where it's NULL
      let transcriptsToBackfill = try Row.fetchAll(db, sql: """
        SELECT id, file_path
        FROM transcripts
        WHERE path_hash IS NULL OR path_hash = ''
      """)

      for row in transcriptsToBackfill {
        let transcriptId: String = row["id"]
        let filePath: String = row["file_path"]

        // Compute normalized path and hash
        let (normalizedPath, pathHash) = PathNormalizer.normalizeAndHash(filePath)

        // Update the transcript
        try db.execute(sql: """
          UPDATE transcripts
          SET normalized_path = ?, path_hash = ?
          WHERE id = ?
        """, arguments: [normalizedPath, pathHash, transcriptId])
      }

      // Step 2: Deduplicate transcripts with same (provider, path_hash)
      // Find groups of duplicate transcripts
      let duplicateGroups = try Row.fetchAll(db, sql: """
        SELECT provider, path_hash, COUNT(*) as count
        FROM transcripts
        WHERE path_hash IS NOT NULL AND path_hash <> ''
          AND (provider_session_id IS NULL OR provider_session_id = '')
        GROUP BY provider, path_hash
        HAVING count > 1
      """)

      for group in duplicateGroups {
        let provider: String = group["provider"]
        let pathHash: String = group["path_hash"]

        // Get all transcripts in this duplicate group, ordered by created_at (oldest first)
        let duplicates = try Row.fetchAll(db, sql: """
          SELECT id, created_at
          FROM transcripts
          WHERE provider = ? AND path_hash = ?
            AND (provider_session_id IS NULL OR provider_session_id = '')
          ORDER BY created_at ASC
        """, arguments: [provider, pathHash])

        guard duplicates.count > 1 else { continue }

        // Keep the oldest transcript (first in list)
        let keeperId: String = duplicates[0]["id"]
        let duplicateIds = duplicates.dropFirst().map { $0["id"] as! String }

        // Reassign entries from duplicates to the keeper
        for dupId in duplicateIds {
          try db.execute(sql: """
            UPDATE transcript_entries
            SET transcript_id = ?
            WHERE transcript_id = ?
          """, arguments: [keeperId, dupId])

          // Delete the duplicate transcript
          try db.execute(sql: """
            DELETE FROM transcripts
            WHERE id = ?
          """, arguments: [dupId])
        }
      }

      // Run ANALYZE to update statistics after bulk operations
      try db.execute(sql: "ANALYZE")
    }

    // v6: Remove denormalized fields (summary, disposition, is_completion, is_directive)
    migrator.registerMigration("v6_remove_denormalized_fields") { db in
      // SQLite doesn't support DROP COLUMN, so we need to recreate the table

      // 1. Create new table without denormalized fields
      try db.create(table: "transcript_entries_new") { t in
        t.column("id", .text).primaryKey()
        t.column("transcript_id", .text).notNull().references("transcripts", onDelete: .cascade)
        t.column("project_id", .text).notNull().references("projects", onDelete: .cascade)
        t.column("session_id", .text)
        t.column("provider", .text).notNull().check(sql: "provider IN ('claude.code','codex.cli','other')")
        t.column("kind", .text).notNull().check(sql: "kind IN ('user','assistant','system')")
        t.column("timestamp", .integer).notNull()
        t.column("content", .text).notNull()
        t.column("content_sha256", .text).notNull()
        t.column("display_in_timeline", .integer).notNull().defaults(to: 1)
        t.column("parent_id", .text).references("transcript_entries", onDelete: .setNull)
        t.column("git_branch", .text)
        t.column("git_commit", .text)
        t.column("cwd", .text)
        t.column("created_at", .integer).notNull()
        t.column("updated_at", .integer).notNull()
        t.column("prev1_id", .text)
        t.column("prev2_id", .text)
        t.column("window_sha256", .text)
        t.column("embedding", .blob)
        t.column("embedding_version", .integer).defaults(to: 1)
        t.column("embedding_generated_at", .integer)
      }

      // 2. Copy data from old table (excluding removed columns)
      try db.execute(sql: """
        INSERT INTO transcript_entries_new
        SELECT id, transcript_id, project_id, session_id, provider, kind,
               timestamp, content, content_sha256, display_in_timeline,
               parent_id, git_branch, git_commit, cwd, created_at, updated_at,
               prev1_id, prev2_id, window_sha256, embedding, embedding_version,
               embedding_generated_at
        FROM transcript_entries
      """)

      // 3. Drop old table
      try db.drop(table: "transcript_entries")

      // 4. Rename new table
      try db.rename(table: "transcript_entries_new", to: "transcript_entries")

      // 5. Recreate all indexes
      try db.create(index: "idx_entries_transcript_time", on: "transcript_entries",
                    columns: ["transcript_id", "timestamp"], ifNotExists: true)
      try db.create(index: "idx_entries_content_sha", on: "transcript_entries",
                    columns: ["content_sha256"], ifNotExists: true)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_project_time
        ON transcript_entries(project_id, timestamp DESC)
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_project_feed
        ON transcript_entries(project_id, timestamp DESC)
        WHERE display_in_timeline = 1
      """)

      // Run ANALYZE to update statistics
      try db.execute(sql: "ANALYZE")
    }

    // MARK: v7 Migration: Add Metadata Tables
    migrator.registerMigration("v7_add_metadata_tables") { db in
      // Create file_snapshots table
      try db.create(table: "file_snapshots") { t in
        t.column("id", .text).primaryKey()
        t.column("transcript_id", .text).notNull()
          .references("transcripts", onDelete: .cascade, onUpdate: .cascade)
        t.column("message_id", .text).notNull()
        t.column("snapshot_timestamp", .integer).notNull()
        t.column("is_snapshot_update", .integer).notNull()
        t.column("created_at", .integer).notNull()
      }

      try db.create(index: "idx_snapshots_transcript", on: "file_snapshots", columns: ["transcript_id"])
      try db.create(index: "idx_snapshots_message", on: "file_snapshots", columns: ["message_id"])
      try db.create(index: "idx_snapshots_timestamp", on: "file_snapshots", columns: ["snapshot_timestamp"])

      // Create tracked_files table
      try db.create(table: "tracked_files") { t in
        t.column("id", .text).primaryKey()
        t.column("snapshot_id", .text).notNull()
          .references("file_snapshots", onDelete: .cascade, onUpdate: .cascade)
        t.column("file_path", .text).notNull()
        t.column("backup_filename", .text)
        t.column("version", .integer).notNull()
        t.column("backup_time", .integer).notNull()
      }

      try db.create(index: "idx_tracked_snapshot", on: "tracked_files", columns: ["snapshot_id"])
      try db.create(index: "idx_tracked_path", on: "tracked_files", columns: ["file_path"])

      // Create transcript_summaries table
      try db.create(table: "transcript_summaries") { t in
        t.column("id", .text).primaryKey()
        t.column("transcript_id", .text).notNull()
          .references("transcripts", onDelete: .cascade, onUpdate: .cascade)
        t.column("summary", .text).notNull()
        t.column("leaf_uuid", .text)
        t.column("cwd", .text)
        t.column("created_at", .integer).notNull()
      }

      try db.create(index: "idx_summaries_transcript", on: "transcript_summaries", columns: ["transcript_id"])

      // Create system_events table
      try db.create(table: "system_events") { t in
        t.column("id", .text).primaryKey()
        t.column("transcript_id", .text).notNull()
          .references("transcripts", onDelete: .cascade, onUpdate: .cascade)
        t.column("timestamp", .integer).notNull()
        t.column("subtype", .text).notNull()
        t.column("level", .text).notNull()
        t.column("content", .text)
        t.column("error", .text)
        t.column("retry_attempt", .integer)
        t.column("max_retries", .integer)
        t.column("retry_in_ms", .integer)
        t.column("parent_uuid", .text)
        t.column("logical_parent_uuid", .text)
        t.column("compact_metadata", .text)
        t.column("created_at", .integer).notNull()
      }

      try db.create(index: "idx_events_transcript", on: "system_events", columns: ["transcript_id"])
      try db.create(index: "idx_events_subtype", on: "system_events", columns: ["subtype"])
      try db.create(index: "idx_events_timestamp", on: "system_events", columns: ["timestamp"])

      // Create assistant_usage table
      try db.create(table: "assistant_usage") { t in
        t.column("entry_id", .text).primaryKey()
          .references("transcript_entries", onDelete: .cascade, onUpdate: .cascade)
        t.column("request_id", .text)
        t.column("model", .text).notNull()
        t.column("input_tokens", .integer).notNull()
        t.column("output_tokens", .integer).notNull()
        t.column("cache_creation_tokens", .integer).notNull()
        t.column("cache_read_tokens", .integer).notNull()
        t.column("service_tier", .text)
        t.column("ephemeral_5m_tokens", .integer)
        t.column("ephemeral_1h_tokens", .integer)
      }

      try db.create(index: "idx_usage_model", on: "assistant_usage", columns: ["model"])

      // Run ANALYZE to update statistics
      try db.execute(sql: "ANALYZE")
    }

    return migrator
  }

  /// Create all tables and indexes for the database (v1 base schema)
  private static func createBaseSchema(_ db: Database) throws {
    try db.execute(sql: "PRAGMA foreign_keys = ON")
    try db.execute(sql: "PRAGMA journal_mode = WAL")

    // Projects table
    try db.create(table: "projects", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("name", .text)
      t.column("root_path", .text).notNull()
      t.column("root_bookmark", .blob)
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()
    }
    try db.create(index: "idx_projects_root_path", on: "projects", columns: ["root_path"], unique: true, ifNotExists: true)

    // Transcripts table
    try db.create(table: "transcripts", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("project_id", .text).notNull().references("projects", onDelete: .cascade)
      t.column("file_path", .text).notNull()
      t.column("provider", .text).notNull().check(sql: "provider IN ('claude.code','codex.cli','other')")
      t.column("provider_session_id", .text)
      t.column("last_modified", .integer).notNull()
      t.column("file_size", .integer)
      t.column("line_count", .integer).notNull().defaults(to: 0)
      t.column("bookmark", .blob)
      // Ingestion state
      t.column("last_processed_line", .integer).notNull().defaults(to: 0)
      t.column("parser_version", .integer).notNull().defaults(to: 1)
      t.column("status", .text).notNull().defaults(to: "active").check(sql: "status IN ('active','unavailable','error')")
      t.column("last_error", .text)
      // Bookkeeping
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()

      t.uniqueKey(["project_id", "file_path"])
    }
    try db.create(index: "idx_transcripts_project", on: "transcripts", columns: ["project_id", "updated_at"], ifNotExists: true)
    try db.create(index: "idx_transcripts_status", on: "transcripts", columns: ["status"], ifNotExists: true, condition: "status != 'active'")
    try db.create(index: "idx_transcripts_provider_session", on: "transcripts", columns: ["provider_session_id"], ifNotExists: true, condition: "provider_session_id IS NOT NULL")

    // Transcript entries table
    try db.create(table: "transcript_entries", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("transcript_id", .text).notNull().references("transcripts", onDelete: .cascade)
      t.column("project_id", .text).notNull().references("projects", onDelete: .cascade)
      t.column("session_id", .text)
      t.column("provider", .text).notNull().check(sql: "provider IN ('claude.code','codex.cli','other')")
      t.column("kind", .text).notNull().check(sql: "kind IN ('user','assistant','system')")
      t.column("timestamp", .integer).notNull()
      t.column("content", .text).notNull()
      t.column("content_sha256", .text).notNull()
      t.column("display_in_timeline", .integer).notNull().defaults(to: 1)
      t.column("parent_id", .text).references("transcript_entries", onDelete: .setNull)
      t.column("git_branch", .text)
      t.column("git_commit", .text)
      t.column("cwd", .text)
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()
    }
    try db.create(index: "idx_entries_transcript_time", on: "transcript_entries", columns: ["transcript_id", "timestamp"], ifNotExists: true)
    try db.create(index: "idx_entries_content_sha", on: "transcript_entries", columns: ["content_sha256"], ifNotExists: true)
    // Project time indexes with DESC for ORDER BY performance
    try db.execute(sql: """
      CREATE INDEX IF NOT EXISTS idx_entries_project_time
      ON transcript_entries(project_id, timestamp DESC)
    """)
    try db.execute(sql: """
      CREATE INDEX IF NOT EXISTS idx_entries_project_feed
      ON transcript_entries(project_id, timestamp DESC)
      WHERE display_in_timeline = 1
    """)

    // Timeline cache table (WITHOUT ROWID for composite PK optimization)
    try db.execute(sql: """
      CREATE TABLE IF NOT EXISTS timeline_cache (
        content_sha256 TEXT NOT NULL,
        window_sha256 TEXT NOT NULL,
        entry_id TEXT NOT NULL REFERENCES transcript_entries(id) ON DELETE CASCADE,
        generator_signature TEXT NOT NULL,
        disposition TEXT NOT NULL,
        present_form TEXT NOT NULL,
        past_form TEXT NOT NULL,
        selected_form TEXT NOT NULL CHECK (selected_form IN ('present','past')),
        verb_lemma TEXT,
        generated_at INTEGER NOT NULL,
        user_edited INTEGER NOT NULL DEFAULT 0,
        user_text TEXT,
        edited_at INTEGER,
        request_id TEXT,
        duration REAL,
        PRIMARY KEY (content_sha256, window_sha256)
      ) WITHOUT ROWID
    """)
    try db.create(index: "idx_cache_entry_window", on: "timeline_cache", columns: ["entry_id", "window_sha256"], unique: true, ifNotExists: true)

    // Transcript metadata table
    try db.create(table: "transcript_metadata", ifNotExists: true) { t in
      t.column("transcript_id", .text).primaryKey().references("transcripts", onDelete: .cascade)
      t.column("project_id", .text).notNull().references("projects", onDelete: .cascade)
      t.column("title", .text).notNull()
      t.column("description", .text).notNull()
      t.column("topics", .text).notNull().check(sql: "json_valid(topics)")
      t.column("confidence", .double).notNull()
      t.column("may_contain_hallucinations", .integer).notNull().defaults(to: 0)
      t.column("needs_review", .integer).notNull().defaults(to: 0)
      t.column("generated_at", .integer).notNull()
      t.column("model", .text).notNull()
      t.column("prompt_version", .integer).notNull()
      t.column("generator_version", .integer).notNull()
      t.column("transcript_sha256", .text).notNull()
      t.column("message_count", .integer).notNull()
      t.column("strategy", .text).notNull().check(sql: "strategy IN ('full','bookends','heuristic')")
      t.column("llm_calls", .integer).notNull()
      t.column("latency_ms", .integer).notNull()
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()
    }
    try db.create(index: "idx_tmeta_project", on: "transcript_metadata", columns: ["project_id"], ifNotExists: true)
    try db.create(index: "idx_tmeta_needs_review", on: "transcript_metadata", columns: ["needs_review"], ifNotExists: true, condition: "needs_review = 1")
    try db.create(index: "idx_tmeta_prompt_ver", on: "transcript_metadata", columns: ["prompt_version"], ifNotExists: true)
    try db.create(index: "idx_tmeta_gen_ver", on: "transcript_metadata", columns: ["generator_version"], ifNotExists: true)

    // Parse errors table
    try db.create(table: "parse_errors", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("transcript_id", .text).notNull().references("transcripts", onDelete: .cascade)
      t.column("line_number", .integer).notNull()
      t.column("raw_line", .text).notNull()
      t.column("error_message", .text).notNull()
      t.column("created_at", .integer).notNull()
    }
    try db.create(index: "idx_parse_errors_transcript", on: "parse_errors", columns: ["transcript_id", "created_at"], ifNotExists: true)
  }
}
```

#### `app/Sources/ContextifyCore/Database/Repositories.swift`

```swift
import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "Repositories")

// MARK: - Project Repository

public protocol ProjectRepository {
  func create(name: String?, rootPath: String, bookmark: Data?) throws -> String
  func list() throws -> [Project]
  func get(id: String) throws -> Project?
  func update(id: String, name: String?, bookmark: Data?) throws
  func delete(id: String) throws
}

public final class ProjectRepositoryImpl: ProjectRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func create(name: String?, rootPath: String, bookmark: Data?) throws -> String {
    let id = UUID().uuidString
    let now = Int(Date().timeIntervalSince1970)
    let canonPath = PathUtils.canonicalizePath(rootPath)

    try db.write { db in
      let project = Project(
        id: id,
        name: name,
        rootPath: canonPath,
        rootBookmark: bookmark,
        createdAt: now,
        updatedAt: now
      )
      try project.insert(db)
    }

    return id
  }

  public func list() throws -> [Project] {
    try db.read { db in
      try Project.fetchAll(db)
    }
  }

  public func get(id: String) throws -> Project? {
    try db.read { db in
      try Project.fetchOne(db, key: id)
    }
  }

  public func update(id: String, name: String?, bookmark: Data?) throws {
    let now = Int(Date().timeIntervalSince1970)

    try db.write { db in
      guard var project = try Project.fetchOne(db, key: id) else {
        throw RepositoryError.notFound
      }
      project.name = name
      project.rootBookmark = bookmark
      project.updatedAt = now
      try project.update(db)
    }
  }

  public func delete(id: String) throws {
    try db.write { db in
      try Project.deleteOne(db, key: id)
    }
  }
}

// MARK: - Transcript Repository

public protocol TranscriptRepository {
  func upsert(
    projectId: String,
    fileURL: URL,
    provider: String,
    providerSessionId: String?,
    lastModified: Date,
    fileSize: Int?
  ) throws -> String

  func setIngestionState(
    id: String,
    lastProcessedLine: Int,
    lineCount: Int,
    parserVersion: Int,
    status: String,
    lastError: String?
  ) throws

  func byProject(_ projectId: String) throws -> [Transcript]
  func get(_ transcriptId: String) throws -> Transcript?
  func needsReparse(currentVersion: Int) throws -> [Transcript]

... (file continues - see full file at path above)
```

#### `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`

```swift
import Foundation
import GRDB
import OSLog
import CryptoKit

private let log = Logger(subsystem: "dev.contextify", category: "TranscriptOrchestrator")

// MARK: - Public API Types

/// Lightweight input for batch transcript discovery
public struct DiscoveredTranscript: Sendable {
  public let fileURL: URL
  public let provider: String
  public let sessionId: String?

  public init(fileURL: URL, provider: String, sessionId: String?) {
    self.fileURL = fileURL
    self.provider = provider
    self.sessionId = sessionId
  }
}

/// Output from transcript upsert with canonical ID
public struct ResolvedTranscript: Sendable {
  public let transcriptId: String
  public let fileURL: URL
  public let provider: String
  public let wasCreated: Bool  // true if new, false if existing

  public init(transcriptId: String, fileURL: URL, provider: String, wasCreated: Bool) {
    self.transcriptId = transcriptId
    self.fileURL = fileURL
    self.provider = provider
    self.wasCreated = wasCreated
  }
}

/// High-level orchestrator for transcript ingestion and monitoring
/// NOT @MainActor - allows safe concurrent access from background tasks
/// Sendable: GRDB pool handles thread-safety, repositories are stateless
public final class TranscriptOrchestrator: @unchecked Sendable {
  private let dbManager: DatabaseManager
  private let projectRepo: ProjectRepository
  private let transcriptRepo: TranscriptRepository
  private let entryRepo: EntryRepository
  private let errorRepo: ParseErrorRepository
  private let metadataRepo: MetadataRepository
  nonisolated(unsafe) private let cacheRepo: CacheRepository  // Thread-safe via GRDB pool

  private let hooverEngine: HooverEngine
  private let watcher: TranscriptWatcher

  public init(dbManager: DatabaseManager) throws {
    self.dbManager = dbManager
    let pool = try dbManager.pool

    // Initialize repositories
    self.projectRepo = ProjectRepositoryImpl(db: pool)
    self.transcriptRepo = TranscriptRepositoryImpl(db: pool)
    self.entryRepo = EntryRepositoryImpl(db: pool)
    self.errorRepo = ParseErrorRepositoryImpl(db: pool)
    self.metadataRepo = MetadataRepositoryImpl(db: pool)
    self.cacheRepo = CacheRepositoryImpl(db: pool)

    // v7: Initialize metadata repositories
    let fileSnapshotRepo = FileSnapshotRepositoryImpl(db: pool)
    let trackedFileRepo = TrackedFileRepositoryImpl(db: pool)
    let transcriptSummaryRepo = TranscriptSummaryRepositoryImpl(db: pool)
    let systemEventRepo = SystemEventRepositoryImpl(db: pool)
    let assistantUsageRepo = AssistantUsageRepositoryImpl(db: pool)

    // Initialize hoover engine with multi-provider parser
    let parser = MultiProviderParser()
    let metadataParser = MultiProviderMetadataParser()
    self.hooverEngine = HooverEngine(
      db: pool,
      transcriptRepo: transcriptRepo,
      entryRepo: entryRepo,
      errorRepo: errorRepo,
      parser: parser,
      fileSnapshotRepo: fileSnapshotRepo,
      trackedFileRepo: trackedFileRepo,
      transcriptSummaryRepo: transcriptSummaryRepo,
      systemEventRepo: systemEventRepo,
      assistantUsageRepo: assistantUsageRepo,
      metadataParser: metadataParser
    )

    // Initialize watcher (invalidation callback set after initialization)
    self.watcher = TranscriptWatcher(
      hooverEngine: hooverEngine,
      transcriptRepo: transcriptRepo
    )

    // Set metadata invalidation callback with weak self reference
    watcher.setMetadataInvalidator { [weak self] transcriptId in
      try? self?.deleteMetadata(forTranscript: transcriptId)
    }
  }

  // MARK: - Project Management

  public func createProject(name: String?, rootPath: String, bookmark: Data?) throws -> String {
    try projectRepo.create(name: name, rootPath: rootPath, bookmark: bookmark)
  }

  public func getOrCreateProject(name: String?, rootPath: String, bookmark: Data? = nil) throws -> String {
    // Try to find existing project by canonicalized path
    let canon = PathUtils.canonicalizePath(rootPath)
    if let existing = try projectRepo.list().first(where: { $0.rootPath == canon }) {
      log.info("Found existing project: \(existing.id) for path: \(canon)")
      return existing.id
    }

    // Create new project
    let projectId = try projectRepo.create(name: name, rootPath: rootPath, bookmark: bookmark)
    log.info("Created new project: \(projectId) for path: \(canon)")

    // Verify the project was created
    if let verified = try projectRepo.get(id: projectId) {
      log.info("✅ Project creation verified: \(verified.id)")
    } else {
      log.error("❌ Project creation failed - cannot retrieve project \(projectId)")
    }

    return projectId
  }

  public func listProjects() throws -> [Project] {
    try projectRepo.list()
  }

  public func getProject(id: String) throws -> Project? {
    try projectRepo.get(id: id)
  }

  // MARK: - Transcript Discovery & Ingestion

  /// Discover and ingest a transcript file
  public func discoverTranscript(
    projectId: String,
    fileURL: URL,
    provider: String,
    providerSessionId: String?,
    startWatching: Bool = true,
    progress: IngestProgressSink? = nil
  ) throws {
    // Diagnostic: Verify project exists before proceeding
    guard let project = try projectRepo.get(id: projectId) else {
      log.error("❌ FK validation failed: project \(projectId) does not exist")
      throw RepositoryError.notFound
    }
    log.debug("✅ FK validation: project \(projectId) exists")

    // Get file metadata
    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let lastModified = attrs[.modificationDate] as? Date ?? Date()
    let fileSize = attrs[.size] as? Int

    // Upsert transcript record
    log.debug("Upserting transcript for project \(projectId), file: \(fileURL.lastPathComponent)")
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: fileURL,
      provider: provider,
      providerSessionId: providerSessionId,
      lastModified: lastModified,
      fileSize: fileSize
    )
    log.debug("✅ Transcript upserted: \(transcriptId)")

    // Get transcript
    guard let transcript = try transcriptRepo.get(transcriptId) else {
      log.error("❌ Transcript \(transcriptId) not found after upsert")
      throw RepositoryError.notFound
    }

    // Verify transcript has correct project ID
    guard transcript.projectId == projectId else {
      log.error("❌ Transcript projectId mismatch: expected \(projectId), got \(transcript.projectId)")
      throw RepositoryError.invalidData
    }

    // Hoover the transcript
    log.debug("Hoovering transcript: \(transcriptId)")
    let progressSink = progress ?? NoOpProgressSink()
    let transcriptSHA256 = try hooverEngine.hooverTranscript(transcript, fileURL: fileURL, progress: progressSink)
    // TODO: pass transcriptSHA256 to metadata generation/persistence when implemented

    // Start watching if requested
    if startWatching {
      try watcher.watch(transcriptId: transcriptId, fileURL: fileURL)
    }

    log.info("Discovered and hoovered transcript: \(transcriptId)")
  }

  /// Batch discover transcripts for a project
  public func discoverTranscripts(
    projectId: String,

... (file continues - see full file at path above)
```

#### `Contextify/Contextify/ConversationMonitor.swift`

```swift
import Foundation
import Observation
import OSLog
import ContextifyCore
import AppKit

/// Single-source container for timeline entries and derived cache index
@MainActor
@Observable
final class TimelineState {
    var entries: [TimelineEntry] = []
    private(set) var revision: UInt64 = 0

    // Derived map stays in sync because it's computed
    var indexByCacheKey: [CacheKey: Int] {
        Dictionary(uniqueKeysWithValues: entries.enumerated().compactMap { i, e in
            e.cacheKey.map { ($0, i) }
        })
    }

    func replace(with entries: [TimelineEntry]) {
        self.entries = entries
        revision &+= 1
    }

    func append(_ e: TimelineEntry) {
        entries.append(e)
        revision &+= 1
    }

    func update(at index: Int, to newValue: TimelineEntry) {
        guard entries.indices.contains(index) else { return }
        entries[index] = newValue
        revision &+= 1
    }

    func sortChronologically() {
        entries.sort { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return a.sourceIdentifier < b.sourceIdentifier
        }
        revision &+= 1
    }

    func trim(to max: Int) {
        if entries.count > max { entries = Array(entries.suffix(max)); revision &+= 1 }
    }
}

@Observable
@MainActor
final class ConversationMonitor {
    static let shared = ConversationMonitor()

    private let log = Logger(subsystem: "dev.contextify", category: "Timeline")
    private let config = MonitorConfig()
    // conversationResolver removed - now using database-backed session discovery
    private let affirmativeLexicon: Set<String> = [
        "yes", "y", "ok", "okay", "sure", "👍", "yep", "yup", "sounds", "good", "go", "ahead",
        "proceed", "do", "it", "please", "sgtm", "roger", "affirmative", "yeah", "yah", "make", "so"
    ]
    private let negativeLexicon: Set<String> = [
        "no", "nope", "nah", "not", "now", "yet", "hold", "off", "stop", "don't", "do", "cancel", "abort"
    ]
    private let actionHintCues: [String] = [
        "would you like me to", "shall i", "i can ", "i will ",
        "proceed", "change it to", "ensure ", "run ", "fix ", "update ", "refactor ", "implement "
    ]

    private let state = TimelineState()

    /// Read-only view over state.entries (single source of truth)
    var entries: [TimelineEntry] { state.entries }

    /// All entries are visible - sessions appear as one continuous stream
    /// No filtering by session - timeline shows chronological view across all sessions
    var visibleEntries: [TimelineEntry] {
        state.entries
    }

    private(set) var isCollapsed = false
    private(set) var isMonitoring = false
    private(set) var isProcessing = false
    private(set) var lastError: String?
    private(set) var lastUpdate: Date?
    var autoScroll = true

    @ObservationIgnored private var didEmitSessionStart = false
    @ObservationIgnored private(set) var activeSession: TranscriptSession?
    // MUST be observable for UI - inventory and session switching depend on this
    private(set) var allSessions: [TranscriptSession] = []
    @ObservationIgnored private var lastUserDirectiveId: UUID?
    @ObservationIgnored private var lastUserDirectiveTimestamp: Date?
    @ObservationIgnored private var sessionEpoch = UUID()  // Track session to cancel cross-session tasks
    // Tracks the currently selected session for inventory UI (not used for timeline filtering)
    private var currentSessionId: String? {
        didSet {
            onProjectOrSessionChange()
        }
    }
    @ObservationIgnored private var currentProjectId: String? {  // SQL project ID
        didSet {
            onProjectOrSessionChange()
        }
    }
    @ObservationIgnored private var lastSeenCursor: (timestamp: Int, createdAt: Int, id: String)?  // Keyset cursor for incremental updates
    @ObservationIgnored var orchestrator: TranscriptOrchestrator!  // Shared instance (nonisolated, accessible to inventory view)
    @ObservationIgnored private var seenEntryIDs = Set<String>()  // Deduplicate entries
    @ObservationIgnored private var backgroundTasks: Task<Void, Never>?  // Parent task for all background work
    @ObservationIgnored private var cacheMissGenerator: TimelineCacheMissGenerator?  // Background cache generation
    @ObservationIgnored private var cacheUpdateObserver: NSObjectProtocol?  // For cache update notifications
    @ObservationIgnored private var projectChangeObserver: NSObjectProtocol?  // For project root change notifications
    @ObservationIgnored private var updateInFlight = false  // Single-flight guard for processIncrementalUpdate
    @ObservationIgnored private var updateDirty = false    // Marks that updates arrived during processing
    @ObservationIgnored private let updateDrainMaxItersDefault = 8  // Max drain loop iterations to prevent starvation
    @ObservationIgnored private var updateDrainItersRemaining = 8  // Current iterations remaining
    @ObservationIgnored private var debounceTask: Task<Void, Never>?  // Debounce task for transcript updates

    private init() {}

    @MainActor
    func startMonitoring() {
        // Cancel residual background work before starting new group
        backgroundTasks?.cancel()
        backgroundTasks = nil
        seenEntryIDs.removeAll(keepingCapacity: false)

        guard !isMonitoring else { return }

        log.info("⭐️ Timeline integration starting")
        log.info("Starting SQL-based timeline monitoring")

        Task { @MainActor [weak self] in
            guard let self else { return }

            // 1. Get project from HUD
            guard let projectRoot = HUDViewModel.shared.projectRootURL else {
                self.lastError = "No project root set"
                self.log.error("No project root URL available from HUDViewModel")
                return
            }

            // 2. Initialize shared orchestrator (nonisolated - safe for concurrent access)
            do {
                self.orchestrator = try TranscriptOrchestrator(dbManager: .shared)

                // CRITICAL: Create project on main actor and wait for DB commit
                // This ensures the project exists before background tasks access it
                self.currentProjectId = try self.orchestrator.getOrCreateProject(
                    name: projectRoot.lastPathComponent,
                    rootPath: projectRoot.path
                )
                self.log.info("📁 Project ID set: \(self.currentProjectId ?? "nil")")

                // Verify project was persisted (forces read from DB, ensures commit)
                let projectId = self.currentProjectId!
                guard let _ = try self.orchestrator.getProject(id: projectId) else {
                    self.lastError = "Failed to verify project creation"
                    self.log.error("❌ Project \(projectId) not found after creation")
                    return
                }
                self.log.info("✅ Project \(projectId) verified in database")

                // 3. Initialize cache miss generator
                self.cacheMissGenerator = TimelineCacheMissGenerator(orchestrator: self.orchestrator)

                // 4. Start background work (discovery + debounced updates) in a single parent task
                let orchestrator = self.orchestrator!
                self.log.info("🚀 Spawning background tasks for project: \(projectId)")
                self.backgroundTasks = Task { [weak self] in
                    guard let self else { return }

                    // Initialize metadata orchestrator with SQL backend (await before use)
                    await TranscriptMetadataOrchestrator.shared.initialize(orchestrator: orchestrator)

                    await withTaskGroup(of: Void.self) { group in
                        // Task 1: Discovery loop (structured, cancellable)
                        group.addTask { [weak self] in
                            guard let self else { return }
                            do {
                                try await self.discoverNewTranscripts(projectId: projectId, orchestrator: orchestrator)
                            } catch is CancellationError {
                                return
                            } catch {
                                await MainActor.run {
                                    self.log.error("Background discovery failed: \(error.localizedDescription, privacy: .public)")
                                }
                            }
                        }

                        // Task 2: Debounced transcript updates
                        group.addTask { [weak self] in
                            await self?.watchForDebouncedTranscriptUpdates()
                        }
                    }
                }

                // 5. Load initial feed (fast - single query)
                await self.loadFeedFromSQL()

                // 6. Subscribe to realtime updates (SQL notifications handled by watchForDebouncedTranscriptUpdates)
                // self.setupSQLNotifications()  // Disabled: debouncing is handled by background watcher
                self.setupCacheUpdateNotifications()
                self.setupProjectChangeNotifications()

                self.isMonitoring = true
                self.log.info("SQL-based timeline monitoring started for project: \(projectRoot.lastPathComponent)")
            } catch {
                self.lastError = "Failed to start monitoring: \(error.localizedDescription)"
                self.log.error("Monitoring startup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    func stopMonitoring() {
        isMonitoring = false
        activeSession = nil
        backgroundTasks?.cancel()   // NEW: cancels the whole background task group
        backgroundTasks = nil
        debounceTask?.cancel()
        debounceTask = nil

        if let observer = cacheUpdateObserver {
            NotificationCenter.default.removeObserver(observer)
            cacheUpdateObserver = nil
        }

        if let observer = projectChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            projectChangeObserver = nil
        }

        // Stop all watchers using shared orchestrator
        if orchestrator != nil {
            orchestrator.stopAllWatchers()
        }

        // Clear state
        seenEntryIDs.removeAll()
        lastSeenCursor = nil
        currentProjectId = nil
        cacheMissGenerator = nil
    }

    /// Cancel pending debounce task on project changes to avoid late callbacks into torn state
    @MainActor
    private func onProjectOrSessionChange() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// Structured watcher for debounced transcript updates (off main actor, no polling)
    private func watchForDebouncedTranscriptUpdates() async {
        let center = NotificationCenter.default
        let name = NSNotification.Name("TranscriptUpdated")

        for await note in center.notifications(named: name) {
            if Task.isCancelled { break }
            let pid = note.userInfo?["projectId"] as? String

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard pid == nil || pid == self.currentProjectId else { return }

                // Cancel existing debounce task and start new one
                self.debounceTask?.cancel()
                self.debounceTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms
                    guard let self, !Task.isCancelled else { return }
                    await self.processIncrementalUpdate()
                }
            }
        }
    }

    @available(*, unavailable, message: "Use watchForDebouncedTranscriptUpdates()")
    private func handleTranscriptUpdate(projectId: String?) async {}

    @MainActor
    private func pruneSeenIDsIfNeeded() {
        let cap = config.maxEntries * 2
        if seenEntryIDs.count > cap {
            seenEntryIDs = Set(state.entries.map { $0.sourceIdentifier })
        }
    }

    @MainActor
    private func setEntries(_ new: [TimelineEntry]) {
        state.replace(with: new)
    }

    @MainActor
    private func appendEntry(_ e: TimelineEntry) {
        state.append(e)
    }

    @MainActor
    private func updateEntry(at i: Int, with e: TimelineEntry) {
        state.update(at: i, to: e)

... (file continues - see full file at path above)
```

#### `app/Sources/ContextifyCore/HUDCore.swift` (HUDViewModel)

```swift
import Foundation
import Observation
import OSLog
import Dispatch
import Darwin

#if os(macOS)
import AppKit
#endif

// MARK: - HUDPreferences

public enum HUDPreferences {
  public static let projectRootKey = "dev.contextify.projectRoot"
  public static let projectRootBookmarkKey = "dev.contextify.projectRootBookmark"
  public static let autoPersistKey = "dev.contextify.autoPersist"

  nonisolated(unsafe) private static let sharedDefaults: UserDefaults = {
    if let suite = UserDefaults(suiteName: "dev.contextify"), probeDefaultsWriteability(suite) {
      return suite
    }
    return .standard
  }()
  nonisolated(unsafe) private static var hasWarnedLegacyDefaults = false

  public static func getPersistedRoot() -> String? {
    warnIfLegacyDefaultsPresent()
    return sharedDefaults.string(forKey: projectRootKey)
  }

  public static func setPersistedRoot(_ path: String?) {
    guard let path, !path.isEmpty else {
      clearPersistedRoot()
      return
    }
    storeRootURL(URL(fileURLWithPath: path))
  }

  public static func setPersistedRoot(_ url: URL) {
    storeRootURL(url)
  }

  public static func clearPersistedRoot() {
    sharedDefaults.removeObject(forKey: projectRootKey)
    sharedDefaults.removeObject(forKey: projectRootBookmarkKey)
  }

  public static func shouldAutoPersist() -> Bool {
    warnIfLegacyDefaultsPresent()
    if let value = sharedDefaults.object(forKey: autoPersistKey) as? Bool { return value }
    return true
  }

  public static func setAutoPersist(_ enabled: Bool) {
    sharedDefaults.set(enabled, forKey: autoPersistKey)
  }

  public static func resolveBookmark() -> URL? {
    guard let data = sharedDefaults.data(forKey: projectRootBookmarkKey) else { return nil }
    return resolveBookmarkData(data)
  }

  private static func resolveBookmarkData(_ data: Data) -> URL? {
    let primary: URL.BookmarkResolutionOptions = Sandbox.isSandboxed ? [.withSecurityScope] : []
    for options in [primary, []] {
      var stale = false
      do {
        let url = try URL(
          resolvingBookmarkData: data,
          options: options,
          relativeTo: nil,
          bookmarkDataIsStale: &stale
        )
        if stale {
          storeRootURL(url)
        }
        return url
      } catch {
        continue
      }
    }
    sharedDefaults.removeObject(forKey: projectRootBookmarkKey)
    if let path = sharedDefaults.string(forKey: projectRootKey) {
      var isDir: ObjCBool = false
      if !(FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue) {
        sharedDefaults.removeObject(forKey: projectRootKey)
      }
    }
    return nil
  }

  private static func storeRootURL(_ url: URL) {
    let canonical = url.resolvingSymlinksInPath()
    sharedDefaults.set(canonical.path, forKey: projectRootKey)
    try? storeBookmark(for: canonical)
  }

  private static func storeBookmark(for url: URL) throws {
    #if os(macOS)
    let options: URL.BookmarkCreationOptions = Sandbox.isSandboxed ? [.withSecurityScope] : []
    let data = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    sharedDefaults.set(data, forKey: projectRootBookmarkKey)
    #endif
  }

  @discardableResult
  private static func probeDefaultsWriteability(_ defaults: UserDefaults) -> Bool {
    let probeKey = "dev.contextify.defaults.probe"
    defaults.set(true, forKey: probeKey)
    if defaults.bool(forKey: probeKey) != true {
      defaults.removeObject(forKey: probeKey)
      return false
    }
    defaults.removeObject(forKey: probeKey)
    return true
  }

  private static func warnIfLegacyDefaultsPresent() {
    guard !hasWarnedLegacyDefaults else { return }
    let legacyDefaults = UserDefaults.standard
    let legacyKeys = [projectRootKey, projectRootBookmarkKey, autoPersistKey]
      .filter { legacyDefaults.object(forKey: $0) != nil }
    guard !legacyKeys.isEmpty else { return }
    hasWarnedLegacyDefaults = true
  }
}

// MARK: - Sandbox

enum Sandbox {
  static var isSandboxed: Bool {
    #if os(macOS)
    if getenv("APP_SANDBOX_CONTAINER_ID") != nil { return true }
    if ProcessInfo.processInfo.environment["__XPC_SANDBOXED"] == "1" { return true }
    #endif
    return false
  }
}

// MARK: - GitRepositoryResolver

public struct GitRepositoryResolver {
  private static let processLog = Logger(subsystem: "dev.contextify", category: "GitProcess")

  public struct GitInfoResult: Sendable {
    public let root: URL?
    public let branch: String?
    public let source: String?
    public let shouldPersist: Bool
    public let alertMessage: String?
    public let clearPersisted: Bool
  }

  public static func computeGitInfo(
    environment: [String: String],
    persistedPath: String?,
    currentRoot: URL?,
    autoPersist: Bool
  ) -> GitInfoResult {
    var alerts: [String] = []
    var candidateRoot: URL? = nil
    var candidateSource: String? = nil
    var candidatePersist = false
    var clearPersisted = false
    var sawEnvOverride = false

    if let envPath = environment["CONTEXTIFY_PROJECT_ROOT"], !envPath.isEmpty {
      sawEnvOverride = true
      let base = URL(fileURLWithPath: envPath).resolvingSymlinksInPath()
      var envIsDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: base.path, isDirectory: &envIsDir), envIsDir.boolValue,
         let root = findGitRoot(startingAt: base) {
        candidateRoot = root
        candidateSource = "env"
        candidatePersist = autoPersist
      } else {
        alerts.append("CONTEXTIFY_PROJECT_ROOT invalid/unreadable:\n\(base.path)")
      }
    }

    if candidateRoot == nil, let persistedPath, !persistedPath.isEmpty {
      let base = URL(fileURLWithPath: persistedPath).resolvingSymlinksInPath()
      var savedIsDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: base.path, isDirectory: &savedIsDir), savedIsDir.boolValue,
         let root = findGitRoot(startingAt: base) {
        candidateRoot = root
        candidateSource = "saved"
        candidatePersist = false
      } else {
        clearPersisted = true
        alerts.append("Stored project root is invalid or unreadable (saved path):\n\(base.path)")
      }
    }

    if candidateRoot == nil, !sawEnvOverride {
      let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      if let cwdRoot = findGitRoot(startingAt: cwd) {
        candidateRoot = cwdRoot
        candidateSource = "cwd"
        candidatePersist = autoPersist

... (file continues - see full file at path above)
```

#### `Contextify/Contextify/ContentView.swift`

```swift
//
//  ContentView.swift
//  Contextify
//
//  Created by Rob Banagale on 9/13/25.
//

import SwiftUI
import AppKit
import OSLog

import ContextifyCore
private let uiLog = Logger(subsystem: "dev.contextify", category: "UI")

struct ContentView: View {
    @Environment(HUDViewModel.self) private var model
    @Environment(ConversationMonitor.self) private var timeline
    @Environment(DeveloperMode.self) private var devMode
    @State private var showToast = false
    @State private var toastText = ""
    @State private var showEmbeddingTest = false
    @State private var showDatabaseTest = false
    @State private var showBatchEmbedding = false
    @State private var showSemanticSearch = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                // REMOVED UI (2025-10-02): Contextify file/URL ingestion features
                // Previously here:
                // - urlEntry: TextField + "Ingest" button for URL ingestion
                // - IngestDropZone: Drag-and-drop zone for files
                // - controls: "New Session", "Checkpoint", "Reveal Outputs" buttons
                // - Session label (e.g., "Session-001")
                // - Status display / Last output URL
                //
                // These features created timestamped Markdown artifacts in ~/Contextify/outputs
                // For restoration, see git history or build/notes/archive/2025-10-02-compose-panel.md
                composeSection
            }
            .frame(minWidth: 640)
            .padding(16)

            ConversationTimelineView()
        }
        .background(WindowTitleWriter(title: "Contextify"))
        .overlay(alignment: .top) { toast }
        .onAppear {
            model.updateGitInfo()
            Task { await refreshSession() }
            TimelineIntegration.shared.startMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextifyShowToast)) { notification in
            guard let payload = notification.userInfo?[ToastPayloadKey.message] as? String else { return }
            let duration = notification.userInfo?[ToastPayloadKey.duration] as? TimeInterval
            presentToast(payload, duration: duration)
        }
        .alert("Project Root", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: model.state) { _, newState in
            if case .success(let msg) = newState {
                toastText = msg
                withAnimation { showToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { showToast = false }
                }
            }
        }
        .frame(minWidth: 940, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let projectPath = model.projectRootURL?.path {
                HStack(spacing: 4) {
                    Button {
                        let ok = pickProjectRoot()
                        uiLog.info("Open project result=\(ok, privacy: .public)")
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Open project...")

                    Text(model.projectDisplayName)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    ProjectBadgesView(projectPath: projectPath)
                }
                Label(model.branchDisplay, systemImage: "arrow.branch")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            } else {
                Button("Open project...") {
                    let ok = pickProjectRoot()
                    uiLog.info("Open project result=\(ok, privacy: .public)")
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("set-project-root")
            }
            Spacer()

            // Developer-only test buttons (hidden by default)
            if devMode.isEnabled {
              Button(action: { showEmbeddingTest.toggle() }) {
                  Image(systemName: "testtube.2")
              }
              .buttonStyle(.borderless)
              .help("Test Embedding Service")

              Button(action: { showDatabaseTest.toggle() }) {
                  Image(systemName: "cylinder")
              }
              .buttonStyle(.borderless)
              .help("Test Embedding Database")
            }

            Button(action: { showBatchEmbedding.toggle() }) {
                Image(systemName: "gearshape.2")
            }
            .buttonStyle(.borderless)
            .help("Batch Embedding Generation")

            Button(action: { showSemanticSearch.toggle() }) {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless)
            .help("Semantic Search")
        }
        .sheet(isPresented: $showEmbeddingTest) {
            EmbeddingTestView()
        }
        .sheet(isPresented: $showDatabaseTest) {
            EmbeddingDatabaseTestView()
        }
        .sheet(isPresented: $showBatchEmbedding) {
            BatchEmbeddingView()
        }
        .sheet(isPresented: $showSemanticSearch) {
            SemanticSearchView()

... (file continues - see full file at path above)
```

