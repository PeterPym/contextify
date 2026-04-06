# SQL Backend Architecture

**Status:** Post-Implementation (v40 current)
**Database:** SQLite via GRDB.swift
**Schema Version:** 40 (latest: slug/entrypoint/custom_title columns on transcripts)
**Related:** `app/Sources/ContextifyCore/Database/README.md` (usage guide)

**Schema versioning note:** References to "v6" in this doc refer to the 6th design iteration (denormalization cleanup), while v40 is the current migration version. See `DatabaseSchema.swift` for complete migration history (v16-v40).

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

**Startup Logging:** DatabaseManager emits `[DB-INIT]` logs on startup showing:
- New vs existing database (loud banner)
- File path and size
- Schema version and record counts (projects/transcripts/entries)

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
├── orphaned_since (INTEGER, v20+, epoch when directory went missing)
├── last_activity_detected_at (INTEGER, v32+, for tiered watcher lifecycle)
└── timestamps (created_at, updated_at)

transcripts
├── id (PK)
├── project_id (FK → projects, CASCADE)
├── file_path (UNIQUE per project)
├── provider (claude.code | codex.cli | other)
├── provider_session_id
├── last_modified + file_size + line_count
├── bookmark (security-scoped bookmark data)
├── slug (TEXT, v40+, human-readable session identifier, write-once)
├── entrypoint (TEXT, v40+, session origin "cli"/"sdk-cli", write-once)
├── custom_title (TEXT, v40+, user-assigned title from custom-title records)
├── ingestion_state
│   ├── last_processed_line
│   ├── last_processed_entry_id (v2+: resume checkpoint)
│   ├── parser_version
│   ├── status (active | unavailable | error)
│   ├── ingest_state (complete | partial, v24+)
│   └── last_error
├── identity_fields (v3+: path-based deduplication)
│   ├── normalized_path + path_hash
│   ├── content_length + mtime_ms + content_sha256
├── lazy_watcher_fields (v31-v32)
│   ├── pending_rehoover (v31+)
│   ├── known_last_entry_ts + known_file_size (v32+)
│   ├── unread_approx_count + unread_approx_confidence (v32+)
│   └── last_activity_detected_at (v32+)
└── timestamps

transcript_entries (CANONICAL SOURCE DATA - v6: removed denormalized fields)
├── id (PK)
├── transcript_id (FK → transcripts, CASCADE)
├── project_id (FK → projects, CASCADE, DENORMALIZED for query performance)
├── session_id
├── provider (claude.code | codex.cli | other)
├── kind (user | assistant | system)
├── timestamp
├── content + content_sha256
├── display_in_timeline (1 = show, 0 = hide thinking-only entries)
├── parent_id (FK → transcript_entries, SET NULL)
├── git_context (git_branch, git_commit, cwd)
├── window_tracking (v2+)
│   ├── prev1_id
│   ├── prev2_id
│   └── window_sha256 (for cache key computation)
├── embedding (BLOB, optional for RAG features)
├── created_ts (REAL, v12+, millisecond-precision epoch for unread queries)
├── is_queued (INTEGER, v27+, transient queued message tracking)
├── is_sidechain (INTEGER, v30+, agent sidechain marker)
└── timestamps (created_at, updated_at)
    Note: v6 REMOVED: summary, disposition, is_completion, is_directive
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

tool_invocations (v30+)
├── id (PK)
├── entry_id (FK → transcript_entries, CASCADE)
├── transcript_id (FK → transcripts, CASCADE)
├── parent_invocation_id (FK → tool_invocations, SET NULL)
├── tool_name + tool_key + tool_use_id
├── tool_result_entry_id (FK → transcript_entries, SET NULL)
├── sidechain_transcript_id + sidechain_agent_id
├── started_at + completed_at + status
├── is_contextify + metadata_json
└── timestamps

transcript_metadata
├── transcript_id (PK, FK → transcripts, CASCADE)
├── project_id (FK → projects, CASCADE)
├── title + description + topics (JSON)
├── confidence + hallucination_flags
├── generation_metadata
│   ├── model, prompt_version, generator_version
│   ├── strategy (full | adaptive | bookends | signalFirst | heuristic)
│   └── transcript_sha256
└── timestamps

parse_errors
├── id (PK)
├── transcript_id (FK → transcripts, CASCADE)
├── line_number + raw_line + error_message
└── created_at

database_access_metadata (v21+)
├── machine_id (PK)
├── machine_name
├── last_access
└── app_version

project_follow_policy (v23+)
├── project_id (UNIQUE, FK → projects, CASCADE)
├── mode (0=auto, 1=manual)
├── pinned_session_id + pinned_provider
└── updated_at

ingestion_locks (v24+)
├── transcript_id (PK, FK → transcripts, CASCADE)
└── locked_at

transcript_preflight_cache (v25+, WITHOUT ROWID)
├── file_path + provider (COMPOSITE PK)
├── mtime + status (passed|failed) + error
└── checked_at

transcript_entries_fts (v28+, FTS5 virtual table)
├── content (indexed)
├── entry_id, project_id, role, created_at (UNINDEXED metadata)
└── Triggers: fts_insert, fts_update, fts_delete

ingestion_runs (v33+)
├── id (PK)
├── started_at + completed_at
├── transcripts_processed + entries_inserted + errors_encountered
├── duration_seconds + status (running|completed|failed)
└── cli_version + timestamps

transcript_tags (v39+)
├── transcript_id (FK → transcripts, CASCADE)
├── tag (TEXT)
└── (transcript_id, tag) COMPOSITE PK
    Purpose: Purpose/category labels for transcripts (e.g., "benchmark", "evaluation")
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
// ConversationMonitor.swift#makeTimelineItem (within the function body)
isCompletion: cached?.disposition == "completion",
isDirective: {
    guard let disp = cached?.disposition else { return false }
    return ["directive", "affirmative", "negative"].contains(disp)
}(),
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

**v27-v30 Migrations (2025-12):** Queue + FTS + Sidechains
- **v27:** Add `is_queued` to `transcript_entries` for queued message badges
- **v28:** Add FTS5 index for conversation search
- **v29:** Expand FTS5 indexing to include summaries
- **v30:** Add `is_sidechain` and `tool_invocations` to support agent sidechains and tool metadata

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

See comprehensive spec in `build/docs/specifications/claude-code-transcript-format.md`.

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
func getOrCreateProject(name: String?, rootPath: String, bookmark: Data?) throws -> ProjectLookupResult

// Discovery & ingestion (async - routes through HooverScheduler)
func discoverTranscript(projectId: String, fileURL: URL, provider: String, providerSessionId: String?, startWatching: Bool, ...) async throws
func discoverTranscripts(projectId: String, transcriptFiles: [(url: URL, provider: String, sessionId: String?)], ...) async throws

// Queries
func getRecentFeed(forProject projectId: String, limit: Int, generatorSignature: String)
  throws -> [(TranscriptEntry, TimelineCache?)]

// Cache (nonisolated - thread-safe via GRDB)
nonisolated func getCachedTimeline(key: CacheKey) throws -> TimelineCache?
nonisolated func saveCachedTimeline(_ cache: TimelineCache) throws
nonisolated func saveCachedTimelineMany(_ caches: [TimelineCache]) throws
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
public protocol EntryRepository {
  func insert(_ entry: TranscriptEntry) throws
  func insertBatch(_ entries: [TranscriptEntry]) throws
  func recentFeed(projectId: String, limit: Int, generatorSignature: String)
    throws -> [(TranscriptEntry, TimelineCache?)]
}

public final class EntryRepositoryImpl: EntryRepository {
  private let db: DatabasePool

  public func recentFeed(...) throws -> [(TranscriptEntry, TimelineCache?)] {
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

See: `build/docs/architecture/conversation-monitor-state.md`

```swift
// Initialize orchestrator (shared, nonisolated)
let orchestrator = try TranscriptOrchestrator(dbManager: .shared)

// Create/get project
let result = try orchestrator.getOrCreateProject(
  name: "MyProject",
  rootPath: "/Users/rob/code/projects/myproject"
)
let projectId = result.projectId

// Background discovery (async - routes through HooverScheduler)
Task.detached {
  try await orchestrator.discoverTranscripts(
    projectId: projectId,
    transcriptFiles: [(url: fileURL, provider: "claude.code", sessionId: nil)],
    startWatching: true
  )
}

// Query feed (synchronous, fast)
let feed = try orchestrator.getRecentFeed(
  forProject: projectId,
  limit: 50,
  generatorSignature: "gpt-4o@2025-09:timeline@3"
)
```

### Timeline Cache Integration

See: `build/docs/components/timeline-cache.md`

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

**Integration Tests:** `Contextify/ContextifyTests/IntegrationTests.swift`
- Full hoover workflow (create project -> discover -> ingest)
- Crash recovery (stop mid-ingestion, verify resume)
- Window tracking correctness (verify prev1/prev2 linkage)

**Load Tests:** `Contextify/ContextifyTests/FeedLoadingDiagnosticTest.swift`
- Feed query performance with 50K entries
- Cache lookup performance with 10K cached entries

**Core Package Tests:** `Tests/ContextifyCoreTests/`
- FastPathIngestionTests - ingestion state machine
- ProjectIdentityTests - path canonicalization
- SandboxEnforcementTests - security-scoped access

---

## Recent Migrations (v18-v23)

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

**v21: Database Access Metadata**
- Add `database_access_metadata` table for multi-machine conflict detection
- Columns: `machine_id` (PK), `machine_name`, `last_access`, `app_version`
- Purpose: Warn users when database is accessed from multiple machines (Dropbox/iCloud scenarios)
- Feature: Custom database location support (Settings > Database tab)

**v22: Strategy Constraint Fix**
- Fix CHECK constraint in `transcript_metadata` table to include all GenerationStrategy enum values
- Add missing strategies: 'adaptive', 'bookends', 'signalFirst', 'heuristic'
- Migration recreates table (SQLite doesn't support ALTER TABLE for CHECK constraints)
- Preserves all data and indexes

**v23: Active Transcript Follow**
- Add `project_follow_policy` table for session switching behavior
- Columns: `project_id`, `mode` (0=auto, 1=manual), `pinned_session_id`, `pinned_provider`, `updated_at`
- Purpose: Control whether timeline automatically follows active transcript or stays pinned to selected session
- Default: Auto mode for all existing projects

## Recent Migrations (v27-v33)

**v27: Queued Messages**
- Add `transcript_entries.is_queued` with default 0
- Index on `(transcript_id, session_id, is_queued, content_sha256)`
- Purpose: Show transient QUEUED badge for messages sent while tools run

**v28: FTS5 Search Index**
- Create `transcript_entries_fts` virtual table
- Index `user` and `assistant` entries (displayable only)
- Add triggers to keep FTS in sync

**v29: Summary Search**
- Expand FTS indexing to include `summary` entries
- Update triggers to allow `kind IN ('user','assistant','summary')`

**v30: Sidechain + Tool Invocations**
- Add `transcript_entries.is_sidechain` with default 0
- Create `tool_invocations` table with linkage to tool_use/tool_result and sidechains
- Re-ingest Claude Code transcripts to backfill tool metadata

**v31: Pending Rehoover**
- Add `transcripts.pending_rehoover` column for lazy watcher catch-up
- Purpose: Mark transcripts needing re-ingestion after COLD→HOT tier promotion

**v32: Lazy Watcher Baseline Tracking**
- Add 7 columns to support watcher budget system and unread approximation:
  - `transcripts.known_last_entry_ts`, `known_file_size`
  - `transcripts.unread_approx_count`, `unread_approx_confidence`, `unread_approx_updated_at`
  - `transcripts.last_activity_detected_at`
  - `projects.last_activity_detected_at`
- Purpose: Enable tiered watcher lifecycle (HOT/WARM/COLD) with efficient unread tracking

**v33: Ingestion Runs**
- Create `ingestion_runs` table for CLI debugging and diagnostics
- Tracks ingestion performance metrics, errors, and outcomes per transcript
- Purpose: Support debugging of ingestion issues and performance monitoring

**v39: Transcript Tags**
- Create `transcript_tags` table with composite PK `(transcript_id, tag)`
- Supports purpose/category labeling for transcripts
- CLI: `contextify tag <transcript-id> [<tag>] [--remove]` lists, adds, or removes tags
- CLI search: `contextify search --exclude-tags <csv>` excludes entries from tagged transcripts
- Benchmark: `prepare-snapshot.sh` auto-excludes transcripts tagged "benchmark" or "evaluation" (override with `--no-exclude-tags`)

**v40: Transcript Identity Fields**
- Add `slug` (TEXT) to transcripts — human-readable session identifier extracted from user/assistant records (e.g., `"streamed-beaming-pumpkin"`); write-once on first non-null value
- Add `entrypoint` (TEXT) to transcripts — session origin (`"cli"` or `"sdk-cli"`); write-once
- Add `custom_title` (TEXT) to transcripts — user-assigned session title from `custom-title` records
- Fixed leafUuid extraction in metadata parser (was reading `leaf_uuid` snake_case; actual JSON field is `leafUuid` camelCase)

---

## Cross-References

- **Timeline Integration:** `build/docs/components/timeline-cache.md`
- **State Management:** `build/docs/architecture/conversation-monitor-state.md`
- **Schema Source:** `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`
- **Repositories:** `app/Sources/ContextifyCore/Database/Repositories.swift`
- **Planning Docs (Archive):** `build/docs/archive/completed-work/technical-brief-sql-migration-architecture.md`
