---
todo_id: P1-CONTEXT-REINJECTION
title: Claude Code Research Report - Database Integration Architecture
type: investigation
date: 2025-12-05
status: active
description: Claude Code response to database integration research prompt
source: Claude Code session using P1-CONTEXT-REINJECTION-cli-research-prompt.md
related:
  - P3-RESTORE-HTTP-API
  - P1-CONTEXT-REINJECTION-cli-research-prompt.md
  - P1-CONTEXT-REINJECTION-codex-research-report.md
---

# Contextify Database Integration for AI Coding Assistants

**Research Report**
**Date:** 2025-12-05
**Status:** Research Complete

---

## 1. Executive Summary

### Recommendation

**Primary Architecture: MCP Server (stdio-based) with CLI Fallback**

After comprehensive evaluation of six integration approaches, I recommend a **phased implementation** centered on an MCP server with a companion CLI tool as fallback:

| Phase | Deliverable | Timeline Priority |
|-------|-------------|-------------------|
| **Phase 1 (MVP)** | CLI companion tool (`contextify-query`) | First |
| **Phase 2** | MCP server for Claude Code | Second |
| **Phase 3** | Skill definition + discovery file | Third |
| **Phase 4** | Codex CLI parity + instrumentation | Fourth |

### Why This Architecture?

1. **CLI-first MVP minimizes risk** - Works immediately with both Claude Code and Codex CLI via shell commands, no server process management, no port conflicts
2. **MCP provides the ideal long-term UX** - Claude Code treats MCP as first-class; tools appear natively without shell command overhead
3. **Skills bias tool selection** - Address the "choosing to use it" problem by explicitly declaring database tools as preferred
4. **Layered approach allows iteration** - Each phase is independently valuable; can stop at any phase if costs exceed benefits

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Transport | stdio (not HTTP) | Works with both Claude Code and Codex CLI; no port management |
| Query model | High-level tools (not raw SQL) | Security, schema evolution, better LLM reasoning |
| Discovery | State file + UserDefaults | Decouples from running app; supports all DB locations |
| Sandbox handling | CLI reads discovery file | Avoids MCP server needing security-scoped access |

### Short-term vs Long-term

**Short-term (MVP):**
- Ship `contextify-query` CLI with 5-6 query presets
- Write `~/.config/contextify/state.json` discovery file from app
- Document in CLAUDE.md for immediate use

**Long-term (Ideal):**
- MCP server with dynamic tool registration
- Skill definition for tool selection bias
- Instrumentation for adoption measurement
- Codex CLI config templates

---

## 2. Detailed Evaluation Matrix

### 2.1 Comparison Table

| Criterion | MCP Server | REST API | CLI Tool | Raw SQL Docs | Skill | Subagent |
|-----------|------------|----------|----------|--------------|-------|----------|
| **Implementation Complexity** | Medium | Medium | Low | Very Low | Low | Medium |
| **Reliability** | High | Medium | Very High | Low | N/A | High |
| **Query Expressiveness** | High | High | Medium | Very High | N/A | High |
| **Performance (latency)** | ~50ms | ~100ms | ~200ms | ~50ms | N/A | ~300ms |
| **Security** | Good | Medium | Very Good | Poor | N/A | Good |
| **Schema Evolution** | Good | Good | Good | Poor | N/A | Good |
| **Degraded Operation** | Requires app | Requires app | Works offline | Works offline | N/A | Requires MCP |
| **Claude Code Support** | Native | Via curl | Via Bash | Via sqlite3 | Native | Native |
| **Codex CLI Support** | stdio only | Via curl | Via Bash | Via sqlite3 | No | No |
| **Adoption Likelihood** | High | Medium | Medium | Low | Amplifier | Amplifier |

### 2.2 Detailed Analysis by Approach

#### (a) MCP Server

**Implementation:**
- ~300-500 lines TypeScript/Python
- Uses `@modelcontextprotocol/sdk` or `fastmcp`
- Exposes 5-8 high-level query tools
- Configured in `~/.claude.json` or `.mcp.json`

**Strengths:**
- Native Claude Code integration (tools appear in tool list)
- Dynamic capability negotiation (schema changes don't break client)
- Best user experience (no shell command overhead)
- Supports structured responses

**Weaknesses:**
- Requires process management (app must spawn server or run separately)
- Codex CLI only supports stdio transport
- Discovery requires Contextify to run first (or discovery file)

**Configuration Example:**
```json
{
  "mcpServers": {
    "contextify": {
      "type": "stdio",
      "command": "contextify-mcp",
      "env": {
        "CONTEXTIFY_DB": "${HOME}/Library/Application Support/Contextify/contextify.db"
      }
    }
  }
}
```

#### (b) REST API on localhost

**Implementation:**
- ~400-600 lines Swift (embedded in Contextify app)
- HTTP server on localhost (e.g., port 19432)
- JSON endpoints for queries
- Requires app to be running

**Strengths:**
- Can leverage existing app infrastructure
- Easy to add new endpoints
- Works with any HTTP client

**Weaknesses:**
- Port conflicts possible
- Firewall/security prompts on macOS
- **App Store sandbox restrictions** - sandboxed apps cannot bind to localhost ports without com.apple.security.network.server entitlement (may complicate review)
- Requires app to be running

**Sandbox Issue:**
App Store builds would need `com.apple.security.network.server` entitlement, which:
1. Requires justification during App Store review
2. May be rejected for a "monitoring" app
3. Creates attack surface perception

**Recommendation:** Avoid for App Store builds; acceptable for DMG-only feature.

#### (c) CLI Companion Tool

**Implementation:**
- ~200-400 lines Swift or shell script
- Bundled with Contextify.app or standalone install
- Reads discovery file for DB location
- Outputs JSON for machine parsing

**Strengths:**
- Works offline (no running app needed)
- Works with both Claude Code and Codex CLI
- Simple error handling (exit codes)
- No port management or process lifetime issues
- **Sandbox-safe** - external binary has no sandbox restrictions

**Weaknesses:**
- Shell command overhead (~200ms startup)
- Less discoverable than MCP tools
- Requires separate installation/PATH management
- Query patterns limited to predefined subcommands

**Example Usage:**
```bash
# Search entries across all projects
contextify-query search "authentication bug" --limit 20

# Get recent activity for current project
contextify-query activity --project "$(pwd)" --days 7

# List all summaries
contextify-query summaries --project-id "abc123"
```

#### (d) Raw SQL Documentation

**Implementation:**
- ~50-100 lines documentation
- Schema reference in CLAUDE.md
- Example queries for common patterns

**Strengths:**
- Zero code to maintain
- Maximum query flexibility
- Works immediately

**Weaknesses:**
- **Schema changes break queries** - pre-1.0 app will evolve
- No validation (SQL injection risk if LLM generates bad queries)
- Requires LLM to understand SQLite + GRDB conventions
- **WAL mode complications** - concurrent access can cause SQLITE_BUSY
- No structured output format

**Schema Stability Assessment:**
Current schema is v28. Migrations v16-v28 show active evolution:
- v27: Added `is_queued` column
- v28: Added FTS5 search index
- v29: Added summaries to FTS

**Recommendation:** Useful as fallback documentation, not primary integration.

#### (e) Skill Definition

**Implementation:**
- ~50 lines Markdown with YAML frontmatter
- Placed in `.claude/skills/` or `~/.claude/skills/`
- References MCP tools or CLI commands

**Strengths:**
- **Biases tool selection** - Claude prioritizes skill-approved tools
- Provides context and usage guidelines
- No code to maintain (just documentation)
- Works with existing tools (MCP or CLI)

**Weaknesses:**
- Not a standalone solution (requires underlying tools)
- Claude Code-only (Codex CLI has no skill support)
- Activation is model-driven (may not always trigger)

**Example Skill:**
```yaml
---
name: contextify-history
description: Query conversation history from Contextify database. Use this instead of reading raw transcript files when you need to search past conversations, find related discussions, or understand project history.
allowed-tools:
  - mcp__contextify__search_entries
  - mcp__contextify__get_summaries
  - mcp__contextify__recent_activity
  - Bash(contextify-query *)
---

# Contextify History Assistant

When the user asks about past conversations or project history:
1. Use the Contextify database tools (preferred) over reading raw JSONL files
2. The database contains pre-parsed, indexed, and summarized content
3. Use `search_entries` for text search, `get_summaries` for high-level overviews
```

#### (f) Subagent Definition

**Implementation:**
- ~30 lines YAML configuration
- Placed in `.claude/agents/`
- Scoped tool access and system prompt

**Strengths:**
- Isolated context window (doesn't pollute main conversation)
- Can restrict tool access for security
- Good for complex multi-step analysis

**Weaknesses:**
- Overkill for simple queries
- Additional latency (agent handoff)
- Claude Code-only (Codex CLI has limited subagent support)
- Requires underlying MCP/CLI tools

**Recommendation:** Useful for complex historical analysis tasks, not everyday queries.

---

## 3. Recommended Architecture

### 3.1 System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     AI Coding Assistant                          │
│                  (Claude Code / Codex CLI)                       │
└──────────────┬────────────────────────────────────┬─────────────┘
               │                                    │
               │ MCP Protocol (stdio)               │ Shell Command
               │ (Phase 2+)                         │ (Phase 1)
               ▼                                    ▼
┌──────────────────────────┐        ┌──────────────────────────────┐
│    contextify-mcp        │        │    contextify-query          │
│    (MCP Server)          │        │    (CLI Tool)                │
│                          │        │                              │
│  - search_entries        │        │  - search <query>            │
│  - get_summaries         │        │  - activity [--days N]       │
│  - recent_activity       │        │  - summaries [--project]     │
│  - project_stats         │        │  - stats                     │
│  - fts_search            │        │  - fts <query>               │
└──────────────┬───────────┘        └──────────────┬───────────────┘
               │                                    │
               │ Both read from:                    │
               ▼                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│              ~/.config/contextify/state.json                     │
│                      (Discovery File)                            │
│                                                                  │
│  {                                                               │
│    "database_path": "/path/to/contextify.db",                   │
│    "schema_version": 28,                                        │
│    "build_type": "dmg",                                         │
│    "app_version": "0.9.5",                                      │
│    "last_updated": "2025-12-05T10:30:00Z",                      │
│    "capabilities": ["fts_search", "summaries", "usage_stats"]   │
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘
               │
               │ SQLite (read-only)
               ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Contextify Database                            │
│           ~/Library/Application Support/Contextify/              │
│                     contextify.db                                │
│                                                                  │
│  Tables: projects, transcripts, transcript_entries,              │
│          timeline_cache, transcript_metadata, ...                │
│  FTS: transcript_entries_fts (v28+)                              │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Discovery File Specification

**Location:** `~/.config/contextify/state.json`

**Written by:** Contextify app on startup and when database location changes

**Schema:**
```json
{
  "$schema": "https://contextify.sh/schemas/state-v1.json",
  "database_path": "/Users/rob/Library/Application Support/Contextify/contextify.db",
  "schema_version": 28,
  "build_type": "dmg",
  "app_version": "0.9.5",
  "last_updated": "2025-12-05T10:30:00Z",
  "capabilities": [
    "fts_search",
    "summaries",
    "usage_stats",
    "project_metadata"
  ],
  "tools_available": {
    "cli": "/Applications/Contextify.app/Contents/MacOS/contextify-query",
    "mcp": null
  }
}
```

**Discovery Logic (in tools):**
```python
def discover_database():
    # 1. Check discovery file
    state_path = Path.home() / ".config" / "contextify" / "state.json"
    if state_path.exists():
        state = json.loads(state_path.read_text())
        db_path = Path(state["database_path"])
        if db_path.exists():
            return db_path, state["schema_version"]

    # 2. Fallback to UserDefaults (macOS only)
    result = subprocess.run(
        ["defaults", "read", "dev.contextify", "dev.contextify.customDatabaseLocation"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        custom_dir = result.stdout.strip()
        db_path = Path(custom_dir) / "contextify.db"
        if db_path.exists():
            return db_path, None  # Unknown version

    # 3. Default location
    default_path = Path.home() / "Library" / "Application Support" / "Contextify" / "contextify.db"
    if default_path.exists():
        return default_path, None

    raise FileNotFoundError("Contextify database not found")
```

### 3.3 Tool Definitions

#### MCP Tools (Phase 2)

| Tool | Description | Parameters |
|------|-------------|------------|
| `search_entries` | Full-text search across conversation content | `query: string`, `limit?: int`, `project_id?: string` |
| `get_summaries` | Get LLM-generated session summaries | `project_id?: string`, `days?: int`, `limit?: int` |
| `recent_activity` | Get recent conversation entries | `project_id?: string`, `hours?: int`, `limit?: int` |
| `project_stats` | Get project statistics (entry count, date range) | `project_id: string` |
| `fts_search` | FTS5 search with ranking | `query: string`, `limit?: int` |
| `get_entry_context` | Get entry with surrounding context | `entry_id: string`, `context_lines?: int` |

#### CLI Subcommands (Phase 1)

```bash
contextify-query search <query> [--limit N] [--project PATH]
contextify-query activity [--hours N] [--project PATH]
contextify-query summaries [--days N] [--project PATH]
contextify-query stats [--project PATH]
contextify-query fts <query> [--limit N]
contextify-query schema-version  # For compatibility checks
contextify-query --json  # Machine-readable output
```

### 3.4 Sandbox Compatibility

| Component | DMG Build | App Store Build |
|-----------|-----------|-----------------|
| Discovery file write | Works | Works (file is outside sandbox) |
| CLI tool access to DB | Works | Works (CLI is not sandboxed) |
| MCP server access to DB | Works | Works if launched externally |
| REST API on localhost | Works | **Blocked** (needs entitlement) |

**Key insight:** The CLI tool and MCP server run as separate processes outside the app sandbox. They only need read access to the SQLite database file, which is possible because:

1. Database is in `~/Library/Application Support/` (user-writable)
2. Custom locations are user-chosen (explicit permission)
3. Discovery file in `~/.config/` is always accessible

### 3.5 Schema Version Handling

**Strategy:** Capability-based negotiation

1. Discovery file includes `schema_version` and `capabilities` array
2. Tools check version before executing queries
3. If version mismatch:
   - For minor changes: Warn but proceed
   - For breaking changes: Return error with upgrade instructions

**Example:**
```python
def check_compatibility(state):
    if state["schema_version"] < 28:
        if "fts_search" in requested_tools:
            raise IncompatibleSchemaError(
                "FTS search requires Contextify 0.9.5+ (schema v28). "
                "Please update Contextify."
            )
    return True
```

---

## 4. Implementation Roadmap

### Phase 0: Baseline (Current State)

**What exists today:**
- Database at `~/Library/Application Support/Contextify/contextify.db`
- Custom location in UserDefaults: `dev.contextify.customDatabaseLocation`
- Schema v28 with FTS5 search
- No external query interface

**Cost:** $0 (already done)

**Capabilities:**
- Manual `sqlite3` queries possible but undocumented
- No discovery mechanism for external tools

### Phase 1: CLI Tool + Discovery File (MVP)

**Deliverables:**
1. `contextify-query` CLI binary (Swift, bundled in app)
2. Discovery file writer in Contextify app
3. CLAUDE.md documentation update

**Implementation Steps:**

1. **Add discovery file writer** (~50 lines Swift)
   - Write `~/.config/contextify/state.json` on app startup
   - Update when database location changes
   - Include schema version, capabilities, tool paths

2. **Create CLI tool** (~300 lines Swift)
   - Subcommands: search, activity, summaries, stats, fts
   - Read discovery file for DB location
   - Output JSON for machine parsing
   - Handle missing/locked DB gracefully

3. **Bundle CLI in app** (build system change)
   - Add CLI target to Xcode project
   - Copy to `Contents/MacOS/` in app bundle
   - Symlink to `/usr/local/bin/` on install (optional)

4. **Document in CLAUDE.md** (~100 lines)
   - Tool descriptions and examples
   - When to use DB queries vs raw files
   - Error handling guidance

**Estimated Effort:** 2-3 days

**Go/No-Go Checkpoint:**
- Does the CLI work reliably?
- Is discovery file written correctly?
- Does Claude Code actually use it when prompted?

### Phase 2: MCP Server

**Deliverables:**
1. `contextify-mcp` stdio server (TypeScript or Python)
2. Claude Code configuration template
3. Updated skill definition

**Implementation Steps:**

1. **Create MCP server** (~400 lines)
   - Use `fastmcp` (Python) or `@modelcontextprotocol/sdk` (TypeScript)
   - Implement 6 tools from specification
   - Read discovery file for DB location
   - Handle connection lifecycle

2. **Add Claude Code configuration**
   - `.mcp.json` template in repo
   - Installation instructions

3. **Create skill definition**
   - Bias tool selection toward MCP tools
   - Provide usage context

**Estimated Effort:** 3-4 days

**Go/No-Go Checkpoint:**
- Does MCP server start reliably?
- Are tools discovered by Claude Code?
- Is there measurable adoption vs Phase 1?

### Phase 3: Skill + Instrumentation

**Deliverables:**
1. Polished skill definition
2. Usage instrumentation
3. Subagent for complex analysis (optional)

**Implementation Steps:**

1. **Refine skill definition**
   - Add more context about when to use
   - Include example queries
   - Test activation patterns

2. **Add instrumentation** (~100 lines)
   - Log query events to separate file
   - Track tool usage vs raw file access
   - Privacy-preserving (no content, just metadata)

3. **Optional: Analysis subagent**
   - For complex multi-step historical analysis
   - Dedicated context window

**Estimated Effort:** 2-3 days

### Phase 4: Codex CLI Parity

**Deliverables:**
1. Codex CLI config template (`~/.codex/config.toml`)
2. Documentation for Codex users
3. Possible `codex-mcp` wrapper if needed

**Implementation Steps:**

1. **Create Codex config template**
   ```toml
   [mcp_servers.contextify]
   command = "contextify-mcp"
   args = []
   env = {}
   ```

2. **Test with Codex CLI**
   - Verify stdio transport works
   - Check tool discovery
   - Document any differences

3. **Update documentation**
   - Add Codex-specific instructions
   - Note any limitations

**Estimated Effort:** 1-2 days

### Rollback Options

| Phase | Rollback Strategy |
|-------|-------------------|
| Phase 1 | Remove CLI binary, delete discovery file writer |
| Phase 2 | Users remove MCP config; CLI still works |
| Phase 3 | Remove skill file; tools still work |
| Phase 4 | Codex users remove config; Claude Code unaffected |

---

## 5. Maintenance Cost Analysis

### 5.1 User Costs

| Cost Type | Phase 1 (CLI) | Phase 2 (MCP) | Phase 3 (Skill) |
|-----------|---------------|---------------|-----------------|
| **Initial Setup** | None (bundled) | Add config to ~/.claude.json | Copy skill file |
| **Ongoing** | App updates | App + config updates | Skill file sync |
| **Failure Recovery** | Re-run app | Check MCP process | Re-copy skill |

**Failure Modes:**
- **DB missing:** Clear error message, suggest running Contextify
- **Schema mismatch:** Version warning, suggest app update
- **MCP not starting:** Fallback to CLI tool

### 5.2 Developer Costs

| Cost Type | Phase 1 | Phase 2 | Phase 3+ |
|-----------|---------|---------|----------|
| **Initial Implementation** | 2-3 days | 3-4 days | 2-3 days |
| **Schema Migration** | Update CLI queries | Update MCP tools | None |
| **Documentation** | CLI reference | MCP + Claude config | Skill guide |
| **Testing** | CLI unit tests | MCP integration tests | Manual testing |

**Schema Migration Impact:**
- New columns: Usually no change needed (queries select specific columns)
- Renamed columns: Update queries in CLI/MCP
- New tables: Add new tools/subcommands
- Breaking changes: Version check + error message

### 5.3 Token/Latency Overhead

| Operation | Tokens | Latency | Notes |
|-----------|--------|---------|-------|
| CLI discovery | ~50 | ~200ms | One-time per session |
| CLI query | ~100-500 | ~200-400ms | Depends on result size |
| MCP tool call | ~50-200 | ~50-100ms | Lower latency than CLI |
| Raw file scan | ~1000+ | ~500ms+ | Often needs multiple files |

**Net effect:** Database queries typically use fewer tokens and lower latency than raw file parsing, especially for search operations.

---

## 6. Effectiveness Measurement

### 6.1 Adoption Metrics

**What to measure:**
1. Tool invocation count (by tool name)
2. Success/failure rate
3. Fallback to raw file access
4. Query latency distribution

**Instrumentation approach:**
```json
// ~/.local/share/contextify/query-log.jsonl
{"ts": "2025-12-05T10:30:00Z", "tool": "search_entries", "success": true, "latency_ms": 150, "result_count": 5}
{"ts": "2025-12-05T10:30:05Z", "tool": "fts_search", "success": false, "error": "schema_version_mismatch"}
```

**Privacy considerations:**
- No query content logged
- No result content logged
- Only metadata (tool name, success, latency, counts)
- Local-only by default
- Opt-in for any telemetry

### 6.2 Quality Metrics

**Accuracy baseline:**
1. Define 10 reference queries with known-good answers
2. Run queries via DB tools vs raw file parsing
3. Compare accuracy and completeness

**Example reference queries:**
1. "Find all discussions about authentication in project X"
2. "What files were modified in the last session?"
3. "Show me the summary of yesterday's work"
4. "When did we discuss the database schema?"
5. "List all projects with activity in the last week"

### 6.3 A/B Testing

**Methodology:**
1. Enable DB tools for 50% of sessions (based on session ID hash)
2. Track query patterns and fallback rates
3. Compare token usage and latency

**Signals to watch:**
- Higher fallback rate in DB group = tools not being discovered/used
- Lower fallback rate = tools working as intended
- Similar query count = no change in behavior

---

## 7. Open Questions for the App Developer

### Critical Questions (Block Implementation)

1. **Long-running processes:** Is it acceptable to spawn a background MCP server process, or must all integration be stateless CLI calls?

2. **CLI bundling:** Should `contextify-query` be:
   - Bundled in app Contents/MacOS/ (easiest)
   - Installed to /usr/local/bin/ (requires installer)
   - Separate Homebrew formula (more maintenance)

3. **Discovery file location:** Is `~/.config/contextify/state.json` acceptable, or should it use:
   - `~/Library/Application Support/Contextify/state.json` (macOS convention)
   - `/tmp/contextify-state.json` (already used for diagnostics)

### Important Questions (Inform Design)

4. **Codex CLI priority:** Should Phase 4 (Codex parity) happen before or after Phase 3 (instrumentation)?

5. **Write operations:** Should we plan for future write operations (adding notes, tags, corrections), or is read-only sufficient for v1?

6. **Schema stability:** Are there any planned breaking schema changes before 1.0 that would affect tool design?

### Nice-to-Know Questions

7. **Telemetry:** Is any form of opt-in usage telemetry acceptable, or must all analytics be local-only?

8. **Third-party tools:** Should the integration be generic enough for other tools (Cursor, Windsurf) to use, or Claude Code/Codex only?

---

## 8. Appendix

### A. Schema Reference (v28)

**Core Tables:**

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `projects` | Project metadata | id, name, root_path, last_viewed_ts, hidden |
| `transcripts` | Transcript files | id, project_id, file_path, provider, status |
| `transcript_entries` | Individual messages | id, transcript_id, project_id, kind, timestamp, content |
| `timeline_cache` | LLM-generated summaries | content_sha256, window_sha256, present_form, past_form |
| `transcript_metadata` | Session summaries | transcript_id, title, description, topics, confidence |

**FTS Table (v28+):**

| Table | Purpose | Indexed Columns |
|-------|---------|-----------------|
| `transcript_entries_fts` | Full-text search | content (with entry_id, project_id, role, created_at unindexed) |

**Key Relationships:**
```
projects (1) ──< transcripts (N) ──< transcript_entries (N)
                                  └──< timeline_cache (1)
```

### B. Example Queries

#### 1. Full-Text Search (FTS5)

```sql
-- Search for "authentication" across all projects
SELECT
  e.id,
  e.project_id,
  e.kind,
  e.timestamp,
  snippet(transcript_entries_fts, 0, '>>>', '<<<', '...', 32) as snippet
FROM transcript_entries_fts fts
JOIN transcript_entries e ON e.id = fts.entry_id
WHERE transcript_entries_fts MATCH 'authentication'
ORDER BY rank
LIMIT 20;
```

#### 2. Recent Activity by Project

```sql
-- Get last 50 entries for a project
SELECT
  e.id,
  e.kind,
  e.timestamp,
  e.content,
  tc.present_form as summary
FROM transcript_entries e
LEFT JOIN timeline_cache tc
  ON tc.content_sha256 = e.content_sha256
  AND tc.window_sha256 = COALESCE(e.window_sha256, '')
WHERE e.project_id = ?
  AND e.display_in_timeline = 1
ORDER BY e.timestamp DESC, e.created_at DESC
LIMIT 50;
```

#### 3. Project Statistics

```sql
-- Get project stats
SELECT
  p.id,
  p.name,
  p.root_path,
  COUNT(DISTINCT t.id) as transcript_count,
  COUNT(e.id) as entry_count,
  MIN(e.timestamp) as first_entry,
  MAX(e.timestamp) as last_entry
FROM projects p
LEFT JOIN transcripts t ON t.project_id = p.id
LEFT JOIN transcript_entries e ON e.transcript_id = t.id
WHERE p.hidden = 0
GROUP BY p.id
ORDER BY MAX(e.timestamp) DESC;
```

#### 4. Session Summaries

```sql
-- Get summaries for recent sessions
SELECT
  tm.transcript_id,
  tm.title,
  tm.description,
  tm.topics,
  tm.confidence,
  tm.generated_at,
  t.file_path,
  p.name as project_name
FROM transcript_metadata tm
JOIN transcripts t ON t.id = tm.transcript_id
JOIN projects p ON p.id = tm.project_id
WHERE tm.generated_at > strftime('%s', 'now', '-7 days')
ORDER BY tm.generated_at DESC
LIMIT 20;
```

#### 5. Unread Entries

```sql
-- Get unread entries for a project
SELECT
  e.id,
  e.kind,
  e.timestamp,
  e.content
FROM transcript_entries e
JOIN projects p ON p.id = e.project_id
WHERE e.project_id = ?
  AND e.display_in_timeline = 1
  AND e.created_ts > p.last_viewed_ts
ORDER BY e.created_ts ASC;
```

#### 6. Token Usage Statistics

```sql
-- Get token usage by model
SELECT
  au.model,
  COUNT(*) as request_count,
  SUM(au.input_tokens) as total_input,
  SUM(au.output_tokens) as total_output,
  SUM(au.cache_read_tokens) as total_cache_read
FROM assistant_usage au
JOIN transcript_entries e ON e.id = au.entry_id
WHERE e.timestamp > strftime('%s', 'now', '-24 hours')
GROUP BY au.model
ORDER BY total_output DESC;
```

### C. CLI Tool Specification

```
contextify-query - Query Contextify database from command line

USAGE:
    contextify-query <COMMAND> [OPTIONS]

COMMANDS:
    search <query>     Full-text search across entries
    activity           Get recent conversation activity
    summaries          Get session summaries
    stats              Get project statistics
    fts <query>        FTS5 search with ranking
    version            Show schema and app version

GLOBAL OPTIONS:
    --project <PATH>   Filter by project path (default: current directory)
    --project-id <ID>  Filter by project ID
    --limit <N>        Maximum results (default: 20)
    --json             Output as JSON (default: human-readable)
    --db <PATH>        Override database path
    --verbose          Show debug information

EXAMPLES:
    # Search for "bug fix" in current project
    contextify-query search "bug fix"

    # Get last 24 hours of activity
    contextify-query activity --hours 24

    # Get summaries as JSON
    contextify-query summaries --json --limit 10

    # Check version compatibility
    contextify-query version

EXIT CODES:
    0  Success
    1  Database not found
    2  Schema version mismatch
    3  Query error
    4  Invalid arguments
```

### D. MCP Server Tool Schemas

```typescript
// Tool: search_entries
{
  name: "search_entries",
  description: "Search conversation entries by text content. Use for finding discussions about specific topics.",
  inputSchema: {
    type: "object",
    properties: {
      query: { type: "string", description: "Search query (supports FTS5 syntax)" },
      limit: { type: "integer", default: 20, description: "Maximum results" },
      project_id: { type: "string", description: "Optional project ID filter" }
    },
    required: ["query"]
  }
}

// Tool: get_summaries
{
  name: "get_summaries",
  description: "Get LLM-generated session summaries. Use for high-level overview of past work.",
  inputSchema: {
    type: "object",
    properties: {
      project_id: { type: "string", description: "Optional project ID filter" },
      days: { type: "integer", default: 7, description: "Number of days to look back" },
      limit: { type: "integer", default: 10, description: "Maximum summaries" }
    }
  }
}

// Tool: recent_activity
{
  name: "recent_activity",
  description: "Get recent conversation entries. Use for understanding recent context.",
  inputSchema: {
    type: "object",
    properties: {
      project_id: { type: "string", description: "Optional project ID filter" },
      hours: { type: "integer", default: 24, description: "Hours to look back" },
      limit: { type: "integer", default: 50, description: "Maximum entries" }
    }
  }
}
```

### E. Skill Definition Template

```yaml
---
name: contextify-history
description: |
  Query conversation history from Contextify's indexed database.
  Use this instead of reading raw transcript JSONL files when you need to:
  - Search past conversations for specific topics
  - Find related discussions across sessions
  - Get summaries of previous work
  - Understand project history and context

  The database contains pre-parsed, indexed, and LLM-summarized content
  that is faster and more accurate than re-parsing raw files.
allowed-tools:
  - mcp__contextify__search_entries
  - mcp__contextify__get_summaries
  - mcp__contextify__recent_activity
  - mcp__contextify__project_stats
  - mcp__contextify__fts_search
  - Bash(contextify-query *)
---

# Contextify History Assistant

## When to Use

Use Contextify database tools when:
- User asks about past conversations or "what we discussed"
- Need to find specific topics across multiple sessions
- Want high-level summaries of previous work
- Searching for code changes or decisions made earlier

## When NOT to Use

Use raw file access when:
- Need the exact, unprocessed transcript content
- Debugging transcript parsing issues
- Working with a transcript not yet ingested

## Tool Selection Priority

1. **FTS search** (`fts_search`) - Best for keyword searches
2. **Summaries** (`get_summaries`) - Best for "what did we do" questions
3. **Recent activity** (`recent_activity`) - Best for recent context
4. **Raw files** - Only as fallback if database unavailable

## Example Queries

"Find where we discussed authentication":
→ Use `search_entries` with query "authentication"

"What did we work on yesterday?":
→ Use `get_summaries` with days=1

"Show me recent conversations":
→ Use `recent_activity` with hours=24
```

---

## References

### Contextify Codebase
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` - Schema definition
- `build/docs/operations/DATABASE-LOCATIONS.md` - Location discovery
- `build/docs/architecture/sql-backend.md` - Architecture overview
- `build/docs/architecture/transcript-access-security.md` - Sandbox handling

### Claude Code Documentation
- MCP servers: https://code.claude.com/docs/en/mcp.md
- Skills: https://code.claude.com/docs/en/skills.md
- Subagents: https://code.claude.com/docs/en/sub-agents.md

### Codex CLI Documentation
- CLI reference: https://developers.openai.com/codex/cli/
- MCP configuration: https://developers.openai.com/codex/mcp/
- Config file format: https://developers.openai.com/codex/local-config/

### Model Context Protocol
- Architecture: https://modelcontextprotocol.io/docs/learn/architecture
- Versioning: https://modelcontextprotocol.io/specification/versioning
- Python SDK: https://github.com/modelcontextprotocol/python-sdk
