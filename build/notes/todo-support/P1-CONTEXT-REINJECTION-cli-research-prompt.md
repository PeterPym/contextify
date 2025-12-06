---
todo_id: P1-CONTEXT-REINJECTION
title: CLI AI Research Prompt - Database Integration
type: prompt
date: 2025-12-05
status: active
description: Research prompt for CLI-based AI sessions to investigate database integration architecture
related:
  - P3-RESTORE-HTTP-API
  - build/docs/operations/DATABASE-LOCATIONS.md
  - build/docs/architecture/sql-backend.md
---

# Research Task: Contextify Database Integration for AI Coding Assistants

You are a **senior AI systems architect and LLM tooling researcher** with deep experience in:

- Claude Code / Anthropic MCP ecosystem
- Codex CLI / tool use in shell-centric workflows
- SQLite schema design, migrations, and query optimization
- macOS sandboxing and App Store distribution

Your job is to design a **practical, maintainable integration architecture** that lets AI coding assistants query Contextify's SQLite database directly instead of re-parsing raw transcript files.

---

## 1. Background & Objectives

**Contextify** is a macOS app that monitors Claude Code and Codex CLI transcripts, parses them, and stores:

- Normalized transcript entries
- Rich metadata
- LLM-generated summaries

...into a **SQLite database** that is already:

- Pre-indexed and optimized for search
- Evolving (schema changes likely; app is pre-1.0)
- Potentially stored in multiple user-chosen locations (local, Dropbox, iCloud, custom)

Today, AI coding assistants (Claude Code, Codex CLI) typically:

- Read **raw JSONL transcript files** via shell commands
- Re-parse and re-summarize content the app has already processed

**Goal:** Enable Claude Code and Codex CLI to **use the Contextify database natively** (read-only queries at first), in a way that is:

- Architecturally sound and secure
- Maintainable by a solo developer
- Robust to schema evolution and database relocation
- Compatible with both **App Store (sandboxed)** and **DMG (unsandboxed)** builds
- Likely to be **actually used** by the assistants (not just theoretically available)

---

## 2. Your Task

Research and recommend an integration architecture that enables AI coding assistants to query the Contextify database effectively and safely.

You should assume:

- Contextify controls the app + database, but **does not control** Claude Code or Codex CLI codebases.
- You can define MCP servers, skills, tools, and subagents where supported.
- You can ship **companion binaries / scripts** with Contextify if appropriate.

---

## 3. Integration Approaches to Evaluate

For each approach below, **evaluate it in detail** and compare them in a unified matrix.

### Common Evaluation Criteria

For each approach, assess:

- **Implementation complexity (Contextify side)**
  - New components, code size, required libraries
  - Complexity of testing and CI
- **Reliability & error handling**
  - Handling of missing/locked DB, corrupted DB, schema mismatch
  - Network/process lifetime issues (where applicable)
- **Query expressiveness**
  - What kinds of questions can the assistant reliably answer?
  - Can it support richer queries (e.g., "show me all refactors touching X in last week")?
- **Performance characteristics**
  - Latency per query
  - Overhead vs direct SQLite access
  - Impact on app responsiveness
- **Security & privacy**
  - Exposure surface (ports, files, IPC)
  - Protection of sensitive transcript content
  - Risk of accidental data exfiltration by tools
- **Schema versioning & evolution**
  - How does the integration cope with schema changes?
  - How are incompatible versions detected and handled?
- **Degraded operation**
  - What happens if Contextify isn't running?
  - What happens if DB is moved, missing, or unreadable?
  - Failure modes from both app and CLI perspective
- **Compatibility / adoption**
  - Support for **Claude Code** today
  - Support / parity path for **Codex CLI**
  - Risk that tools are "available" but **rarely used** by the assistant

### Approaches

#### (a) MCP Server (Contextify as MCP Tool Host)

- Contextify runs an **MCP server** exposing database query tools.
- Claude Code connects via MCP protocol and calls high-level query tools.
- You must research:
  - How MCP servers are structured and configured for Claude Code.
  - How tooling discovery works (file-based config, manifests, etc.).
  - Typical implementation footprint for a small MCP server.
  - How to expose **high-level query tools**, not just raw SQL.
  - How schema versioning and capability negotiation can be modeled.
- Clarify: MCP is **not** competing with skills or subagents; it is the **tool transport layer** they can use.

#### (b) REST API on localhost

- Contextify hosts a small **HTTP API** on `localhost` exposing query endpoints.
- Assistants call this via `curl`/`fetch` or equivalent.
- You must research:
  - Localhost port selection and discovery (fixed port vs dynamic with discovery file).
  - Authentication strategy (if any) for localhost-only API.
  - CORS is likely irrelevant for CLI tools, but confirm edge cases.
  - How this interacts with **macOS sandboxing** (App Store build).
  - How to avoid exposing sensitive data beyond the local machine.
  - Tradeoffs vs MCP (tooling discovery, multi-agent usage, etc.).

#### (c) CLI Companion Tool

- Ship a `contextify-query` CLI binary/script:
  - Finds the DB
  - Validates compatible schema version
  - Executes well-defined query presets (not arbitrary SQL)
  - Outputs machine-readable JSON for the assistant
- Assistants call it via shell commands.
- You must research:
  - Distribution and updates (bundled with app vs standalone).
  - Cross-platform implications (even if Contextify is macOS-only now).
  - Version negotiation between CLI and DB schema.
  - How to encode **query patterns** in flags/subcommands.
  - How this compares to MCP server in terms of:
    - Adoption likelihood (Shell tool vs MCP tool)
    - Reliability
    - Integration complexity

#### (d) Raw SQL Documentation

- Publish the DB schema and example queries in a `CLAUDE.md` / `CONTEXTIFY-DB.md`.
- Assistants call `sqlite3` directly on the DB file.
- You must research:
  - How stable the schema is likely to be pre-1.0.
  - How migrations would be communicated to the assistant.
  - How CLI can discover which schema version is present.
  - Risk of:
    - Breakage when schema changes
    - Accidental destructive queries (mitigation options)
  - Whether this might be better as a **fallback** rather than a primary strategy.

#### (e) Skill Definition

- Create a **Claude Code skill** specifically for transcript analysis using Contextify.
- The skill would:
  - Encode recommended query patterns or narratives.
  - Possibly reference MCP tools or the CLI companion as building blocks.
- You must research:
  - Current skill definition format and capabilities.
  - Whether skills can:
    - Include tool definitions directly
    - Or must reference separately configured MCP tools / commands.
  - How skills interact with:
    - Tool selection heuristics
    - Subagents (if present)
  - Whether skills can help address the **"choosing to use it"** problem:
    - Making the assistant prefer DB queries over raw file scans.

#### (f) Subagent Definition

- Define a **Contextify-specialized subagent** (or equivalent agent pattern).
- This subagent owns:
  - All database interactions
  - Some or all reasoning about transcript history queries
- You must research:
  - How custom subagents (or comparable constructs) are defined for Claude Code and Codex CLI.
  - Whether this is available now or still "coming soon".
  - How subagents discover and call MCP tools or CLIs.
  - How control is delegated (when the main assistant hands off to the subagent).

> Important: **MCP, skills, and subagents are complementary**, not mutually exclusive.
> Part of your job is to explain **how they can stack together** in a long-term architecture.

---

## 4. Database Location & Existence Discovery

The database location is **user-configurable** and may live in:

- Local disk (default)
- Dropbox / iCloud Drive
- Arbitrary custom locations

Additionally:

- App Store builds are **sandboxed**, DMG builds are not.
- The database may be **missing, corrupted, or mid-migration**.

You must:

1. **Separate two problems:**
   - **Existence discovery:** "Does a usable Contextify DB exist on this machine?"
   - **Location discovery:** "If yes, where is it, and is it safe to open?"

2. For each integration approach, analyze how it handles:
   - **Initial discovery**
     - How does the assistant first learn where/how to query?
     - Who is responsible: Contextify, MCP server, CLI, or assistant prompt?
   - **Database relocation**
     - If user moves DB (e.g., new folder, different sync provider), how is this detected?
     - What update path do tools follow?
   - **Missing/corrupt DB**
     - What does the assistant see and how should it respond?
     - Recommended UX for error messages / recovery instructions.
   - **App Store vs DMG**
     - Any differences in:
       - Reading/writing discovery files
       - Running local servers
       - Using companion CLIs
       - File system access patterns

3. Investigate the **current state** (from the codebase docs):

   - Where is the database path preference stored?
   - Is there a stable, machine-readable API/file that external tools could read now?
   - Should Contextify write a **discovery file**, such as:
     - `~/.config/contextify/state.json`
     - Or another well-defined location containing:
       - Current DB path
       - Schema version
       - Build flavor (App Store vs DMG)
       - Feature flags/capabilities

---

## 5. Maintenance Cost Analysis

For each integration approach, provide a **cost model** broken down as:

### 5.1 User Costs

- **Setup**
  - What the user must install/configure.
  - Any environment variables, config files, or UI steps.
- **Ongoing maintenance**
  - Handling of app / plugin / CLI updates.
  - What breaks when versions drift.
- **Failure modes**
  - What users are likely to encounter and how hard it is to recover.

### 5.2 Developer (Contextify) Costs

- **Initial implementation**
  - Estimated complexity and time for a solo developer.
- **Schema migration handling**
  - How much migration logic needs to be stable and documented.
- **Documentation**
  - What docs must be maintained (DB schema, query recipes, troubleshooting).
- **Cross-version compatibility**
  - Strategy for:
    - Old Contextify app + new integration code
    - New Contextify app + old tools / skills / MCP configs

### 5.3 CLI / Assistant Engagement Costs

- **Token / latency overhead**
  - How much "chatter" is required just to discover and validate the DB.
- **Tool selection risk**
  - Likelihood that the assistant **ignores** the database tools and falls back to raw file scans.
  - Prompt design / skills needed to bias toward DB usage.
- **Training / prompting requirements**
  - How much **prompt engineering** is necessary in:
    - Project-specific instructions
    - Tool descriptions
    - Skills / subagent configuration

---

## 6. Effectiveness Measurement

Design a way to determine whether the integration is actually **useful in practice**.

### 6.1 Adoption Metrics

- How often does the CLI / assistant:
  - Use the database vs raw files?
  - Retry on DB errors?
- Distribution of **query types**:
  - Aggregations, recent activity, per-file history, etc.
- Frequency and patterns of:
  - Errors
  - Fallback to raw file scanning

### 6.2 Quality / UX Metrics

- **Accuracy** of answers (vs a known-good baseline).
- **Time-to-answer**:
  - Wall-clock latency from request to response.
- **User satisfaction signals** (non-invasive):
  - Users opting in/out of the feature.
  - Retention of the integration configuration.
  - Presence of "this helped / this was wrong" style feedback if available.

### 6.3 Instrumentation & Privacy

- Propose a **minimal, privacy-preserving** logging strategy:
  - What events to log (e.g., "DB query executed", "DB unavailable, fell back to raw files").
  - No logging of raw content; stick to structured metadata.
- How to analyze this data:
  - Time-windowed summaries.
  - A/B tests:
    - e.g., some users see DB integration enabled vs disabled.
- Make sure all recommendations are compatible with:
  - Local-only analytics
  - Or optional, explicit user opt-in for any telemetry.

---

## 7. Research Resources

Use these as starting points:

**Contextify codebase:**

- Database schema:
  - `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`
- Database location logic:
  - `build/docs/operations/DATABASE-LOCATIONS.md`
- SQL backend architecture:
  - `build/docs/architecture/sql-backend.md`

**Claude Code documentation (current state as of your execution time):**

- MCP servers:
  - Supported protocols, configuration files, tooling examples.
- Skills:
  - Definition format, capabilities, and how they reference tools/MCP.
- Subagents:
  - How (and whether) custom subagents can be defined and wired up.

**Codex CLI:**

- Current tool definition format.
- Any public plans / docs for:
  - Skill support
  - Subagents
  - Database-like integrations.

When citing external resources, prefer **primary or official docs** over random blog posts, but you may use high-quality community articles for pattern examples.

---

## 8. Output Requirements

Write your report to:

`/tmp/contextify-database-integration-report.md`

The report must be structured as:

1. **Executive Summary**
   - 1-2 pages
   - Clear recommendation of the **primary architecture** (and any staged rollout)
   - Explicitly call out:
     - Short-term (MVP) plan
     - Long-term (ideal) plan
2. **Detailed Evaluation Matrix**
   - One consolidated table comparing all approaches (MCP, REST, CLI tool, raw SQL docs, skill, subagent).
   - Rows = evaluation criteria from Sections 3-5.
3. **Recommended Architecture & Justification**
   - Explain how MCP, skills, and subagents fit together (if applicable).
   - Show how Codex CLI can reach near-parity, even if staged later.
   - Address security, schema evolution, and App Store sandbox explicitly.
4. **Implementation Roadmap (Phased)**
   - Phase 0: "Do nothing" baseline (for comparison).
   - Phase 1: MVP integration (minimal viable approach).
   - Phase 2+: Hardening, MCP/skill/subagent refinements, instrumentation.
   - Identify clear "go / no-go" checkpoints and rollback options.
5. **Open Questions for the App Developer**
   - List of concrete questions that must be answered before implementation.
   - Example categories:
     - Tolerance for long-lived background processes (MCP/REST).
     - Willingness to ship companion CLIs.
     - Priority of Codex CLI support vs Claude Code-only initially.
6. **Appendix**
   - **Schema reference** (summarized; not a raw dump).
   - **Example queries**:
     - At least 6-10 canonical query patterns that should be supported by the chosen architecture.
   - Any helpful diagrams (textual description is fine if diagrams can't be rendered).

---

## 9. Clarifying Questions (If Needed)

If clarification is required before you begin, prioritize these questions:

1. Should the integration be **Contextify-specific** or framed as a reusable pattern for "apps with SQLite knowledge bases"?
2. Is **read-only** DB access sufficient, or should we plan for future **write operations** (e.g., notes, tags, manual corrections)?
3. How important is **Codex CLI parity** versus a Claude Code-only integration in v1?
4. What's the acceptable **latency budget** for DB-backed queries during an analysis session (per query)?
5. Should the integration **require Contextify to be running**, or must it work purely against the DB file on disk?

If you can reasonably proceed without answers, you may explicitly state your assumptions and continue.

---

## Constraints & Design Principles

- Must be maintainable by a **solo developer**.
- Must **degrade gracefully** when:
  - DB is missing / invalid
  - Contextify is not running
  - Integration config is out of date
- Must respect **macOS App Store sandbox restrictions**.
- Must consider that Contextify is **pre-1.0**:
  - Schema and features will evolve.
  - Avoid overly rigid integration contracts that make iteration painful.
