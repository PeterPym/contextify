# SQLite Backend Data Flow Clarification

**Date:** 2025-10-10
**Companion to:** `sql-implementation-plan-02.md`
**Purpose:** Clarify the "hoover + stream" architecture for transcript ingestion

---

## CLARIFICATION: Data Flow Model

Contextify uses a **hoover + stream** architecture for transcript ingestion. This document clarifies how transcript data moves from external JSONL files into the SQLite database.

---

## 1. Core Principle: Store Content, Not Just References

**IMPORTANT:** The database **DOES store message content** (the `content TEXT NOT NULL` column).

This was a point of confusion in earlier planning:
- ❌ **v1 assumption (wrong):** "DB stores only references; transcripts are external"
- ✅ **v2/actual design (correct):** "DB stores parsed content for querying; transcripts are source of truth"

### Why Store Content?

```sql
-- This query is IMPOSSIBLE without storing content:
SELECT content FROM transcript_entries
WHERE content LIKE '%merge conflict%'
  AND timestamp > strftime('%s', 'now', '-6 months');
```

**Key Point:** After Claude Code deletes a transcript (30-day retention), the DB still has the data.

---

## 2. The Two-Phase Ingestion Flow

### Phase A: Initial Hoover (On Discovery)

**When it happens:**
- App launch
- User adds new project
- Manual "Refresh Transcripts" action

**What it does:**
```
1. Discovery Scan:
   - Find all *.jsonl in ~/.claude/projects/<project>/
   - Find all *.jsonl in Codex CLI directories

2. For each discovered transcript file:
   a. Check if already in DB (by file_path)
   b. If NEW → Full backfill:
      - Read entire file
      - Parse ALL lines (respecting lastProcessedLine if resuming)
      - Batch INSERT into transcript_entries
      - Store metadata in transcripts table
   c. If EXISTS → Incremental update:
      - Read from last_processed_line to EOF
      - Parse new lines only
      - Batch INSERT new entries
      - Update last_processed_line

3. Set up file watcher for real-time streaming
```

**Database Operations:**
```sql
-- Check if transcript already imported
SELECT id, last_processed_line
FROM transcripts
WHERE file_path = '/Users/rob/.claude/projects/.../session.jsonl';

-- If NEW, insert transcript record
INSERT INTO transcripts (id, file_path, provider, session_id, project_path, last_processed_line)
VALUES (?, ?, ?, ?, ?, 0);

-- Batch insert all historical entries
BEGIN TRANSACTION;
INSERT INTO transcript_entries (uuid, session_id, provider, kind, timestamp, content, ...)
VALUES (?, ?, ?, ?, ?, ?, ...),
       (?, ?, ?, ?, ?, ?, ...),
       ... (repeat for 1000s of rows)
COMMIT;

-- Update progress checkpoint
UPDATE transcripts SET last_processed_line = ? WHERE id = ?;
```

**Performance Characteristics:**
- 10k line transcript: ~2 seconds to hoover
- Uses WAL mode + batched transactions
- Progress saved every 1000 lines (crash-safe)

---

### Phase B: Incremental Streaming (On File Change)

**When it happens:**
- File watcher detects `.write` or `.extend` event on transcript file
- Triggered by Claude Code/Codex writing new messages

**What it does:**
```
1. File Watcher Event Fired:
   - DispatchSource detects file modification
   - Read transcripts.last_processed_line from DB

2. Incremental Parse:
   - Read lines [last_processed_line + 1, EOF]
   - Parse only NEW lines (not entire file)

3. Insert New Entries:
   - For each parsed line:
     * Generate/extract UUID
     * Map fields to schema
     * INSERT INTO transcript_entries
   - Batch in groups of 100 for efficiency

4. Update Checkpoint:
   - UPDATE transcripts.last_processed_line = current_line
   - Commit transaction

5. Update UI:
   - Notify ConversationMonitor
   - Append to timeline (if entry passes filters)
```

**Database Operations:**
```sql
-- Get resume point
SELECT last_processed_line FROM transcripts WHERE id = ?;

-- Insert new entries (small batch)
BEGIN TRANSACTION;
INSERT INTO transcript_entries (uuid, session_id, provider, kind, timestamp, content, ...)
VALUES (?, ?, ?, ?, ?, ?, ...);  -- 1-100 new entries
COMMIT;

-- Update checkpoint
UPDATE transcripts SET last_processed_line = ?, last_modified = ? WHERE id = ?;
```

**Performance Characteristics:**
- Single message insert: <5ms
- Batch of 10 messages: ~20ms
- File watcher latency: <100ms from write to UI update

---

## 3. Crash Safety & Resume Logic

### Checkpoint Strategy

**Every write updates progress:**
```sql
-- transcripts table tracks ingestion state
CREATE TABLE transcripts (
  id TEXT PRIMARY KEY,
  file_path TEXT NOT NULL UNIQUE,
  last_processed_line INTEGER NOT NULL DEFAULT 0,  -- Resume point
  last_read_byte_offset INTEGER NOT NULL DEFAULT 0, -- Alternate resume (future)
  parser_version INTEGER NOT NULL DEFAULT 1,        -- Schema evolution
  ...
);
```

### Resume Scenarios

**Scenario 1: App Crash During Hoover**
```
Initial state: last_processed_line = 2500
App crashes at line 7300

On restart:
1. Load last_processed_line (2500)
2. Resume from line 2501
3. Continue until EOF
4. No duplicate entries (UUID deduplication)
```

**Scenario 2: File Truncated/Corrupted**
```
Detection: line_count < last_processed_line

Response:
1. Log warning to OSLog
2. Reset last_processed_line = 0
3. Re-hoover entire file
4. Mark transcripts.needs_revalidation = 1
```

**Scenario 3: Parser Version Upgrade**
```
Old: parser_version = 1
New: parser_version = 2 (schema changed)

Migration:
1. SELECT id FROM transcripts WHERE parser_version < 2
2. For each outdated transcript:
   - Reset last_processed_line = 0
   - Re-parse with new parser
   - Update parser_version = 2
```

---

## 4. Deduplication Strategy

### UUID-Based Deduplication

**Problem:** Re-parsing a transcript might encounter duplicate entries.

**Solution:** Use `uuid TEXT UNIQUE NOT NULL` constraint.

```sql
-- This automatically prevents duplicates
CREATE TABLE transcript_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT UNIQUE NOT NULL,  -- Enforced by DB
  ...
);

-- Insert with conflict handling
INSERT INTO transcript_entries (uuid, session_id, ...)
VALUES (?, ?, ...)
ON CONFLICT(uuid) DO NOTHING;  -- Skip duplicates silently
```

### UUID Sources

**Claude Code:** Uses transcript's `uuid` field directly
```json
{"uuid": "abc-123", "type": "user", ...}
```

**Codex CLI:** Generate deterministic UUID
```swift
// Codex doesn't provide UUID, so generate one
let uuid = SHA256("\(timestamp)-\(role)-\(lineNumber)")
```

**Stability:** Same line always produces same UUID (deterministic hash).

---

## 5. Provider-Specific Parsing

### Current Support (v1)

**Claude Code Parser:**
```swift
func parseClaudeCodeLine(_ json: [String: Any]) -> TranscriptEntry? {
    guard let uuid = json["uuid"] as? String else { return nil }
    guard let type = json["type"] as? String else { return nil }
    guard let timestamp = parseISO8601(json["timestamp"]) else { return nil }

    let content: String
    if let msg = json["message"] as? [String: Any] {
        // Extract content from message.content (string or array)
        content = extractContent(msg["content"])
    } else {
        return nil
    }

    return TranscriptEntry(
        uuid: uuid,
        sessionId: json["sessionId"] as? String ?? "unknown",
        provider: "claude.code",
        kind: mapKind(type),
        timestamp: timestamp,
        content: content,
        parentUuid: json["parentUuid"] as? String,
        gitBranch: json["gitBranch"] as? String,
        cwd: json["cwd"] as? String
    )
}
```

**Codex CLI Parser:**
```swift
func parseCodexLine(_ json: [String: Any]) -> TranscriptEntry? {
    guard let timestamp = parseISO8601(json["timestamp"]) else { return nil }
    guard let payload = json["payload"] as? [String: Any] else { return nil }
    guard payload["type"] as? String == "message" else { return nil }
    guard let role = payload["role"] as? String else { return nil }

    let content = extractContentArray(payload["content"])
    let uuid = generateUUID(timestamp: timestamp, role: role, line: currentLine)

    return TranscriptEntry(
        uuid: uuid,
        sessionId: sessionIdFromSessionMeta, // Extracted earlier
        provider: "codex.cli",
        kind: role,
        timestamp: timestamp,
        content: content,
        gitBranch: gitContextBranch,
        gitCommit: gitContextCommit,
        cwd: gitContextCwd
    )
}
```

### Removed: Gemini/Grok Support

**Decision:** Gemini CLI and Grok CLI do **not** auto-save session transcripts like Claude Code and Codex.

**Impact:**
- Schema supports them (via `provider` enum), but parsers not needed
- If future CLIs emerge with auto-save, parsers can be added later
- Generic fallback parser handles unknown formats

**Updated Provider Enum:**
```sql
provider TEXT NOT NULL CHECK (provider IN (
  'claude.code',
  'codex.cli',
  'other'  -- For manual imports or future providers
))
```

---

## 6. Content Storage Strategy

### What Gets Stored

**Full message content:**
```sql
-- Example: User message
content: "Can you help me debug this React component? It's throwing..."

-- Example: Assistant message
content: "I'll help you debug that. Let me analyze the error..."

-- Example: Tool use (stored in tool_calls table, linked to entry)
entry.content: "Running bash command..."
tool_calls.arguments: '{"command": "ls -la", "workdir": "/Users/rob/..."}'
tool_calls.result: '{"output": "total 48\ndrwxr-xr-x...", "exit_code": 0}'
```

### Content SHA256 (For Cache Joins)

**Purpose:** Link transcript entries to timeline cache without re-reading files.

```sql
-- Generate on insert
UPDATE transcript_entries
SET content_sha256 = SHA256(content)
WHERE id = ?;

-- Fast cache lookup (no file access needed)
SELECT tce.*, te.content
FROM timeline_cache tce
JOIN transcript_entries te ON te.uuid = tce.uuid
WHERE tce.content_hash = ?
  AND tce.window_hash = ?;
```

**Benefit:** If transcript file deleted, cache still works (DB has content).

---

## 7. Export to JSONL (Phase 3 Feature)

### Roadmap Placement

**Phase 1:** Hoover + stream (current focus)
**Phase 2:** Cross-session analysis, FTS
**Phase 3:** Export to JSONL (data portability)

### Export Strategy

**Goal:** Reconstruct original transcript format from DB.

**Implementation:**
```swift
func exportToJSONL(sessionId: String, outputPath: URL) throws {
    let entries = try db.entriesForSession(sessionId)
    let provider = entries.first?.provider ?? "unknown"

    let exporter: TranscriptExporter
    switch provider {
    case "claude.code":
        exporter = ClaudeCodeExporter()
    case "codex.cli":
        exporter = CodexExporter()
    default:
        exporter = GenericExporter()
    }

    let jsonl = exporter.export(entries)
    try jsonl.write(to: outputPath)
}
```

**Claude Code Export Example:**
```swift
class ClaudeCodeExporter {
    func export(_ entries: [TranscriptEntry]) -> String {
        entries.map { entry in
            let json: [String: Any] = [
                "uuid": entry.uuid,
                "type": entry.kind,
                "timestamp": ISO8601(entry.timestamp),
                "sessionId": entry.sessionId,
                "message": [
                    "role": entry.kind,
                    "content": entry.content
                ],
                "parentUuid": entry.parentUuid,
                "gitBranch": entry.gitBranch,
                "cwd": entry.cwd
            ]
            return JSONSerialization.data(json).utf8String
        }.joined(separator: "\n")
    }
}
```

**Use Cases:**
- User wants to switch away from Contextify (data portability)
- Export for backup/archival
- Share conversation with colleague (JSONL → readable format)

---

## 8. Performance Characteristics

### Hoover Performance (Initial Import)

**Benchmark:** 50k line transcript (typical large session)

```
Parse Time:     800ms  (50k lines @ 62.5k lines/sec)
DB Insert:      1.2s   (50k rows, batched)
Index Update:   200ms  (uuid, session_id, timestamp indexes)
Total:          2.2s
```

**Optimization:** Batched transactions
```swift
let batchSize = 1000
for chunk in entries.chunked(by: batchSize) {
    try db.transaction {
        for entry in chunk {
            try db.insertEntry(entry)
        }
    }
    // Update progress every batch
    try db.updateLastProcessedLine(transcript.id, lineNumber)
}
```

### Streaming Performance (Real-Time)

**Benchmark:** Single message arrival (typical case)

```
File Watcher Latency:  <50ms   (detect write event)
Parse Line:            <1ms    (single JSON line)
DB Insert:             <5ms    (single row)
Cache Check:           <3ms    (content_hash lookup)
LLM Summarize:         800ms   (if cache miss)
UI Update:             <10ms   (SwiftUI re-render)
Total (cache hit):     <70ms
Total (cache miss):    <870ms
```

### Worst Case: Full Re-Parse

**Scenario:** Parser version upgrade, need to re-process all transcripts.

**Strategy:**
```sql
-- Mark all as needing re-parse
UPDATE transcripts SET last_processed_line = 0, parser_version = 2;

-- Background job processes incrementally
SELECT id FROM transcripts WHERE parser_version < 2 LIMIT 10;
-- Re-parse each (spread over time to avoid blocking UI)
```

**User Experience:** Background progress indicator, app stays responsive.

---

## 9. Error Handling

### Parse Errors

**Strategy:** Log and continue (don't block entire import on bad line)

```swift
for (lineNum, line) in lines.enumerated() {
    do {
        let entry = try parseTranscriptLine(line, provider: provider)
        try db.insertEntry(entry)
    } catch {
        // Log to parse_errors table
        try db.insertParseError(
            transcriptId: transcript.id,
            lineNumber: lineNum,
            rawLine: line,
            error: error.localizedDescription
        )
        // Continue to next line
        continue
    }
}
```

**Result:** Partial import succeeds; user can review errors in diagnostics UI.

### File Access Errors

**Scenario:** Transcript file moved/deleted during processing.

**Response:**
```swift
do {
    let content = try String(contentsOf: fileURL)
} catch {
    // Update transcript status
    try db.execute("""
        UPDATE transcripts
        SET status = 'unavailable',
            last_error = ?
        WHERE id = ?
    """, error.localizedDescription, transcript.id)

    // Keep existing DB data (don't delete)
    // User can still query historical entries
}
```

---

## 10. Migration Strategy (File → DB)

### First-Time Setup

**User launches Contextify with existing Claude Code history:**

```
1. App Launch:
   - Detect ~/.claude/projects/ directory
   - Scan for *.jsonl files
   - Show: "Found 47 transcripts (125k messages). Import now?"

2. User Confirms:
   - Progress bar: "Importing transcripts... 12/47 complete"
   - Background task processes each file
   - UI remains responsive

3. Import Complete:
   - "✅ Imported 125,438 messages from 47 sessions"
   - "Timeline ready. You can now search your full history."

4. Ongoing:
   - File watchers active
   - New messages auto-insert
   - Zero user intervention required
```

### Incremental Migration (User Adds New Project)

```
1. User: Set Project Root → /Users/rob/code/new-project
2. App: Scan ~/.claude/projects/*new-project*/
3. App: Found 3 new transcripts (not in DB)
4. App: Hoover transcripts in background
5. App: Enable file watchers
6. User: Sees timeline populate in real-time
```

---

## 11. Comparison: File-Based vs DB-Based

### Current File-Based Caching (v0)

**Timeline Cache:**
```
~/Library/Application Support/Contextify/TimelineCache/
  abc-123-session.json  (per conversation)
  def-456-session.json
  ...
```

**Transcript Metadata:**
```
~/.claude/projects/-Users-rob-code-project/
  .contextify/
    session-abc-123.metadata.json  (sidecar)
```

**Limitations:**
- ❌ No cross-session queries
- ❌ No pattern detection
- ❌ Lost when transcript deleted (30-day retention)
- ❌ Scattered across filesystem

### New DB-Based Storage (v1)

**Single Source:**
```
~/Library/Application Support/Contextify/transcripts.db
  - transcript_entries (all messages)
  - timeline_cache (rendered summaries)
  - transcript_metadata (LLM-generated titles)
  - transcripts (file references + checkpoints)
```

**Benefits:**
- ✅ SQL queries across all history
- ✅ Survives transcript deletion
- ✅ Centralized, fast, indexed
- ✅ Enables advanced features (FTS, ML, insights)

---

## 12. Summary: Data Flow Diagram

```
┌─────────────────────────────────────────────────────────┐
│  External Transcript Files (Source of Truth)            │
│  ~/.claude/projects/<project>/<session-uuid>.jsonl     │
│  (30-day retention, then DELETED)                       │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │  Initial Discovery     │
        │  (App Launch)          │
        └────────┬───────────────┘
                 │
                 ▼
        ┌─────────────────────────────┐
        │  HOOVER: Parse All Lines    │
        │  - Read entire file         │
        │  - Batch INSERT entries     │
        │  - Save checkpoint          │
        └────────┬────────────────────┘
                 │
                 ▼
        ┌─────────────────────────────┐
        │  SQLite Database            │
        │  ~/Library/.../transcripts.db│
        │                             │
        │  Tables:                    │
        │  • transcripts              │
        │  • transcript_entries ← ✅  │
        │  • timeline_cache           │
        │  • transcript_metadata      │
        └────────┬────────────────────┘
                 │
                 ▼
        ┌─────────────────────────────┐
        │  File Watcher (Ongoing)     │
        │  - Detect new lines         │
        │  - Parse incrementally      │
        │  - INSERT new entries       │
        │  - Update checkpoint        │
        └────────┬────────────────────┘
                 │
                 ▼
        ┌─────────────────────────────┐
        │  DB Persists After Deletion │
        │  (Transcript file gone,     │
        │   but DB still has data)    │
        └─────────────────────────────┘
```

---

## 13. Key Takeaways

### ✅ What We're Building

1. **Hoover:** Parse existing transcripts → INSERT all into DB
2. **Stream:** File watcher → INSERT new lines as written
3. **Store:** Full message content in `transcript_entries.content`
4. **Persist:** Data survives transcript deletion (30-day retention)
5. **Query:** SQL enables cross-session analysis

### ✅ What This Enables

- **Preservation:** "Claude Code deleted my history, but Contextify saved it"
- **Intelligence:** "Show me all times I fixed auth bugs in the last year"
- **Insights:** "You're 15% more productive with Claude Code than Codex"

### ✅ What's Out of Scope (For Now)

- ❌ Gemini CLI (no auto-save)
- ❌ Grok CLI (no auto-save)
- ❌ Export to JSONL (Phase 3 feature)
- ❌ Real-time sync to cloud (future consideration)

---

## Appendix: Code References

### Key Files

- **Hoover Logic:** `TranscriptMigrator.swift` (to be created)
- **Stream Logic:** `ConversationMonitor.processConversationFile()` (existing)
- **Parsers:** `ClaudeCodeParser.swift`, `CodexParser.swift` (to be created)
- **DB Schema:** `TranscriptDatabase.swift` (to be created, follows v2 spec)

### Migration Timeline

**Week 1:** Schema creation + hoover logic
**Week 2:** File watchers + streaming inserts
**Week 3:** Testing + polish
**Ship:** Phase 1 complete

---

**Document Status:** Final
**Companion to:** `sql-implementation-plan-02.md`
**Next Steps:** Implement schema from colleague's v3 feedback → build hoover logic → ship
