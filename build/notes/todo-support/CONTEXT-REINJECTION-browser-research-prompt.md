---
todo_id: P1-CONTEXT-REINJECTION
title: Browser AI Research Prompt - Database Integration
type: prompt
date: 2025-12-05
status: active
description: Research prompt for browser-based AI sessions (Claude.ai, ChatGPT) to investigate database integration architecture
related:
  - P3-RESTORE-HTTP-API
  - build/docs/operations/DATABASE-LOCATIONS.md
  - build/docs/architecture/sql-backend.md
note: Content identical to CLI prompt; differs only in execution context (browser vs terminal)
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
- **Reliability & error handling**
- **Query expressiveness**
- **Performance characteristics**
- **Security & privacy**
- **Schema versioning & evolution**
- **Degraded operation**
- **Compatibility / adoption**

### Approaches

#### (a) MCP Server (Contextify as MCP Tool Host)
#### (b) REST API on localhost
#### (c) CLI Companion Tool
#### (d) Raw SQL Documentation
#### (e) Skill Definition
#### (f) Subagent Definition

> Important: **MCP, skills, and subagents are complementary**, not mutually exclusive.

---

## 4. Database Location & Existence Discovery

Separate two problems:
- **Existence discovery:** "Does a usable Contextify DB exist on this machine?"
- **Location discovery:** "If yes, where is it, and is it safe to open?"

---

## 5. Maintenance Cost Analysis

Provide cost model for: User Costs, Developer Costs, CLI/Assistant Engagement Costs.

---

## 6. Effectiveness Measurement

Design adoption metrics, quality/UX metrics, and instrumentation approach.

---

## 7. Research Resources

**Contextify codebase:**
- Database schema: `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`
- Database location logic: `build/docs/operations/DATABASE-LOCATIONS.md`
- SQL backend architecture: `build/docs/architecture/sql-backend.md`

**External:**
- Claude Code MCP documentation
- Codex CLI tool definition format

---

## 8. Output Requirements

Structure report as:
1. Executive Summary (with MVP and long-term plans)
2. Detailed Evaluation Matrix
3. Recommended Architecture & Justification
4. Implementation Roadmap (Phased)
5. Open Questions for the App Developer
6. Appendix (schema reference, example queries)

---

## 9. Constraints & Design Principles

- Must be maintainable by a **solo developer**.
- Must **degrade gracefully**.
- Must respect **macOS App Store sandbox restrictions**.
- Must consider that Contextify is **pre-1.0**.
