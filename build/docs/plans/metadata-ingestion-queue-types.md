# Metadata Ingestion Implementation Plan (v3 - Final)

**Date:** 2025-11-14
**Status:** Action required - New metadata types not being stored
**Priority:** Medium (data loss for future features)
**Review status:** Incorporates three-pass review feedback + systems review

---

## Executive Summary

**Current state:** Parser skips 5 metadata record types, but metadata parser only collects 3 of them:
- ✅ **Stored:** file-history-snapshot, summary, system events
- ❌ **Skipped & Discarded:** queue-operation, timeline-state, queue-operation-result

**Root cause:** `ClaudeCodeMetadataParser.parseMetadata()` (`TranscriptParsers.swift:445-620`) only has cases for known types; new types fall through and return empty `MetadataParseResult`, which `HooverEngine` ignores during batch insert.

**Solution:** Extend metadata parser, add tables (v26), update repositories, add telemetry

---

## Control Flow Analysis (Detailed)

### Entry Point: Line Parsing

**File:** `app/Sources/ContextifyCore/Database/HooverEngine.swift:383-433`

```swift
// 1. Try conversation parser
do {
  let entry = try parser.parse(line, ...)  // TranscriptParsers.swift:59-400
  batch.append(entry)
} catch ParserError.skipEntry {
  // Metadata types throw here (TranscriptParsers.swift:88-90)
}

// 2. ALWAYS try metadata parser
if let metadataResult = try? metadataParser.parseMetadata(line, ...) {
  metadataBatch.add(metadataResult)  // HooverEngine.swift:432
}

// 3. Batch insert when threshold reached
if batch.count >= MonitorConfig.batchLines {
  try repository.insertBatch(
    entries: batch,
    metadata: metadataBatch,  // → Repository inserts
    ...
  )
  metadataBatch.clear()  // HooverEngine.swift:458
}
```

### Metadata Parser Flow

**File:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift:445-620`

```swift
public func parseMetadata(...) -> MetadataParseResult {
  let type = json["type"] as? String

  if type == "file-history-snapshot" {
    return MetadataParseResult(fileSnapshot: ..., trackedFiles: ...)
  }
  if type == "summary" {
    return MetadataParseResult(transcriptSummary: ...)
  }
  if type == "system" {
    return MetadataParseResult(systemEvent: ...)
  }
  // Assistant usage extraction for assistant messages
  if type == "assistant" {
    return MetadataParseResult(assistantUsage: ...)
  }

  // ❌ queue-operation, timeline-state, queue-operation-result fall through
  return MetadataParseResult()  // Empty → discarded
}
```

### MetadataBatch Accumulation

**File:** `app/Sources/ContextifyCore/Database/HooverEngine.swift:126-142`

```swift
private struct MetadataBatch {
  var fileSnapshots: [FileSnapshot] = []
  var trackedFiles: [TrackedFile] = []
  var transcriptSummaries: [TranscriptSummary] = []
  var systemEvents: [SystemEvent] = []
  var assistantUsages: [AssistantUsage] = []
  // ❌ No queue/timeline collections

  mutating func add(_ result: MetadataParseResult) {
    if let snapshot = result.fileSnapshot {
      fileSnapshots.append(snapshot)
    }
    // ... other types
    // ❌ Queue metadata not added
  }
}
```

### Repository Insert

**File:** `app/Sources/ContextifyCore/Database/TranscriptRepository.swift` (location TBD in Phase 0)

```swift
func insertBatch(
  entries: [EntryInsert],
  metadata: MetadataBatch,
  ...
) throws {
  try db.write { db in
    // Insert entries
    for entry in entries {
      try entry.toModel().insert(db)
    }

    // Insert metadata
    for snapshot in metadata.fileSnapshots {
      try snapshot.insert(db)
    }
    for file in metadata.trackedFiles {
      try file.insert(db)
    }
    // ... summaries, events, usage
    // ❌ No queue/timeline inserts
  }
}
```

**Gap:** No insert logic for queue/timeline metadata even if it were collected

---

## Implementation Plan

### Phase 0: Architecture Review & Repository Location

**Goal:** Locate exact repository methods to extend

**Actions:**

1. **Find repository insert method:**
```bash
# Primary search
grep -rn "func insertBatch" app/Sources/ContextifyCore/Database/

# Alternative names
grep -rn "func insertMetadata" app/Sources/ContextifyCore/Database/
grep -rn "metadata.*insert\|insert.*metadata" app/Sources/ContextifyCore/Database/ | grep -v "//.*insert"

# Expected: TranscriptRepository.swift or MetadataRepository.swift
```

2. **Document findings:**
   - File path: `app/Sources/ContextifyCore/Database/<Repository>.swift`
   - Method signature: `func insertBatch(...) throws` or similar
   - Line numbers for extension points

3. **Verify MetadataBatch structure:**
```bash
grep -A 30 "struct MetadataBatch" app/Sources/ContextifyCore/Database/HooverEngine.swift
# Confirm location: HooverEngine.swift:126-142
```

**Deliverable:** Phase 0 report with exact file paths and line numbers

---

### Phase 1: Documentation & Schema Analysis

**Goal:** Capture real metadata schemas before implementation

#### Step 1.1: Extract Samples

**Script:** `scripts/analyze_metadata_schemas.sh`

```bash
#!/bin/bash
set -e

EXAMPLES_DIR="build/docs/specifications/examples/metadata"
ANALYSIS_FILE="$EXAMPLES_DIR/analysis-report.md"

mkdir -p "$EXAMPLES_DIR"

echo "# Metadata Schema Analysis Report" > "$ANALYSIS_FILE"
echo "Date: $(date)" >> "$ANALYSIS_FILE"
echo "" >> "$ANALYSIS_FILE"

# Queue operations
echo "## Queue Operations" >> "$ANALYSIS_FILE"
echo "Extracting queue-operation samples..."
grep -h '"type":"queue-operation"' ~/.claude/projects/*/*.jsonl 2>/dev/null \
  | head -10 \
  | python3 -m json.tool \
  > "$EXAMPLES_DIR/queue-operation-samples.json" || echo "No samples found"

QUEUE_COUNT=$(grep -h '"type":"queue-operation"' ~/.claude/projects/*/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
echo "- **Count:** $QUEUE_COUNT records" >> "$ANALYSIS_FILE"

if [ -f "$EXAMPLES_DIR/queue-operation-samples.json" ]; then
  echo "- **Sample location:** \`$EXAMPLES_DIR/queue-operation-samples.json\`" >> "$ANALYSIS_FILE"

  # Extract field inventory
  echo "- **Fields detected:**" >> "$ANALYSIS_FILE"
  python3 -c "
import json, sys
fields = set()
with open('$EXAMPLES_DIR/queue-operation-samples.json') as f:
    samples = json.load(f) if isinstance(json.load(f), list) else [json.load(f)]
    for sample in samples:
        fields.update(sample.keys())
for field in sorted(fields):
    print(f'  - \`{field}\`')
" >> "$ANALYSIS_FILE" 2>/dev/null || echo "  - (Analysis failed)" >> "$ANALYSIS_FILE"
fi
echo "" >> "$ANALYSIS_FILE"

# Timeline states
echo "## Timeline States" >> "$ANALYSIS_FILE"
echo "Extracting timeline-state samples..."
grep -h '"type":"timeline-state"' ~/.claude/projects/*/*.jsonl 2>/dev/null \
  | head -10 \
  | python3 -m json.tool \
  > "$EXAMPLES_DIR/timeline-state-samples.json" || echo "No samples found"

TIMELINE_COUNT=$(grep -h '"type":"timeline-state"' ~/.claude/projects/*/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
echo "- **Count:** $TIMELINE_COUNT records" >> "$ANALYSIS_FILE"

if [ -f "$EXAMPLES_DIR/timeline-state-samples.json" ]; then
  echo "- **Sample location:** \`$EXAMPLES_DIR/timeline-state-samples.json\`" >> "$ANALYSIS_FILE"

  echo "- **Fields detected:**" >> "$ANALYSIS_FILE"
  python3 -c "
import json, sys
fields = set()
with open('$EXAMPLES_DIR/timeline-state-samples.json') as f:
    data = json.load(f)
    samples = data if isinstance(data, list) else [data]
    for sample in samples:
        fields.update(sample.keys())
for field in sorted(fields):
    print(f'  - \`{field}\`')
" >> "$ANALYSIS_FILE" 2>/dev/null || echo "  - (Analysis failed)" >> "$ANALYSIS_FILE"
fi
echo "" >> "$ANALYSIS_FILE"

# Queue results
echo "## Queue Operation Results" >> "$ANALYSIS_FILE"
echo "Extracting queue-operation-result samples..."
grep -h '"type":"queue-operation-result"' ~/.claude/projects/*/*.jsonl 2>/dev/null \
  | head -10 \
  | python3 -m json.tool \
  > "$EXAMPLES_DIR/queue-operation-result-samples.json" || echo "No samples found"

RESULT_COUNT=$(grep -h '"type":"queue-operation-result"' ~/.claude/projects/*/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
echo "- **Count:** $RESULT_COUNT records" >> "$ANALYSIS_FILE"

if [ -f "$EXAMPLES_DIR/queue-operation-result-samples.json" ]; then
  echo "- **Sample location:** \`$EXAMPLES_DIR/queue-operation-result-samples.json\`" >> "$ANALYSIS_FILE"

  echo "- **Fields detected:**" >> "$ANALYSIS_FILE"
  python3 -c "
import json, sys
fields = set()
with open('$EXAMPLES_DIR/queue-operation-result-samples.json') as f:
    data = json.load(f)
    samples = data if isinstance(data, list) else [data]
    for sample in samples:
        fields.update(sample.keys())
for field in sorted(fields):
    print(f'  - \`{field}\`')
" >> "$ANALYSIS_FILE" 2>/dev/null || echo "  - (Analysis failed)" >> "$ANALYSIS_FILE"
fi
echo "" >> "$ANALYSIS_FILE"

# Summary
echo "## Summary" >> "$ANALYSIS_FILE"
echo "- Queue operations: $QUEUE_COUNT" >> "$ANALYSIS_FILE"
echo "- Timeline states: $TIMELINE_COUNT" >> "$ANALYSIS_FILE"
echo "- Queue results: $RESULT_COUNT" >> "$ANALYSIS_FILE"
TOTAL=$((QUEUE_COUNT + TIMELINE_COUNT + RESULT_COUNT))
echo "- **Total metadata records to be stored:** $TOTAL" >> "$ANALYSIS_FILE"
echo "" >> "$ANALYSIS_FILE"
echo "**Next step:** Review samples to confirm join keys (operationId linking)" >> "$ANALYSIS_FILE"

# Output summary
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Metadata Schema Analysis Complete"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Samples saved:"
echo "  - Queue operations: $QUEUE_COUNT records"
echo "  - Timeline states: $TIMELINE_COUNT records"
echo "  - Queue results: $RESULT_COUNT records"
echo ""
echo "Report: $ANALYSIS_FILE"
echo "Samples: $EXAMPLES_DIR/"
echo ""
echo "Next: Review samples to confirm field names and join keys"
```

**Run:**
```bash
chmod +x scripts/analyze_metadata_schemas.sh
./scripts/analyze_metadata_schemas.sh
```

**Review:** `build/docs/specifications/examples/metadata/analysis-report.md`

**Critical validation:**
- Confirm `operationId` exists in queue-operation records (for join key)
- Confirm `operationId` exists in queue-operation-result records (for link)
- Identify actual field names (stateId, messageId, timestamp, etc.)

#### Step 1.2: Update Documentation

**File:** `build/docs/specifications/claude-code-transcript-format.md`

**Location:** After Section 5 (System Messages), insert new section at ~line 290

**Add:**

```markdown
---

## Additional Metadata Record Types

### 6. Queue Operation (`type: "queue-operation"`)

**Purpose:** Internal queue operation tracking for debugging and session replay.

**Fields:** (Confirmed from analysis in Phase 1)
```typescript
{
  type: "queue-operation",
  operationId: string,      // Unique operation ID (JOIN KEY)
  messageId: string?,       // Associated message UUID
  timestamp: string,        // ISO 8601
  operationType: string?,   // Operation type (TBD from samples)
  // Additional fields from analysis
}
```

**Examples:** See `build/docs/specifications/examples/metadata/queue-operation-samples.json`

**Frequency:** [COUNT from analysis] records across analyzed transcripts

**Database Storage:** `queue_operations` table (v26+)

**Value:**
- Queue performance monitoring
- Session replay capabilities
- Operation failure analysis

---

### 7. Timeline State (`type: "timeline-state"`)

**Purpose:** Timeline state snapshots for debugging and replay.

**Fields:** (Confirmed from analysis in Phase 1)
```typescript
{
  type: "timeline-state",
  stateId: string?,         // State identifier
  messageId: string?,       // Associated message UUID
  timestamp: string,        // ISO 8601
  stateType: string?,       // State type (TBD from samples)
  // Additional fields from analysis
}
```

**Examples:** See `build/docs/specifications/examples/metadata/timeline-state-samples.json`

**Frequency:** [COUNT from analysis] records across analyzed transcripts

**Database Storage:** `timeline_states` table (v26+)

**Value:**
- Timeline corruption debugging
- State evolution tracking
- Replay functionality

---

### 8. Queue Operation Result (`type: "queue-operation-result"`)

**Purpose:** Queue operation results, linked to operations via operationId.

**Fields:** (Confirmed from analysis in Phase 1)
```typescript
{
  type: "queue-operation-result",
  resultId: string?,        // Result identifier
  operationId: string?,     // JOIN KEY → links to queue-operation.operationId
  messageId: string?,       // Associated message UUID
  timestamp: string,        // ISO 8601
  success: boolean?,        // Success flag
  error: string?,           // Error message if failed
  // Additional fields from analysis
}
```

**Examples:** See `build/docs/specifications/examples/metadata/queue-operation-result-samples.json`

**Frequency:** [COUNT from analysis] records across analyzed transcripts

**Database Storage:** `queue_operation_results` table (v26+)

**Value:**
- Success rate tracking
- Failure pattern analysis
- Operation-result correlation

**Join Relationship:**
```sql
SELECT qo.*, qor.success, qor.error
FROM queue_operations qo
LEFT JOIN queue_operation_results qor
  ON qo.operation_id = qor.operation_id
WHERE qo.transcript_id = ?
```

---
```

**File:** `build/docs/architecture/sql-backend.md`

**Location:** Update schema section (~line 95) to add new tables

**Add after existing metadata tables:**

```markdown
queue_operations (v26+)
├── id (PK)
├── transcript_id (FK → transcripts, CASCADE)
├── operation_id (Stable ID from JSON, JOIN KEY)
├── message_id
├── timestamp
├── operation_type
├── operation_data (JSON blob)
└── created_at

timeline_states (v26+)
├── id (PK)
├── transcript_id (FK → transcripts, CASCADE)
├── state_id (Stable ID from JSON)
├── message_id
├── timestamp
├── state_type
├── state_data (JSON blob)
└── created_at

queue_operation_results (v26+)
├── id (PK)
├── transcript_id (FK → transcripts, CASCADE)
├── result_id (Stable ID from JSON)
├── operation_id (FK → queue_operations.operation_id)
├── message_id
├── timestamp
├── success (0/1 boolean)
├── error_message
├── result_data (JSON blob)
└── created_at
```

**Deliverable:** Updated documentation with real field names from analysis

---

### Phase 2: Database Schema (v26 Migration)

**File:** `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`

**Location:** After last migration (v25), before `createMigrator()` return

**Add:**

```swift
// v26: Queue metadata tables
// Stores queue-operation, timeline-state, queue-operation-result records
// Fields confirmed from schema analysis (build/docs/specifications/examples/metadata/)
migrator.registerMigration("v26_queue_metadata_tables") { db in

  // Queue operations
  try db.execute(sql: """
    CREATE TABLE IF NOT EXISTS queue_operations (
      id TEXT PRIMARY KEY,
      transcript_id TEXT NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
      operation_id TEXT NOT NULL,
      message_id TEXT,
      timestamp INTEGER NOT NULL,
      operation_type TEXT,
      operation_data TEXT,
      created_at INTEGER NOT NULL
    )
  """)
  try db.execute(sql: """
    CREATE INDEX IF NOT EXISTS idx_queue_ops_transcript
    ON queue_operations(transcript_id, timestamp DESC)
  """)
  try db.execute(sql: """
    CREATE UNIQUE INDEX IF NOT EXISTS idx_queue_ops_operation_id
    ON queue_operations(operation_id)
  """)

  // Timeline states
  try db.execute(sql: """
    CREATE TABLE IF NOT EXISTS timeline_states (
      id TEXT PRIMARY KEY,
      transcript_id TEXT NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
      state_id TEXT,
      message_id TEXT,
      timestamp INTEGER NOT NULL,
      state_type TEXT,
      state_data TEXT,
      created_at INTEGER NOT NULL
    )
  """)
  try db.execute(sql: """
    CREATE INDEX IF NOT EXISTS idx_timeline_states_transcript
    ON timeline_states(transcript_id, timestamp DESC)
  """)
  try db.execute(sql: """
    CREATE INDEX IF NOT EXISTS idx_timeline_states_state_id
    ON timeline_states(state_id)
  """)

  // Queue operation results
  try db.execute(sql: """
    CREATE TABLE IF NOT EXISTS queue_operation_results (
      id TEXT PRIMARY KEY,
      transcript_id TEXT NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
      result_id TEXT,
      operation_id TEXT,
      message_id TEXT,
      timestamp INTEGER NOT NULL,
      success INTEGER,
      error_message TEXT,
      result_data TEXT,
      created_at INTEGER NOT NULL
    )
  """)
  try db.execute(sql: """
    CREATE INDEX IF NOT EXISTS idx_queue_results_transcript
    ON queue_operation_results(transcript_id, timestamp DESC)
  """)
  try db.execute(sql: """
    CREATE INDEX IF NOT EXISTS idx_queue_results_operation_id
    ON queue_operation_results(operation_id)
  """)
}
```

**Update version:**
```swift
enum DatabaseSchema {
  static let version = 26  // Was 25
```

**Design notes:**
- UNIQUE index on operation_id prevents duplicates and optimizes joins
- Compound indexes (transcript_id, timestamp DESC) optimize timeline queries
- JSON blobs preserve full records for unknown fields
- No WITHOUT ROWID to maintain WAL compatibility

---

### Phase 3: Model Types

**File:** `app/Sources/ContextifyCore/Database/Models.swift`

**Location:** After existing metadata models (~line 400+)

**Add:**

```swift
// MARK: - Queue Metadata (v26)

/// Queue operation record (type: queue-operation)
public struct QueueOperation: Codable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "queue_operations"

  public let id: String
  public let transcriptId: String
  public let operationId: String
  public let messageId: String?
  public let timestamp: Int
  public let operationType: String?
  public let operationData: String?
  public let createdAt: Int

  public init(
    id: String,
    transcriptId: String,
    operationId: String,
    messageId: String?,
    timestamp: Int,
    operationType: String?,
    operationData: String?,
    createdAt: Int
  ) {
    self.id = id
    self.transcriptId = transcriptId
    self.operationId = operationId
    self.messageId = messageId
    self.timestamp = timestamp
    self.operationType = operationType
    self.operationData = operationData
    self.createdAt = createdAt
  }
}

/// Timeline state snapshot (type: timeline-state)
public struct TimelineState: Codable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "timeline_states"

  public let id: String
  public let transcriptId: String
  public let stateId: String?
  public let messageId: String?
  public let timestamp: Int
  public let stateType: String?
  public let stateData: String?
  public let createdAt: Int

  public init(
    id: String,
    transcriptId: String,
    stateId: String?,
    messageId: String?,
    timestamp: Int,
    stateType: String?,
    stateData: String?,
    createdAt: Int
  ) {
    self.id = id
    self.transcriptId = transcriptId
    self.stateId = stateId
    self.messageId = messageId
    self.timestamp = timestamp
    self.stateType = stateType
    self.stateData = stateData
    self.createdAt = createdAt
  }
}

/// Queue operation result (type: queue-operation-result)
public struct QueueOperationResult: Codable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "queue_operation_results"

  public let id: String
  public let transcriptId: String
  public let resultId: String?
  public let operationId: String?
  public let messageId: String?
  public let timestamp: Int
  public let success: Int?
  public let errorMessage: String?
  public let resultData: String?
  public let createdAt: Int

  public init(
    id: String,
    transcriptId: String,
    resultId: String?,
    operationId: String?,
    messageId: String?,
    timestamp: Int,
    success: Int?,
    errorMessage: String?,
    resultData: String?,
    createdAt: Int
  ) {
    self.id = id
    self.transcriptId = transcriptId
    self.resultId = resultId
    self.operationId = operationId
    self.messageId = messageId
    self.timestamp = timestamp
    self.success = success
    self.errorMessage = errorMessage
    self.resultData = resultData
    self.createdAt = createdAt
  }
}
```

---

### Phase 4: Extend MetadataParseResult

**File:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

**Location:** Lines 405-429 (struct MetadataParseResult)

**Modify:**

```swift
/// Result of parsing metadata from a transcript line
public struct MetadataParseResult {
  public let fileSnapshot: FileSnapshot?
  public let trackedFiles: [TrackedFile]
  public let transcriptSummary: TranscriptSummary?
  public let systemEvent: SystemEvent?
  public let assistantUsage: AssistantUsage?

  // v26: Queue metadata
  public let queueOperation: QueueOperation?
  public let timelineState: TimelineState?
  public let queueOperationResult: QueueOperationResult?

  public init(
    fileSnapshot: FileSnapshot? = nil,
    trackedFiles: [TrackedFile] = [],
    transcriptSummary: TranscriptSummary? = nil,
    systemEvent: SystemEvent? = nil,
    assistantUsage: AssistantUsage? = nil,
    queueOperation: QueueOperation? = nil,
    timelineState: TimelineState? = nil,
    queueOperationResult: QueueOperationResult? = nil
  ) {
    self.fileSnapshot = fileSnapshot
    self.trackedFiles = trackedFiles
    self.transcriptSummary = transcriptSummary
    self.systemEvent = systemEvent
    self.assistantUsage = assistantUsage
    self.queueOperation = queueOperation
    self.timelineState = timelineState
    self.queueOperationResult = queueOperationResult
  }

  public var hasMetadata: Bool {
    fileSnapshot != nil ||
    !trackedFiles.isEmpty ||
    transcriptSummary != nil ||
    systemEvent != nil ||
    assistantUsage != nil ||
    queueOperation != nil ||
    timelineState != nil ||
    queueOperationResult != nil
  }
}
```

---

### Phase 5: Extend Metadata Parser

**File:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

**Location:** Lines 445-620 (ClaudeCodeMetadataParser)

**Add logger import at top if not present:**
```swift
import OSLog
private let metadataLog = Logger(subsystem: "dev.contextify", category: "MetadataParser")
```

**Add cases after existing parsers (~line 546):**

```swift
public struct ClaudeCodeMetadataParser: TranscriptMetadataParser {
  public func parseMetadata(...) -> MetadataParseResult {

    // ... existing parsers for file-history-snapshot, summary, system, assistant ...

    // v26: queue-operation
    if type == "queue-operation" {
      // Extract stable operation ID (confirmed in Phase 1 analysis)
      let operationId = json["operationId"] as? String ?? UUID().uuidString
      let messageId = json["messageId"] as? String

      let timestamp: Date
      if let timestampStr = json["timestamp"] as? String,
         let parsedTimestamp = parseISO8601(timestampStr) {
        timestamp = parsedTimestamp
      } else {
        timestamp = Date()
      }

      // Serialize full JSON for forward compatibility
      let operationData = try? JSONSerialization.data(withJSONObject: json)
      let operationDataString = operationData.flatMap { String(data: $0, encoding: .utf8) }

      let operation = QueueOperation(
        id: UUID().uuidString,
        transcriptId: transcriptId,
        operationId: operationId,
        messageId: messageId,
        timestamp: Int(timestamp.timeIntervalSince1970),
        operationType: json["operationType"] as? String,
        operationData: operationDataString,
        createdAt: now
      )

      metadataLog.debug("[META-INGEST] type=queue-operation id=\(operationId, privacy: .public)")
      return MetadataParseResult(queueOperation: operation)
    }

    // v26: timeline-state
    if type == "timeline-state" {
      let stateId = json["stateId"] as? String  // May be null
      let messageId = json["messageId"] as? String

      let timestamp: Date
      if let timestampStr = json["timestamp"] as? String,
         let parsedTimestamp = parseISO8601(timestampStr) {
        timestamp = parsedTimestamp
      } else {
        timestamp = Date()
      }

      let stateData = try? JSONSerialization.data(withJSONObject: json)
      let stateDataString = stateData.flatMap { String(data: $0, encoding: .utf8) }

      let state = TimelineState(
        id: UUID().uuidString,
        transcriptId: transcriptId,
        stateId: stateId,
        messageId: messageId,
        timestamp: Int(timestamp.timeIntervalSince1970),
        stateType: json["stateType"] as? String,
        stateData: stateDataString,
        createdAt: now
      )

      metadataLog.debug("[META-INGEST] type=timeline-state id=\(stateId ?? "nil", privacy: .public)")
      return MetadataParseResult(timelineState: state)
    }

    // v26: queue-operation-result
    if type == "queue-operation-result" {
      let resultId = json["resultId"] as? String
      let operationId = json["operationId"] as? String  // JOIN KEY
      let messageId = json["messageId"] as? String

      let timestamp: Date
      if let timestampStr = json["timestamp"] as? String,
         let parsedTimestamp = parseISO8601(timestampStr) {
        timestamp = parsedTimestamp
      } else {
        timestamp = Date()
      }

      let resultData = try? JSONSerialization.data(withJSONObject: json)
      let resultDataString = resultData.flatMap { String(data: $0, encoding: .utf8) }

      let result = QueueOperationResult(
        id: UUID().uuidString,
        transcriptId: transcriptId,
        resultId: resultId,
        operationId: operationId,
        messageId: messageId,
        timestamp: Int(timestamp.timeIntervalSince1970),
        success: (json["success"] as? Bool).map { $0 ? 1 : 0 },
        errorMessage: json["error"] as? String,
        resultData: resultDataString,
        createdAt: now
      )

      metadataLog.debug("[META-INGEST] type=queue-operation-result id=\(resultId ?? "nil", privacy: .public) success=\(result.success ?? -1, privacy: .public)")
      return MetadataParseResult(queueOperationResult: result)
    }

    // Return empty for unknown types (existing behavior)
    return MetadataParseResult()
  }
}
```

---

### Phase 6: Extend MetadataBatch

**File:** `app/Sources/ContextifyCore/Database/HooverEngine.swift`

**Location:** Lines 126-142 (struct MetadataBatch)

**Modify:**

```swift
/// Container for accumulated metadata during ingestion
private struct MetadataBatch {
  var fileSnapshots: [FileSnapshot] = []
  var trackedFiles: [TrackedFile] = []
  var transcriptSummaries: [TranscriptSummary] = []
  var systemEvents: [SystemEvent] = []
  var assistantUsages: [AssistantUsage] = []

  // v26: Queue metadata
  var queueOperations: [QueueOperation] = []
  var timelineStates: [TimelineState] = []
  var queueOperationResults: [QueueOperationResult] = []

  mutating func add(_ result: MetadataParseResult) {
    if let snapshot = result.fileSnapshot {
      fileSnapshots.append(snapshot)
    }
    trackedFiles.append(contentsOf: result.trackedFiles)
    if let summary = result.transcriptSummary {
      transcriptSummaries.append(summary)
    }
    if let event = result.systemEvent {
      systemEvents.append(event)
    }
    if let usage = result.assistantUsage {
      assistantUsages.append(usage)
    }

    // v26
    if let operation = result.queueOperation {
      queueOperations.append(operation)
    }
    if let state = result.timelineState {
      timelineStates.append(state)
    }
    if let opResult = result.queueOperationResult {
      queueOperationResults.append(opResult)
    }
  }

  var isEmpty: Bool {
    fileSnapshots.isEmpty &&
    trackedFiles.isEmpty &&
    transcriptSummaries.isEmpty &&
    systemEvents.isEmpty &&
    assistantUsages.isEmpty &&
    queueOperations.isEmpty &&
    timelineStates.isEmpty &&
    queueOperationResults.isEmpty
  }

  mutating func clear() {
    fileSnapshots.removeAll()
    trackedFiles.removeAll()
    transcriptSummaries.removeAll()
    systemEvents.removeAll()
    assistantUsages.removeAll()
    queueOperations.removeAll()
    timelineStates.removeAll()
    queueOperationResults.removeAll()
  }
}
```

---

### Phase 7: Repository Integration

**File:** Located in Phase 0 (likely `app/Sources/ContextifyCore/Database/TranscriptRepository.swift`)

**Action:** Find `insertBatch` method signature from Phase 0

**Expected pattern:**

```swift
func insertBatch(
  entries: [EntryInsert],
  metadata: MetadataBatch,
  errors: [(lineNumber: Int, rawLine: String, error: String)],
  ...
) throws {
  try db.write { db in

    // Existing inserts
    for entry in entries {
      try entry.toModel().insert(db)
    }

    for snapshot in metadata.fileSnapshots {
      try snapshot.insert(db)
    }
    for file in metadata.trackedFiles {
      try file.insert(db)
    }
    for summary in metadata.transcriptSummaries {
      try summary.insert(db)
    }
    for event in metadata.systemEvents {
      try event.insert(db)
    }
    for usage in metadata.assistantUsages {
      try usage.insert(db)
    }

    // v26: Queue metadata inserts
    for operation in metadata.queueOperations {
      try operation.insert(db)
    }
    for state in metadata.timelineStates {
      try state.insert(db)
    }
    for result in metadata.queueOperationResults {
      try result.insert(db)
    }

    // ... rest of method (errors, checkpoints, etc.)
  }

  // Add telemetry logging AFTER successful insert
  log.info("[HOOVER-UPDATE-ROWS] entries=\(entries.count, privacy: .public) snapshots=\(metadata.fileSnapshots.count, privacy: .public) summaries=\(metadata.transcriptSummaries.count, privacy: .public) events=\(metadata.systemEvents.count, privacy: .public) queue_ops=\(metadata.queueOperations.count, privacy: .public) timeline_states=\(metadata.timelineStates.count, privacy: .public) queue_results=\(metadata.queueOperationResults.count, privacy: .public)")
}
```

**If insertBatch doesn't exist, create it based on existing insert patterns found in Phase 0**

---

### Phase 8: Telemetry & Monitoring

#### Update Logging Documentation

**File:** `scripts/logging/README.md`

**Add to log tag inventory:**

```markdown
### Metadata Ingestion Tags (v26+)

**[META-INGEST]** - Metadata record successfully parsed
- **Category:** MetadataParser
- **Level:** debug
- **Format:** `[META-INGEST] type=<type> id=<id> [success=<0|1>]`
- **Examples:**
  - `[META-INGEST] type=queue-operation id=op-12345`
  - `[META-INGEST] type=timeline-state id=state-abc`
  - `[META-INGEST] type=queue-operation-result id=res-789 success=1`
- **Use:** Track metadata parsing and verify new types being collected
- **Script:** `monitor-metadata-ingestion.sh`

**[HOOVER-UPDATE-ROWS]** - Batch insert completed (extended in v26)
- **Category:** HooverEngine
- **Level:** info
- **Format:** `[HOOVER-UPDATE-ROWS] entries=<n> snapshots=<n> summaries=<n> events=<n> queue_ops=<n> timeline_states=<n> queue_results=<n>`
- **Use:** Track ingestion throughput including new metadata types
- **Script:** `monitor-ingestion-rate.sh`

**[META-INSERT-ERROR]** - Metadata insert failed (new in v26)
- **Category:** TranscriptRepository
- **Level:** error
- **Format:** `[META-INSERT-ERROR] type=<type> id=<id> error=<message>`
- **Use:** Alert on metadata insert failures
- **Script:** `analyze-metadata-errors.sh`
```

#### Create Monitoring Script

**File:** `scripts/logging/monitor-metadata-ingestion.sh`

```bash
#!/bin/bash

SUBSYSTEM="dev.contextify"
CATEGORIES="MetadataParser|HooverEngine|TranscriptRepository"
PATTERN="META-INGEST|HOOVER-UPDATE-ROWS|META-INSERT-ERROR"
LEVEL="debug"

echo "Monitoring metadata ingestion..."
echo "Press Ctrl+C to stop"
echo ""

log stream \
  --predicate "subsystem BEGINSWITH \"$SUBSYSTEM\" AND (${CATEGORIES})" \
  --level "$LEVEL" \
  --style compact \
  2>&1 | grep --line-buffered -E "\[($PATTERN)\]"
```

#### Add Analysis Script

**File:** `scripts/logging/analyze-metadata-stats.sh`

```bash
#!/bin/bash
# Analyze metadata ingestion statistics from logs

if [ -z "$1" ]; then
  echo "Usage: $0 <logfile>"
  echo "Example: $0 /tmp/ingestion-log.txt"
  exit 1
fi

LOGFILE="$1"

echo "Metadata Ingestion Statistics"
echo "=============================="
echo ""

# Count by type
echo "Records by type:"
grep "\[META-INGEST\]" "$LOGFILE" | sed 's/.*type=\([^ ]*\).*/\1/' | sort | uniq -c | sort -rn

echo ""
echo "Success/Failure (queue-operation-result):"
grep "\[META-INGEST\] type=queue-operation-result" "$LOGFILE" | \
  grep -oE "success=[01]" | sort | uniq -c

echo ""
echo "Insert errors:"
grep "\[META-INSERT-ERROR\]" "$LOGFILE" | wc -l | xargs echo "Total errors:"

echo ""
echo "Batch statistics:"
grep "\[HOOVER-UPDATE-ROWS\]" "$LOGFILE" | tail -10
```

---

## Testing Strategy

### Unit Tests

**File:** Create `app/ContextifyTests/MetadataParserTests.swift`

**Add comprehensive parser tests:**

```swift
import XCTest
@testable import ContextifyCore

final class MetadataParserTests: XCTestCase {

  // MARK: - Queue Operations

  func testParseQueueOperation() throws {
    // Use real sample from Phase 1 analysis
    let json = """
    {
      "type": "queue-operation",
      "operationId": "op-12345",
      "messageId": "msg-abc",
      "timestamp": "2025-11-14T10:00:00.000Z",
      "operationType": "enqueue"
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "transcript-1",
      projectId: "project-1",
      provider: "claude.code",
      entryId: nil
    )

    XCTAssertNotNil(result.queueOperation)
    XCTAssertEqual(result.queueOperation?.operationId, "op-12345")
    XCTAssertEqual(result.queueOperation?.operationType, "enqueue")
    XCTAssertNotNil(result.queueOperation?.operationData)  // JSON preserved
  }

  func testParseQueueOperationMissingOptionalFields() throws {
    // Test with minimal fields
    let json = """
    {
      "type": "queue-operation",
      "timestamp": "2025-11-14T10:00:00.000Z"
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "t1",
      projectId: "p1",
      provider: "claude.code",
      entryId: nil
    )

    XCTAssertNotNil(result.queueOperation)
    // operationId should be generated UUID since missing from JSON
    XCTAssertNotNil(result.queueOperation?.operationId)
  }

  // MARK: - Timeline States

  func testParseTimelineState() throws {
    let json = """
    {
      "type": "timeline-state",
      "stateId": "state-67890",
      "messageId": "msg-def",
      "timestamp": "2025-11-14T10:00:00.000Z",
      "stateType": "snapshot"
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "t1",
      projectId: "p1",
      provider: "claude.code",
      entryId: nil
    )

    XCTAssertNotNil(result.timelineState)
    XCTAssertEqual(result.timelineState?.stateId, "state-67890")
    XCTAssertEqual(result.timelineState?.stateType, "snapshot")
    XCTAssertNotNil(result.timelineState?.stateData)
  }

  // MARK: - Queue Operation Results

  func testParseQueueOperationResult() throws {
    let json = """
    {
      "type": "queue-operation-result",
      "resultId": "result-abc",
      "operationId": "op-12345",
      "messageId": "msg-ghi",
      "timestamp": "2025-11-14T10:00:01.000Z",
      "success": true
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "t1",
      projectId: "p1",
      provider: "claude.code",
      entryId: nil
    )

    XCTAssertNotNil(result.queueOperationResult)
    XCTAssertEqual(result.queueOperationResult?.resultId, "result-abc")
    XCTAssertEqual(result.queueOperationResult?.operationId, "op-12345")
    XCTAssertEqual(result.queueOperationResult?.success, 1)
  }

  func testParseQueueOperationResultFailure() throws {
    let json = """
    {
      "type": "queue-operation-result",
      "operationId": "op-999",
      "timestamp": "2025-11-14T10:00:01.000Z",
      "success": false,
      "error": "Timeout after 30s"
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "t1",
      projectId: "p1",
      provider: "claude.code",
      entryId: nil
    )

    XCTAssertNotNil(result.queueOperationResult)
    XCTAssertEqual(result.queueOperationResult?.success, 0)
    XCTAssertEqual(result.queueOperationResult?.errorMessage, "Timeout after 30s")
  }

  // MARK: - Database Integration

  func testQueueOperationResultJoin() throws {
    let db = try setupTestDatabase()

    // Insert operation
    let operation = QueueOperation(
      id: UUID().uuidString,
      transcriptId: "t1",
      operationId: "op-123",
      messageId: "msg-1",
      timestamp: 1000,
      operationType: "test",
      operationData: nil,
      createdAt: 1000
    )
    try db.write { try operation.insert($0) }

    // Insert result
    let result = QueueOperationResult(
      id: UUID().uuidString,
      transcriptId: "t1",
      resultId: "res-1",
      operationId: "op-123",  // Links to operation
      messageId: "msg-2",
      timestamp: 1001,
      success: 1,
      errorMessage: nil,
      resultData: nil,
      createdAt: 1001
    )
    try db.write { try result.insert($0) }

    // Query join
    let joined = try db.read { db in
      try Row.fetchAll(db, sql: """
        SELECT qo.operation_type, qor.success
        FROM queue_operations qo
        JOIN queue_operation_results qor
          ON qo.operation_id = qor.operation_id
        WHERE qo.operation_id = ?
      """, arguments: ["op-123"])
    }

    XCTAssertEqual(joined.count, 1)
    XCTAssertEqual(joined[0]["operation_type"] as? String, "test")
    XCTAssertEqual(joined[0]["success"] as? Int, 1)
  }

  func testMetadataBatchAccumulation() throws {
    var batch = MetadataBatch()

    // Add queue operation
    let operation = QueueOperation(
      id: "1", transcriptId: "t1", operationId: "op-1",
      messageId: nil, timestamp: 1000, operationType: "test",
      operationData: nil, createdAt: 1000
    )
    batch.add(MetadataParseResult(queueOperation: operation))

    // Add timeline state
    let state = TimelineState(
      id: "2", transcriptId: "t1", stateId: "s1",
      messageId: nil, timestamp: 1001, stateType: "snapshot",
      stateData: nil, createdAt: 1001
    )
    batch.add(MetadataParseResult(timelineState: state))

    // Add queue result
    let result = QueueOperationResult(
      id: "3", transcriptId: "t1", resultId: "r1", operationId: "op-1",
      messageId: nil, timestamp: 1002, success: 1,
      errorMessage: nil, resultData: nil, createdAt: 1002
    )
    batch.add(MetadataParseResult(queueOperationResult: result))

    XCTAssertEqual(batch.queueOperations.count, 1)
    XCTAssertEqual(batch.timelineStates.count, 1)
    XCTAssertEqual(batch.queueOperationResults.count, 1)
    XCTAssertFalse(batch.isEmpty)

    batch.clear()
    XCTAssertTrue(batch.isEmpty)
  }
}
```

### Integration Tests

**File:** `app/ContextifyTests/HooverEngineTests.swift`

**Add end-to-end test:**

```swift
func testQueueMetadataEndToEnd() throws {
  // Setup: Fresh database with v26 migration
  let db = try setupTestDatabase()

  // Create test transcript with queue metadata
  let transcriptContent = """
  {"type":"queue-operation","operationId":"op-1","timestamp":"2025-11-14T10:00:00Z","operationType":"enqueue"}
  {"type":"user","uuid":"msg-1","timestamp":"2025-11-14T10:00:01Z","message":{"role":"user","content":"test"}}
  {"type":"timeline-state","stateId":"state-1","timestamp":"2025-11-14T10:00:02Z","stateType":"snapshot"}
  {"type":"queue-operation-result","resultId":"res-1","operationId":"op-1","timestamp":"2025-11-14T10:00:03Z","success":true}
  """

  let tempFile = FileManager.default.temporaryDirectory
    .appendingPathComponent("test-\(UUID().uuidString).jsonl")
  try transcriptContent.write(to: tempFile, atomically: true, encoding: .utf8)

  // Ingest
  let repository = TranscriptRepository(database: db)
  let hoover = HooverEngine(repository: repository)
  try hoover.ingestTranscript(path: tempFile, projectId: "test-project")

  // Verify: Queue metadata stored
  let queueOps = try db.read { try QueueOperation.fetchAll($0) }
  XCTAssertEqual(queueOps.count, 1)
  XCTAssertEqual(queueOps[0].operationId, "op-1")
  XCTAssertEqual(queueOps[0].operationType, "enqueue")

  let states = try db.read { try TimelineState.fetchAll($0) }
  XCTAssertEqual(states.count, 1)
  XCTAssertEqual(states[0].stateId, "state-1")

  let results = try db.read { try QueueOperationResult.fetchAll($0) }
  XCTAssertEqual(results.count, 1)
  XCTAssertEqual(results[0].operationId, "op-1")  // Linked
  XCTAssertEqual(results[0].success, 1)

  // Verify: Conversation entry also stored
  let entries = try db.read { try TranscriptEntry.fetchAll($0) }
  XCTAssertEqual(entries.count, 1)
  XCTAssertEqual(entries[0].id, "msg-1")

  // Verify: Join works
  let joined = try db.read { db in
    try Row.fetchAll(db, sql: """
      SELECT qo.operation_type, qor.success
      FROM queue_operations qo
      JOIN queue_operation_results qor
        ON qo.operation_id = qor.operation_id
      WHERE qo.operation_id = 'op-1'
    """)
  }
  XCTAssertEqual(joined.count, 1)
  XCTAssertEqual(joined[0]["success"] as? Int, 1)
}
```

### Manual Verification

```bash
# 1. Clean database
./scripts/db_manager.sh clean

# 2. Launch app with v26
bash scripts/xc.sh build
open .derived-dmg/Build/Products/Debug/Contextify.app

# 3. Monitor metadata ingestion
./scripts/logging/monitor-metadata-ingestion.sh > /tmp/metadata-ingestion-log.txt

# Expected logs:
# [META-INGEST] type=queue-operation id=...
# [META-INGEST] type=timeline-state id=...
# [META-INGEST] type=queue-operation-result id=... success=1
# [HOOVER-UPDATE-ROWS] ... queue_ops=X timeline_states=Y queue_results=Z

# 4. Wait for ingestion (30-60s)

# 5. Verify database
sqlite3 ~/Library/Application\ Support/Contextify/contextify.db "
  SELECT
    'queue_operations' as table_name,
    COUNT(*) as count
  FROM queue_operations
  UNION ALL
  SELECT 'timeline_states', COUNT(*) FROM timeline_states
  UNION ALL
  SELECT 'queue_operation_results', COUNT(*) FROM queue_operation_results
"

# Expected: All counts > 0

# 6. Test join
sqlite3 ~/Library/Application\ Support/Contextify/contextify.db "
  SELECT
    qo.operation_type,
    COUNT(qor.id) as result_count,
    SUM(CASE WHEN qor.success = 1 THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN qor.success = 0 THEN 1 ELSE 0 END) as failed
  FROM queue_operations qo
  LEFT JOIN queue_operation_results qor
    ON qo.operation_id = qor.operation_id
  GROUP BY qo.operation_type
"

# 7. Analyze statistics
./scripts/logging/analyze-metadata-stats.sh /tmp/metadata-ingestion-log.txt

# 8. Check for errors
grep "\[META-INSERT-ERROR\]" /tmp/metadata-ingestion-log.txt
# Expected: No errors (or investigate any that appear)
```

---

## Performance Validation

### Baseline Measurement

**Before v26 implementation:**

```bash
# Clean database
./scripts/db_manager.sh clean

# Time full ingestion
time bash scripts/xc.sh build && open .derived-dmg/Build/Products/Debug/Contextify.app

# Monitor ingestion rate
./scripts/logging/monitor-transcript-queues.sh | tee /tmp/baseline-ingestion.log

# Extract rate
grep "\[HOOVER-UPDATE-ROWS\]" /tmp/baseline-ingestion.log | \
  awk '{print $NF}' | \
  python3 -c "import sys; times=[float(l.strip()) for l in sys.stdin]; print(f'Avg entries/batch: {sum(times)/len(times):.1f}')"

# Note database size
du -h ~/Library/Application\ Support/Contextify/contextify.db
```

### Post-Implementation Measurement

**After v26 implementation:**

```bash
# Same process
./scripts/db_manager.sh clean
time bash scripts/xc.sh build && open .derived-dmg/Build/Products/Debug/Contextify.app
./scripts/logging/monitor-transcript-queues.sh | tee /tmp/v26-ingestion.log

# Compare rate
grep "\[HOOVER-UPDATE-ROWS\]" /tmp/v26-ingestion.log | \
  awk '{print $NF}' | \
  python3 -c "import sys; times=[float(l.strip()) for l in sys.stdin]; print(f'Avg entries/batch: {sum(times)/len(times):.1f}')"

# Compare database size
du -h ~/Library/Application\ Support/Contextify/contextify.db
```

**Acceptance criteria:**
- ✅ Ingestion rate within 5% of baseline
- ✅ Database size increase < 20%
- ❌ Abort if: >5% slowdown or >20% size increase

### Storage Analysis

```sql
-- Table sizes
SELECT
  name,
  ROUND(SUM(pgsize) / 1024.0 / 1024.0, 2) as size_mb,
  ROUND(100.0 * SUM(pgsize) / (SELECT SUM(pgsize) FROM dbstat), 1) as pct
FROM dbstat
WHERE name IN (
  'transcript_entries',
  'file_snapshots',
  'tracked_files',
  'transcript_summaries',
  'system_events',
  'queue_operations',
  'timeline_states',
  'queue_operation_results'
)
GROUP BY name
ORDER BY size_mb DESC;

-- Row counts
SELECT
  'transcript_entries' as table_name,
  COUNT(*) as rows
FROM transcript_entries
UNION ALL
SELECT 'queue_operations', COUNT(*) FROM queue_operations
UNION ALL
SELECT 'timeline_states', COUNT(*) FROM timeline_states
UNION ALL
SELECT 'queue_operation_results', COUNT(*) FROM queue_operation_results
UNION ALL
SELECT 'file_snapshots', COUNT(*) FROM file_snapshots;
```

---

## Future Enhancements (Low Priority)

### 1. Metadata Retention Policy

**Goal:** Prevent unbounded growth of metadata tables

**Implementation:**
- Add `scripts/prune_old_metadata.sh` to remove metadata older than N days
- Configurable retention window (default: 90 days)
- Preserve metadata for active/recent transcripts

**Trigger:** If queue metadata tables exceed 20% of transcript_entries size

**Priority:** Low (implement only if storage becomes issue)

**Tracking:** Add TODO to `build/docs/future-features.md`

### 2. JSON Blob Compression

**Goal:** Reduce storage for large metadata payloads

**Implementation:**
- Compress `operation_data`, `state_data`, `result_data` columns
- Use zlib/gzip compression before insert
- Transparent decompression on read

**Trigger:** If average JSON blob > 10KB

**Priority:** Low (implement only if storage metrics show need)

**Tracking:** Add TODO to `build/docs/future-features.md`

### 3. Metadata-Only Transcript Deferral

**Goal:** Prioritize conversational transcripts during ingestion

**Problem:** Transcripts with only metadata records (no conversation entries) block ingestion queue

**Implementation:**
- Add `has_conversation` flag to transcript discovery
- Defer metadata-only transcripts to background queue
- Process conversational transcripts first
- Still ingest metadata, just at lower priority

**Trigger:** If users report slow initial population

**Priority:** Medium (UX improvement)

**Tracking:** Add to `build/docs/future-features.md` under "Ingestion Optimization"

---

## Rollout Checklist

### Pre-Implementation

- [ ] **Phase 0:** Locate repository insert method
  - [ ] File path documented
  - [ ] Method signature confirmed
  - [ ] Extension points identified

- [ ] **Phase 1:** Run schema analysis
  - [ ] `analyze_metadata_schemas.sh` executed
  - [ ] Samples saved to `build/docs/specifications/examples/metadata/`
  - [ ] Field names confirmed (operationId, stateId, resultId)
  - [ ] Join keys validated (operationId exists in both tables)
  - [ ] `claude-code-transcript-format.md` updated
  - [ ] `sql-backend.md` updated

### Implementation

- [ ] **Phase 2:** Database schema
  - [ ] v26 migration added to DatabaseSchema.swift
  - [ ] Schema version updated to 26
  - [ ] Migration tested on dev database

- [ ] **Phase 3:** Models
  - [ ] QueueOperation struct added
  - [ ] TimelineState struct added
  - [ ] QueueOperationResult struct added

- [ ] **Phase 4:** MetadataParseResult
  - [ ] Three new fields added
  - [ ] Init updated
  - [ ] hasMetadata updated

- [ ] **Phase 5:** Metadata parser
  - [ ] queue-operation parser added
  - [ ] timeline-state parser added
  - [ ] queue-operation-result parser added
  - [ ] Telemetry logging added ([META-INGEST])

- [ ] **Phase 6:** MetadataBatch
  - [ ] Three new collections added
  - [ ] add() method updated
  - [ ] isEmpty updated
  - [ ] clear() updated

- [ ] **Phase 7:** Repository
  - [ ] Insert methods added for new types
  - [ ] [HOOVER-UPDATE-ROWS] telemetry extended

- [ ] **Phase 8:** Telemetry
  - [ ] `scripts/logging/README.md` updated
  - [ ] `monitor-metadata-ingestion.sh` created
  - [ ] `analyze-metadata-stats.sh` created

### Testing

- [ ] **Unit tests:**
  - [ ] testParseQueueOperation
  - [ ] testParseTimelineState
  - [ ] testParseQueueOperationResult
  - [ ] testQueueOperationResultJoin
  - [ ] testMetadataBatchAccumulation

- [ ] **Integration tests:**
  - [ ] testQueueMetadataEndToEnd
  - [ ] Transcript fixture with all metadata types

- [ ] **Manual verification:**
  - [ ] Clean database ingestion
  - [ ] Verify counts > 0
  - [ ] Check logs for [META-INGEST]
  - [ ] Test JOIN queries
  - [ ] No [META-INSERT-ERROR] logs

- [ ] **Performance:**
  - [ ] Baseline measurement captured
  - [ ] Post-implementation measurement captured
  - [ ] Ingestion rate within 5% of baseline
  - [ ] Database size increase < 20%

### Documentation

- [ ] `claude-code-transcript-format.md` updated (Phase 1)
- [ ] `sql-backend.md` updated (Phase 1)
- [ ] `scripts/logging/README.md` updated (Phase 8)
- [ ] Future enhancements documented

### Validation

- [ ] All 3 new tables have rows > 0
- [ ] JOIN queries work (operation → result)
- [ ] [META-INGEST] logs show correct types
- [ ] [HOOVER-UPDATE-ROWS] includes queue metadata counts
- [ ] Performance acceptable
- [ ] Storage impact acceptable

---

## Success Criteria

✅ **Documentation complete**
- Real samples captured from transcripts
- Field names confirmed from analysis
- Sections added to claude-code-transcript-format.md and sql-backend.md
- Examples directory populated

✅ **All metadata types stored**
- queue-operation → queue_operations table
- timeline-state → timeline_states table
- queue-operation-result → queue_operation_results table

✅ **Telemetry operational**
- [META-INGEST] logs for each type
- [HOOVER-UPDATE-ROWS] includes queue metadata
- Monitoring scripts functional

✅ **Joins functional**
- operation_id links operations to results
- Query examples work
- Unit tests validate joins

✅ **Performance acceptable**
- Ingestion speed < 5% slower than baseline
- Database size increase < 20%
- No regressions in conversation ingestion

✅ **Tests passing**
- All unit tests pass
- Integration test passes
- Manual verification complete

✅ **Forward compatible**
- JSON blobs preserve unknown fields
- Schema can be refined without breaking changes
- Future metadata types easy to add

---

## Timeline

**Week 1:**
- **Day 1:** Phase 0 (repository location) + Phase 1 (schema analysis)
- **Day 2:** Phase 1 (documentation) + Phase 2 (database schema)
- **Day 3:** Phase 3 (models) + Phase 4 (MetadataParseResult)
- **Day 4-5:** Phase 5 (parser cases) + Phase 6 (MetadataBatch)

**Week 2:**
- **Day 1-2:** Phase 7 (repository) + Phase 8 (telemetry)
- **Day 3:** Unit tests
- **Day 4:** Integration tests + manual verification
- **Day 5:** Performance validation + documentation finalization

**Total: 10 working days**

---

## References

**Code:**
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift:5-10` - Skip list
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift:445-620` - Metadata parser
- `app/Sources/ContextifyCore/Database/HooverEngine.swift:383-433` - Dual-parser flow
- `app/Sources/ContextifyCore/Database/HooverEngine.swift:126-142` - MetadataBatch
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` - Schema migrations
- TBD (Phase 0): Repository insert location

**Documentation:**
- `build/docs/specifications/claude-code-transcript-format.md` - Format specs
- `build/docs/architecture/sql-backend.md` - Database architecture
- `build/docs/specifications/examples/metadata/` - Real samples (Phase 1)
- `scripts/logging/README.md` - Logging tags and scripts

**Commits:**
- `51d4174` - Initial metadata skip fix
- `b7ca8bd` - Extended metadata skip + primer prioritization

---

**Review status:** Three-pass review incorporated + systems review feedback
**Ready for:** Phase 0 (repository location) → Phase 1 (schema analysis)
