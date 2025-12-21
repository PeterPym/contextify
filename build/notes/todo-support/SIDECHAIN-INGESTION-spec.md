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

### Agent Transcript Structure

Each agent-*.jsonl file contains:
- `agentId`: Matches filename suffix (e.g., `agent-a54dafc.jsonl` has `agentId: "a54dafc"`)
- `sessionId`: Points to parent main session UUID
- `isSidechain: true`: Marker on all records
- Records: Typically 1-5 user/assistant message pairs
- Content: The subagent's internal conversation (tool uses, reasoning, responses)

### Current Exclusion Points

1. **Parser level** (`TranscriptParsers.swift:163-164`):
   ```swift
   if (json["isSidechain"] as? Bool) == true {
       // skipped
   }
   ```

2. **Query level** (`TranscriptOrchestrator.swift:2342`):
   ```sql
   AND t.file_path NOT LIKE '%/agent-%'
   ```

3. **Priority level** (`FastPathIngestionCoordinator.swift:582-586`):
   Agent files sorted last during ingestion.

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
- Content increase: ~1 MB (4,245 × 239 bytes)
- With indexes and overhead: **2-5 MB increase**

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
```

---

## Proposed Solution: Option A (Simple Columns)

Add columns to `transcript_entries` to track tool invocation metadata and sidechain linkage.

### Schema Changes (Migration v27+)

```sql
ALTER TABLE transcript_entries ADD COLUMN tool_name TEXT;
ALTER TABLE transcript_entries ADD COLUMN tool_key TEXT;
ALTER TABLE transcript_entries ADD COLUMN tool_use_id TEXT;
ALTER TABLE transcript_entries ADD COLUMN parent_agent_id TEXT;
ALTER TABLE transcript_entries ADD COLUMN is_sidechain INTEGER DEFAULT 0;

CREATE INDEX idx_entries_tool_key ON transcript_entries(tool_key);
CREATE INDEX idx_entries_parent_agent ON transcript_entries(parent_agent_id);
CREATE INDEX idx_entries_sidechain ON transcript_entries(is_sidechain);
```

### Column Definitions

| Column | Type | Purpose |
|--------|------|---------|
| `tool_name` | TEXT | Tool type: "Skill", "Task", "Bash", etc. |
| `tool_key` | TEXT | Specific identifier: skill name or subagent_type |
| `tool_use_id` | TEXT | Links tool_use to tool_result |
| `parent_agent_id` | TEXT | For sidechain entries, links to parent agent |
| `is_sidechain` | INTEGER | 1 if from agent-*.jsonl, 0 otherwise |

### Parser Changes

1. Remove `isSidechain` skip in `TranscriptParsers.swift`
2. Extract tool metadata from `tool_use` blocks
3. Populate new columns during parsing
4. Link sidechain entries via `agentId` -> main transcript's Task `tool_use_id`

### Query Changes

1. Remove `NOT LIKE '%/agent-%'` filter in `TranscriptOrchestrator.swift`
2. Add `WHERE is_sidechain = 0` to timeline queries (preserve current behavior)
3. Add new queries for sidechain exploration

---

## Migration Path: Option A to Option B

If future requirements demand more sophisticated tool chain tracking, Option A can migrate to Option B (dedicated table) as follows:

### Option B Schema (Future)

```sql
CREATE TABLE tool_invocations (
  id TEXT PRIMARY KEY,
  entry_id TEXT NOT NULL REFERENCES transcript_entries(id),
  parent_invocation_id TEXT REFERENCES tool_invocations(id),
  tool_name TEXT NOT NULL,
  tool_key TEXT,
  tool_use_id TEXT,
  sidechain_transcript_id TEXT REFERENCES transcripts(id),
  started_at INTEGER,
  completed_at INTEGER,
  status TEXT,
  metadata_json TEXT
);

CREATE INDEX idx_invocations_entry ON tool_invocations(entry_id);
CREATE INDEX idx_invocations_parent ON tool_invocations(parent_invocation_id);
CREATE INDEX idx_invocations_sidechain ON tool_invocations(sidechain_transcript_id);
```

### Migration Steps

1. Create `tool_invocations` table
2. Populate from existing `transcript_entries` columns:
   ```sql
   INSERT INTO tool_invocations (id, entry_id, tool_name, tool_key, tool_use_id)
   SELECT
     id || '-inv',
     id,
     tool_name,
     tool_key,
     tool_use_id
   FROM transcript_entries
   WHERE tool_name IS NOT NULL;
   ```
3. Build parent-child relationships from `parent_agent_id`
4. Optionally drop columns from `transcript_entries` (or keep for backward compat)

### When to Consider Option B

- Need to track multi-level tool chains (agent -> skill -> tool)
- Need to store invocation timing/status separate from entry content
- Need to query tool usage patterns across entries
- Need to link sidechains to specific parent invocations (not just entries)

---

## Implementation Plan (Draft)

### Phase 1: Schema & Parser
- [ ] Add schema migration v27 with new columns
- [ ] Update `TranscriptParsers.swift` to extract tool metadata
- [ ] Update `TranscriptParsers.swift` to allow sidechain records
- [ ] Add unit tests for tool metadata extraction

### Phase 2: Ingestion Pipeline
- [ ] Remove `NOT LIKE '%/agent-%'` filter in ingestion queries
- [ ] Update FastPath priority (agents still lower priority, but processed)
- [ ] Add `is_sidechain` population during parse
- [ ] Add parent linkage via `agentId` -> `tool_use_id` matching

### Phase 3: UI/Query Changes
- [ ] Add `WHERE is_sidechain = 0` to timeline queries
- [ ] (Future) Add UI to explore sidechain content
- [ ] (Future) Add search to include sidechain entries

### Phase 4: Testing
- [ ] Unit tests for sidechain parsing
- [ ] Integration test with real agent transcripts
- [ ] Verify no regression in main transcript display
- [ ] Verify database size increase is within estimate

---

## Open Questions

1. **Should sidechain entries appear in timeline?** (Recommend: No, filter by default)
2. **Should sidechain content be searchable?** (Recommend: Yes, include in FTS)
3. **How to handle orphaned sidechains?** (Agent file exists but parent transcript deleted)
4. **Priority vs main transcripts?** (Keep lower priority, process after mains)

---

## Related Work

- **DECORATE-CONTEXTIFY-CALLS**: Uses same tool metadata extraction, but only for decoration (no sidechain ingestion). Uses Option A schema.
