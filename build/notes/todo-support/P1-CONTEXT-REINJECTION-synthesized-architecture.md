---
todo_id: P1-CONTEXT-REINJECTION
title: Synthesized Architecture - Database Integration
type: plan
date: 2025-12-05
status: active
description: Synthesized action plan combining Claude Code and Codex research reports
source: Combination of P1-CONTEXT-REINJECTION-claude-code-research-report.md and P1-CONTEXT-REINJECTION-codex-research-report.md
related:
  - P3-RESTORE-HTTP-API
  - P1-CONTEXT-REINJECTION-claude-code-research-report.md
  - P1-CONTEXT-REINJECTION-codex-research-report.md
---

# Contextify Database Integration for AI Coding Assistants

**Integrated Architecture & Action Plan**
**Date:** 2025-12-05

---

## 0. Brief Comparison: Report A vs Report B

* **Where they fully agree**

  * The database should be the *canonical* source of history for Claude Code / Codex, not JSONL.
  * You want **one shared, read-only query layer** over SQLite/GRDB.
  * Two primary transports:

    * **MCP server (stdio)** for first-class Claude Code integration.
    * **Companion CLI (`contextify-query`)** as fallback and Codex CLI integration.
  * A **discovery contract** (state file + prefs) is essential so tools don't guess paths.
  * Everything should be **read-only**, WAL-safe, and version-aware (schema_version + capabilities).
  * REST/localhost HTTP is optional at best and probably not worth the App Store/sandbox friction.

* **Where Report A is stronger**

  * More explicit **tool definitions** (e.g., `search_entries`, `get_summaries`, `recent_activity`, etc.).
  * Clearer, stepwise **Phase breakdown** (Phase 1: CLI, Phase 2: MCP, Phase 3: skills/instrumentation, etc.).
  * Details on **discovery algorithm** (state file → CFPreferences → default path).

* **Where Report B is stronger**

  * Tighter articulation of **design principles**: one query core, thin transports.
  * Better emphasis on **sandbox/App Store constraints** and realistic paths.
  * More concrete **query patterns** (recent feed, unseen since last visit, token rollups, diagnostics).
  * Clearer security posture: **no open ports, read-only everywhere, queries only**.

The integrated plan below keeps the structure and concreteness of Report A, with the sharper architectural framing and constraints from Report B.

---

## 1. Executive Summary

**Goal:** Stop re-parsing JSONL. Make Claude Code and Codex CLI query Contextify's SQLite database directly through a safe, versioned, read-only interface.

**Core decision:** Build **one shared query core**, expose it via **two transports**, and drive adoption using a **discovery file + Claude skill**:

1. **Shared Query Core (GRDB/SQLite, read-only)**

   * Knows the schema (v28/v29+), FTS tables, and canonical query patterns (recent feed, FTS search, summaries, cost rollups, etc.).
   * Enforces **read-only, WAL-safe access** and is aware of `schema_version` and `capabilities`.

2. **Transport #1 - CLI Companion (`contextify-query`)**

   * Short-lived, read-only process with JSON output and clear exit codes.
   * Works for **Claude Code** (via shell) and **Codex CLI** out of the box.
   * Does *not* require the GUI app to be running.

3. **Transport #2 - MCP Server (stdio)**

   * Thin host around the same query core that exposes **high-level tools**, not raw SQL.
   * Claude Code-native: tools appear in its tool list, with schema/capability negotiation.
   * No open ports, no network entitlements: **stdio only**.

4. **Discovery Contract**

   * A small JSON **state file** plus CFPreferences lookup that tells the tools:

     * `db_path`
     * `schema_version`
     * `build_flavor` (dmg/appstore)
     * `capabilities[]` (e.g., `fts_search`, `usage_stats`).
   * This is the *only* supported way to discover the DB; no path guessing.

5. **Steering the LLM**

   * A **Claude Code skill** that explicitly instructs the assistant:

     * Use `contextify-query`/MCP tools for history/search/summaries.
     * Use raw JSONL only as fallback if DB is unavailable.

**Opinionated call to action:**
**Phase 1 (this week):** implement the discovery file + CLI + minimal skill and start *actually using it* yourself in Claude Code/Codex.
**Phase 2 (next):** wrap the query core in an MCP stdio server once you're happy with the CLI UX. Everything else (REST, writes) can wait indefinitely.

---

## 2. Core Architecture

### 2.1 Design Principles

* **Single source of truth:** The SQLite/GRDB database is canonical for all timeline/history/search questions.
* **One query layer, multiple transports:** Query logic lives in one place; CLI and MCP are thin wrappers.
* **Read-only everywhere:** No migrations or writes from tools; they only read and aggregate.
* **Version and capability aware:** Tools check `schema_version` and `capabilities` and fail fast with actionable messages.
* **No open ports:** No localhost HTTP server in the App Store build; no `network.server` entitlement.
* **Sandbox-friendly:** App Store and DMG share the same discovery contract; paths differ, contract doesn't.

### 2.2 High-Level Diagram

```text
Claude Code / Codex CLI
         │
         ├── Shell → contextify-query (CLI)  [Phase 1]
         │
         └── MCP (stdio) → contextify-mcp   [Phase 2]
                          │
                  Shared Query Core (GRDB)
                          │
                   Contextify Database
```

---

## 3. Discovery Contract

### 3.1 State File

**Purpose:** Make the database discoverable and versioned without guessing paths.

**Location (opinionated choice):**

* For simplicity and cross-build consistency, use a **single external path**:

```text
~/.config/contextify/state.json
```

The app writes it; CLI and MCP read it. For App Store builds, the app also stores the real DB in the container, but still writes this external state file with the resolved `db_path`.

**Example schema:**

```json
{
  "$schema": "https://contextify.sh/schemas/state-v1.json",
  "database_path": "/Users/rob/Library/Application Support/Contextify/contextify.db",
  "schema_version": 29,
  "build_flavor": "appstore",
  "app_version": "1.0.0",
  "last_migrated_at": "2025-12-05T10:30:00Z",
  "capabilities": [
    "fts_search",
    "summaries",
    "usage_stats",
    "project_metadata"
  ]
}
```

### 3.2 Resolution Rules (Tools Side)

When CLI or MCP needs the DB:

1. Read `~/.config/contextify/state.json`. If present and `database_path` exists → use it.
2. If missing/stale:

   * Optionally check CFPreferences key `dev.contextify.customDatabaseLocation` for a custom root.
   * As an ultimate fallback, check known defaults (per your `DATABASE-LOCATIONS.md`).
3. If not found, return a **structured error**:
   `"Contextify database not found. Please open Contextify once to initialize it."`

### 3.3 Schema Compatibility

Tools must:

* Compare `schema_version` in the state file to their own supported version.
* If DB is *newer* than the tool: refuse to run and say "update Contextify/CLI".
* If DB is *older*: allow a best-effort run but warn if a requested capability is missing (e.g., FTS).

---

## 4. Shared Query Core

This is the code you write once and reuse from both CLI and MCP.

### 4.1 Responsibilities

* Open the DB with GRDB/SQLite in **read-only mode** with WAL-safe options.
* Implement a stable set of **canonical queries**, for example:

1. **Recent Activity (project feed)**

   * Inputs: `project_id`, `limit`, `since` (optional)
   * Output: entries where `display_in_timeline=1`, ordered by `timestamp DESC`.
   * Join with `timeline_cache` for summary/disposition where available.

2. **Unseen Since Last Visit**

   * Inputs: `project_id`
   * Output: entries with `created_ts > projects.last_viewed_ts`.

3. **FTS Search**

   * Inputs: `query`, optional `project_id`, `limit`
   * Output: `entry_id`, `project_id`, snippet, timestamps; ordered by FTS rank.

4. **Session / Transcript Summaries**

   * Inputs: `transcript_id` or `project_id`, `days`, `limit`
   * Output: rows from `transcript_metadata` (titles, topics, description, confidence).

5. **File History**

   * Inputs: `file_path`
   * Output: entries mentioning that path plus linked `file_snapshots` metadata.

6. **Token/Cost Rollups**

   * Inputs: `project_id`, time window
   * Output: aggregates from `assistant_usage` (by model/day).

7. **Diagnostics**

   * Inputs: `limit`
   * Output: recent `system_events` with level error/warn and recent `parse_errors`.

### 4.2 Safety

* **Read-only handle**: open DB with `immutable` / `read_only` flags where possible.
* **No migrations**: migrations remain the app's job; tools never alter schema.
* **Timeouts**: set reasonable query timeouts to avoid long locks.

---

## 5. Transport 1 - CLI Companion (`contextify-query`)

### 5.1 CLI Shape

Basic form (pulled from the best parts of both reports):

```bash
contextify-query <COMMAND> [OPTIONS]

COMMANDS:
  search        Full-text search across entries
  activity      Recent conversation activity feed
  summaries     LLM-generated session summaries
  stats         Project statistics
  diagnostics   Recent system_events/parse_errors
  version       Print db/app schema info
```

Example:

```bash
# Search for "authentication" in current project
contextify-query search "authentication" --project "$(pwd)" --limit 20 --json

# Last 24h of activity in a project
contextify-query activity --project "$(pwd)" --hours 24

# Summaries for the past week
contextify-query summaries --days 7 --json

# Check version/schema
contextify-query version
```

### 5.2 Output & Exit Codes

* Default output: human-readable.
* `--json` flag: machine-readable, stable JSON schema.
* Exit codes:

  * `0`: success
  * `1`: DB not found
  * `2`: schema version mismatch (DB too new)
  * `3`: query error
  * `4`: invalid arguments

### 5.3 Packaging

Opinionated choice:

* Build CLI as an Xcode target.
* Install it into:

```text
/Applications/Contextify.app/Contents/MacOS/contextify-query
~/Library/Application Support/Contextify/bin/contextify-query   (symlink)
```

* Recommend users add this bin directory to their PATH in the docs.

---

## 6. Transport 2 - MCP Server (stdio)

### 6.1 Role

* Thin wrapper around the shared query core.
* Exposes a small number of **well-described tools**; no raw SQL.

### 6.2 Example Tool Set

Borrowing the better pieces from Report A:

* `search_entries(query, limit?, project_id?)`
* `get_summaries(project_id?, days?, limit?)`
* `recent_activity(project_id?, hours?, limit?)`
* `project_stats(project_id)`
* `get_entry_context(entry_id, context_lines?)`
* `fts_search(query, limit?, project_id?)` (optional advanced tool)

Each tool:

* Accepts a JSON object as input.
* Returns structured JSON (no UI formatting).
* Checks schema/capabilities before running and returns clear errors on mismatch.

### 6.3 MCP Integration

* Server binary: `contextify-mcp`.
* Configure Claude Code via `.mcp.json` or equivalent:

```json
{
  "mcpServers": {
    "contextify": {
      "type": "stdio",
      "command": "contextify-mcp"
    }
  }
}
```

* The MCP server reads the same discovery file as the CLI.

---

## 7. Steering with Skills (Claude Code)

A short, opinionated skill file that:

* Defines **when to use** Contextify tools:

  * "When the user asks about past conversations, history, what we discussed before, recent work, etc."
* Defines **when not to use** them:

  * "When debugging raw transcript parsing, or inspecting a file not yet ingested."
* Sets **tool priority order**:

  1. MCP tools (`contextify.search_entries`, etc.) if available.
  2. `Bash(contextify-query ...)` if MCP unavailable.
  3. Raw JSONL only as a last resort.

You don't need all the verbose copy from Report A; you just need enough to bias the model.

---

## 8. Sandbox & Security Posture

* **No localhost HTTP API** in App Store builds (avoid `network.server` entitlement and review complexity).
* Both CLI and MCP:

  * Are separate processes from the app.
  * Read the DB path from the discovery file.
  * Open the database read-only.
* App Store build:

  * Database still lives in the container.
  * App writes the external `~/.config/contextify/state.json` pointing to the container path.
  * External tools follow that path and read it; no extra entitlements needed.

---

## 9. Measurement & Diagnostics

Local, non-content logs for both CLI and MCP:

* For each query:

  * `ts`, `tool_or_command`, `success`, `latency_ms`, `result_count`, `db_schema_version`, `error_code`.
* Example log line:

```json
{"ts":"2025-12-05T10:30:00Z","tool":"search_entries","success":true,"latency_ms":140,"result_count":7,"db_schema_version":29}
```

Use this to:

* Confirm adoption (are queries using DB vs raw files?).
* Spot breakage (schema mismatch spikes, DB not found).
* Tune latency and limits.

Logs stay local by default.

---

## 10. Focused Implementation Roadmap

### Phase 0 - Reality Check (very short)

* Confirm current DB schema/version (v28/v29).
* Confirm where the DB actually lives in both DMG and App Store builds.
* Draft the **state.json** schema and decide on the exact `~/.config/contextify/state.json` location.

### Phase 1 - MVP: Discovery + CLI + Skill

**Target: ~2-3 days of focused work.**

1. **Discovery writer (in the app)**

   * On startup and after migrations/path changes, write `~/.config/contextify/state.json` with:

     * `database_path`
     * `schema_version`
     * `build_flavor`
     * `app_version`
     * `capabilities[]`
   * Handle failures gracefully; don't crash the app if writing fails.

2. **Shared query core**

   * Implement recent activity, FTS search, summaries, stats, version query.
   * Make it an internal Swift module that can be used by both app/CLI.

3. **`contextify-query` CLI**

   * Wrap 4-6 query patterns in subcommands with JSON output and exit codes.
   * Read the discovery file; handle missing DB/schema mismatch cleanly.

4. **Skill + docs**

   * Short Claude skill file pointing to `contextify-query` via `Bash(...)`.
   * Update `CLAUDE.md` / internal docs with examples and PATH instructions.

**Success criteria:**

* You can sit in Claude Code/Codex and reliably run `contextify-query` via shell to get useful history/search results.
* No noticeable regressions or DB lock issues.

### Phase 2 - MCP Server (stdio)

**Target: ~3-4 days once Phase 1 feels solid.**

1. Implement `contextify-mcp` that:

   * Uses the same query core as the CLI.
   * Implements a minimal tool set (`search_entries`, `get_summaries`, `recent_activity`, `project_stats`).
   * Reads discovery file and enforces schema compatibility.

2. Add Claude configuration snippet and update the skill to:

   * Prefer MCP tools.
   * Fall back to CLI when MCP unavailable.

3. Extend local metrics to distinguish MCP vs CLI usage.

**Success criteria:**

* Claude Code shows Contextify tools in its tool list.
* Tools work with low latency and clear errors.
* You see a meaningful share of history/search queries going through MCP.

### Phase 3 - Hardening & Nice-to-Haves

* Add richer FTS tools and diagnostics as needed.
* Consider a dedicated "Contextify history" subagent once the ecosystem stabilizes.
* Optional: build a tiny in-app diagnostics view summarizing tool usage/errors from the local logs.

---

## 11. Narrowed Open Questions (Blocking First Steps Only)

You can safely defer everything else.

1. **Discovery location final decision**

   * Are you comfortable committing to `~/.config/contextify/state.json` as the single external discovery file for both DMG and App Store builds?

2. **CLI install UX**

   * Are you okay with the `~/Library/Application Support/Contextify/bin` + "add this to PATH" pattern, or do you want to avoid touching PATH and rely on fully-qualified paths in docs?

3. **Latency budget**

   * What's your acceptable 95th percentile latency for the most common queries (e.g., project feed, FTS search)?
     Pick a number (e.g., 150-200ms) to guide indexing and limits.

Everything else (writes, REST, subagents, telemetry beyond local logs) can follow once the basic read-only query stack is working and you've used it for a week or two.

---

If you want, next step we can concretely draft:

* The `state.json` Swift writer (real code).
* A minimal `contextify-query` spec with exact JSON response shapes for 2-3 commands.
