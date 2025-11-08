# SQL Backend Architecture

**Status:** Post-Implementation (v20 current)
**Database:** SQLite via GRDB.swift
**Schema Version:** 20 (v18-v20: project visibility, display order, orphan tracking)
**Related:** `app/Sources/ContextifyCore/Database/README.md` (usage guide)

---

## System Overview

Contextify uses a SQLite database to store transcript data with streaming ingestion, crash-safe checkpointing, and real-time file monitoring. The architecture follows a repository pattern with an orchestrator for high-level coordination.

**Key Design Principles:**
- WAL mode for concurrent reads during writes
- Denormalized project_id in entries for fast queries (only denormalized field)
- Window tracking (prev1/prev2) for LLM context caching
- Streaming parser with O(batch_size) memory usage
- Error isolation (bad lines don't block ingestion)
- **Separation of concerns:** Canonical data (transcript_entries) vs. derived data (timeline_cache)

---

## Schema Design (v6)

### Tables

```
projects
├── id (PK)
├── name
├── root_path (UNIQUE)
├── root_bookmark (security-scoped)
├── last_viewed_ts (REAL, v12+, epoch for unread tracking)
├── hidden (INTEGER DEFAULT 0, v18+, hide from UI)
├── display_order (INTEGER, v19+, tab ordering)
├── is_orphaned (INTEGER DEFAULT 0, v20+, directory missing)
├── orphaned_since (TEXT, v20+, ISO8601 timestamp)
└── timestamps

transcripts
├── id (PK)
├── project_id (FK → projects, CASCADE)
├── file_path (UNIQUE per project)
├── provider (claude.code | codex.cli | other)
├── provider_session_id
├── ingestion_state
│   ├── last_processed_line
│   ├── last_processed_entry_id (v2+: resume checkpoint)
│   ├── parser_version
│   └── status (active | unavailable | error)
└── timestamps

transcript_entries (CANONICAL SOURCE DATA - v6: removed denormalized fields)
├── id (PK)
├── transcript_id (FK → transcripts, CASCADE)
├── project_id (FK → projects, CASCADE, DENORMALIZED for query performance)
├── session_id
├── kind (user | assistant | system)
├── timestamp
├── content + content_sha256
├── window_tracking (v2+)
│   ├── prev1_id
│   ├── prev2_id
│   └── window_sha256 (for cache key computation)
├── display_in_timeline (1 = show, 0 = hide thinking-only entries)
├── created_ts (REAL, v12+, millisecond-precision epoch for unread queries)
├── git_context (branch, commit, cwd)
└── embedding (BLOB, optional for RAG features)
    └── v6 REMOVED: summary, disposition, is_completion, is_directive
                   (all moved to timeline_cache - see "Schema Evolution" below)

timeline_cache (WITHOUT ROWID - DERIVED/COMPUTED DATA)
├── content_sha256 + window_sha256 (COMPOSITE PK, NO generator_signature)
├── entry_id (FK → transcript_entries, CASCADE)
├── generator_signature (filter column, NOT in PK)
├── disposition (SOURCE OF TRUTH for isDirective/isCompletion flags)
│   └── Values: directive, affirmative, negative, completion, analysis,
│                proposal, question, unknown
├── present_form + past_form (LLM-generated summaries)
├── selected_form
├── verb_lemma
└── user_edits (user_edited, user_text, edited_at)

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

### Schema Evolution

**v6 Migration (2025-10-23): Denormalization Removal**

Removed denormalized fields from `transcript_entries` that violated data architecture principles:
- `summary` (TEXT) - Always NULL, never populated
- `disposition` (TEXT) - Always NULL, never populated
- `is_completion` (INTEGER) - Derived flag, now computed from disposition at runtime
- `is_directive` (INTEGER) - Derived flag, now computed from disposition at runtime

**Rationale:**
- `transcript_entries` should contain only canonical data from transcript files
- LLM-generated classifications belong in `timeline_cache` (single source of truth)
- Avoids update anomalies (flags inconsistent with disposition)
- Allows regenerating classifications without touching source data

**UI Flag Derivation (post-v6):**
```swift
// ConversationMonitor.swift:513-517
let cached = try? orchestrator.getCachedTimeline(
  contentSha256: entry.contentSha256,
  windowSha256: entry.windowSha256 ?? ""
)
let isCompletion = cached?.disposition == "completion"
let isDirective: Bool = {
  guard let disp = cached?.disposition else { return false }
  return ["directive", "affirmative", "negative"].contains(disp)
}()
```

**Migration Strategy:**
- Table recreation (SQLite doesn't support DROP COLUMN)
- Copy data excluding removed columns
- Recreate indexes (removed `idx_entries_is_completion`)
- Column count: 23 → 19

**v7-v11 Migrations:** Metadata tables (file_snapshots, tracked_files, transcript_summaries, system_events, assistant_usage), FK hardening with staging table, composite PKs

**v12-v17 Migrations (2025-10):** Unread Tracking & Performance
- **v12:** Epoch timestamps (`projects.last_viewed_ts`, `entries.created_ts`) for timezone-free unread tracking
- **v13:** Partial indices, backfills from legacy project_visits
- **v14:** Request ID normalization (empty → entry_id fallback) in assistant_usage
- **v15:** Index cleanup (remove redundant indices, add composite pending index)
- **v16:** Schema collapse (v1-v16 merged into single base), `idx_entries_unread_join` for GROUP BY optimization
- **v17:** Hotfix for v16 collapse - backfills for NULL timestamps, missing indexes, composite PK on `assistant_usage_pending`, file migration (transcripts.db → contextify.db)

**Proposed v7 Schema:**
```
file_snapshots (NEW)
├── id, transcript_id, message_id, snapshot_timestamp
├── is_snapshot_update, created_at
└── Purpose: Track when snapshots occurred

tracked_files (NEW)
├── id, snapshot_id, file_path, backup_filename
├── version, backup_time
└── Purpose: Which files were modified (avg ~25 files/session)

transcript_summaries (NEW)
├── id, transcript_id, summary, leaf_uuid, cwd
└── Purpose: Fallback titles, cross-session linking

system_events (NEW)
├── id, transcript_id, timestamp, subtype, level
├── content, error, retry_attempt, max_retries
└── Purpose: Command usage, error tracking, debugging

assistant_usage (NEW)
├── entry_id, request_id, model, input_tokens
├── output_tokens, cache_creation_tokens, cache_read_tokens
└── Purpose: Token/cost analytics, cache effectiveness
```

**Enabled Features:**
- Session details: "Files Modified: 12, Tokens: 125K, Cost: $0.42"
- File timeline: Show file modification history across sessions
- Command analytics: Slash command usage statistics
- Cost dashboard: Daily/weekly token usage, projections

**Migration Strategy:**
- Backward compatible (no changes to existing tables)
- Parser updates to extract metadata during ingestion
- Optional backfill for existing transcripts
- Incremental UI rollout

See comprehensive spec in `build/notes/technical-reference/claude-code-transcript-format.md`.

### Critical Indexes

**Feed Query Optimization (v2+, updated v6):**
```sql
-- Covering index for fast feed loading with cache join
-- v6: removed is_completion (now derived from timeline_cache.disposition)
CREATE INDEX idx_entries_feed_cover ON transcript_entries(
  project_id,
  timestamp,      -- Primary sort
  created_at,     -- Tie-breaker
  id,             -- Stable sort
  content_sha256,
  window_sha256,
  kind,
  session_id
) WHERE display_in_timeline = 1;

-- Feed query includes generator_signature filter in JOIN
SELECT e.*, c.*
FROM transcript_entries e
LEFT JOIN timeline_cache c
  ON c.content_sha256 = e.content_sha256
 AND c.window_sha256 = e.window_sha256
 AND c.generator_signature = ?  -- Filter by current generator version
WHERE e.project_id = ?
  AND e.display_in_timeline = 1
ORDER BY e.timestamp ASC, e.created_at ASC, e.id ASC
LIMIT ?;
```

**Cache Lookup:**
```sql
-- WITHOUT ROWID optimization for composite PK
CREATE UNIQUE INDEX idx_cache_entry_window
  ON timeline_cache(entry_id, window_sha256);
```

**Performance:** Single query loads 50 entries + joined cache in <5ms (p95 target, measured on Release build with 50K entries, Apple M3).

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
│    Contextify/contextify.db         │
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

**Window SHA Computation (deterministic):**
```swift
let components = [prev2_id, prev1_id].compactMap { $0 }
let concatenated = components.joined(separator: "|")  // Pipe delimiter
let windowSha = SHA256(concatenated).hexString
```

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

## Performance Characteristics

**Test Environment:** Release build, 50K entries dataset, Apple M3

| Operation | Target (p95) | Measured (p95) | Notes |
|-----------|--------------|----------------|-------|
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

**Cloud Sync Considerations:**
- WAL mode creates `*-wal` and `*-shm` files that some cloud providers sync poorly
- **Recommendation for cloud locations:** Run periodic WAL checkpointing (`TRUNCATE`) to minimize sync churn
- See `TODOS.md` "Configurable Database Location" feature for cloud sync strategies

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

## Recent Migrations (v18-v20)

**v18: Project Visibility**
- Add `hidden` column (default 0)
- Partial index on `hidden = 1` for filtering
- UI: Hide/restore projects from tab bar

**v19: Display Order**
- Add `display_order` column with deterministic backfill (id-based)
- Index for ORDER BY queries
- Two-phase bulk update (negative ranks, then final) to avoid transient odd ordering
- One-shot SQLITE_BUSY retry for WAL contention

**v20: Orphan Tracking**
- Add `is_orphaned` and `orphaned_since` columns
- Detect missing directories at discovery time
- UI: Show warning badge, allow cleanup

---

## Cross-References

- **Usage Guide:** `app/Sources/ContextifyCore/Database/README.md`
- **Timeline Integration:** `build/notes/technical-reference/timeline-cache-llm-architecture.md`
- **State Management:** `build/notes/technical-reference/conversation-monitor-state-architecture.md`
- **Planning Docs (Archive):** `build/notes/archive/technical-brief-sql-migration-architecture.md`
