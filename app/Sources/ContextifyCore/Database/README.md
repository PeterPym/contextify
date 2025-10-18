# SQLite Backend - Usage Guide

**Architecture Reference:** See `build/notes/technical-reference/sql-backend-architecture.md` for schema design, performance characteristics, and migration details.

**Related Technical Briefs:**
- Cache + LLM Integration: `build/notes/technical-reference/timeline-cache-llm-architecture.md`
- State Management: `build/notes/technical-reference/conversation-monitor-state-architecture.md`

---

## Quick Start

### 1. Basic Setup (Using Orchestrator - Recommended)

```swift
import ContextifyCore

// Initialize orchestrator (manages all repos and engine)
let orchestrator = try TranscriptOrchestrator()

// Create a project
let projectId = try orchestrator.createProject(
  name: "My Project",
  rootPath: "/Users/rob/code/projects/myproject",
  bookmark: nil
)
```

### 2. Discover and Hoover Transcripts

```swift
// Find Claude Code transcripts
let claudeDir = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent(".claude/projects/myproject")

let transcriptFiles = try FileManager.default.contentsOfDirectory(
  at: claudeDir,
  includingPropertiesForKeys: nil
).filter { $0.pathExtension == "jsonl" }

// Batch discover with progress reporting
let files = transcriptFiles.map {
  (url: $0, provider: "claude.code", sessionId: nil)
}

let progress = LoggingProgressSink(
  log: Logger(subsystem: "dev.contextify", category: "hoover")
)

try orchestrator.discoverTranscripts(
  projectId: projectId,
  transcriptFiles: files,
  progress: progress
)
```

### 3. Query Entries

```swift
// Get recent entries for a project
let recent = try orchestrator.getRecentEntries(
  forProject: projectId,
  limit: 50
)

// Get all entries for a specific transcript
let entries = try orchestrator.getEntries(
  forTranscript: transcriptId
)

// Search across all entries
let results = try orchestrator.searchEntries(
  content: "merge conflict",
  projectId: projectId
)
```

### 4. Enable Real-Time Monitoring

```swift
// Transcripts are automatically watched after discovery
// Listen for updates:
NotificationCenter.default.addObserver(
  forName: NSNotification.Name("TranscriptUpdated"),
  object: nil,
  queue: .main
) { notification in
  if let transcriptId = notification.object as? String {
    print("Transcript updated: \(transcriptId)")
    // Refresh UI
  }
}
```

### 5. Cache Timeline Summaries

```swift
// Check cache first
if let cached = try orchestrator.getCachedTimeline(
  contentSha256: entrySHA,
  windowSha256: windowSHA
) {
  return cached.presentForm
}

// Generate and save
let timeline = TimelineCache(
  contentSha256: entrySHA,
  windowSha256: windowSHA,
  entryId: entryId,
  generatorSignature: "gpt-4o@2025-09:timeline@3",
  disposition: "success",
  presentForm: "Claude is implementing feature X",
  pastForm: "Claude implemented feature X",
  selectedForm: "present",
  verbLemma: "implement",
  generatedAt: Int(Date().timeIntervalSince1970),
  userEdited: 0,
  userText: nil,
  editedAt: nil,
  requestId: nil,
  duration: 0.5
)

try orchestrator.saveCachedTimeline(timeline)
```

## Advanced Usage

### Direct Repository Access

```swift
// Get database pool
let pool = try DatabaseManager.shared.pool

// Create specific repos
let projectRepo = ProjectRepositoryImpl(db: pool)
let transcriptRepo = TranscriptRepositoryImpl(db: pool)
let entryRepo = EntryRepositoryImpl(db: pool)

// Use repos directly
let projects = try projectRepo.list()
let transcripts = try transcriptRepo.byProject(projectId)
```

### Custom Progress Reporting

```swift
class MyProgressSink: IngestProgressSink {
  func didStartTranscript(name: String, totalLines: Int?) {
    print("Starting \(name)...")
  }

  func didAdvance(linesProcessed: Int, totalLines: Int?) {
    if let total = totalLines {
      let percent = (Double(linesProcessed) / Double(total)) * 100
      print("Progress: \(Int(percent))%")
    }
  }

  func didCompleteTranscript(durationMs: Int) {
    print("Completed in \(durationMs)ms")
  }

  func didFailTranscript(error: String) {
    print("Error: \(error)")
  }

  func didStartProject(name: String, transcriptCount: Int) {
    print("Starting project \(name) with \(transcriptCount) transcripts")
  }

  func didCompleteProject(name: String) {
    print("Project \(name) complete!")
  }
}

// Use custom progress
try orchestrator.discoverTranscripts(
  projectId: projectId,
  transcriptFiles: files,
  progress: MyProgressSink()
)
```

### Maintenance Operations

```swift
// Run periodic maintenance
try orchestrator.performMaintenance()

// This includes:
// - WAL checkpoint if > 100MB
// - ANALYZE for query optimization
// - VACUUM if bloat > 25%
```

## Database Location

- **Production:** `~/Library/Application Support/Contextify/transcripts.db`
- **Sandboxed:** App's container Application Support directory

## Key Features

✅ **Crash-safe checkpointing** - Resumes from `last_processed_line` after crashes
✅ **Streaming parser** - Processes 50K lines in ~2s with O(batch_size) memory
✅ **Concurrent reads** - WAL mode enables simultaneous read queries
✅ **Parse error isolation** - Bad lines don't block entire import
✅ **Provider agnostic** - Supports Claude Code and Codex CLI formats
✅ **Real-time updates** - File watcher triggers incremental ingestion
✅ **Timeline caching** - LLM-generated summaries cached by content+window hash

## Performance Targets

| Operation | Target (p95) |
|-----------|--------------|
| Recent feed (50K entries) | ≤5ms |
| Hoover batch (1K rows) | ≤40ms |
| Stream insert (≤100 rows) | ≤20ms |
| Cache lookup | ≤5ms |

## Testing

See `IntegrationTests.swift` for complete examples:
- Initial hoover workflow
- Crash recovery
- Using the orchestrator API

Run tests:
```bash
make test
# or
bash scripts/xc.sh test
```

## Inspecting the Database

### Recommended macOS Tools

**1. DB Browser for SQLite (Free, Open Source)**
- Download: https://sqlitebrowser.org
- Best for: Browsing tables, running queries, viewing schema
- Install: `brew install --cask db-browser-for-sqlite`
- Open: `/Users/rob/Library/Application Support/Contextify/transcripts.db`

**2. TablePlus (Free tier available)**
- Download: https://tableplus.com
- Best for: Beautiful UI, real-time updates, query tabs
- Install: `brew install --cask tableplus`
- Supports live refresh when database changes

**3. DataGrip (JetBrains, paid)**
- Download: https://www.jetbrains.com/datagrip/
- Best for: Advanced SQL IDE, autocomplete, refactoring
- Install: `brew install --cask datagrip`

**4. Command Line (Built-in)**
```bash
# Open SQLite CLI
sqlite3 ~/Library/Application\ Support/Contextify/transcripts.db

# Useful commands:
.tables                    # List all tables
.schema transcript_entries # Show table schema
SELECT COUNT(*) FROM transcript_entries;
SELECT * FROM transcript_entries ORDER BY timestamp DESC LIMIT 10;
.quit
```

### Useful Queries

```sql
-- Recent entries by project
SELECT e.content, e.timestamp, e.kind
FROM transcript_entries e
WHERE e.project_id = 'YOUR-PROJECT-ID'
ORDER BY e.timestamp DESC
LIMIT 20;

-- Parse errors
SELECT transcript_id, line_number, error_message
FROM parse_errors
ORDER BY created_at DESC;

-- Timeline cache hit rate
SELECT
  (SELECT COUNT(*) FROM timeline_cache) as cached,
  (SELECT COUNT(*) FROM transcript_entries) as total;

-- Transcripts by status
SELECT provider, status, COUNT(*)
FROM transcripts
GROUP BY provider, status;

-- Denormalization invariant check (should return no rows)
SELECT e.id
FROM transcript_entries e
LEFT JOIN transcripts t ON t.id = e.transcript_id
WHERE t.project_id IS NULL OR e.project_id <> t.project_id
LIMIT 1;
```

### Live Monitoring

For real-time updates while the app runs, use **TablePlus**:
1. Open the database in TablePlus
2. Enable auto-refresh (⌘R or View → Auto Refresh)
3. Set refresh interval to 1-2 seconds
4. Run your app and watch entries appear in real-time!

### Export Data

```bash
# Export to CSV
sqlite3 -header -csv transcripts.db \
  "SELECT * FROM transcript_entries LIMIT 1000" \
  > entries.csv

# Export entire database to SQL
sqlite3 transcripts.db .dump > backup.sql
```

## Troubleshooting

### "Database is locked"
- Ensure single writer (orchestrator manages this)
- Check WAL checkpoint isn't stuck (`performMaintenance()`)

### "No such table"
- Database migration runs automatically on first connection
- Check `DatabaseSchema.migrate()` was called

### "Duplicate entries"
- UUIDs should be deterministic (Claude) or generated (Codex)
- Check `ON CONFLICT IGNORE` is working

### Slow queries
- Run `performMaintenance()` to update statistics
- Check indexes with `EXPLAIN QUERY PLAN`
