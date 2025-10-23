# Claude Code Transcript Format - Complete Technical Reference

**Status:** Comprehensive Analysis (2025-10-23)
**Source:** Local analysis of 43 transcripts (18,589 total records) + community tool research
**Related:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

---

## Overview

Claude Code stores conversation history in **JSONL** (JSON Lines) format, with one record per line. Each transcript file represents a single session and contains mixed record types: conversation messages, file snapshots, system events, and metadata.

**Storage Location:**
- `~/.claude/projects/<project-key>/<session-uuid>.jsonl`
- `<project-key>` = project path with `/` → `-` (e.g., `-Users-rob-code-projects-contextify`)
- `<session-uuid>` = unique session identifier (e.g., `ce6e090b-603e-484a-977e-546214573964.jsonl`)

**Key Characteristics:**
- **Append-only:** New records appended as session progresses
- **Mixed types:** Conversation, metadata, snapshots, system events
- **Self-contained:** Each record is independent and parseable
- **Streaming-friendly:** Can be processed line-by-line without loading entire file

---

## Record Type Summary

From analysis of 18,589 records across 43 transcripts:

| Type | Count | Percentage | Purpose |
|------|-------|------------|---------|
| `assistant` | 11,188 | 60.1% | Claude responses with usage metadata |
| `user` | 6,391 | 34.3% | User inputs, commands, tool results |
| `file-history-snapshot` | 907 | 4.9% | File backup/version tracking |
| `system` | 55 | 0.3% | System events, commands, errors |
| `summary` | 48 | 0.3% | Session summaries for navigation |

---

## Record Type Specifications

### 1. User Messages (`type: "user"`)

**Purpose:** User inputs, tool execution results, and command wrappers.

**Fields (all records):**
```typescript
{
  type: "user",
  uuid: string,              // Unique message ID
  timestamp: string,         // ISO 8601 (e.g., "2025-10-19T04:10:40.044Z")
  parentUuid: string | null, // Parent message for threading
  sessionId: string,         // Session UUID
  version: string,           // Claude Code version (e.g., "2.0.22")
  userType: "external",      // Always "external" in observed data
  cwd: string,               // Current working directory
  gitBranch: string,         // Active git branch
  isSidechain: boolean,      // True = warmup/non-conversational
  isMeta: boolean?,          // True = meta/command wrapper (optional)
  message: {
    role: "user",
    content: string | ContentBlock[]
  },
  toolUseResult: ToolUseResult?, // Tool execution result (optional)
  thinkingMetadata: ThinkingMetadata?, // Thinking trigger info (optional)
  isVisibleInTranscriptOnly: boolean?, // UI hint (optional)
  isCompactSummary: boolean? // Compact mode flag (optional)
}
```

**Content Block Types:**
```typescript
type ContentBlock =
  | { type: "text", text: string }
  | { type: "image", source: ImageSource }
  | { type: "tool_use", id: string, name: string, input: object }
  | { type: "tool_result", tool_use_id: string, content: string, is_error?: boolean }
  | { type: "thinking", thinking: string, signature?: string }
```

**ToolUseResult Structure:**
```typescript
{
  stdout: string,           // Command stdout
  stderr: string,           // Command stderr
  isImage: boolean,         // True if result contains image
  interrupted: boolean,     // True if execution was interrupted
  filePath: string?,        // File path for edit operations
  structuredPatch: object?, // Structured diff for edits
  userModified: boolean?,   // True if user modified result
  replaceAll: boolean?,     // True for replace-all edits
  originalFile: string?,    // Original file content
  oldString: string?        // String being replaced
}
```

**ThinkingMetadata:**
```typescript
{
  triggers: string[],  // What triggered thinking (e.g., ["complexity"])
  level: string,       // Thinking depth level
  disabled: boolean    // Whether thinking was disabled
}
```

**Special Cases:**
- **`isSidechain: true`:** Warmup/initialization messages (e.g., "Warmup" for project context loading). Should be skipped for timeline display but may contain valuable project context.
- **`isMeta: true`:** Meta/command wrappers (e.g., "DO NOT respond to these messages..."). System-generated, not user-initiated.

**Frequency:** 6,391 records (34.3%)

---

### 2. Assistant Messages (`type: "assistant"`)

**Purpose:** Claude's responses with full message content and usage/billing metadata.

**Fields:**
```typescript
{
  type: "assistant",
  uuid: string,
  timestamp: string,
  parentUuid: string | null,
  sessionId: string,
  version: string,
  userType: "external",
  cwd: string,
  gitBranch: string,
  isSidechain: boolean,
  requestId: string?,  // API request ID for tracking
  isApiErrorMessage: boolean?,  // True if this is an error message
  message: {
    id: string,          // Message ID from API
    type: "message",
    role: "assistant",
    model: string,       // e.g., "claude-sonnet-4-5-20250929"
    content: ContentBlock[],
    stop_reason: string | null,  // Why generation stopped
    stop_sequence: string | null,
    usage: UsageInfo
  }
}
```

**UsageInfo Structure:**
```typescript
{
  input_tokens: number,
  cache_creation_input_tokens: number,  // Tokens used to create cache
  cache_read_input_tokens: number,      // Tokens read from cache
  output_tokens: number,
  service_tier: string,  // e.g., "standard"
  cache_creation: {
    ephemeral_5m_input_tokens: number,  // 5-minute cache
    ephemeral_1h_input_tokens: number   // 1-hour cache
  },
  server_tool_use?: {  // Server-side tool execution metadata
    // ... (11 records contain this, structure varies)
  }
}
```

**Content Blocks:**
- Same types as user messages: `text`, `tool_use`, `tool_result`, `thinking`
- Most common: `text` (3,010), followed by `thinking` (2,620)

**Frequency:** 11,188 records (60.1%)

---

### 3. File-History-Snapshot (`type: "file-history-snapshot"`)

**Purpose:** Track file modifications and backups during the session. Captures which files Claude is watching/editing and their backup metadata.

**Fields:**
```typescript
{
  type: "file-history-snapshot",
  messageId: string,        // Associated message UUID
  isSnapshotUpdate: boolean,  // True if updating existing snapshot
  snapshot: {
    messageId: string,      // Same as top-level messageId
    timestamp: string,      // Snapshot creation time
    trackedFileBackups: {
      [filePath: string]: {
        backupFileName: string | null,  // Backup file name (e.g., "27928849ab545735@v1")
        version: number,                // File version number
        backupTime: string              // ISO 8601 timestamp
      }
    }
  }
}
```

**Example:**
```json
{
  "type": "file-history-snapshot",
  "messageId": "269239a1-8f0d-4d21-8466-02452cb25aa4",
  "snapshot": {
    "messageId": "269239a1-8f0d-4d21-8466-02452cb25aa4",
    "trackedFileBackups": {
      "Contextify/Contextify/ContentView.swift": {
        "backupFileName": "27928849ab545735@v1",
        "version": 1,
        "backupTime": "2025-10-19T04:11:25.377Z"
      },
      "/Users/rob/code/projects/contextify/CLAUDE.md": {
        "backupFileName": null,
        "version": 1,
        "backupTime": "2025-10-19T04:10:40.044Z"
      }
    },
    "timestamp": "2025-10-19T04:10:40.044Z"
  },
  "isSnapshotUpdate": false
}
```

**Analysis:**
- 813 of 907 snapshots (89.6%) contain tracked files
- Average: ~25 files per snapshot
- File paths: Absolute or project-relative
- `backupFileName: null` = file tracked but not backed up (read-only access)

**Value:**
- **Session scope analysis:** Which files were touched during conversation
- **File version tracking:** Track file evolution across session
- **Backup recovery:** Locate backed-up versions of files
- **Correlation:** Link file changes to conversation context

**Frequency:** 907 records (4.9%)

---

### 4. Summary Messages (`type: "summary"`)

**Purpose:** Claude Code's internal conversation summaries for navigation and cross-session linking.

**Fields:**
```typescript
{
  type: "summary",
  summary: string,   // Human-readable session summary
  leafUuid: string,  // Conversation tree leaf identifier
  cwd: string?       // Working directory (optional)
}
```

**Examples:**
- `"Claude Code Contextify Project Navigation Warmup"`
- `"Batch Update JSON File Timestamps to Match Content"`
- `"Contextify macOS HUD Project Setup Review"`

**Analysis:**
- Appears to be generated asynchronously (may arrive after session)
- Used for session picker UI and search
- Links to conversation tree structure (`leafUuid`)

**Frequency:** 48 records (0.3%)

---

### 5. System Messages (`type: "system"`)

**Purpose:** System events, commands, errors, and compact mode boundaries.

**Fields:**
```typescript
{
  type: "system",
  uuid: string,
  timestamp: string,
  parentUuid: string | null,
  sessionId: string,
  version: string,
  userType: "external",
  cwd: string,
  gitBranch: string,
  isSidechain: boolean,
  isMeta: boolean?,
  subtype: "local_command" | "compact_boundary" | "api_error",
  level: "info" | "error",
  content: string?,         // Message content (for local_command, error details)
  logicalParentUuid: string?,  // For compact mode threading
  compactMetadata: object?,    // Compact mode metadata
  error: string?,           // Error message (for api_error)
  retryAttempt: number?,    // Retry attempt number
  maxRetries: number?,      // Max retry attempts
  retryInMs: number?        // Retry delay in milliseconds
}
```

**Subtypes:**

1. **`local_command`** (26 records):
   - Represents slash commands (e.g., `/config`, `/help`)
   - Content format: `<command-name>...</command-name><command-message>...</command-message>`

2. **`compact_boundary`** (21 records):
   - Marks boundaries in compact mode (collapsed conversation sections)
   - Contains `logicalParentUuid` and `compactMetadata`

3. **`api_error`** (8 records):
   - API errors with retry information
   - Contains `error`, `retryAttempt`, `maxRetries`, `retryInMs`

**Frequency:** 55 records (0.3%)

---

## Content Block Type Reference

Used within `message.content` arrays for both user and assistant messages.

### Text Block
```typescript
{
  type: "text",
  text: string  // Markdown-formatted text
}
```
**Frequency:** 3,010 blocks

### Tool Use Block
```typescript
{
  type: "tool_use",
  id: string,        // Tool invocation ID
  name: string,      // Tool name (e.g., "Read", "Bash", "Edit")
  input: object      // Tool-specific parameters
}
```
**Frequency:** 5,685 blocks

### Tool Result Block
```typescript
{
  type: "tool_result",
  tool_use_id: string,  // References tool_use.id
  content: string,      // Tool output
  is_error: boolean?    // True if tool execution failed
}
```
**Frequency:** 5,684 blocks

### Thinking Block
```typescript
{
  type: "thinking",
  thinking: string,     // Internal reasoning text
  signature: string?    // Thinking signature/hash
}
```
**Frequency:** 2,620 blocks
**Note:** Thinking blocks contain Claude's internal reasoning process. May be hidden from user in UI.

### Image Block
```typescript
{
  type: "image",
  source: {
    type: "base64",
    media_type: string,  // e.g., "image/png"
    data: string         // Base64-encoded image data
  }
}
```
**Frequency:** 22 blocks

---

## Parsing Recommendations

### Current Implementation (Contextify)

**What we parse (store in DB):**
- `user` and `assistant` messages with `uuid`, `isMeta: false`, `isSidechain: false`
- Extract: `content`, `timestamp`, `parentUuid`, `sessionId`, `provider`, `kind`, `gitBranch`, `gitCommit`, `cwd`

**What we skip:**
- `isSidechain: true` - Warmup/initialization messages
- `isMeta: true` - Meta/command wrappers
- `summary` - Internal navigation metadata
- `file-history-snapshot` - File tracking metadata
- `system` - System events
- Empty content - Tool-use-only messages

### Proposed Enhancements

**1. File-History-Snapshot Storage:**
```sql
CREATE TABLE file_snapshots (
  id TEXT PRIMARY KEY,
  transcript_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  snapshot_timestamp INTEGER NOT NULL,
  is_snapshot_update INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
);

CREATE TABLE tracked_files (
  id TEXT PRIMARY KEY,
  snapshot_id TEXT NOT NULL,
  file_path TEXT NOT NULL,
  backup_filename TEXT,
  version INTEGER NOT NULL,
  backup_time INTEGER NOT NULL,
  FOREIGN KEY (snapshot_id) REFERENCES file_snapshots(id) ON DELETE CASCADE
);

CREATE INDEX idx_tracked_files_path ON tracked_files(file_path);
CREATE INDEX idx_tracked_files_snapshot ON tracked_files(snapshot_id);
```

**Value:**
- Query files touched in a session
- Track file evolution timeline
- Correlate file changes with conversation
- Session scope visualization ("Files Modified: 12")

**2. Summary Storage:**
```sql
CREATE TABLE transcript_summaries (
  id TEXT PRIMARY KEY,
  transcript_id TEXT NOT NULL,
  summary TEXT NOT NULL,
  leaf_uuid TEXT,
  cwd TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
);
```

**Value:**
- Use as fallback for transcript titles
- Cross-session navigation via leaf_uuid
- Improve search relevance

**3. System Event Storage:**
```sql
CREATE TABLE system_events (
  id TEXT PRIMARY KEY,
  transcript_id TEXT NOT NULL,
  uuid TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  subtype TEXT NOT NULL,
  level TEXT NOT NULL,
  content TEXT,
  error TEXT,
  retry_attempt INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
);

CREATE INDEX idx_system_events_subtype ON system_events(subtype);
CREATE INDEX idx_system_events_transcript ON system_events(transcript_id);
```

**Value:**
- Track slash command usage
- Error rate monitoring
- Session debugging (api_error events)
- Compact mode analysis

**4. Usage Metadata Storage:**
```sql
-- Add to transcript_entries table:
ALTER TABLE transcript_entries ADD COLUMN usage_metadata TEXT; -- JSON

-- Or separate table:
CREATE TABLE assistant_usage (
  entry_id TEXT PRIMARY KEY,
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  cache_creation_tokens INTEGER NOT NULL,
  cache_read_tokens INTEGER NOT NULL,
  service_tier TEXT,
  request_id TEXT,
  FOREIGN KEY (entry_id) REFERENCES transcript_entries(id) ON DELETE CASCADE
);
```

**Value:**
- Token usage analytics
- Cache effectiveness analysis
- Cost tracking per session
- Performance optimization

---

## Data Architecture Principles

Following Contextify's v6 schema principles:

**transcript_entries (CANONICAL):**
- Store only core conversation data from transcript files
- Fields: `id`, `content`, `timestamp`, `kind`, `provider`, `sessionId`, `parentId`, `gitBranch`, `gitCommit`, `cwd`
- NO derived/computed data

**New metadata tables (DERIVED):**
- `file_snapshots` + `tracked_files`: File tracking metadata
- `transcript_summaries`: Claude Code summaries
- `system_events`: System events and commands
- `assistant_usage`: Token/billing metadata

**Rationale:**
- Separation of concerns (canonical vs. metadata)
- Metadata can be regenerated without touching source
- Query optimization (don't inflate transcript_entries)
- Future-proof for new metadata types

---

## UI/Feature Opportunities

### 1. Session Details View
**Data sources:** `file_snapshots`, `tracked_files`, `assistant_usage`

**Display:**
```
Session: Fixing Timeline Filter Issues
Duration: 2h 15m
Files Modified: 12
  - ConversationMonitor.swift (v3)
  - TranscriptInventoryView.swift (v2)
  - DatabaseSchema.swift (v1)
  ...

Token Usage:
  Input: 125,432 tokens
  Output: 8,231 tokens
  Cache Hit Rate: 87%

Cost Estimate: $0.42
```

### 2. File Timeline
**Data source:** `tracked_files`

**Feature:** Show file modification history across all sessions
```
ContentView.swift Timeline:
  Oct 23, 1:15 AM - "Add timeline filter" (v5)
  Oct 22, 11:30 PM - "Fix session switching" (v4)
  Oct 22, 9:45 PM - "Initial inventory view" (v3)
  ...
```

### 3. Command Usage Analytics
**Data source:** `system_events` (subtype: local_command)

**Display:**
```
Most Used Commands:
  /build: 156 times
  /run: 89 times
  /config: 12 times
```

### 4. Error/Retry Monitoring
**Data source:** `system_events` (subtype: api_error)

**Alert:** "Session had 3 API errors with retries. Performance may have been impacted."

### 5. Token/Cost Dashboard
**Data source:** `assistant_usage`

**Features:**
- Daily/weekly/monthly token usage graphs
- Cost per project/session
- Cache effectiveness trends
- Model usage distribution

---

## Migration Strategy

### Phase 1: Schema Extension (backward compatible)
1. Add new tables: `file_snapshots`, `tracked_files`, `transcript_summaries`, `system_events`, `assistant_usage`
2. No changes to existing `transcript_entries` schema
3. Parser update: Extract and store metadata alongside current entries

### Phase 2: Backfill (optional)
1. Reingest existing transcripts to populate metadata tables
2. Use `scripts/db_manager.sh reingest_transcript <transcript-id>`
3. Progress tracking: `X of Y transcripts reingested`

### Phase 3: UI Implementation
1. Session details view (files + usage)
2. File timeline view
3. Command analytics
4. Cost dashboard

### Phase 4: Optimization
1. Add indexes based on query patterns
2. Materialized views for expensive aggregations
3. Periodic cleanup of old snapshots (retention policy)

---

## References

**Community Tools:**
- [claude-code-log](https://github.com/daaain/claude-code-log) - Python parser with Pydantic models
- [claude-code-viewer](https://github.com/philipp-spiess/claude-code-viewer) - Web viewer for transcripts
- [ClaudeCodeJSONLParser](https://github.com/amac0/ClaudeCodeJSONLParser) - HTML log viewer

**Related Docs:**
- `build/notes/archive/technical-briefing-local-history-claude-code-codex.md` - Claude Code vs Codex comparison
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` - Current parser implementation
- `build/notes/technical-reference/sql-backend-architecture.md` - Database architecture

**Analysis Data:**
- 43 transcript files analyzed
- 18,589 total records
- 6 distinct record types
- 5 content block types
- Generated: 2025-10-23
