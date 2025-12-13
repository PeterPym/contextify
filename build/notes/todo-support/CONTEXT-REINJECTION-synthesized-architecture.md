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
  * A **companion CLI (`contextify-query`)** is the safest, lowest-friction transport for early adoption and works for both Claude Code and Codex.
  * A **discovery contract** (state file + prefs) is essential so tools don't guess paths.
  * Everything should be **read-only**, WAL-safe, and version-aware (schema_version + capabilities).
  * REST/localhost HTTP is optional at best and probably not worth the App Store/sandbox friction.

* **Where Report A is stronger**

  * More explicit **tool definitions** (e.g., `search_entries`, `get_summaries`, `recent_activity`, etc.).
  * Clearer, stepwise **Phase breakdown** (Phase 1: CLI contract, Phase 2: skills + distribution, Phase 3: hardening, etc.).
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

**Core decision:** Build **one shared query core**, expose it via **one stable transport first**, and drive adoption using a **discovery contract + skills**:

1. **Shared Query Core (GRDB/SQLite, read-only)**

   * Knows the schema (v28/v29+), FTS tables, and canonical query patterns (recent feed, FTS search, summaries, cost rollups, etc.).
   * Enforces **read-only, WAL-safe access** and is aware of `schema_version` and `capabilities`.

2. **Transport #1 - CLI Companion (`contextify-query`)**

   * Short-lived, read-only process with JSON output and clear exit codes.
   * Works for **Claude Code** (via shell) and **Codex CLI** out of the box.
   * Does *not* require the GUI app to be running.

3. **Discovery Contract**

   * A small JSON **state file** plus CFPreferences lookup that tells the tools:

     * `db_path`
     * `schema_version`
     * `build_flavor` (dmg/appstore)
     * `capabilities[]` (e.g., `fts_search`, `usage_stats`).
   * This is the *only* supported way to discover the DB; no path guessing.

4. **Steering the LLM**

   * A **Claude Code skill** that explicitly instructs the assistant:

     * Use `contextify-query` for history/search/summaries.
     * Use raw JSONL only as fallback if DB is unavailable.

**Opinionated call to action:**
**Phase 1:** implement the discovery contract + CLI + minimal skill and start *actually using it* yourself in Claude Code/Codex.
**Phase 2:** ship skills and a CLI distribution/install story so external tools can reliably invoke `contextify-query` without bespoke setup.

---

## 2. Core Architecture

### 2.1 Design Principles

* **Single source of truth:** The SQLite/GRDB database is canonical for all timeline/history/search questions.
* **One query layer, multiple surfaces:** Query logic lives in one place; the CLI is the stable surface, and other integrations can be layered later.
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
         └── Skills → codify how to query + reinject  [Phase 2]
                      │
              Shared Query Core (GRDB)
                      │
               Contextify Database
```

---

## 3. Discovery Contract

### 3.1 State File

**Purpose:** Make the database discoverable and versioned without guessing paths.

**Location:**

The app writes a discovery sidecar next to the active database:

```text
<db-dir>/.state/state.json
```

Tools discover the DB by checking explicit flags first (`--db-path`/`--db-dir`), then preferences/default locations, then probing known App Store container paths and reading the sidecar when present.

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

When a tool needs the DB:

1. Prefer explicit flags (`--db-path` / `--db-dir`) when provided.
2. Otherwise, check known locations:

   * preferences/custom database location (if set)
   * default Application Support database path
   * known App Store container Application Support paths
3. If a candidate database directory contains `.state/state.json`, use it as a discovery hint for the active DB path.
4. If not found, return a **structured error**:
   `"Contextify database not found. Please open Contextify once to initialize it."`

### 3.3 Schema Compatibility

Tools must:

* Compare `schema_version` in the state file to their own supported version.
* If DB is *newer* than the tool: refuse to run and say "update Contextify/CLI".
* If DB is *older*: allow a best-effort run but warn if a requested capability is missing (e.g., FTS).

---

## 4. Shared Query Core

This is the code you write once and reuse from the CLI and any future integrations.

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
  * `1`: `entryNotFound`
  * `2`: `dbNotFound` / `dbProjectNotFound`
  * `3`: `featureUnavailable`
  * `64`: `invalidArgs`

### 5.3 Packaging

The CLI is a SwiftPM executable (`contextify-query`) that external tools invoke as a subprocess.

Distribution patterns:

* DMG builds can offer an explicit “install CLI” flow (symlink/copy into a PATH directory).
* App Store builds can bundle the CLI inside the app and provide a user-driven install to a user-writable directory (commonly `~/bin`), or require invocation by absolute path.

---

## 6. Skills and Distribution (Phase 2)

### 6.1 Skills

The primary adoption mechanism is skills that teach external tools when and how to call `contextify-query` (search → anchor entry id → context window → reinject) while staying within a context budget.

### 6.2 CLI distribution and install

External tools need a reliable way to invoke `contextify-query`:

* DMG builds can install/symlink the CLI into a PATH directory (`/usr/local/bin` or `/opt/homebrew/bin`) with explicit user consent.
* App Store builds can bundle the CLI inside the app and support a user-driven install to a user-writable directory (commonly `~/bin`) with clear PATH instructions, or require invocation by absolute path.

---

## 7. Steering with Skills (Claude Code)

A short, opinionated skill file that:

* Defines **when to use** Contextify tools:

  * "When the user asks about past conversations, history, what we discussed before, recent work, etc."
* Defines **when not to use** them:

  * "When debugging raw transcript parsing, or inspecting a file not yet ingested."
* Sets **tool priority order**:

  1. `Bash(contextify-query ... --json)` as the primary mechanism.
  2. Raw JSONL only as a last resort.

You don't need all the verbose copy from Report A; you just need enough to bias the model.

---

## 8. Sandbox & Security Posture

* **No localhost HTTP API** in App Store builds (avoid `network.server` entitlement and review complexity).
* The CLI is a separate process from the app:

  * Discover the DB via explicit flags, preferences/default locations, and the discovery sidecar next to the DB.
  * Open the database read-only.
* App Store build keeps the database in the container; the CLI probes known container Application Support directories during discovery.

---

## 9. Measurement & Diagnostics

Local, non-content logs for the CLI:

* For each query:

  * `ts`, `tool_or_command`, `success`, `latency_ms`, `result_count`, `db_schema_version`, `error_code`.
* Example log line:

```json
{"ts":"2025-12-05T10:30:00Z","command":"search","success":true,"latency_ms":140,"result_count":7,"db_schema_version":29}
```

Use this to:

* Confirm adoption (are queries using DB vs raw files?).
* Spot breakage (schema mismatch spikes, DB not found).
* Tune latency and limits.

Logs stay local by default.

---

## 10. Focused Implementation Roadmap

### Phase 1 - MVP: Discovery + CLI contract (complete)

* The CLI provides a stable, read-only JSON contract for discovery + search + entry-anchored retrieval.
* Discovery checks explicit flags (`--db-path`/`--db-dir`), preferences/default locations, and the discovery sidecar next to the DB.
* Queries are deterministic and bounded; the tool remains read-only.

### Phase 2 - Skills + CLI install story

1. Ship a Codex skill (and Claude Code equivalent, if needed) that:
   * Encodes the reinjection workflow (search → entry id → context window → reinject).
   * Includes error handling (`dbNotFound`, `dbProjectNotFound`, `featureUnavailable`, `invalidArgs`) and budgeting guidance.
2. Ship a DMG-friendly install flow so `contextify-query` is callable reliably from shells and other tools.
3. Document App Store constraints and provide a user-driven install option when appropriate.

### Phase 3 - Hardening & follow-ons

* Add CLI-level contract tests for exit codes and JSON envelopes.
* Add “Copy with Context” UI affordances once the reinjection loop is stable in daily use.

---

## 11. Narrowed Open Questions (Blocking Next Steps Only)

1. **Skill target(s)**

   * Do you ship skills for Codex first, Claude Code first, or both?

2. **CLI install UX**

   * DMG channel: do you install/symlink into `/usr/local/bin` or `/opt/homebrew/bin`?
   * App Store channel: do you support a user-driven install to `~/bin`, or rely on absolute app-bundle invocation?

3. **Latency budget**

   * What's your acceptable 95th percentile latency for the most common queries (e.g., project feed, FTS search)?

---

## References

- Phase 1 spec: `build/notes/todo-support/CONTEXT-REINJECTION-spec.md`
- Phase 1 plan: `build/notes/todo-support/CONTEXT-REINJECTION-plan.md`
- Phase 2 spec: `build/notes/todo-support/CONTEXT-REINJECTION-phase2-spec.md`
