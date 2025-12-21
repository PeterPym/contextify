---
todo_id: SIDECHAIN-INGESTION
title: Ingest Agent Sidechain Transcripts
type: spec
date: 2025-12-21
status: draft
description: Add ingestion of agent-*.jsonl sidechain transcripts to preserve subagent conversation data.
---

# Sidechain Transcript Ingestion

## Problem Statement

Contextify claims to back up transcript data, but currently excludes **55% of transcript files** (agent sidechains). These files are actively deleted by Claude Code, meaning we're losing data that could otherwise be preserved.

**Who is affected:** Users relying on Contextify as a transcript backup/archive.

**What does success look like:** All agent sidechain transcripts are ingested and searchable, linked to their parent Task invocations.

---

## Investigation Findings (2025-12-21)

### Current State

| Metric | Value |
|--------|-------|
| Total transcripts in DB | 1,732 |
| Agent transcripts (excluded) | 951 (55%) |
| Main transcripts (ingested) | 781 (45%) |
| Agent files still on disk | 888 |
| Agent files already deleted | 63 (7%) |
| Total entries from main | 86,079 |
| Entries from agent | 0 |

### Deletion Timeline

All 63 missing agent files were:
- Discovered: 2025-12-19 (first scan)
- Deleted: Between 2025-12-19 and 2025-12-21

Claude Code actively cleans up agent transcripts within days. Without ingestion, this data is permanently lost.

### Agent Transcript Characteristics

| Metric | Value |
|--------|-------|
| Total file size (all agents) | 18.58 MB |
| Average file size | 20.5 KB |
| Min file size | 329 bytes |
| Max file size | 1.6 MB |
| Total lines (existing files) | 4,245 |
| Average lines per file | 4.7 |

### Why Size Increase is Small

Agent transcripts are "wide but shallow":
- **Wide:** Large file sizes due to tool output payloads (file contents, bash results)
- **Shallow:** Few conversation turns (avg 4.7 lines = 1-5 user/assistant pairs)

We only store summarizable text content (avg 239 bytes/entry), not raw tool outputs.

### Agent Transcript Structure

Each agent-*.jsonl file contains:
- `agentId`: Matches filename suffix (e.g., `agent-a54dafc.jsonl` has `agentId: "a54dafc"`)
- `sessionId`: Points to parent main session UUID
- `isSidechain: true`: Marker on all records
- Records: Typically 1-5 user/assistant message pairs
- Content: The subagent's internal conversation (tool uses, reasoning, responses)

---

## Database Size Impact Estimate

### Current Database
- Size: 188 MB
- Entries: 86,091
- Average content per entry: 239 bytes
- Total content: ~20.5 MB

### Estimated Addition
- New entries: ~4,245 (from 888 existing agent files)
- Entry increase: ~5%
- Content increase: ~1 MB (4,245 x 239 bytes)
- With indexes and overhead: **2-5 MB increase**
- New `tool_invocations` table: ~0.5-1 MB (mostly index overhead)
- **Total estimated increase: 3-6 MB (~2-3%)**

### Queries Used

```sql
-- Total transcripts by type
SELECT
  (SELECT COUNT(*) FROM transcripts) as total,
  (SELECT COUNT(*) FROM transcripts WHERE file_path LIKE '%/agent-%') as agents,
  (SELECT COUNT(*) FROM transcripts WHERE file_path NOT LIKE '%/agent-%') as main;

-- Agent file sizes
SELECT
  SUM(file_size) as total_bytes,
  ROUND(SUM(file_size) / 1024.0 / 1024.0, 2) as total_mb,
  AVG(file_size) as avg_bytes
FROM transcripts
WHERE file_path LIKE '%/agent-%';

-- Verify all agents have 0 entries
SELECT COUNT(DISTINCT t.id)
FROM transcripts t
INNER JOIN transcript_entries e ON e.transcript_id = t.id
WHERE t.file_path LIKE '%/agent-%';

-- Check deletion timeline
SELECT
  datetime(MIN(created_at), 'unixepoch', 'localtime') as earliest,
  datetime(MAX(created_at), 'unixepoch', 'localtime') as latest
FROM transcripts
WHERE file_path LIKE '%/agent-%';
```

---

## Proposed Solution: Option B (Dedicated Table)

Use a dedicated `tool_invocations` table to track tool metadata and sidechain linkage. This approach:
- Cleanly separates tool metadata from entry content
- Enables sophisticated chain tracking (agent -> skill -> tool)
- Supports the DECORATE-CONTEXTIFY-CALLS feature
- Provides a foundation for future tool analytics

### Schema Changes (Migration v27+)

```sql
-- New table for tool invocations
CREATE TABLE tool_invocations (
  id TEXT PRIMARY KEY,
  entry_id TEXT NOT NULL REFERENCES transcript_entries(id) ON DELETE CASCADE,
  transcript_id TEXT NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
  parent_invocation_id TEXT REFERENCES tool_invocations(id) ON DELETE SET NULL,
  tool_name TEXT NOT NULL,              -- "Skill", "Task", "Bash", "Read", etc.
  tool_key TEXT,                        -- skill name or subagent_type
  tool_use_id TEXT,                     -- Claude's tool_use.id for linking
  sidechain_transcript_id TEXT REFERENCES transcripts(id) ON DELETE SET NULL,
  sidechain_agent_id TEXT,              -- agentId from sidechain file
  started_at INTEGER,                   -- timestamp of tool_use
  completed_at INTEGER,                 -- timestamp of tool_result
  status TEXT DEFAULT 'unknown',        -- 'pending', 'completed', 'failed', 'unknown'
  is_contextify INTEGER DEFAULT 0,      -- 1 if this is a Contextify skill/agent call
  metadata_json TEXT,                   -- additional tool-specific data
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Indexes for common queries
CREATE INDEX idx_invocations_entry ON tool_invocations(entry_id);
CREATE INDEX idx_invocations_transcript ON tool_invocations(transcript_id);
CREATE INDEX idx_invocations_parent ON tool_invocations(parent_invocation_id);
CREATE INDEX idx_invocations_sidechain ON tool_invocations(sidechain_transcript_id);
CREATE INDEX idx_invocations_tool_key ON tool_invocations(tool_key);
CREATE INDEX idx_invocations_contextify ON tool_invocations(is_contextify) WHERE is_contextify = 1;

-- Add sidechain marker to transcript_entries (minimal change)
ALTER TABLE transcript_entries ADD COLUMN is_sidechain INTEGER DEFAULT 0;
CREATE INDEX idx_entries_sidechain ON transcript_entries(is_sidechain);
```

### Column Definitions

| Column | Type | Purpose |
|--------|------|---------|
| `id` | TEXT | Primary key (entry_id + tool index or generated) |
| `entry_id` | TEXT | FK to transcript_entries (the tool_use entry) |
| `transcript_id` | TEXT | FK to transcripts (denormalized for query perf) |
| `parent_invocation_id` | TEXT | Self-FK for nested invocations |
| `tool_name` | TEXT | Tool type: "Skill", "Task", "Bash", etc. |
| `tool_key` | TEXT | Specific identifier: skill name or subagent_type |
| `tool_use_id` | TEXT | Claude's tool_use.id for tool_result linking |
| `sidechain_transcript_id` | TEXT | FK to agent-*.jsonl transcript |
| `sidechain_agent_id` | TEXT | agentId from sidechain (for linking) |
| `started_at` | INTEGER | Unix timestamp of invocation start |
| `completed_at` | INTEGER | Unix timestamp of completion |
| `status` | TEXT | Invocation status |
| `is_contextify` | INTEGER | 1 for Contextify skill/agent calls |
| `metadata_json` | TEXT | Additional tool-specific data |

---

## Ingestion Method Audit

All code paths that handle transcript ingestion, parsing, or filtering need analysis.

### Ingestion Pipeline Overview

```
File System
    ↓
TranscriptWatcher / HooverScheduler (file change detection)
    ↓
FastPathIngestionCoordinator (prioritization)
    ↓
ProjectDiscoveryService (discovery triggers)
    ↓
TranscriptOrchestrator.ingestTranscript() (orchestration)
    ↓
HooverEngine (streaming parse + batch insert)
    ↓
TranscriptParsers (Claude/Codex line parsing)
    ↓
Database (transcript_entries + tool_invocations)
```

### Component Analysis Table

| Component | File:Line | Current Behavior | Needs Update | Notes |
|-----------|-----------|------------------|--------------|-------|
| **ClaudeCodeLineParser** | `TranscriptParsers.swift:163-166` | Skips `isSidechain: true` records | **YES** | Remove skip, populate `is_sidechain` field instead |
| **ClaudeCodeLineParser** | `TranscriptParsers.swift:168-350` | Extracts content, ignores tool metadata | **YES** | Add tool_use block extraction for `tool_invocations` |
| **CodexLineParser** | `TranscriptParsers.swift:645-810` | No sidechain handling (Codex has none) | NO | Codex doesn't use sidechains |
| **HooverEngine.storeEntries** | `HooverEngine.swift:721-750` | Inserts transcript_entries only | **YES** | Also insert `tool_invocations` records |
| **HooverEngine.EntryInsert** | `HooverEngine.swift:70-138` | No tool metadata fields | **YES** | Add `isSidechain`, `toolInvocations` array |
| **FastPathIngestionCoordinator** | `FastPathIngestionCoordinator.swift:582-586` | Deprioritizes agent-* files | OPTIONAL | Keep deprioritization (process mains first) or remove |
| **TranscriptOrchestrator** | `TranscriptOrchestrator.swift:2342` | Excludes agent-* from some queries | **YES** | Remove or change to `is_sidechain = 0` filter |
| **TranscriptOrchestrator** | Multiple timeline queries | No sidechain filter | **YES** | Add `WHERE is_sidechain = 0` to preserve UI |
| **TranscriptConverter** | `TranscriptConverter.swift:191-193` | Skips meta/sidechain for format conversion | NO | Converter is for export, not ingestion |
| **DatabaseSchema** | `DatabaseSchema.swift` (migrations) | No tool_invocations table | **YES** | Add migration v27+ |
| **Models.swift** | `Models.swift:104-163` | TranscriptEntry has no sidechain field | **YES** | Add `is_sidechain` column |
| **Models.swift** | N/A | No ToolInvocation model | **YES** | Add new model struct |
| **Repositories.swift** | `Repositories.swift:332-339` | Entry insert only | **YES** | Add ToolInvocationRepository |
| **FTS Triggers** | `DatabaseSchema.swift:616-760` | Index all entries | OPTIONAL | May want to exclude sidechain from FTS or include |

### Detailed Changes Required

#### 1. TranscriptParsers.swift (Critical)

**Current:**
```swift
// Line 163-166
// Skip sidechain messages
if (json["isSidechain"] as? Bool) == true {
    throw ParserError.skipEntry
}
```

**New:**
```swift
// Extract sidechain flag (don't skip)
let isSidechain = (json["isSidechain"] as? Bool) == true
let agentId = json["agentId"] as? String

// Extract tool_use blocks from assistant messages
var toolInvocations: [ToolInvocationInsert] = []
if type == "assistant", let contentBlocks = message["content"] as? [[String: Any]] {
    for block in contentBlocks where block["type"] as? String == "tool_use" {
        let inv = ToolInvocationInsert(
            toolName: block["name"] as? String ?? "unknown",
            toolKey: extractToolKey(from: block),
            toolUseId: block["id"] as? String,
            isContextify: isContextifyTool(block)
        )
        toolInvocations.append(inv)
    }
}

// Return entry with sidechain/tool metadata
return EntryInsert(
    // ... existing fields ...
    isSidechain: isSidechain,
    agentId: agentId,
    toolInvocations: toolInvocations
)
```

#### 2. HooverEngine.swift (Critical)

**Add after line 722 (entry insert):**
```swift
// Insert tool invocations
for invocation in entry.toolInvocations {
    let model = ToolInvocation(
        id: "\(entry.id)-\(invocation.toolUseId ?? UUID().uuidString)",
        entryId: entry.id,
        transcriptId: transcriptId,
        toolName: invocation.toolName,
        toolKey: invocation.toolKey,
        toolUseId: invocation.toolUseId,
        isContextify: invocation.isContextify ? 1 : 0,
        createdAt: now,
        updatedAt: now
    )
    try model.insert(db, onConflict: .ignore)
}
```

#### 3. TranscriptOrchestrator.swift (Critical)

**Timeline queries - add filter:**
```swift
// Before: No sidechain filter
// After: Exclude sidechains from timeline display
WHERE e.display_in_timeline = 1 AND e.is_sidechain = 0
```

**Remove agent-* exclusion (line 2342):**
```swift
// Before:
AND t.file_path NOT LIKE '%/agent-%'

// After: Remove this filter (or replace with is_sidechain check)
```

#### 4. Models.swift (Required)

**Add to TranscriptEntry:**
```swift
public var isSidechain: Int  // SQLite boolean (0=false, 1=true)
```

**Add new model:**
```swift
public struct ToolInvocation: Codable, FetchableRecord, PersistableRecord, Sendable {
    public var id: String
    public var entryId: String
    public var transcriptId: String
    public var parentInvocationId: String?
    public var toolName: String
    public var toolKey: String?
    public var toolUseId: String?
    public var sidechainTranscriptId: String?
    public var sidechainAgentId: String?
    public var startedAt: Int?
    public var completedAt: Int?
    public var status: String
    public var isContextify: Int
    public var metadataJson: String?
    public var createdAt: Int
    public var updatedAt: Int

    public static let databaseTableName = "tool_invocations"
}
```

---

## Integration with DECORATE-CONTEXTIFY-CALLS

The `tool_invocations` table directly enables the decoration feature:

```swift
// Query for Contextify tool invocations
SELECT ti.*, e.id as entry_id
FROM tool_invocations ti
JOIN transcript_entries e ON ti.entry_id = e.id
WHERE ti.is_contextify = 1
  AND e.transcript_id = ?
```

**Decoration rules:**
- `tool_name = "Skill"` AND `tool_key = "query:contextify-reinject"` -> Contextify icon
- `tool_name = "Task"` AND `tool_key = "query:contextify-researcher"` -> Detective + Contextify icon

The DECORATE-CONTEXTIFY-CALLS spec should be updated to reference `tool_invocations` table queries instead of re-parsing transcripts.

---

## Implementation Plan

### Phase 1: Schema & Models
- [ ] Add migration v27 with `tool_invocations` table
- [ ] Add `is_sidechain` column to `transcript_entries`
- [ ] Create `ToolInvocation` model in Models.swift
- [ ] Create `ToolInvocationRepository` in Repositories.swift
- [ ] Add unit tests for new models

### Phase 2: Parser Updates
- [ ] Update `EntryInsert` struct with sidechain/tool fields
- [ ] Modify `ClaudeCodeLineParser` to extract tool_use blocks
- [ ] Remove sidechain skip, populate `isSidechain` instead
- [ ] Add `isContextifyTool()` detection helper
- [ ] Add unit tests for tool extraction

### Phase 3: Ingestion Pipeline
- [ ] Update `HooverEngine.storeEntries()` to insert tool_invocations
- [ ] Remove `NOT LIKE '%/agent-%'` filter in `TranscriptOrchestrator`
- [ ] Add `is_sidechain = 0` filter to timeline queries
- [ ] Update FastPath priority handling (optional: keep deprioritizing)
- [ ] Add integration tests

### Phase 4: Sidechain Linkage
- [ ] Link sidechain entries to parent Task invocations via agentId
- [ ] Populate `sidechain_transcript_id` on tool_invocations
- [ ] Build parent-child invocation relationships
- [ ] Add queries for exploring sidechain content

### Phase 5: UI & Testing
- [ ] Add decoration support using tool_invocations (see DECORATE-CONTEXTIFY-CALLS)
- [ ] (Future) Add UI to explore sidechain content
- [ ] Full regression testing
- [ ] Verify database size within estimate

---

## Open Questions

1. **Should sidechain entries appear in timeline?** (Recommend: No, filter by default)
2. **Should sidechain content be searchable?** (Recommend: Yes, include in FTS)
3. **How to handle orphaned sidechains?** (Agent file exists but parent deleted)
4. **Keep FastPath deprioritization?** (Recommend: Yes, process mains first)
5. **Backfill existing transcripts?** (Recommend: Yes, re-parse with new logic)

---

## Related Work

- **DECORATE-CONTEXTIFY-CALLS**: Uses `tool_invocations` table for decoration (updated spec)
- **Transcript Formats Spec**: Needs update to document tool_use/Skill/Task identification
