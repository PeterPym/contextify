---
title: Claude Code Session Name Integration
created: 2025-12-29
status: draft
priority: P1
todo_id: session-name-display
---

# Claude Code Session Name Integration

## Problem Statement

Claude Code v2.0.64+ supports **named sessions** via `/rename` command. Users can assign meaningful names like `auth-refactor` or `bugfix-123` to their sessions. Currently, Contextify displays sessions using auto-generated summaries or timestamps, missing this user-assigned context.

## Feature Overview (Claude Code)

### User-Facing Commands

```bash
/rename auth-refactor          # Name current session
claude --resume auth-refactor  # Resume by name
/resume auth-refactor          # Resume from REPL
```

### Storage

Session names stored in Claude Code's SQLite database alongside:
- Session ID (UUID)
- Last update timestamp
- Working directory/project path
- Auto-generated summary
- Git branch
- Message count

Transcript files: `~/.claude/projects/[project-hash]/[session-uuid].jsonl`

## Integration Opportunities

### 1. Display Session Name in Timeline (P1)

**Current:** Timeline shows auto-summary or "Session started at..."
**Proposed:** Show user-assigned session name prominently when available

```
┌─────────────────────────────────────────┐
│ auth-refactor                    2:34 PM │  <- Named session
│ Working on OAuth2 integration...         │
├─────────────────────────────────────────┤
│ Session started at 10:15 AM      10:15 AM│  <- Unnamed session
│ Debugging test failures...               │
└─────────────────────────────────────────┘
```

### 2. Search by Session Name (P1)

Add session names to search index so users can find sessions by the names they assigned.

### 3. Session Grouping in History (P2)

Group related sessions (same name prefix) or show session lineage (forks).

### 4. Name Change Tracking (P3)

If a session is renamed, track the history for audit purposes.

## Technical Approach

### Option A: Parse Claude Code's SQLite Database (Recommended)

**Location:** `~/.claude/` (or `$CLAUDE_CONFIG_DIR`)

**Pros:**
- Direct access to authoritative metadata
- Contains all sessions with names
- SQLite is fast and reliable

**Cons:**
- Database schema may change
- Need to handle `CLAUDE_CONFIG_DIR` override
- Adds dependency on Claude Code's internal storage format

**Implementation:**
1. Locate Claude Code's SQLite database
2. Query for session metadata (id, name, timestamp, project)
3. Join with Contextify's transcript records by session ID
4. Store name in Contextify's database for search indexing

### Option B: Extract from JSONL Transcripts

Check if session name appears in transcript metadata records.

**Pros:**
- Uses existing transcript parsing infrastructure
- No new file dependencies

**Cons:**
- Name may not be in transcript (stored separately)
- Would need to verify format

### Option C: Hook into Claude Code Events

Use Claude Code hooks to capture `/rename` events in real-time.

**Pros:**
- Real-time updates
- Clean integration point

**Cons:**
- Only captures new renames (not historical)
- Requires hook setup per user

### Recommended: Option A + C Hybrid

1. **Startup:** Query Claude Code SQLite for all session names
2. **Runtime:** Hook into rename events for real-time updates
3. **Fallback:** Parse transcripts if SQLite unavailable

## Database Schema Changes

```sql
-- Add column to existing transcripts table
ALTER TABLE transcripts ADD COLUMN session_name TEXT;

-- Or create separate metadata table
CREATE TABLE session_metadata (
  session_id TEXT PRIMARY KEY,
  session_name TEXT,
  source TEXT,  -- 'claude_db', 'hook', 'manual'
  updated_at INTEGER
);
```

## UI Changes

### Timeline View

```swift
// In TranscriptRowView or equivalent
var displayName: String {
  if let name = transcript.sessionName, !name.isEmpty {
    return name
  }
  return transcript.autoSummary ?? "Session \(transcript.sessionId.prefix(8))"
}
```

### Search

Add `session_name` to FTS index alongside existing searchable fields.

## Open Questions

1. **SQLite location:** Is Claude Code's database always in `~/.claude/` or is there a settings.json that specifies it?

2. **Schema stability:** How stable is Claude Code's internal database schema? Should we treat it as public API or be defensive?

3. **Sync frequency:** How often should we refresh session names from Claude Code's database?

4. **CLAUDE_CONFIG_DIR:** Should Contextify honor this env var for finding Claude Code data?

5. **Codex CLI:** Does Codex have equivalent session naming? Need to check.

## Implementation Plan

### Phase 1: Research & Validate (P1)
- [ ] Locate and inspect Claude Code's SQLite database schema
- [ ] Verify session name storage location
- [ ] Check if name appears in JSONL transcripts
- [ ] Test with `CLAUDE_CONFIG_DIR` override

### Phase 2: Core Integration (P1)
- [ ] Add `session_name` column to Contextify schema
- [ ] Implement SQLite reader for Claude Code metadata
- [ ] Populate session names on transcript ingest
- [ ] Display in timeline view

### Phase 3: Search Integration (P1)
- [ ] Add session_name to search index
- [ ] Update search UI to show name matches

### Phase 4: Real-time Updates (P2)
- [ ] Implement Claude Code hook for rename events
- [ ] Update Contextify in real-time when sessions renamed

## Success Criteria

1. Named sessions display their user-assigned name in Contextify timeline
2. Users can search for sessions by name
3. Unnamed sessions gracefully fall back to auto-summary
4. Works with both Claude Code and (potentially) Codex CLI

## References

- Research: `/tmp/claude-code-labeling-research.md`
- Claude Code docs: https://code.claude.com/docs/en/common-workflows
- Transcript format spec: `build/docs/specifications/transcript-formats.md`
