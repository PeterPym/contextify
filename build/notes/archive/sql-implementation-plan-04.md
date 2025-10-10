# SQLite Backend Architecture Brief (v4 - Production Ready)

**Date:** 2025-10-10
**Status:** Final specification - ready for implementation
**Supersedes:** v3 (incorporated final production hardening feedback)

---

# 0. Executive Summary

Contextify is a macOS developer companion that **monitors and analyzes AI coding sessions** in real-time. It automatically discovers conversation transcripts from Claude Code and Codex CLI, renders them as navigable timelines with LLM-powered summaries, and provides rich metadata for search and correlation.

**This document specifies a production-hardened SQLite backend** that:
- **Preserves transcript data** after providers delete it (Claude Code: 30-day retention)
- **Enables cross-session queries** unavailable in source tools
- **Stores parsed message content** for analysis (not just file references)
- **Tracks ingestion state** for crash-safe resumption
- **Handles production edge cases** (concurrent reads, WAL monitoring, parse errors)

**Key Decision: GREENFIELD ONLY.** No migration from file-based caches. All derived data regenerates from external transcripts.

---

# 1. Non-Goals & Boundaries

**Out of scope for v1:**

* ❌ Migration from file-based caches (greenfield = clean slate)
* ❌ Dual-write (no file cache compatibility mode)
* ❌ Server/CloudKit/sync (local-only DB)
* ❌ At-rest DB encryption (defer to v1.x)
* ❌ Full-text search (Phase 2: FTS5)
* ❌ Job/queue tables (regen stays in-memory)
* ❌ Export to JSONL (Phase 2+)
* ❌ Mobile entities (artifact, task, branch - Phase 2)
* ❌ Rollback mechanism (drop/recreate = acceptable; derived data regenerates)

**Acceptable assumptions:**

* Single writer process (no concurrent DB writes; concurrent reads OK via WAL)
* Providers have stable UUIDs (Claude) or enough fields for deterministic IDs (Codex)
* Transcripts remain accessible via security-scoped bookmarks

---

# 2. Vocabulary (v1 Canonical)

**Core entities:**

* **project** — workspace rooted at code directory (e.g., `/Users/rob/code/contextify`)
* **transcript** — external JSONL file tracked in DB with ingestion state
* **entry** — parsed message from transcript; **DB stores full content**
* **metadata** — LLM-generated title/description/topics per transcript (derived)
* **timeline cache** — rendered entry with disposition + tense forms (derived)

**Session terminology (unified):**

* **`provider_session_id`** — Provider's own conversation/session identifier (e.g., Claude's `sessionId`). Stored in `transcripts.provider_session_id`.
* **`session_id`** (in entries) — **Denormalized copy** of `provider_session_id` for query convenience and filtering without joins. May be `NULL` if provider doesn't expose session ID.
* **Rationale:** Mirrors the `project_id` denorm pattern to keep entry queries single-table.

**Operations:**

* **hoover** — initial parse of entire transcript on discovery
* **stream** — incremental parse of new lines via file watcher

---

# 3. Core Principle: Hoover + Stream Architecture

## 3.1 Data Flow Model

```
┌─────────────────────────────────────────┐
│  External Transcript Files              │
│  (Source of Truth)                      │
│  ~/.claude/projects/<project>/*.jsonl   │
│  (30-day retention → DELETED)           │
└──────────────┬──────────────────────────┘
               │
               ▼
    ┌──────────────────────┐
    │  Phase A: HOOVER     │
    │  (On Discovery)      │
    │  - Stream parse      │
    │  - Batch INSERT      │
    │  - Save checkpoint   │
    └──────────┬───────────┘
               │
               ▼
    ┌──────────────────────────────┐
    │  SQLite Database             │
    │  ~/Library/.../transcripts.db│
    │                              │
    │  • projects                  │
    │  • transcripts (file refs)   │
    │  • transcript_entries ← ✅   │
    │  • timeline_cache            │
    │  • transcript_metadata       │
    │  • parse_errors              │
    └──────────┬───────────────────┘
               │
               ▼
    ┌──────────────────────┐
    │  Phase B: STREAM     │
    │  (File Watcher)      │
    │  - Detect new lines  │
    │  - Parse incremental │
    │  - Batch INSERT      │
    │  - Update checkpoint │
    └──────────────────────┘
```

## 3.2 Why Store Content in DB?

**CRITICAL:** The database **DOES store parsed message content** (`entry.content TEXT NOT NULL`).

**Rationale:**
```sql
-- This query is IMPOSSIBLE without storing content:
SELECT content FROM transcript_entries
WHERE content LIKE '%merge conflict%'
  AND timestamp > strftime('%s', 'now', '-6 months')
  AND project_id = ?;
```

**After Claude Code deletes transcript (day 31), DB still has:**
- Full message text
- LLM summaries
- Timeline cache
- Cross-session correlations

**Storage cost:** ~1KB per message × 100K messages = ~100MB (acceptable for moat value)

---

# 4. Schema Specification (Single Source of Truth)

## 4.1 Design Principles

1. **UUID TEXT Primary Keys** — all entities use `TEXT PRIMARY KEY` (UUIDv4)
2. **No AUTOINCREMENT** — avoids integer key mismatches across FK types
3. **Project FK scoping** — children reference `project_id` (denormalized for performance)
4. **Composite PK for cache** — `(content_sha256, window_sha256)` matches lookup pattern
5. **Ingestion state tracking** — `last_processed_line`, `parser_version`, `status`
6. **Parse error isolation** — bad lines don't block entire import
7. **SHA256 naming consistency** — use `_sha256` suffix everywhere (not `_hash`)

## 4.2 DDL (Authoritative v1)

> **Conventions:**
> - Booleans = `INTEGER` (0/1)
> - Timestamps = `INTEGER` (epoch seconds)
> - All tables have `created_at`/`updated_at` set by app
> - Hash columns explicitly named `*_sha256`

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

/* ========== PROJECTS ========== */
CREATE TABLE projects (
  id            TEXT PRIMARY KEY,             -- UUID
  name          TEXT,
  root_path     TEXT NOT NULL,                -- Canonicalized absolute path
  root_bookmark BLOB,                         -- Security-scoped bookmark
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_projects_root_path ON projects(root_path);

/* ========== TRANSCRIPTS (External File Refs + Ingestion State) ========== */
CREATE TABLE transcripts (
  id                   TEXT PRIMARY KEY,      -- UUID (provider's session ID if stable)
  project_id           TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  file_path            TEXT NOT NULL,         -- Canonicalized absolute path
  provider             TEXT NOT NULL CHECK (provider IN ('claude.code','codex.cli','other')),
  provider_session_id  TEXT,                  -- Provider's logical session ID (optional)
  last_modified        INTEGER NOT NULL,      -- File mtime (epoch seconds)
  file_size            INTEGER,
  line_count           INTEGER NOT NULL DEFAULT 0,  -- Incrementally maintained
  bookmark             BLOB,                  -- Security-scoped bookmark
  -- Ingestion state (hoover/stream progress)
  last_processed_line  INTEGER NOT NULL DEFAULT 0,
  parser_version       INTEGER NOT NULL DEFAULT 1,
  status               TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','unavailable','error')),
  last_error           TEXT,
  -- Bookkeeping
  created_at           INTEGER NOT NULL,
  updated_at           INTEGER NOT NULL,
  UNIQUE(project_id, file_path)
);
CREATE INDEX idx_transcripts_project ON transcripts(project_id, updated_at DESC);
CREATE INDEX idx_transcripts_status ON transcripts(status) WHERE status != 'active';

/* ========== TRANSCRIPT ENTRIES (Parsed Messages; Content Persisted) ========== */
CREATE TABLE transcript_entries (
  id             TEXT PRIMARY KEY,            -- UUID (provider's or deterministic)
  transcript_id  TEXT NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
  project_id     TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                 -- ^ Denormalized from transcripts.project_id for query performance
  session_id     TEXT,                        -- Denormalized provider_session_id (optional)
  provider       TEXT NOT NULL CHECK (provider IN ('claude.code','codex.cli','other')),
  kind           TEXT NOT NULL CHECK (kind IN ('user','assistant','system')),
  timestamp      INTEGER NOT NULL,            -- Message timestamp (epoch seconds)
  content        TEXT NOT NULL,               -- Full message text
  content_sha256 TEXT NOT NULL,               -- SHA256(content) for cache joins
  summary        TEXT,                        -- Optional lightweight summary
  disposition    TEXT,                        -- UI hint (e.g., "success", "warning")
  display_in_timeline INTEGER NOT NULL DEFAULT 1,
  is_completion  INTEGER NOT NULL DEFAULT 0,
  is_directive   INTEGER NOT NULL DEFAULT 0,
  parent_id      TEXT REFERENCES transcript_entries(id) ON DELETE SET NULL,  -- Threading
  git_branch     TEXT,
  git_commit     TEXT,
  cwd            TEXT,
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
);
CREATE INDEX idx_entries_transcript_time ON transcript_entries(transcript_id, timestamp);
CREATE INDEX idx_entries_project_time    ON transcript_entries(project_id, timestamp DESC);
CREATE INDEX idx_entries_project_feed    ON transcript_entries(project_id, timestamp DESC)
  WHERE display_in_timeline = 1;
CREATE INDEX idx_entries_content_sha     ON transcript_entries(content_sha256);
CREATE INDEX idx_entries_completion      ON transcript_entries(project_id, is_completion)
  WHERE is_completion = 1;

/* ========== TIMELINE CACHE (Derived; Composite PK) ========== */
-- window_sha256 = SHA256(join([prev2_id, prev1_id], "|")) where N=2 for v1
-- generator_signature = "{model}@{model_version}:{prompt}@{prompt_version}"
--   Example: "gpt-4o@2025-09:timeline@3"
--   Any change invalidates cache entry
CREATE TABLE timeline_cache (
  content_sha256      TEXT NOT NULL,          -- SHA256(entry.content)
  window_sha256       TEXT NOT NULL,          -- SHA256 of context window UUIDs
  entry_id            TEXT NOT NULL REFERENCES transcript_entries(id) ON DELETE CASCADE,
  generator_signature TEXT NOT NULL,          -- See comment above
  disposition         TEXT NOT NULL,
  present_form        TEXT NOT NULL,          -- "Claude is implementing X"
  past_form           TEXT NOT NULL,          -- "Claude implemented X"
  selected_form       TEXT NOT NULL CHECK (selected_form IN ('present','past')),
  verb_lemma          TEXT,                   -- For future conjugation
  generated_at        INTEGER NOT NULL,
  user_edited         INTEGER NOT NULL DEFAULT 0,
  user_text           TEXT,
  edited_at           INTEGER,
  request_id          TEXT,
  duration            REAL,
  PRIMARY KEY (content_sha256, window_sha256)
);
CREATE UNIQUE INDEX idx_cache_entry_window ON timeline_cache(entry_id, window_sha256);

/* ========== TRANSCRIPT METADATA (Derived per Transcript) ========== */
CREATE TABLE transcript_metadata (
  transcript_id              TEXT PRIMARY KEY REFERENCES transcripts(id) ON DELETE CASCADE,
  project_id                 TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                             -- ^ Denormalized from transcripts.project_id for query performance
  title                      TEXT NOT NULL,
  description                TEXT NOT NULL,
  topics                     TEXT NOT NULL CHECK (json_valid(topics)),  -- JSON array
  confidence                 REAL NOT NULL,
  may_contain_hallucinations INTEGER NOT NULL DEFAULT 0,
  needs_review               INTEGER NOT NULL DEFAULT 0,
  generated_at               INTEGER NOT NULL,
  model                      TEXT NOT NULL,
  prompt_version             INTEGER NOT NULL,
  generator_version          INTEGER NOT NULL,
  transcript_sha256          TEXT NOT NULL,
  message_count              INTEGER NOT NULL,
  strategy                   TEXT NOT NULL CHECK (strategy IN ('full','bookends','heuristic')),
  llm_calls                  INTEGER NOT NULL,
  latency_ms                 INTEGER NOT NULL,
  created_at                 INTEGER NOT NULL,
  updated_at                 INTEGER NOT NULL
);
CREATE INDEX idx_tmeta_project       ON transcript_metadata(project_id);
CREATE INDEX idx_tmeta_needs_review  ON transcript_metadata(needs_review) WHERE needs_review = 1;
CREATE INDEX idx_tmeta_prompt_ver    ON transcript_metadata(prompt_version);
CREATE INDEX idx_tmeta_gen_ver       ON transcript_metadata(generator_version);

/* ========== PARSE ERRORS (Diagnostics; Hoover Continues on Bad Lines) ========== */
-- raw_line truncated to ≤4096 bytes; keep last 500 per transcript
CREATE TABLE parse_errors (
  id            TEXT PRIMARY KEY,             -- UUID
  transcript_id TEXT NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
  line_number   INTEGER NOT NULL,
  raw_line      TEXT NOT NULL,                -- Truncated to 4096 bytes
  error_message TEXT NOT NULL,
  created_at    INTEGER NOT NULL
);
CREATE INDEX idx_parse_errors_transcript ON parse_errors(transcript_id, created_at DESC);
```

## 4.3 Phase 2 Tables (Defined, Not Created Now)

**Deferred until Phase 2:**

```sql
-- Full-text search
CREATE VIRTUAL TABLE entry_fts USING fts5(
  entry_id UNINDEXED,
  content,
  tokenize='porter unicode61'
);

-- Tool calls (if we aggregate/render them)
CREATE TABLE tool_calls (
  id            TEXT PRIMARY KEY,
  entry_id      TEXT NOT NULL REFERENCES transcript_entries(id) ON DELETE CASCADE,
  tool_name     TEXT NOT NULL,
  arguments     TEXT,                        -- JSON string
  result        TEXT,
  exit_code     INTEGER,
  duration_seconds REAL,
  timestamp     INTEGER NOT NULL,
  created_at    INTEGER NOT NULL
);

-- Mobile/future entities
CREATE TABLE artifacts (...);
CREATE TABLE tasks (...);
CREATE TABLE ai_jobs (...);
CREATE TABLE feedback (...);
CREATE TABLE branches (...);
CREATE TABLE sync_state (...);
```

---

# 5. Identity & Key Generation

## 5.1 UUID Generation Rules

| Entity | ID Source | Rationale |
|--------|-----------|-----------|
| **projects.id** | `UUID().uuidString` on create | New on each project add |
| **transcripts.id** | Provider's session UUID if stable; else `UUID()` | Prefer provider ID; **never** derive from `file_path` (moves break identity) |
| **transcript_entries.id** | **Claude:** use provider's UUID<br>**Codex:** deterministic SHA256 hash of `(timestamp\|role\|lineNumber\|sessionID)` | Idempotent re-parsing |
| **parse_errors.id** | `UUID().uuidString` | Unique error log entry |
| **content_sha256** | SHA256 of canonicalized `content` string | Stable across re-parses |
| **window_sha256** | SHA256 of `join([prev2_id, prev1_id], "\|")` | N=2 for v1; changing N breaks cache |

## 5.2 Deterministic Entry ID (Codex Example)

```swift
func generateEntryID(timestamp: Date, role: String, lineNumber: Int, sessionID: String) -> String {
    let components = "\(timestamp.timeIntervalSince1970)|\(role)|\(lineNumber)|\(sessionID)"
    let hash = SHA256.hash(data: Data(components.utf8))
    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
    // Convert to UUID format (8-4-4-4-12)
    return "\(hashString.prefix(8))-\(hashString.dropFirst(8).prefix(4))-\(hashString.dropFirst(12).prefix(4))-\(hashString.dropFirst(16).prefix(4))-\(hashString.dropFirst(20).prefix(12))"
}
```

## 5.3 Cache Key Algorithms (Explicit Spec)

**`window_sha256` computation:**
```swift
func computeWindowSHA256(prev2: String?, prev1: String?) -> String {
    let window = [prev2 ?? "", prev1 ?? ""].joined(separator: "|")
    let hash = SHA256.hash(data: Data(window.utf8))
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
```
**N = 2 for v1.** Changing N is a breaking change → bump `generator_signature`.

**`generator_signature` format:**
```
"{model}@{model_version}:{prompt}@{prompt_version}"

Example: "gpt-4o@2025-09:timeline@3"
```
Any component change invalidates all cache entries for that signature.

---

# 6. Data Access Layer (Repository Protocols)

## 6.1 Uniform FK Strategy

All repos use **UUID TEXT** for cross-table references. No integer surrogates.

```swift
protocol ProjectRepo {
    func create(name: String?, rootPath: String, bookmark: Data?) throws -> String  // Returns project_id
    func list() throws -> [Project]
    func update(id: String, name: String?, bookmark: Data?) throws
}

protocol TranscriptRepo {
    func upsert(
        projectID: String,
        fileURL: URL,                        // Will be canonicalized
        provider: String,
        providerSessionID: String?,
        lastModified: Date,
        fileSize: Int?
    ) throws -> String  // Returns transcript_id

    func setIngestionState(
        id: String,
        lastProcessedLine: Int,
        lineCount: Int,                      // Incrementally maintained
        parserVersion: Int,
        status: String,
        lastError: String?
    ) throws

    func byProject(_ projectID: String) throws -> [Transcript]
    func get(_ transcriptID: String) throws -> Transcript?
}

protocol EntryRepo {
    func insertBatch(_ rows: [EntryInsert]) throws  // Handles ON CONFLICT
    func recentByProject(_ projectID: String, limit: Int) throws -> [Entry]
    func byTranscript(_ transcriptID: String, after timestamp: Date?) throws -> [Entry]
}

protocol MetadataRepo {
    func upsert(_ row: TranscriptMetadata) throws
    func get(_ transcriptID: String) throws -> TranscriptMetadata?
    func stale(promptVersion: Int, generatorVersion: Int) throws -> [String]  // transcript IDs
}

protocol CacheRepo {
    func get(contentSHA256: String, windowSHA256: String) throws -> CachedTimeline?
    func upsert(_ row: CachedTimeline) throws
}

protocol ParseErrorRepo {
    func insert(
        transcriptID: String,
        lineNumber: Int,
        rawLine: String,                     // Will be truncated to 4096 bytes
        errorMessage: String
    ) throws
    func byTranscript(_ transcriptID: String, limit: Int) throws -> [ParseError]  // Newest first
    func pruneOldest(transcriptID: String, keepLast: Int) throws  // Retention policy
}
```

---

# 7. Runtime Behavior: Hoover + Stream

## 7.1 Configuration Constants

```swift
enum MonitorConfig {
    static let fileWatcherDebounce: TimeInterval = 0.150  // seconds
    static let batchLines: Int = 1000
    static let checkpointEveryLines: Int = 1000
    static let parseErrorMaxLineLength: Int = 4096        // bytes
    static let parseErrorRetentionPerTranscript: Int = 500
}
```

## 7.2 Phase A: Initial Hoover (Streaming Parser)

**Triggers:**
- App launch (scan all projects)
- User adds new project
- Manual "Refresh Transcripts" action

**Process (streaming, not whole-file load):**

```swift
func hooverTranscript(_ transcript: Transcript, progress: IngestProgressSink) throws {
    let fileURL = transcript.fileURL
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }

    progress.didStartTranscript(name: fileURL.lastPathComponent, totalLines: transcript.line_count)

    var buffer = Data()
    var lineNo = transcript.lastProcessedLine
    var batch: [EntryInsert] = []
    var errors: [ParseError] = []
    let batchSize = MonitorConfig.batchLines

    // Skip to resume point (fast-forward)
    if lineNo > 0 {
        var skippedLines = 0
        while skippedLines < lineNo {
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            buffer.append(chunk)
            while let range = buffer.firstRange(of: Data([0x0A])) {  // '\n'
                buffer.removeSubrange(..<range.upperBound)
                skippedLines += 1
                if skippedLines >= lineNo { break }
            }
        }
        buffer.removeAll()  // Clear partial line after skip
    }

    // Process remaining lines
    while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
        buffer.append(chunk)

        while let range = buffer.firstRange(of: Data([0x0A])) {  // '\n'
            let lineData = buffer[..<range.lowerBound]
            buffer.removeSubrange(..<range.upperBound)
            lineNo += 1

            guard let lineString = String(data: lineData, encoding: .utf8) else {
                errors.append(ParseError(
                    transcriptID: transcript.id,
                    lineNumber: lineNo,
                    rawLine: "<invalid UTF-8>",
                    errorMessage: "Line is not valid UTF-8"
                ))
                continue
            }

            do {
                let entry = try parseTranscriptLine(
                    lineString,
                    provider: transcript.provider,
                    lineNumber: lineNo,
                    sessionID: transcript.provider_session_id
                )
                batch.append(entry)
            } catch {
                let truncated = String(lineString.prefix(MonitorConfig.parseErrorMaxLineLength))
                errors.append(ParseError(
                    transcriptID: transcript.id,
                    lineNumber: lineNo,
                    rawLine: truncated,
                    errorMessage: error.localizedDescription
                ))
            }

            // Checkpoint every N lines
            if batch.count >= batchSize {
                try commitBatch(
                    transcriptID: transcript.id,
                    entries: batch,
                    errors: errors,
                    lastProcessedLine: lineNo,
                    lineCount: lineNo
                )
                batch.removeAll()
                errors.removeAll()
                progress.didAdvance(linesProcessed: lineNo, totalLines: nil)
            }
        }
    }

    // Final batch
    if !batch.isEmpty || !errors.isEmpty {
        try commitBatch(
            transcriptID: transcript.id,
            entries: batch,
            errors: errors,
            lastProcessedLine: lineNo,
            lineCount: lineNo
        )
    }

    progress.didCompleteTranscript(durationMs: Int(elapsed * 1000))
}

func commitBatch(
    transcriptID: String,
    entries: [EntryInsert],
    errors: [ParseError],
    lastProcessedLine: Int,
    lineCount: Int
) throws {
    try db.write { db in
        // Insert entries (ON CONFLICT DO NOTHING for idempotence)
        for entry in entries {
            try db.execute(
                sql: """
                INSERT INTO transcript_entries
                  (id, transcript_id, project_id, session_id, provider, kind, timestamp,
                   content, content_sha256, parent_id, git_branch, git_commit, cwd,
                   created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO NOTHING
                """,
                arguments: [entry.id, entry.transcriptID, /* ... */]
            )
        }

        // Insert errors
        for error in errors {
            try parseErrorRepo.insert(
                transcriptID: error.transcriptID,
                lineNumber: error.lineNumber,
                rawLine: error.rawLine,
                errorMessage: error.errorMessage
            )
        }

        // Prune old errors (keep last 500)
        try parseErrorRepo.pruneOldest(
            transcriptID: transcriptID,
            keepLast: MonitorConfig.parseErrorRetentionPerTranscript
        )

        // Update checkpoint + line count
        try transcriptRepo.setIngestionState(
            id: transcriptID,
            lastProcessedLine: lastProcessedLine,
            lineCount: lineCount,
            parserVersion: 1,
            status: "active",
            lastError: nil
        )
    }
}
```

**Performance:**
- 50k line transcript: ~2 seconds total
- Memory: O(batch_size) = ~1MB per 1000 lines
- Progress updates: Every batch (~40ms per batch)
- Checkpoint: Every batch (crash-safe)

## 7.3 Phase B: Incremental Streaming (File Watcher)

**Triggers:**
- File watcher detects `.write` or `.extend` event
- Debounced to 150ms (configurable via `MonitorConfig.fileWatcherDebounce`)

**Process:**

```swift
func streamNewLines(_ transcript: Transcript) throws {
    // Use same streaming logic as hoover, starting from last_processed_line + 1
    try hooverTranscript(transcript, progress: NoOpProgressSink())

    // Notify UI
    NotificationCenter.default.post(name: .transcriptUpdated, object: transcript.id)
}
```

**Performance:**
- Single message: <5ms DB insert
- Batch of 10 messages: ~20ms
- File watcher latency: <100ms from write to UI update
- Total (cache hit): <70ms
- Total (cache miss + LLM): <870ms

## 7.4 ON CONFLICT Policies (Explicit)

**Initial hoover / normal stream:** Deduplicate silently
```sql
INSERT INTO transcript_entries (id, content, content_sha256, ...)
VALUES (?, ?, ?, ...)
ON CONFLICT(id) DO NOTHING;
```

**Re-parse after provider format change (rare):** Update only if content changed
```sql
INSERT INTO transcript_entries (id, content, content_sha256, updated_at, ...)
VALUES (?, ?, ?, ?, ...)
ON CONFLICT(id) DO UPDATE SET
  content = excluded.content,
  content_sha256 = excluded.content_sha256,
  updated_at = excluded.updated_at
WHERE transcript_entries.content_sha256 != excluded.content_sha256;
```

## 7.5 Crash Safety & Resume

**Checkpoint Strategy:**
- `transcripts.last_processed_line` updated after each batch
- `transcripts.line_count` incremented per batch
- On crash: Resume from last checkpoint
- UUID deduplication prevents duplicates (`ON CONFLICT(id) DO NOTHING`)

**Scenarios:**

| Scenario | Detection | Response |
|----------|-----------|----------|
| App crash during hoover | `last_processed_line < actual_lines` | Resume from checkpoint |
| File truncated/corrupted | `line_count < last_processed_line` | Reset to 0, re-hoover, mark `status='error'` |
| Parser version upgrade | `parser_version < current_version` | See §7.6 |

## 7.6 Parser Upgrade Strategy (Explicit)

**When parser version changes (e.g., v1 → v2):**

```swift
func upgradeTranscriptParser(transcriptID: String, newVersion: Int) throws {
    try db.write { db in
        // 1. Mark transcript for re-parse
        try db.execute(
            sql: """
            UPDATE transcripts
            SET parser_version = ?,
                last_processed_line = 0
            WHERE id = ?
            """,
            arguments: [newVersion, transcriptID]
        )

        // 2. Delete old entries (FK cascades to timeline_cache)
        try db.execute(
            sql: "DELETE FROM transcript_entries WHERE transcript_id = ?",
            arguments: [transcriptID]
        )

        // 3. Metadata survives (no cascade from entries)
        // Timeline cache is deleted via FK cascade
    }

    // 4. Re-hoover with new parser
    let transcript = try transcriptRepo.get(transcriptID)!
    try hooverTranscript(transcript, progress: NoOpProgressSink())
}
```

**Guarantees consistency** without per-row transformations.

---

# 8. Provider-Specific Parsing

## 8.1 Claude Code Format

**Key Fields:**
```json
{
  "uuid": "abc-123-456",
  "type": "user" | "assistant",
  "timestamp": "2025-10-10T12:34:56.789Z",
  "sessionId": "session-uuid",
  "message": {
    "role": "user",
    "content": "string or array"
  },
  "parentUuid": "parent-uuid",
  "gitBranch": "main",
  "cwd": "/Users/rob/code/project"
}
```

**Parser:**
```swift
func parseClaudeCodeLine(_ json: [String: Any], lineNumber: Int) -> EntryInsert? {
    guard let uuid = json["uuid"] as? String else { return nil }
    guard let type = json["type"] as? String else { return nil }
    guard let timestamp = parseISO8601(json["timestamp"]) else { return nil }

    let content: String
    if let msg = json["message"] as? [String: Any] {
        content = extractContent(msg["content"])  // Handle string or array
    } else {
        return nil
    }

    return EntryInsert(
        id: uuid,  // Use provider's UUID
        sessionId: json["sessionId"] as? String,
        provider: "claude.code",
        kind: mapKind(type),
        timestamp: timestamp,
        content: content,
        contentSha256: SHA256(content),
        parentId: json["parentUuid"] as? String,
        gitBranch: json["gitBranch"] as? String,
        cwd: json["cwd"] as? String
    )
}
```

## 8.2 Codex CLI Format

**Key Fields:**
```json
{
  "timestamp": "2025-10-10T12:34:56.789Z",
  "type": "response_item",
  "payload": {
    "type": "message",
    "role": "user" | "assistant",
    "content": [
      { "type": "input_text", "text": "..." }
    ]
  }
}
```

**Parser:**
```swift
func parseCodexLine(_ json: [String: Any], lineNumber: Int, sessionID: String) -> EntryInsert? {
    guard let timestamp = parseISO8601(json["timestamp"]) else { return nil }
    guard let payload = json["payload"] as? [String: Any] else { return nil }
    guard payload["type"] as? String == "message" else { return nil }
    guard let role = payload["role"] as? String else { return nil }

    let content = extractContentArray(payload["content"])
    let entryID = generateEntryID(
        timestamp: timestamp,
        role: role,
        lineNumber: lineNumber,
        sessionID: sessionID
    )

    return EntryInsert(
        id: entryID,  // Deterministic UUID
        sessionId: sessionID,
        provider: "codex.cli",
        kind: role,
        timestamp: timestamp,
        content: content,
        contentSha256: SHA256(content),
        gitBranch: extractGitBranch(from: sessionMeta),
        gitCommit: extractGitCommit(from: sessionMeta),
        cwd: extractCwd(from: sessionMeta)
    )
}
```

---

# 9. Progress UI Contract

## 9.1 Protocol Definition

```swift
protocol IngestProgressSink {
    func didStartTranscript(name: String, totalLines: Int?)
    func didAdvance(linesProcessed: Int, totalLines: Int?)
    func didCompleteTranscript(durationMs: Int)
    func didFailTranscript(error: String)
    func didStartProject(name: String, transcriptCount: Int)
    func didCompleteProject(name: String)
}
```

**ETA computation:** Client-side from `didAdvance` samples (not in protocol).

## 9.2 UI Strings

**Batch import:**
```
"Importing transcripts… 12/47 complete"
"Current: session-abc.jsonl (7,453 / 12,091 lines)"
"Elapsed: 00:42 • Estimated remaining: 02:15"
```

**Single transcript:**
```
"Processing session-xyz.jsonl…"
"Imported 3,287 messages in 1.2s"
```

**Errors:**
```
"⚠️ 5 parse errors in session-abc.jsonl (see diagnostics)"
"❌ Failed to process session-xyz.jsonl: File not accessible"
```

---

# 10. Operational Settings & Health

## 10.1 SQLite Configuration (Production Hardening)

```swift
var config = Configuration()
config.foreignKeysEnabled = true
config.busyMode = .timeout(5.0)  // 5 seconds (handles concurrent reads)
config.prepareDatabase { db in
    try db.execute(sql: "PRAGMA journal_mode=WAL;")
    try db.execute(sql: "PRAGMA synchronous=NORMAL;")      // Balance safety + speed
    try db.execute(sql: "PRAGMA wal_autocheckpoint=1000;") // ~4-8MB
    try db.execute(sql: "PRAGMA temp_store=MEMORY;")
}

// Use DatabasePool for concurrent reads in WAL mode
let db: DatabaseWriter & DatabaseReader = try DatabasePool(path: dbPath, configuration: config)
```

**Key changes from v3:**
- ✅ `busyMode = .timeout(5)` (handles concurrent reads gracefully)
- ✅ `DatabasePool` instead of `DatabaseQueue` (enables concurrent reads)

## 10.2 WAL Monitoring & Checkpointing (Corrected)

**Thresholds:**
- **Warning:** WAL > 50MB → log to OSLog
- **Action:** WAL > 100MB → checkpoint immediately

**Monitoring (no filesystem assumptions):**

```swift
func checkWALSize() throws {
    let pageSize: Int = try db.read { db in
        try Int.fetchOne(db, sql: "PRAGMA page_size")!
    }

    // PRAGMA wal_checkpoint(PASSIVE) returns (busy, log, checkpointed)
    let row: Row? = try db.read { db in
        try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(PASSIVE)")
    }

    guard let row = row, row.count > 1 else { return }
    let logPages = row[1] as? Int ?? 0
    let walMB = (logPages * pageSize) / 1_048_576

    if walMB >= 50 {
        log.warning("WAL size: ~\(walMB)MB")

        if walMB >= 100 {
            try db.write { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE);")
            }
            log.info("WAL checkpoint triggered: \(walMB)MB → truncated")
        }
    }
}
```

**Run on:**
- After large imports (>10k entries)
- App idle for 5 minutes
- App quit (background task)

## 10.3 Startup Health Check

```swift
func validateDatabase() throws {
    // Quick integrity check
    try db.read { db in
        try db.execute(sql: "PRAGMA quick_check;")
    }

    // Canary query
    let projectCount = try db.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects")!
    }

    log.info("Database OK: \(projectCount) projects")
}
```

**On failure:**
- Show alert: "Database corrupted. Reset database?"
- Options: "Reset" (drop/recreate) or "Contact Support"

## 10.4 Maintenance

**ANALYZE:** Weekly (or after importing >50k entries)
```sql
ANALYZE;
```

**VACUUM:** Monthly or when bloat >25%
```swift
let dbSize = try FileManager.default.attributesOfItem(atPath: dbPath.path)[.size] as! Int64
let freePages = try db.read { db in try Int.fetchOne(db, sql: "PRAGMA freelist_count;")! }
let pageSize = try db.read { db in try Int.fetchOne(db, sql: "PRAGMA page_size;")! }
let bloat = Double(freePages * pageSize) / Double(dbSize)

if bloat > 0.25 {
    log.info("VACUUM: \(Int(bloat * 100))% bloat")
    try db.write { db in
        try db.execute(sql: "VACUUM;")
    }
}
```

---

# 11. Performance Targets & Monitoring

## 11.1 SLOs (v1)

| Operation | Target (p95) | Notes |
|-----------|--------------|-------|
| DB open + quick_check | ≤150ms | App launch |
| Recent feed (50k entries) | ≤5ms | Timeline view |
| Hoover batch (1k rows) | ≤40ms | Initial import |
| Stream insert (≤100 rows) | ≤20ms | File watcher |
| Cache lookup | ≤5ms | content_sha256 + window_sha256 |
| Metadata upsert | ≤2ms | Single row |
| Project list | ≤10ms | Sidebar |

## 11.2 Slow Query Logging

```swift
func logSlowQuery(sql: String, duration: TimeInterval, rowCount: Int) {
    if duration >= 0.05 {  // 50ms
        let sqlHash = SHA256(sql).prefix(8)
        log.warning("db.query.slow: \(Int(duration * 1000))ms, \(rowCount) rows, sql_hash=\(sqlHash)")
    }
}
```

**Alerts:**
- ≥50ms: Warning
- ≥500ms: Error
- Include: sql_hash, row_count, duration_ms

---

# 12. Security & Privacy

## 12.1 Storage

- **DB Location:** `~/Library/Application Support/Contextify/transcripts.db`
- **Permissions:** 0600 (user read/write only)
- **Transcripts:** Accessed via security-scoped bookmarks (sandboxed)
- **Path Canonicalization:** Store resolved absolute paths (no symlinks)

## 12.2 Path Canonicalization

```swift
func canonicalizePath(_ path: String) -> String {
    let url = URL(fileURLWithPath: path)
    return url.standardizedFileURL.path  // Resolves symlinks, normalizes
}
```

**Applied to:**
- `projects.root_path`
- `transcripts.file_path`

**Prevents:** Duplicate entries from different symlink spellings.

## 12.3 Data Stored

**What's in DB:**
- ✅ Parsed message text (content column)
- ✅ LLM-generated summaries
- ✅ Timeline metadata
- ✅ Git context (branch, commit, cwd)

**What's NOT in DB:**
- ❌ Raw transcript files (external)
- ❌ Credentials/tokens (not parsed)
- ❌ User authentication data

## 12.4 Privacy Controls

**Future (v1.x):**
- PII detection: Flag entries with emails/keys/tokens
- Redaction: `[REDACTED]` replacement
- Export: GDPR right to deletion (purge project + cascade)

---

# 13. Quality Gates & Testing

## 13.1 Integrity Checks

- **FK cascade delete:** Delete project → cascade to transcripts → cascade to entries/cache/metadata
- **UUID uniqueness:** `ON CONFLICT(id) DO NOTHING` prevents duplicates
- **Deterministic IDs:** Same Codex line → same entry.id on re-parse
- **Parent threading:** `parent_id` FK ensures referential integrity

## 13.2 Test Fixtures

**Golden dataset:**
- Project A: 3 Claude Code transcripts (500, 5k, 50k lines)
- Project B: 2 Codex CLI transcripts (1k, 10k lines)
- Total: ~70k entries

**Test cases:**
- Hoover from scratch (measure p95)
- Resume from crash (simulate at line 5000)
- Parser version upgrade (re-parse with v2)
- Truncated file (detect + reset)
- Duplicated lines (UUID conflict → skip)
- Bad JSON lines (parse error → continue)
- Parse error retention (verify only last 500 kept)

## 13.3 Performance Validation

```swift
func testHooverPerformance() throws {
    let transcript = Transcript(/* 50k lines */)

    measure {
        try hooverTranscript(transcript, progress: NoOpProgressSink())
    }

    XCTAssertLessThan(duration, 3.0, "Hoover 50k lines should take <3s")
}
```

---

# 14. Implementation Phases

## 14.1 Phase 1 (Current: Ship v1)

**Scope:**
- ✅ Schema from §4 (projects, transcripts, entries, cache, metadata, parse_errors)
- ✅ Hoover + stream logic (streaming parser, no whole-file loads)
- ✅ Provider parsers (Claude Code, Codex CLI)
- ✅ Progress UI
- ✅ WAL monitoring (SQLite-based, not filesystem)
- ✅ Crash-safe checkpointing
- ✅ Path canonicalization
- ✅ Parse error truncation + retention

**Out of scope:**
- ❌ FTS (Phase 2)
- ❌ Export to JSONL (Phase 2)
- ❌ Mobile entities (Phase 2)
- ❌ File cache migration (greenfield only)

**Timeline:**
- Week 1: Schema + repos + streaming hoover logic
- Week 2: File watchers + streaming + progress UI
- Week 3: Testing + polish
- **Ship:** End of Week 3

## 14.2 Phase 2 (Deferred, Defined)

**Scope:**
- FTS5 integration (`entry_fts` table + triggers)
- Export to JSONL (reconstruct provider format)
- Tool calls table (if aggregating/rendering)
- Cross-session insights dashboard
- Mobile entities (artifact, task, ai_job, feedback, branch)
- Sync scaffolding (sync_state table)

**Trigger:** After Phase 1 ships + user feedback collected

---

# 15. Risk Mitigation

## 15.1 Provider Format Changes

**Risk:** Claude Code updates JSONL format → parser breaks

**Mitigation:**
- Version detection: Check `version` field in transcript
- Backward-compatible parsers: `ClaudeCodeParserV1`, `ClaudeCodeParserV2`
- Fallback: GenericParser on parse failure
- Log unknown record types for future analysis

## 15.2 Storage Growth

**Risk:** Unlimited storage → disk space issues

**Mitigation:**
- Parse error truncation: 4096 bytes per line
- Parse error retention: 500 per transcript
- Archive old projects (user-initiated)
- Offer "export + delete" workflow

## 15.3 Performance Degradation

**Risk:** 100k+ entries → slow queries

**Mitigation:**
- Partial indexes (WHERE clauses on hot paths)
- Regular ANALYZE (weekly)
- Slow query logs → identify missing indexes
- Add composite indexes if needed

---

# 16. Pre-Implementation Checklist

**Before writing code:**

- [ ] Review schema (§4) with team
- [ ] Approve UUID key strategy (§5)
- [ ] Confirm provider formats (§8)
- [ ] Set up test fixtures (§13.2)
- [ ] Define performance benchmarks (§11.1)

**During implementation:**

- [ ] Wire GRDB with config from §10.1 (DatabasePool + busyMode)
- [ ] Implement streaming parser (§7.2 - no whole-file loads)
- [ ] Implement deterministic entry ID generator (§5.2)
- [ ] Build hoover with progress sink (§7.2)
- [ ] Build stream with file watcher (§7.3)
- [ ] Add slow query logging (§11.2)
- [ ] Test crash recovery (§7.5)
- [ ] Implement WAL monitoring via SQLite PRAGMA (§10.2)
- [ ] Canonicalize paths on insert (§12.2)
- [ ] Implement parse error truncation + pruning (§7.2)

**Before shipping:**

- [ ] Run performance tests (hit p95 targets)
- [ ] Test with 50k line transcript
- [ ] Verify FK cascade deletes
- [ ] Check WAL checkpointing
- [ ] Test parser error handling
- [ ] Verify parse error retention (only last 500)
- [ ] Test concurrent reads (DatabasePool)

---

# 17. Changes from v3

**What Changed:**

| Aspect | v3 | v4 (Production Ready) |
|--------|----|-----------------------|
| Hoover parser | Whole-file `String(contentsOf:)` | ✅ Streaming `FileHandle` |
| GRDB config | `DatabaseQueue` | ✅ `DatabasePool` + `busyMode` |
| WAL monitoring | Filesystem `appendingPathExtension` ❌ | ✅ SQLite `PRAGMA wal_checkpoint(PASSIVE)` |
| Parent FK | No constraint | ✅ `REFERENCES transcript_entries(id) ON DELETE SET NULL` |
| Hash naming | Inconsistent `_hash` / `_sha256` | ✅ Consistent `_sha256` everywhere |
| Cache keys | Undefined algorithms | ✅ Explicit `window_sha256`, `generator_signature` specs |
| Session naming | Vague | ✅ Clear `provider_session_id` vs `session_id` (denorm) |
| Path storage | Raw paths | ✅ Canonicalized (resolves symlinks) |
| Parse errors | Unbounded | ✅ Truncated (4096 bytes) + pruned (keep 500) |
| JSON validity | Unchecked | ✅ `CHECK (json_valid(topics))` |
| ON CONFLICT | Implicit | ✅ Explicit policies documented |
| Denorm rationale | Unclear | ✅ Explicit comments (performance) |

**Key Insight:** v4 is production-hardened with streaming I/O, proper concurrency, and explicit failure modes.

---

**End of Brief**

---

## Appendix: Quick Reference

### Provider Enum Values

```sql
provider IN ('claude.code', 'codex.cli', 'other')
```

### Kind Enum Values

```sql
kind IN ('user', 'assistant', 'system')
```

### Status Enum Values

```sql
status IN ('active', 'unavailable', 'error')
```

### Strategy Enum Values

```sql
strategy IN ('full', 'bookends', 'heuristic')
```

### Selected Form Enum Values

```sql
selected_form IN ('present', 'past')
```

---

**Document Status:** Final - Production Ready
**Version:** 4.0.0 (production hardening)
**Next Steps:** Implement schema → build streaming hoover → ship Phase 1
**Estimated Effort:** ~26 units (~260 minutes = ~4.3 hours of core changes)
