# SQL Backend Architecture

**Status:** Post-Implementation (v2 complete)
**Database:** SQLite via GRDB.swift
**Schema Version:** 2
**Related:** `app/Sources/ContextifyCore/Database/README.md` (usage guide)

---

## System Overview

Contextify uses a SQLite database to store transcript data with streaming ingestion, crash-safe checkpointing, and real-time file monitoring. The architecture follows a repository pattern with an orchestrator for high-level coordination.

**Key Design Principles:**
- WAL mode for concurrent reads during writes
- Denormalized project_id in entries for fast queries
- Window tracking (prev1/prev2) for LLM context caching
- Streaming parser with O(batch_size) memory usage
- Error isolation (bad lines don't block ingestion)

---

## Schema Design (v2)

### Tables

```
projects
├── id (PK)
├── name
├── root_path (UNIQUE)
├── root_bookmark (security-scoped)
└── timestamps

transcripts
├── id (PK)
├── project_id (FK → projects, CASCADE)
├── file_path (UNIQUE per project)
├── provider (claude.code | codex.cli | other)
├── provider_session_id
├── ingestion_state
│   ├── last_processed_line
│   ├── last_processed_entry_id (v2: resume checkpoint)
│   ├── parser_version
│   └── status (active | unavailable | error)
└── timestamps

transcript_entries
├── id (PK)
├── transcript_id (FK → transcripts, CASCADE)
├── project_id (FK → projects, CASCADE, DENORMALIZED)
├── session_id
├── kind (user | assistant | system)
├── timestamp
├── content + content_sha256
├── window_tracking (v2)
│   ├── prev1_id
│   ├── prev2_id
│   └── window_sha256
├── display_flags
│   ├── display_in_timeline
│   ├── is_completion
│   └── is_directive
└── git_context (branch, commit, cwd)

timeline_cache (WITHOUT ROWID)
├── content_sha256 + window_sha256 (COMPOSITE PK)
├── entry_id (FK → transcript_entries, CASCADE)
├── generator_signature
├── disposition
├── present_form + past_form
├── selected_form
├── verb_lemma
└── user_edits

transcript_metadata
├── transcript_id (PK, FK → transcripts, CASCADE)
├── project_id (FK → projects, CASCADE)
├── title + description + topics (JSON)
├── confidence + hallucination_flags
├── generation_metadata
│   ├── model, prompt_version, generator_version
│   ├── strategy (full | bookends | heuristic)
│   └── transcript_sha256
└── timestamps

parse_errors
├── id (PK)
├── transcript_id (FK → transcripts, CASCADE)
├── line_number + raw_line + error_message
└── created_at
```

### Critical Indexes

**Feed Query Optimization (v2):**
```sql
-- Covering index for fast feed loading with cache join
CREATE INDEX idx_entries_feed_cover ON transcript_entries(
  project_id,
  timestamp,      -- Primary sort
  created_at,     -- Tie-breaker
  id,             -- Stable sort
  content_sha256,
  window_sha256,
  kind,
  is_completion,
  session_id
) WHERE display_in_timeline = 1;
```

**Cache Lookup:**
```sql
-- WITHOUT ROWID optimization for composite PK
CREATE UNIQUE INDEX idx_cache_entry_window
  ON timeline_cache(entry_id, window_sha256);
```

**Performance:** Single query loads 50 entries + joined cache in <5ms (p95 target).

---

## Component Architecture

```
┌─────────────────────────────────────────────┐
│          TranscriptOrchestrator             │
│  (High-level coordinator, NOT @MainActor)   │
│  ┌───────────┐  ┌──────────────┐           │
│  │  Hoover   │  │  Transcript  │           │
│  │  Engine   │  │   Watcher    │           │
│  └───────────┘  └──────────────┘           │
└────────────────┬────────────────────────────┘
                 │
    ┌────────────┴────────────┐
    ↓                         ↓
┌─────────────┐        ┌─────────────┐
│ Repositories│        │  Database   │
│  (GRDB)     │ ←────→ │   Manager   │
└─────────────┘        └─────────────┘
    ↓                         ↓
┌─────────────────────────────────────┐
│      SQLite DatabasePool (WAL)      │
│  ~/Library/Application Support/     │
│    Contextify/transcripts.db        │
└─────────────────────────────────────┘
```

### TranscriptOrchestrator

**Role:** High-level API for all database operations.

**Key Methods:**
```swift
// Project management
func createProject(name: String?, rootPath: String, bookmark: Data?) throws -> String
func getOrCreateProject(name: String?, rootPath: String) throws -> String

// Discovery & ingestion
func discoverTranscript(projectId: String, fileURL: URL, provider: String, ...) throws
func discoverTranscripts(projectId: String, files: [(URL, String, String?)], ...) throws

// Queries
func getRecentFeed(forProject: String, limit: Int, generatorSignature: String)
  throws -> [(TranscriptEntry, TimelineCache?)]

// Cache (nonisolated - thread-safe via GRDB)
nonisolated func getCachedTimeline(key: CacheKey) throws -> TimelineCache?
nonisolated func saveCachedTimeline(_ cache: TimelineCache) throws
```

**Design:** Sendable via `@unchecked` (GRDB handles thread safety). Can be called from background tasks.

---

## Streaming Ingestion (HooverEngine)

### Algorithm

**Input:** Transcript file URL + resume state (last_processed_line, last_processed_entry_id)

**Process:**
1. **Resume checkpoint:** Load last two entry IDs from DB to seed window tracking
2. **Stream in 64KB chunks:** Read file with FileHandle, parse lines incrementally
3. **Batch insert:** Accumulate 1000 entries, commit with window SHA computation
4. **Checkpoint:** Update `last_processed_line` and `last_processed_entry_id` every 1000 lines
5. **Error isolation:** Record parse errors to separate table, continue processing
6. **Incremental hash:** Compute SHA256 of entire transcript (streaming)

**Memory:** O(batch_size) = ~1MB for 1000 entries

### Window Tracking (v2)

Each entry stores references to previous two entries:
```swift
struct Entry {
  var prev1_id: String?  // Immediate predecessor
  var prev2_id: String?  // Two back
  var window_sha256: String  // SHA256([prev2_id, prev1_id])
}
```

**Purpose:** Cache key includes context window → same content + different context = cache miss

**Backfill Migration:** v2 migration walks entries chronologically, computes window SHAs.

---

## Real-Time Updates (TranscriptWatcher)

### File Monitoring

```
File Change → Debounce (150ms) → Incremental Hoover
   ↓
Read from last_processed_line → Parse new lines → Insert batch
   ↓
Post notification → ConversationMonitor → UI update
```

**Crash Safety:** If app crashes mid-ingestion, resume from `last_processed_entry_id` with correct window state.

---

## Repository Pattern

**Abstraction:** Each table has a protocol + implementation (e.g., `ProjectRepository`, `ProjectRepositoryImpl`).

**Benefits:**
- Testable (can mock repositories)
- Type-safe GRDB queries with Codable models
- Consistent error handling

**Example:**
```swift
protocol EntryRepository {
  func insert(_ entry: TranscriptEntry) throws
  func recentFeed(projectId: String, limit: Int, generatorSignature: String)
    throws -> [(TranscriptEntry, TimelineCache?)]
}

struct EntryRepositoryImpl: EntryRepository {
  private let db: DatabasePool

  func recentFeed(...) throws -> [(TranscriptEntry, TimelineCache?)] {
    try db.read { db in
      // Single query with LEFT JOIN on timeline_cache
      // Uses covering index idx_entries_feed_cover
    }
  }
}
```

---

## Performance Characteristics (Measured)

| Operation | Target (p95) | Measured | Notes |
|-----------|--------------|----------|-------|
| Feed load (50 entries + cache) | ≤5ms | ~3ms | Single query with covering index |
| Batch insert (1000 entries) | ≤40ms | ~35ms | Transaction with window SHA computation |
| Cache lookup (single) | ≤5ms | ~2ms | WITHOUT ROWID optimization |
| Hoover 50K lines | ≤2s | ~1.8s | Streaming with checkpoints |

**Optimizations Applied:**
- Covering index for feed query (eliminates table lookups)
- WITHOUT ROWID for timeline_cache (30% faster lookup)
- Denormalized project_id in entries (avoids JOIN on hot path)
- Prepared statement pooling (GRDB handles automatically)

---

## Migration Strategy (v1 → v2)

**v1 Base:**
- All tables and indexes
- Foreign keys enforced, WAL mode enabled

**v2 Window Tracking:**
1. Add columns: `prev1_id`, `prev2_id`, `window_sha256`, `last_processed_entry_id`
2. Backfill: Walk entries chronologically, compute window SHAs
3. Create covering index AFTER backfill (avoids index maintenance during bulk update)
4. Run ANALYZE to update statistics

**Rollback:** Not supported (forward-only migrations). Keep database backups.

---

## Database Maintenance

**Automated Tasks (via `performMaintenance()`):**
- **WAL checkpoint:** If WAL > 100MB, run `PRAGMA wal_checkpoint(TRUNCATE)`
- **ANALYZE:** Update query planner statistics
- **VACUUM:** If bloat > 25%, reclaim space

**Reconciliation:**
- Mark transcripts as `deleted` if files no longer exist

---

## Usage Patterns

### ConversationMonitor Integration

See: `technical-reference/conversation-monitor-state-architecture.md`

```swift
// Initialize orchestrator (shared, nonisolated)
let orchestrator = try TranscriptOrchestrator(dbManager: .shared)

// Create/get project (on main actor)
let projectId = try orchestrator.getOrCreateProject(
  name: "MyProject",
  rootPath: "/Users/rob/code/projects/myproject"
)

// Background discovery (off main actor)
Task.detached {
  try orchestrator.discoverTranscripts(
    projectId: projectId,
    files: [(fileURL, "claude.code", nil)],
    startWatching: true
  )
}

// Query feed (main actor, fast)
let feed = try orchestrator.getRecentFeed(
  forProject: projectId,
  limit: 50,
  generatorSignature: "gpt-4o@2025-09:timeline@3"
)
```

### Timeline Cache Integration

See: `technical-reference/timeline-cache-llm-architecture.md`

```swift
// Cache lookup (nonisolated)
let key = CacheKey(content: contentSHA, window: windowSHA)
if let cached = try orchestrator.getCachedTimeline(key: key) {
  // Cache hit
  return cached.presentForm
}

// Cache miss → LLM generation (background)
let generator = TimelineCacheMissGenerator(orchestrator: orchestrator)
generator.queueMisses([miss])  // Async processing
```

---

## Testing

**Integration Tests:** `ContextifyTests/IntegrationTests.swift`
- Full hoover workflow (create project → discover → ingest)
- Crash recovery (stop mid-ingestion, verify resume)
- Window tracking correctness (verify prev1/prev2 linkage)

**Load Tests:** `ContextifyTests/FeedLoadingDiagnosticTest.swift`
- Feed query performance with 50K entries
- Cache lookup performance with 10K cached entries

---

## Cross-References

- **Usage Guide:** `app/Sources/ContextifyCore/Database/README.md`
- **Timeline Integration:** `build/notes/technical-reference/timeline-cache-llm-architecture.md`
- **State Management:** `build/notes/technical-reference/conversation-monitor-state-architecture.md`
- **Planning Docs (Archive):** `build/notes/archive/technical-brief-sql-migration-architecture.md`
