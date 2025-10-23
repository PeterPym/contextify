# Implementation Plan: Transcript Metadata Storage

**Status:** Proposal (2025-10-23)
**Priority:** Medium (enables session analytics and file tracking)
**Related:** `claude-code-transcript-format.md`, `sql-backend-architecture.md`
**Estimated Effort:** 2-3 weeks

---

## Problem Statement

Currently, Contextify only stores conversational messages (`user`/`assistant` records) from Claude Code transcripts. We're discarding valuable metadata:

1. **File-history-snapshot records (907 across 43 transcripts):**
   - Which files were modified during session
   - File versions and backup metadata
   - 813 snapshots with tracked files (avg ~25 files/snapshot)

2. **Summary records (48):**
   - Claude Code's internal session summaries
   - Could improve search and navigation

3. **System events (55):**
   - Slash commands, API errors, compact mode boundaries
   - Useful for debugging and analytics

4. **Usage metadata (in every assistant message):**
   - Token usage (input/output/cache)
   - Cost tracking data
   - Model and service tier

**Result:** "Empty" transcripts with metadata-only content are hidden as useless, when they actually contain file tracking and usage data.

---

## Goals

1. **Store all metadata types** from Claude Code transcripts
2. **Maintain data architecture principles** (canonical vs. derived separation)
3. **Enable new features:**
   - Session details view (files touched, token usage, cost)
   - File timeline (track file evolution across sessions)
   - Command analytics (slash command usage)
   - Cost dashboard (token/billing tracking)
4. **Backward compatible** - no changes to existing transcript_entries schema
5. **Incremental migration** - can backfill existing transcripts gradually

---

## Proposed Schema

### Table 1: file_snapshots

Stores file-history-snapshot record metadata.

```sql
CREATE TABLE file_snapshots (
  id TEXT PRIMARY KEY,              -- UUID
  transcript_id TEXT NOT NULL,       -- Foreign key to transcripts
  message_id TEXT NOT NULL,          -- Associated message UUID
  snapshot_timestamp INTEGER NOT NULL, -- Unix timestamp of snapshot
  is_snapshot_update INTEGER NOT NULL, -- 1 = update to existing, 0 = new
  created_at INTEGER NOT NULL,       -- Record creation time
  FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
);

CREATE INDEX idx_snapshots_transcript ON file_snapshots(transcript_id);
CREATE INDEX idx_snapshots_message ON file_snapshots(message_id);
CREATE INDEX idx_snapshots_timestamp ON file_snapshots(snapshot_timestamp);
```

**Row estimate:** ~21 snapshots per transcript × 100 transcripts = ~2,100 rows

### Table 2: tracked_files

Stores individual file tracking entries from snapshots.

```sql
CREATE TABLE tracked_files (
  id TEXT PRIMARY KEY,                -- UUID
  snapshot_id TEXT NOT NULL,           -- Foreign key to file_snapshots
  file_path TEXT NOT NULL,             -- Absolute or relative path
  backup_filename TEXT,                -- Backup file name (null = not backed up)
  version INTEGER NOT NULL,            -- File version number
  backup_time INTEGER NOT NULL,        -- Unix timestamp of backup
  FOREIGN KEY (snapshot_id) REFERENCES file_snapshots(id) ON DELETE CASCADE
);

CREATE INDEX idx_tracked_files_snapshot ON tracked_files(snapshot_id);
CREATE INDEX idx_tracked_files_path ON tracked_files(file_path);
CREATE INDEX idx_tracked_files_backup_time ON tracked_files(backup_time);
```

**Row estimate:** ~25 files per snapshot × 21 snapshots × 100 transcripts = ~52,500 rows

**Query examples:**
```sql
-- Files touched in a session
SELECT DISTINCT file_path
FROM tracked_files tf
JOIN file_snapshots fs ON fs.id = tf.snapshot_id
WHERE fs.transcript_id = ?
ORDER BY file_path;

-- File modification timeline across all sessions
SELECT t.id, t.provider_session_id, tf.version, tf.backup_time
FROM tracked_files tf
JOIN file_snapshots fs ON fs.id = tf.snapshot_id
JOIN transcripts t ON t.id = fs.transcript_id
WHERE tf.file_path = ?
ORDER BY tf.backup_time DESC;

-- Session file count
SELECT COUNT(DISTINCT tf.file_path) as file_count
FROM tracked_files tf
JOIN file_snapshots fs ON fs.id = tf.snapshot_id
WHERE fs.transcript_id = ?;
```

### Table 3: transcript_summaries

Stores Claude Code's internal session summaries.

```sql
CREATE TABLE transcript_summaries (
  id TEXT PRIMARY KEY,              -- UUID
  transcript_id TEXT NOT NULL,       -- Foreign key to transcripts
  summary TEXT NOT NULL,             -- Human-readable summary
  leaf_uuid TEXT,                    -- Conversation tree leaf ID
  cwd TEXT,                          -- Working directory
  created_at INTEGER NOT NULL,       -- Record creation time
  FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
);

CREATE INDEX idx_summaries_transcript ON transcript_summaries(transcript_id);
CREATE INDEX idx_summaries_leaf ON transcript_summaries(leaf_uuid);
CREATE UNIQUE INDEX idx_summaries_unique ON transcript_summaries(transcript_id);
```

**Row estimate:** ~1 per transcript × 100 = ~100 rows

**Query examples:**
```sql
-- Get summary for a session
SELECT summary FROM transcript_summaries WHERE transcript_id = ?;

-- Use as fallback for untitled sessions
SELECT COALESCE(tm.title, ts.summary, 'Untitled Session') as display_title
FROM transcripts t
LEFT JOIN transcript_metadata tm ON tm.transcript_id = t.id
LEFT JOIN transcript_summaries ts ON ts.transcript_id = t.id
WHERE t.id = ?;
```

### Table 4: system_events

Stores system messages (commands, errors, compact boundaries).

```sql
CREATE TABLE system_events (
  id TEXT PRIMARY KEY,              -- UUID from system record
  transcript_id TEXT NOT NULL,       -- Foreign key to transcripts
  timestamp INTEGER NOT NULL,        -- Unix timestamp
  subtype TEXT NOT NULL,             -- local_command | compact_boundary | api_error
  level TEXT NOT NULL,               -- info | error
  content TEXT,                      -- Event content/message
  error TEXT,                        -- Error message (for api_error)
  retry_attempt INTEGER,             -- Retry attempt number
  max_retries INTEGER,               -- Max retry attempts
  retry_in_ms INTEGER,               -- Retry delay
  parent_uuid TEXT,                  -- Parent message for threading
  logical_parent_uuid TEXT,          -- For compact mode
  compact_metadata TEXT,             -- JSON for compact metadata
  created_at INTEGER NOT NULL,       -- Record creation time
  FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
);

CREATE INDEX idx_system_events_transcript ON system_events(transcript_id);
CREATE INDEX idx_system_events_subtype ON system_events(subtype);
CREATE INDEX idx_system_events_timestamp ON system_events(timestamp);
```

**Row estimate:** ~1-2 per transcript × 100 = ~100-200 rows

**Query examples:**
```sql
-- Slash command usage
SELECT content, COUNT(*) as usage_count
FROM system_events
WHERE subtype = 'local_command'
GROUP BY content
ORDER BY usage_count DESC;

-- API errors in session
SELECT timestamp, error, retry_attempt
FROM system_events
WHERE transcript_id = ?
  AND subtype = 'api_error'
ORDER BY timestamp;

-- Sessions with errors
SELECT t.id, t.provider_session_id, COUNT(*) as error_count
FROM transcripts t
JOIN system_events se ON se.transcript_id = t.id
WHERE se.subtype = 'api_error'
GROUP BY t.id
ORDER BY error_count DESC;
```

### Table 5: assistant_usage

Stores token usage and billing metadata from assistant messages.

```sql
CREATE TABLE assistant_usage (
  entry_id TEXT PRIMARY KEY,         -- Foreign key to transcript_entries
  request_id TEXT,                   -- API request ID
  model TEXT NOT NULL,               -- Model name (e.g., claude-sonnet-4-5-20250929)
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  cache_creation_tokens INTEGER NOT NULL,
  cache_read_tokens INTEGER NOT NULL,
  service_tier TEXT,                 -- e.g., "standard"
  ephemeral_5m_tokens INTEGER,       -- 5-minute cache tokens
  ephemeral_1h_tokens INTEGER,       -- 1-hour cache tokens
  FOREIGN KEY (entry_id) REFERENCES transcript_entries(id) ON DELETE CASCADE
);

CREATE INDEX idx_usage_request ON assistant_usage(request_id);
CREATE INDEX idx_usage_model ON assistant_usage(model);
```

**Row estimate:** ~11,000 assistant messages × 100 transcripts / 43 existing = ~25,581 rows

**Query examples:**
```sql
-- Total token usage for session
SELECT
  SUM(input_tokens) as total_input,
  SUM(output_tokens) as total_output,
  SUM(cache_read_tokens) as cache_hits
FROM assistant_usage au
JOIN transcript_entries e ON e.id = au.entry_id
WHERE e.transcript_id = ?;

-- Cache hit rate
SELECT
  SUM(cache_read_tokens) * 100.0 / NULLIF(SUM(input_tokens), 0) as cache_hit_rate
FROM assistant_usage au
JOIN transcript_entries e ON e.id = au.entry_id
WHERE e.transcript_id = ?;

-- Cost estimation (approximate)
SELECT
  SUM(input_tokens) * 0.000003 + -- $3 per 1M input tokens
  SUM(output_tokens) * 0.000015 + -- $15 per 1M output tokens
  SUM(cache_creation_tokens) * 0.00000375 -- 25% of input cost for cache creation
  as estimated_cost_usd
FROM assistant_usage au
JOIN transcript_entries e ON e.id = au.entry_id
WHERE e.transcript_id = ?;

-- Daily usage trend
SELECT
  DATE(e.timestamp, 'unixepoch') as date,
  SUM(au.input_tokens + au.output_tokens) as total_tokens
FROM assistant_usage au
JOIN transcript_entries e ON e.id = au.entry_id
JOIN transcripts t ON t.id = e.transcript_id
WHERE t.project_id = ?
GROUP BY date
ORDER BY date DESC
LIMIT 30;
```

---

## Parser Updates

### New Parser Method: `parseMetadata()`

```swift
// In TranscriptParsers.swift

public protocol TranscriptMetadataParser {
  func parseFileSnapshot(line: String, transcriptId: String) throws -> FileSnapshot?
  func parseSummary(line: String, transcriptId: String) throws -> TranscriptSummary?
  func parseSystemEvent(line: String, transcriptId: String) throws -> SystemEvent?
}

public struct FileSnapshot {
  let id: String
  let transcriptId: String
  let messageId: String
  let snapshotTimestamp: Date
  let isSnapshotUpdate: Bool
  let trackedFiles: [TrackedFile]
}

public struct TrackedFile {
  let id: String
  let snapshotId: String
  let filePath: String
  let backupFilename: String?
  let version: Int
  let backupTime: Date
}

public struct TranscriptSummary {
  let id: String
  let transcriptId: String
  let summary: String
  let leafUuid: String?
  let cwd: String?
}

public struct SystemEvent {
  let id: String
  let transcriptId: String
  let timestamp: Date
  let subtype: String
  let level: String
  let content: String?
  let error: String?
  let retryAttempt: Int?
  let maxRetries: Int?
  let retryInMs: Int?
  let parentUuid: String?
  let logicalParentUuid: String?
  let compactMetadata: String?
}
```

### HooverEngine Updates

```swift
// In HooverEngine.swift

public func hooverTranscript(...) throws -> String {
  // ... existing code ...

  // Process each line
  do {
    // Try parsing as message first
    let entry = try parser.parse(...)
    batch.append(entry)

    // Extract usage metadata if assistant message
    if entry.kind == "assistant", let usage = extractUsage(line) {
      usageBatch.append(usage)
    }
  } catch ParserError.skipEntry {
    // Try parsing as metadata
    if let snapshot = try? metadataParser.parseFileSnapshot(line, transcriptId: transcript.id) {
      snapshotBatch.append(snapshot)
    } else if let summary = try? metadataParser.parseSummary(line, transcriptId: transcript.id) {
      summaryBatch.append(summary)
    } else if let event = try? metadataParser.parseSystemEvent(line, transcriptId: transcript.id) {
      eventBatch.append(event)
    }
    // Else: truly skip (meta messages, etc.)
  } catch {
    errors.append(...)
  }

  // Commit batches
  if batch.count >= batchSize {
    try commitBatch(
      entries: batch,
      snapshots: snapshotBatch,
      usage: usageBatch,
      summaries: summaryBatch,
      events: eventBatch,
      errors: errors
    )
  }
}
```

---

## Migration Strategy

### Phase 1: Schema Migration (v7)

**Database migration:**
```swift
// In DatabaseSchema.swift

migrator.registerMigration("v7_add_metadata_tables") { db in
  // Create file_snapshots table
  try db.create(table: "file_snapshots") { t in
    t.primaryKey("id", .text)
    t.column("transcript_id", .text).notNull().references("transcripts", onDelete: .cascade)
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
    t.primaryKey("id", .text)
    t.column("snapshot_id", .text).notNull().references("file_snapshots", onDelete: .cascade)
    t.column("file_path", .text).notNull()
    t.column("backup_filename", .text)
    t.column("version", .integer).notNull()
    t.column("backup_time", .integer).notNull()
  }
  try db.create(index: "idx_tracked_files_snapshot", on: "tracked_files", columns: ["snapshot_id"])
  try db.create(index: "idx_tracked_files_path", on: "tracked_files", columns: ["file_path"])
  try db.create(index: "idx_tracked_files_backup_time", on: "tracked_files", columns: ["backup_time"])

  // Create transcript_summaries table
  try db.create(table: "transcript_summaries") { t in
    t.primaryKey("id", .text)
    t.column("transcript_id", .text).notNull().references("transcripts", onDelete: .cascade)
    t.column("summary", .text).notNull()
    t.column("leaf_uuid", .text)
    t.column("cwd", .text)
    t.column("created_at", .integer).notNull()
  }
  try db.create(index: "idx_summaries_transcript", on: "transcript_summaries", columns: ["transcript_id"])
  try db.create(index: "idx_summaries_leaf", on: "transcript_summaries", columns: ["leaf_uuid"])
  try db.create(uniqueIndex: "idx_summaries_unique", on: "transcript_summaries", columns: ["transcript_id"])

  // Create system_events table
  try db.create(table: "system_events") { t in
    t.primaryKey("id", .text)
    t.column("transcript_id", .text).notNull().references("transcripts", onDelete: .cascade)
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
  try db.create(index: "idx_system_events_transcript", on: "system_events", columns: ["transcript_id"])
  try db.create(index: "idx_system_events_subtype", on: "system_events", columns: ["subtype"])
  try db.create(index: "idx_system_events_timestamp", on: "system_events", columns: ["timestamp"])

  // Create assistant_usage table
  try db.create(table: "assistant_usage") { t in
    t.primaryKey("entry_id", .text).references("transcript_entries", onDelete: .cascade)
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
  try db.create(index: "idx_usage_request", on: "assistant_usage", columns: ["request_id"])
  try db.create(index: "idx_usage_model", on: "assistant_usage", columns: ["model"])
}
```

**Timeline:** 1-2 days (schema + models + repositories)

### Phase 2: Parser Implementation

**Tasks:**
1. Create `TranscriptMetadataParser` protocol and implementation
2. Update `HooverEngine` to call metadata parsers
3. Add metadata batch commit logic
4. Update `TranscriptOrchestrator` with new repository methods
5. Unit tests for each metadata type

**Timeline:** 3-4 days

### Phase 3: Backfill Tool

**Create:** `scripts/backfill_metadata.py`

```python
#!/usr/bin/env python3
"""
Backfill metadata for existing transcripts.
Uses db_manager.sh reingest under the hood.
"""

import sqlite3
import subprocess
import sys

def get_transcripts_without_metadata(db_path):
    """Find transcripts with no metadata records."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT t.id, COUNT(fs.id) as snapshot_count
        FROM transcripts t
        LEFT JOIN file_snapshots fs ON fs.transcript_id = t.id
        GROUP BY t.id
        HAVING snapshot_count = 0
        ORDER BY t.last_modified DESC
    """)

    return [row[0] for row in cursor.fetchall()]

def reingest_transcript(transcript_id):
    """Reingest transcript using db_manager.sh."""
    result = subprocess.run(
        ["./scripts/db_manager.sh", "reingest_transcript", transcript_id],
        capture_output=True,
        text=True
    )
    return result.returncode == 0

if __name__ == "__main__":
    db_path = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.expanduser("~/Library/Application Support/Contextify/transcripts.db")

    transcripts = get_transcripts_without_metadata(db_path)
    print(f"Found {len(transcripts)} transcripts without metadata")

    for i, tid in enumerate(transcripts, 1):
        print(f"[{i}/{len(transcripts)}] Reingesting {tid}...")
        if reingest_transcript(tid):
            print(f"  ✓ Success")
        else:
            print(f"  ✗ Failed")
```

**Timeline:** 1 day

### Phase 4: UI Features (incremental)

**Priority order:**

1. **Session Details View** (3-4 days)
   - Show files touched, token usage, cost estimate
   - Display in transcript inventory detail panel

2. **File Timeline View** (2-3 days)
   - Show file modification history across sessions
   - Accessible from session details

3. **Command Analytics** (1-2 days)
   - Show slash command usage in stats panel
   - Simple bar chart of top commands

4. **Cost Dashboard** (3-4 days)
   - Daily/weekly token usage graphs
   - Cost projections and trends
   - Per-project breakdown

**Total UI timeline:** 2-3 weeks (can be parallelized with other work)

---

## Testing Strategy

### Unit Tests

1. **Parser tests:**
   - Parse file-history-snapshot with multiple files
   - Parse summary records
   - Parse each system event subtype
   - Extract usage metadata from assistant messages

2. **Repository tests:**
   - Insert/query file snapshots and tracked files
   - Aggregate queries (file count, token usage)
   - JOIN queries (session files, file timeline)

3. **Migration tests:**
   - Schema v6 → v7 migration runs cleanly
   - Indexes created correctly
   - Foreign keys enforce correctly

### Integration Tests

1. **Hoover with metadata:**
   - Ingest transcript with file snapshots
   - Verify snapshots + tracked files in DB
   - Ingest transcript with summaries/events
   - Verify metadata in DB

2. **Query performance:**
   - Session details query <10ms
   - File timeline query <50ms
   - Daily usage aggregate <100ms

### Manual Testing

1. Reingest existing transcript with metadata
2. Verify session details view shows correct data
3. Check file timeline accuracy
4. Verify cost calculations match expectations

---

## Risks & Mitigations

**Risk 1: Performance impact on ingestion**

- **Impact:** Parsing 5 record types instead of 2 may slow hoover
- **Mitigation:** Benchmark before/after, optimize batch commits
- **Fallback:** Make metadata parsing optional via flag

**Risk 2: Schema complexity**

- **Impact:** 5 new tables adds maintenance burden
- **Mitigation:** Comprehensive documentation, clear naming
- **Benefit:** Properly normalized, follows v6 principles

**Risk 3: Backfill takes too long**

- **Impact:** 43+ transcripts × 1 min each = 43+ minutes
- **Mitigation:** Background task, progress indicator, pauseable
- **Alternative:** Lazy backfill (on-demand when viewing session)

**Risk 4: Storage growth**

- **Impact:** ~52,500 tracked_file rows + ~25,000 usage rows
- **Mitigation:** Indexes, periodic cleanup, retention policies
- **Estimate:** ~5-10 MB per 100 transcripts (acceptable)

---

## Success Metrics

1. **Data completeness:**
   - 100% of file snapshots stored
   - 100% of summaries stored
   - 100% of usage metadata stored

2. **Query performance:**
   - Session details <10ms (p95)
   - File timeline <50ms (p95)
   - Daily usage aggregate <100ms (p95)

3. **User value:**
   - "Files Modified" count displayed for all sessions
   - Token usage/cost visible in session details
   - File timeline helps identify when changes occurred

4. **Reliability:**
   - Zero foreign key constraint violations
   - Metadata parsing errors logged but don't block message ingestion
   - Backfill completes without crashes

---

## Future Enhancements

### Phase 5+: Advanced Features

1. **File diff viewer:**
   - Show actual diffs between file versions
   - Link to backup files (if accessible)

2. **Cost predictions:**
   - "This project costs ~$X/week"
   - "You're on track to spend $Y this month"

3. **Cache optimization suggestions:**
   - "Cache hit rate dropped 20% - consider regenerating"
   - "High cache miss rate on project X"

4. **Command recommendations:**
   - "You use /build often, consider adding a pre-commit hook"
   - "Try /config to customize settings"

5. **Export capabilities:**
   - Export session report (PDF/HTML) with files + usage
   - Export file timeline CSV for analysis

---

## Appendix: SQL Query Cookbook

### Session Analytics

```sql
-- Session summary with metadata
SELECT
  t.id,
  t.provider_session_id,
  tm.title,
  ts.summary,
  COUNT(DISTINCT tf.file_path) as files_modified,
  COUNT(DISTINCT e.id) as message_count,
  SUM(au.input_tokens + au.output_tokens) as total_tokens,
  SUM(au.cache_read_tokens) * 100.0 / NULLIF(SUM(au.input_tokens), 0) as cache_hit_rate
FROM transcripts t
LEFT JOIN transcript_metadata tm ON tm.transcript_id = t.id
LEFT JOIN transcript_summaries ts ON ts.transcript_id = t.id
LEFT JOIN file_snapshots fs ON fs.transcript_id = t.id
LEFT JOIN tracked_files tf ON tf.snapshot_id = fs.id
LEFT JOIN transcript_entries e ON e.transcript_id = t.id
LEFT JOIN assistant_usage au ON au.entry_id = e.id
WHERE t.id = ?
GROUP BY t.id;
```

### Project-Wide Analytics

```sql
-- Project totals
SELECT
  p.id,
  p.name,
  COUNT(DISTINCT t.id) as session_count,
  COUNT(DISTINCT tf.file_path) as unique_files,
  SUM(au.input_tokens + au.output_tokens) as total_tokens,
  SUM(au.input_tokens) * 0.000003 + SUM(au.output_tokens) * 0.000015 as estimated_cost
FROM projects p
JOIN transcripts t ON t.project_id = p.id
LEFT JOIN file_snapshots fs ON fs.transcript_id = t.id
LEFT JOIN tracked_files tf ON tf.snapshot_id = fs.id
LEFT JOIN transcript_entries e ON e.transcript_id = t.id
LEFT JOIN assistant_usage au ON au.entry_id = e.id
WHERE p.id = ?
GROUP BY p.id;
```

### File History

```sql
-- File modification timeline
SELECT
  t.provider_session_id,
  tm.title,
  tf.version,
  tf.backup_filename,
  tf.backup_time,
  e.content as related_message
FROM tracked_files tf
JOIN file_snapshots fs ON fs.id = tf.snapshot_id
JOIN transcripts t ON t.id = fs.transcript_id
LEFT JOIN transcript_metadata tm ON tm.transcript_id = t.id
LEFT JOIN transcript_entries e ON e.uuid = fs.message_id
WHERE tf.file_path = ?
ORDER BY tf.backup_time DESC;
```

### Command Usage

```sql
-- Slash command leaderboard
SELECT
  SUBSTRING(content, INSTR(content, '/'), INSTR(content, '<') - INSTR(content, '/')) as command,
  COUNT(*) as usage_count,
  MIN(timestamp) as first_used,
  MAX(timestamp) as last_used
FROM system_events
WHERE subtype = 'local_command'
  AND content LIKE '%/%'
GROUP BY command
ORDER BY usage_count DESC
LIMIT 10;
```

---

## References

- **Technical Spec:** `build/notes/technical-reference/claude-code-transcript-format.md`
- **Current Parser:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`
- **Database Arch:** `build/notes/technical-reference/sql-backend-architecture.md`
- **Analysis Data:** 43 transcripts, 18,589 records, 5 record types
