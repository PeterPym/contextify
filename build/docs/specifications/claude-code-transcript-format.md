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

## Queue Operations

### Overview

Claude Code queues user messages sent during tool execution to prevent interruption of active operations. Queue operations are recorded as metadata records with `type: "queue-operation"`.

**Purpose:** When Claude is executing tools (Read, Edit, Bash, etc.), user input cannot interrupt the current turn. Messages sent during execution are queued and processed after completion, maintaining conversation coherence while preserving user input.

**Design Philosophy:** Queue first, process after completion. Users can continue sending messages while Claude works, and those messages are addressed in subsequent turns.

**⚠️ Version-Specific Behavior:** Queue operation semantics changed significantly between Claude Code versions. See [Queue Operations Architecture](../architecture/queue-operations.md) for full implementation details including v2.0.37 vs v2.0.50 behavior differences.

### Version Behavior Differences

**v2.0.37 (Nov 2025) - DEQUEUE Pattern:**
- `enqueue` → queued message held in memory
- `dequeue` → message released into conversation
- Real `user` message record written to transcript
- Timeline shows permanent conversation record

**v2.0.50+ (Current) - REMOVE Pattern:**
- `enqueue` → queued message held in memory
- `remove` → message processed ephemerally
- **NO** `user` message record in transcript
- Assistant still responds, but message leaves no permanent trace
- Requires synthetic timeline entries for visibility

**Key Difference:** v2.0.50 treats queued messages as ephemeral (influence conversation but aren't persisted), while v2.0.37 promoted them to permanent user records.

### Record Format

```typescript
{
  type: "queue-operation",
  operation: "enqueue" | "remove" | "popAll" | "dequeue",
  timestamp: string,         // ISO 8601
  content?: string,          // User message text (absent in dequeue)
  sessionId: string          // Session UUID
}
```

**Key Characteristics:**
- **Metadata-only:** Queue operations are not conversational messages
- **Content field:** Present in `enqueue`, `remove`, `popAll`; **absent** in `dequeue`
- **Not displayed:** Should not appear as timeline entries (only affect display of related user messages)
- **Session-scoped:** Queue state is per-session (isolated by `sessionId`)

### Operation Types

#### 1. enqueue

**Trigger:** User sends a message while Claude is executing tools

**Record:**
```json
{
  "type": "queue-operation",
  "operation": "enqueue",
  "timestamp": "2025-11-12T19:51:40.564Z",
  "content": "may be okay to not include these big thigns in teh git ",
  "sessionId": "2393f674-7037-407a-a0ed-0f7e7b61625d"
}
```

**Semantics:**
- User message is captured and queued for later processing
- Content field contains the full user message text
- Message will be processed after current tool execution completes
- Multiple messages can be enqueued in rapid succession

**Parser Note:** Enqueue operations should mark the corresponding user message as "queued" in the UI.

#### 2. remove

**Trigger:** Claude processes a queued message after tool execution completes

**Record:**
```json
{
  "type": "queue-operation",
  "operation": "remove",
  "timestamp": "2025-11-12T19:51:53.870Z",
  "content": "may be okay to not include these big thigns in teh git ",
  "sessionId": "2393f674-7037-407a-a0ed-0f7e7b61625d"
}
```

**Semantics (v2.0.50+):**
- Message processed **ephemerally** - influences conversation but **not persisted**
- Content field matches the corresponding `enqueue` operation
- **NO** corresponding `user` message record written to transcript
- Assistant still responds to the message despite no permanent record
- One `remove` operation per queued message

**Semantics (v2.0.37):**
- Used same operation name but different behavior
- Message would appear as permanent `user` record after `remove`
- See "Version Behavior Differences" section above

**Parser Note:** Match `remove` to `enqueue` by content. In v2.0.50+, synthetic timeline entries are needed to show these ephemeral messages.

**Timing Pattern Example:**
```
Line 271: enqueue at 19:51:40.564Z
Line 272: enqueue at 19:51:45.694Z
[Claude continues tool execution]
Line 276: remove at 19:51:53.870Z (13 seconds after first enqueue)
Line 277: remove at 19:51:53.870Z (same timestamp, batch removal)
```

**Note:** Multiple `remove` operations often share identical timestamp, suggesting batch dequeue.

#### 3. popAll

**Trigger:** User sends a NEW message that supersedes/combines previous queued message(s)

**Record:**
```json
{
  "type": "queue-operation",
  "operation": "popAll",
  "timestamp": "2025-11-12T21:40:37.908Z",
  "content": "if you have not, you should include any discovered methodology for performing queries etc on imssages",
  "sessionId": "2393f674-7037-407a-a0ed-0f7e7b61625d"
}
```

**Semantics:**
- Original queued message is being replaced/combined with new user input
- Different from `remove`: message is NOT processed standalone
- Used when user refines/expands queued message before Claude responds
- Next `enqueue` will contain the combined/replacement message

**Example Lifecycle:**
```
Line 592: enqueue "if you have not, you should include..."
[User decides to add more context]
Line 593: popAll "if you have not, you should include..." (1m 48s later)
Line 597: enqueue "Do you have the url...?\n\n---\n\nif you have not..." (12s after popAll)
```

**Parser Note:** The `---` separator in combined messages suggests Claude Code appends original message to new message when user sends additional input.

**Key Difference:**
- `remove`: Message will be processed as-is
- `popAll`: Message is discarded/combined, won't be processed standalone

**UI Guidance:** Change badge from "QUEUED" to "REFINED" when `popAll` occurs, then show combined message as newly queued.

#### 4. dequeue

**Trigger:** Queue is cleared without processing messages (session end, cancellation, or reset)

**Record:**
```json
{
  "type": "queue-operation",
  "operation": "dequeue",
  "timestamp": "2025-11-12T21:40:55.094Z",
  "sessionId": "2393f674-7037-407a-a0ed-0f7e7b61625d"
}
```

**Semantics:**
- **NO content field** (unlike enqueue/remove/popAll)
- Clears entire queue without processing
- All queued messages are discarded
- Typically occurs at session boundaries or when user cancels

**Triggers for dequeue:**
- Session ends (user closes Claude Code)
- User cancels pending work
- User switches projects/sessions
- Error conditions requiring queue reset

**Parser Note:** Must track all queued messages separately to determine what was discarded. Dequeue does NOT indicate which messages were cleared.

**UI Guidance:** Remove all queue badges or mark queued messages as "CANCELLED" when `dequeue` occurs.

### Queue Lifecycle Patterns

#### Pattern 1: Single Message (Standard Flow)

**Sequence:**
```
Line N:   {"type":"user",...}                      // User sends message, tool execution starts
Line N+1: {"operation":"enqueue","content":"..."}  // User sends another message (queued)
Line N+2: {"type":"assistant",...}                 // Tool execution completes
Line N+3: {"operation":"remove","content":"..."}   // Message dequeued
Line N+4: {"type":"assistant",...}                 // Claude addresses queued message
```

**Real Example:**
```
Line 360: enqueue "if nothing is found go back to the external drive..."
Line 361: remove "if nothing is found go back to the external drive..." (1m 55s later)
[Next assistant turn addresses this message]
```

**Timing:** Queue duration varies from seconds to minutes depending on tool execution time.

#### Pattern 2: Multiple Messages (Batch Processing)

**Sequence:**
```
Line N:   {"type":"user",...}                      // Initial message
Line N+1: {"operation":"enqueue","content":"msg1"} // First queued message
Line N+2: {"operation":"enqueue","content":"msg2"} // Second queued message
Line N+3: {"type":"assistant",...}                 // Tool execution continues
Line N+4: {"operation":"remove","content":"msg1"}  // Both messages removed
Line N+5: {"operation":"remove","content":"msg2"}  // (often same timestamp)
Line N+6: {"type":"assistant",...}                 // Addresses both messages
```

**Real Example:**
```
Line 271: enqueue "may be okay to not include these big thigns in teh git"
Line 272: enqueue "mabye git ignore them"
[Tool execution continues for ~8 seconds]
Line 276: remove "may be okay to not include these big thigns in teh git"
Line 277: remove "mabye git ignore them" (same timestamp: 19:51:53.870Z)
```

**Observation:** Multiple `remove` operations often share identical timestamp, suggesting batch dequeue.

#### Pattern 3: Message Refinement (popAll)

**Sequence:**
```
Line N:   {"operation":"enqueue","content":"original message"}
Line N+1: {"operation":"popAll","content":"original message"}     // User refines
Line N+2: {"operation":"enqueue","content":"refined + original"}  // Combined message
Line N+3: [Possibly dequeue or remove depending on what happens next]
```

**Real Example:**
```
Line 592: enqueue "if you have not, you should include any discovered methodology..."
Line 593: popAll "if you have not, you should include any discovered methodology..." (1m 48s later)
Line 597: enqueue "Do you have hte url...?\n\n---\n\nif you have not..." (12s after popAll)
Line 598: dequeue (6s after refined enqueue)
```

**Interpretation:**
1. User sent message A while Claude was working (enqueued)
2. User decided to add more context (popAll discards A)
3. User sends combined message "B + A" (re-enqueued)
4. Queue was then cleared (dequeue), possibly due to cancellation

#### Pattern 4: Queue Clear (dequeue)

**Sequence:**
```
Line N:   {"operation":"enqueue","content":"..."}
Line N+1: {"operation":"dequeue"}                  // Queue cleared
[No remove operation - message was NOT processed]
```

**Real Example:**
```
Line 597: enqueue "Do you have hte url...?"
Line 598: dequeue (6 seconds later)
```

### Parsing Considerations

**1. Queue-operation records are metadata**
- Type: `"queue-operation"` (NOT `"user"` or `"assistant"`)
- Should NOT be displayed as timeline entries
- Should modify state of related user message entries

**2. Content Matching**
```swift
// Match enqueue → remove by content
if operation == "remove" && content == previousEnqueueContent {
    // Mark corresponding user message as processed
}
```

**3. Edge Cases**
- **Multiple enqueues:** User sends 3 messages → 3 enqueue operations → 3 remove operations
- **Out-of-order removal:** FIFO order not guaranteed (batch remove may have same timestamp)
- **Orphaned enqueues:** Enqueue without corresponding remove (session crashed)
- **Empty dequeue:** Dequeue with empty queue (redundant operation)

**4. Dequeue Handling**
```swift
// Dequeue has NO content - must clear all tracked queued messages
if operation == "dequeue" {
    clearAllQueuedMessages(sessionId: sessionId)
}
```

**5. Session Boundaries**
- Queue state is per-session (isolated by `sessionId`)
- Switching sessions should clear queue display
- Historical session playback should replay queue operations

### Implementation Guidance

**Database Storage:**

**Option 1: Transient Computation (RECOMMENDED)**
- Parse transcript and compute queue state dynamically
- Track which messages are currently queued based on `enqueue`/`remove`/`popAll`/`dequeue` records
- Display queue status in UI without persisting to database

**Pros:**
- No schema changes required
- Always accurate (reflects transcript state)
- Simpler implementation

**Option 2: Database Column**
- Add `is_queued BOOLEAN` column to transcript_entries
- Update column when parsing queue-operation records

**Pros:**
- Faster queries (no parsing required)
- Simpler UI logic

**Recommendation:** Use **Option 1 (Transient)** because:
1. Queue state is inherently transient (only meaningful during active session)
2. Historical transcripts don't need queue status (already processed)
3. Simpler implementation without schema changes

**UI Display Guidelines:**

1. **Show "QUEUED" badge on timeline entries**
   - Display when `enqueue` operation is recorded
   - Remove badge when corresponding `remove` operation occurs
   - Grey out when `popAll` occurs (will be refined/replaced)
   - Remove entirely when `dequeue` occurs (cancelled)

2. **Visual States:**
   ```
   [Enqueued]     → Yellow badge "QUEUED" on timeline entry
   [Removed]      → Badge removed, entry shows as normal user message
   [PopAll]       → Badge changes to "REFINED" or entry is greyed out
   [Dequeued]     → Entry removed from timeline or marked "CANCELLED"
   ```

3. **InfoButton Tooltip:**
   ```
   When hovering over "QUEUED" badge:
   "This message was sent while Claude was executing tools.
    It will be addressed after the current operation completes."
   ```

4. **Persistence:**
   - Queue status is **transient** - only relevant for active sessions
   - Historical transcripts should NOT show queue badges (all messages already processed)
   - Exception: Show badge if viewing transcript replay mode

**Swift Implementation Example:**
```swift
class QueueStateTracker {
    private var queuedMessages: [String: String] = [:]  // content -> timestamp

    func process(operation: QueueOperation) {
        switch operation.operation {
        case "enqueue":
            queuedMessages[operation.content] = operation.timestamp
        case "remove":
            queuedMessages.removeValue(forKey: operation.content)
        case "popAll":
            queuedMessages.removeValue(forKey: operation.content)
        case "dequeue":
            queuedMessages.removeAll()
        }
    }

    func isQueued(content: String) -> Bool {
        return queuedMessages[content] != nil
    }
}
```

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
- `build/docs/archive/completed-work/technical-briefing-local-history-claude-code-codex.md` - Claude Code vs Codex comparison
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` - Current parser implementation
- `build/docs/architecture/sql-backend.md` - Database architecture

**Analysis Data:**
- 43 transcript files analyzed
- 18,589 total records
- 6 distinct record types
- 5 content block types
- Generated: 2025-10-23

---

## Transcript Classification Guide

**Purpose:** Multi-dimensional classification system for understanding transcript structure and content.

### Multi-Dimensional Classification Model

Transcripts should be classified across **four orthogonal axes**:

#### Axis 1: Primary Classification

**1. Conversational** (40 in sample DB - most common)
- **Has:** Non-sidechain user and/or assistant messages
- **Database:** `entryCount > 0`
- **Parser behavior:** Creates `transcript_entries` with `display_in_timeline = 1`
- **Relevant sections:** §1 (User), §2 (Assistant), optionally §3-5

**2. Sidechain-Only** (warmup/initialization sessions)
- **Has:** ONLY messages with `isSidechain: true`
- **Purpose:** Project context loading, warmup before actual conversation
- **Database:** `entryCount = 0` (skipped by parser)
- **File content:** 2-10 lines typically
- **Relevant sections:** §1 (User Messages - Special Cases)

**3. Metadata-Only** (file tracking without conversation)
- **Has:** ONLY file-history-snapshot, summary, or system records
- **No conversation:** No user/assistant OR only sidechain/meta
- **Database:** `entryCount = 0`, v7 metadata tables populated
- **File content:** Can be 10-400+ lines
- **Relevant sections:** §3 (File-History), §4 (Summary), §5 (System)

**4. Empty/Unprocessed**
- **Has:** No records OR incomplete ingestion
- **Database:** `entryCount = 0`, no v7 metadata
- **Status:** Not yet ingested or session never started

#### Axis 2: Metadata Richness

**Snapshot-Rich:**
- Has `file-history-snapshot` records with `trackedFileBackups`
- Database: Entries in `file_snapshots` + `tracked_files` tables
- Value: Track file modifications, versions, backup times
- Average: ~25 files per snapshot across 813/907 non-empty snapshots

**Summary-Enhanced:**
- Has `type: "summary"` records
- Database: Entries in `transcript_summaries` table
- Purpose: Claude Code's internal session summaries
- 48 records across sample (0.3% of all records)

**Event-Tracked:**
- Has `type: "system"` records
- Database: Entries in `system_events` table
- Types: slash_command, api_error, compact_mode_boundary
- 55 records across sample (0.3% of all records)

**Usage-Rich:**
- Has assistant messages with detailed `usage` metadata
- Database: Entries in `assistant_usage` table
- Metrics: input/output tokens, cache creation/read, cost data
- Present in every assistant message (11,188 records)

#### Axis 3: Content Characteristics

**Tool-Heavy:**
- High ratio of `tool_use` / `tool_result` content blocks
- Dominant tools: Bash, Edit, Read, Write, Grep
- Indicates automation-focused session

**Thinking-Heavy:**
- Messages with `thinking` content blocks
- Parser: `hasTextContent = false` if ONLY thinking
- Display: `display_in_timeline = 0` (hidden from timeline)

**Image-Containing:**
- Messages with `type: "image"` content blocks
- Structure: `{ type: "image", source: { type: "base64", media_type, data } }`
- Use case: Screenshot analysis, visual debugging

**Text-Only:**
- String content or only `type: "text"` blocks
- Simplest structure, no special handling

#### Axis 4: Database State

**Active:** `status = 'active'`
- Fully ingested, file accessible
- `last_processed_line` matches file line count

**Unavailable:** `status = 'unavailable'`
- File moved/deleted since discovery
- Metadata retained, file inaccessible

**Error:** `status = 'error'`
- Parser errors, corrupted JSON
- Ingestion stopped at `last_processed_line`

**Unprocessed:** Not in database
- Discovered but not yet ingested
- Or failed discovery phase

### Real-World Distribution (Sample Database: 67 transcripts)

| Primary | Count | Metadata | Content | State |
|---------|-------|----------|---------|-------|
| conversational-only | 39 | No v7 metadata yet | Mixed | active |
| conversational+metadata | 1 | Has snapshots | Tool+text | active |
| metadata-only | 1 | 8 snapshots | N/A | active |
| sidechain-only | ~5 | No metadata | Warmup | active |
| summary-only | ~5 | Summaries | N/A | active |
| empty/unprocessed | 26 | None | None | varies |

**Important Notes:**
- "Empty" transcripts often contain sidechain or summary records (misnamed)
- 813 of 907 snapshots contain tracked files (not empty backups)
- Many "conversational" transcripts also have rich metadata
- Sidechain sessions are 2-10 lines of initialization messages

### Classification Scripts

**Simple Classification:** `scripts/classify_transcript.sh`
- Fast single-dimension classification
- Returns: conversational | metadata-only | empty

```bash
./scripts/classify_transcript.sh A31F3D0A-4820-41AB-8121-0C81AC8533C4
```

**Multi-Dimensional Classification:** `scripts/classify_transcript_detailed.sh`
- Comprehensive analysis across all four axes
- Returns: primary classification + dimensions breakdown

```bash
./scripts/classify_transcript_detailed.sh A31F3D0A-4820-41AB-8121-0C81AC8533C4
```

**Example Output (detailed):**
```json
{
  "primary_classification": "sidechain-only",
  "dimensions": {
    "conversation": {"has_user": false, "has_assistant": false, "db_entry_count": 0},
    "metadata": {"has_snapshots": false, "has_summaries": false, "has_events": false},
    "content_flags": {"has_sidechain": true, "has_meta": false, "has_tool_use": false},
    "state": "active"
  }
}
```

### Field Reference by Classification

| Classification | Required Fields | Record Types | Database Tables |
|---------------|-----------------|--------------|-----------------|
| **Conversational** | uuid, timestamp, type, message | user, assistant, (+ metadata) | transcript_entries, (+ v7 tables) |
| **Metadata-Only** | messageId/uuid, type, snapshot/summary | file-history-snapshot, summary, system | file_snapshots, tracked_files, system_events |
| **Empty** | (none) | (none) | transcripts only |

### Agent Workflow

When analyzing a transcript:

1. **Classify first:** `./scripts/classify_transcript.sh <id>`
2. **Read relevant sections:**
   - `conversational` → Read §1-2, optionally §3-5
   - `metadata-only` → Read §3-5 only
   - `empty` → No further analysis needed
3. **Reference parser:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` for implementation details

---

## Claude Code Web Transcript Corruption

**Status:** Observed and documented (2025-11-08)
**Affects:** Claude Code Web "teleport" feature (session transfer from web to CLI)
**Impact:** Some teleported transcripts contain structural corruption that can cause API 400 errors

### Background

Claude Code Web (launched 2025) includes a "Send to CLI" teleport feature that allows users to transfer frozen/hung web sessions to the local CLI. When a web session freezes, users can click "Send to CLI" which copies a command like `claude --teleport session_011C...` to the clipboard. Running this command downloads the web transcript to the local `~/.claude/projects/` directory and opens the session in CLI.

However, the teleport process frequently creates **corrupted transcript files** where the web session's frozen/hung state results in malformed JSONL records.

### Corruption Patterns Observed

Analysis of 355 local transcripts revealed 8 corrupted files (2.3%), with teleported sessions having significantly higher corruption rates.

#### Pattern 1: Orphaned tool_result Blocks

**Description:** User messages contain `tool_result` blocks that reference non-existent `tool_use_id` values from preceding assistant messages.

**Example:**
```json
// Line 1746: Assistant message with stop_reason="tool_use" but NO tool_use blocks
{
  "type": "assistant",
  "message": {
    "role": "assistant",
    "content": [
      {"type": "thinking", "thinking": "I need to check the file..."}
    ],
    "stop_reason": "tool_use"  // Claims tool_use but content has none!
  }
}

// Line 1747: User message with orphaned tool_result
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_018qN95KtDr14JxyYbwYssxo",  // References missing tool_use
        "content": "..."
      }
    ]
  }
}
```

**Impact:** Causes API 400 error when the corrupted message is within the conversation window sent to the Anthropic Messages API.

**API Error Message:**
```
API Error: 400 {"type":"error","error":{"type":"invalid_request_error",
"message":"messages.72.content.0: unexpected `tool_use_id` found in
`tool_result` blocks: toolu_018qN95KtDr14JxyYbwYssxo. Each `tool_result`
block must have a corresponding `tool_use` block in the previous message."}}
```

#### Pattern 2: stop_reason Mismatch

**Description:** Assistant messages have `stop_reason: "tool_use"` but contain no `tool_use` content blocks (only `text` or `thinking` blocks).

**Example:**
```json
{
  "type": "assistant",
  "message": {
    "role": "assistant",
    "content": [
      {"type": "text", "text": "Let me analyze that..."}
    ],
    "stop_reason": "tool_use"  // Mismatch: no tool_use in content!
  }
}
```

**Impact:** Does NOT cause API errors. Claude Code CLI handles this gracefully. Only affects metadata accuracy.

### Corruption Statistics

**Sample Analysis (Nov 7-8, 2025):**

| Transcript | Date | Type | Issues | orphaned_tool_result | stop_reason_mismatch |
|------------|------|------|--------|---------------------|---------------------|
| 42d110d2 | Nov 7 | Teleport | 41 | 17 | 24 |
| e0703ed4 | Nov 7 | Teleport | 36 | Unknown | Unknown |
| 04b40bae | Nov 7 | Teleport | 12 | Unknown | Unknown |
| 93673e11 | Nov 7 | Teleport | 1 | 0 | 1 |
| d71598f2 | Nov 8 | Teleport | 7 | 2 | 5 |
| 47eff2ef | Nov 8 | Teleport | 4 | 0 | 4 |

**Key Observations:**
- Teleported sessions: 4-41 corruption issues per transcript
- Normal CLI sessions: 0-1 issues (97.7% clean)
- `stop_reason_mismatch` is more common than `orphaned_tool_result`
- Severity varies widely (1-41 issues)

### The Sliding Window Hypothesis

**Observation:** Not all corrupted transcripts fail to continue in CLI. Whether continuation succeeds depends on the **position of corruption relative to where the user tries to continue**.

#### Example 1: Corruption BEFORE Active Window (Success)

**Transcript d71598f2:**
- Total lines: 546
- Corruption at lines: 209 (orphaned), 277 (orphaned), 403-530 (stop_reason)
- Session resumed at: line 541 (teleport point)
- User sent "testing" at: ~line 542
- Result: ✅ **Continued successfully**

**Hypothesis:** The Anthropic Messages API receives a **sliding window** of recent messages (estimated ~50-100 messages). The orphaned_tool_result at line 277 was 265 lines before the continuation point, placing it outside the API window.

#### Example 2: Corruption WITHIN Active Window (Failure)

**Transcript 42d110d2:**
- Total lines: 1990
- Last orphaned_tool_result at: line 1464
- Session resumed at: line 1889 (teleport point)
- User sent message at: ~line 1890
- Result: ❌ **API 400 error on first new message**

**Hypothesis:** The orphaned_tool_result at line 1464 was only 425 lines before continuation, likely still within the API's conversation window (estimated ~500-1000 messages for longer sessions).

#### API Window Estimation

Based on observations:
- **Estimated window size:** 50-1000 messages (context-dependent)
- **Likely mechanism:** Claude Code CLI sends recent conversation history to API
- **Critical factor:** Distance between last `orphaned_tool_result` and continuation point

**Rule of thumb:** If last corruption is <100 messages from where you continue, expect API errors. If >300 messages away, likely safe.

### Detection and Repair

**Detection Tools:**

1. **During ingestion:** Contextify's HooverEngine validates messages (as of 2025-11-08)
2. **Manual analysis:** `scripts/transcript-repair/repair_transcript.py --dry-run <path>`

**Repair Workflow:**

```bash
# Analyze transcript for corruption
python3 scripts/transcript-repair/repair_transcript.py <transcript-path> --dry-run

# Repair (creates automatic backup)
python3 scripts/transcript-repair/repair_transcript.py <transcript-path>

# Result: Removes orphaned_tool_result records, fixes stop_reason mismatches
```

**Repair Actions:**
- **orphaned_tool_result:** Remove entire message record, update parent chains
- **stop_reason_mismatch:** Change `stop_reason` from `"tool_use"` to `"end_turn"`

**See:** `build/docs/operations/transcript-corruption-detection.md` for comprehensive guide.

### Impact on Contextify

**Contextify Database Ingestion:**
- HooverEngine **skips** corrupted records during ingestion
- Transcript status: `corruption_detected = 1` (future v24 schema)
- Timeline displays clean entries only
- User sees: "⚠️ 33 corruption issues detected"

**User Experience:**
- ✅ **Timeline works:** Contextify displays all clean messages
- ❌ **CLI broken:** Cannot continue conversation in Claude Code without repair
- 💡 **Solution:** Repair file → enables CLI continuation

### Future Considerations

**If Claude Code Web fixes corruption:**
- This documentation serves as historical record
- Repair tools remain useful for legacy transcripts
- Detection logic can be deprecated once corruption rate drops to 0%

**Potential Anthropic API Enhancement:**
- Looser validation: Warn instead of reject for orphaned_tool_result
- Client-side filtering: Claude Code could strip corrupted messages before sending
- Recovery mode: API could attempt to continue despite structural issues

**Database Schema (Proposed v24):**
```sql
-- Track corruption in transcripts table
ALTER TABLE transcripts ADD COLUMN corruption_detected INTEGER DEFAULT 0;
ALTER TABLE transcripts ADD COLUMN corruption_count INTEGER DEFAULT 0;
ALTER TABLE transcripts ADD COLUMN corruption_types TEXT; -- JSON array

-- Detailed corruption tracking
CREATE TABLE transcript_corruption (
  id TEXT PRIMARY KEY,
  transcript_id TEXT NOT NULL,
  line_number INTEGER NOT NULL,
  entry_uuid TEXT,
  corruption_type TEXT NOT NULL,  -- orphaned_tool_result, stop_reason_mismatch
  details TEXT NOT NULL,
  detected_at INTEGER NOT NULL,
  FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
);
```

### References

- **Repair utility:** `scripts/transcript-repair/repair_transcript.py`
- **Operations guide:** `build/docs/operations/transcript-corruption-detection.md`
- **Detection implementation:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` (validateMessageIntegrity)
- **Sample corrupted transcripts:** Nov 7-8, 2025 teleport sessions
