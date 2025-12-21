---
todo_id: CROSS-PLATFORM-INGESTION
title: Cross-Platform Ingestion Engine (Linux/Windows) Investigation
type: investigation
date: 2025-12-20
status: active
description: Research and design notes for a cross-platform CLI ingestion engine that writes Contextify-compatible databases.
---

# Contextify Cross-Platform Ingestion Engine (Linux + Windows)

Last Updated: 2025-12-20

## Executive Summary
Contextify already ships a SwiftPM package (`ContextifyCore`) with ingestion, parsing, and database orchestration logic. The fastest path to a Linux/Windows command-line ingestion engine is to extract a platform-neutral ingestion core from `ContextifyCore`, keep the existing pipeline (discovery → orchestrator → hoover), and add a dedicated CLI target that runs batch or incremental ingestion into the same SQLite schema. The primary architectural risk is database portability: Contextify currently uses GRDB, which is robust on Apple platforms but not documented here for Linux/Windows. A portability layer is needed to either keep GRDB with pinned versions + CI or to add a SQLite C API backend for non-Apple platforms.

## Inputs From Contextify (Ground Truth)
This design aligns with the current ingestion pipeline and schema:
- Ingestion flow: `LightweightDiscoveryService` → `TranscriptOrchestrator` → `HooverEngine` (streaming parse + batch insert + checkpoints). (See `build/docs/architecture/ingestion-workflow.md`.)
- Database: SQLite, WAL mode, schema v28 with `projects`, `transcripts`, `transcript_entries`, `timeline_cache`, `parse_errors`, etc. (See `build/docs/architecture/sql-backend.md`.)
- Transcript formats: Claude Code and Codex CLI JSONL, streaming-friendly, monotonic timestamps required. (See `build/docs/specifications/transcript-formats.md`.)
- Project identity: `ActiveProjectContext.id` is the canonical identity; avoid raw path lookups. (See `build/docs/architecture/startup-coordinator.md`.)

## Web Research Highlights (Best Practices)
- Swift toolchains are first-class for Linux and Windows, with official install guides and SwiftPM CLI workflows for building executables. (Swift.org install pages: Linux and Windows.)
- Swift Argument Parser is the standard, type-safe way to build Swift CLIs. (Swift Argument Parser repo.)
- SQLite prohibits non-deterministic functions in schema elements such as CHECK constraints, partial indexes, expression indexes, and generated columns. This matters for reproducible, cross-platform DB builds. (SQLite deterministic functions docs.)
- The SQLite C API remains the lowest-level, most portable database interface when library support is uncertain across OSes. (SQLite C API reference overview.)

Sources:
- https://www.swift.org/install/linux/
- https://www.swift.org/install/windows/
- https://github.com/apple/swift-argument-parser
- https://sqlite.org/deterministic.html
- https://sqlite.org/c3ref/intro.html

## Assessment of the Colleague Note (What Holds / What Needs Adjustment)
**Works as-is:**
- Extracting an ingestion core + CLI wrapper is aligned with the current architecture and keeps UI separate from ingestion concerns.
- Batch + incremental modes map cleanly to `HooverEngine` checkpoints and existing `ingest_state` fields.
- A small CLI surface (`ingest`, `verify`, `schema`) is a good match for Contextify’s ingestion needs.

**Needs correction or expansion for Contextify:**
- Contextify already has a SwiftPM package (`ContextifyCore`) and two CLI targets, but the package currently targets macOS only (`platforms: [.macOS(.v14)]`). Porting requires lifting platform restrictions and isolating macOS-only APIs.
- Contextify’s ingestion logic uses `TranscriptOrchestrator` and `HooverEngine`, which are layered on GRDB. Cross-platform database support is the key risk and must be explicitly designed.
- The canonical identity is `ActiveProjectContext.id` (DB project ID). The CLI must create or fetch project IDs and use them for all queries and state, not raw paths.
- App Store sandbox rules require all file access under `accessProvider.withAccess`. The CLI can use a no-op access provider, but the contract remains if code is shared.

## GRDB Usage Reality Check (Based on Repo Scan)
Contextify is not “barely using” GRDB. It is a hybrid: core infrastructure relies on GRDB, while many business queries are raw SQL.

**GRDB-heavy areas (non-trivial to replace):**
- Connection pooling, WAL config, and migrations (`app/Sources/ContextifyCore/Database/DatabaseManager.swift`).
- Schema migrator and migration orchestration (`app/Sources/ContextifyCore/Database/DatabaseSchema.swift`).
- Record mapping and persistence (`FetchableRecord`/`PersistableRecord`) in `app/Sources/ContextifyCore/Database/Models.swift` and repositories.

**Raw SQL-heavy areas (portable):**
- Most migrations are raw SQL (`DatabaseSchema`).
- Query CLI and query services are largely SQL strings with small decode structs (`ContextifyQueryService`).
- Hoover uses SQL for updates and seed lookups, even though it sits behind GRDB (`HooverEngine`).

**Implication for cross-platform ingestion:**
- You can keep GRDB everywhere if it compiles on Linux/Windows; this is the fastest path.
- If GRDB is unstable off macOS, the hardest part to replace is pooling + migrations + record mapping. Many query strings could carry over directly to SQLite C.

## Design Goals
- Cross-platform CLI ingestion on Linux and Windows that writes a Contextify-compatible database.
- Reuse as much existing Swift ingestion code as possible.
- Deterministic, repeatable ingestion outputs across OSes.
- Zero UI dependencies; no SwiftUI/AppKit in ingestion path.

## Non-Goals (Phase 1)
- Built-in real-time file watching (FSEvents / inotify / ReadDirectoryChangesW).
- LLM-driven `timeline_cache` generation (CLI ingestion focuses on canonical data).
- Mac App Store sandbox features (not needed for Linux/Windows CLI).

## Proposed Architecture
### Package Structure (SwiftPM)
- `ContextifyIngestionCore` (new library target)
  - Reuse: `TranscriptOrchestrator`, `HooverEngine`, `TranscriptParsers`, repositories.
  - Own: ingestion configuration, normalization, deterministic ordering rules.
  - Dependencies: Foundation, CryptoKit (if used), DB backend (GRDB or SQLite C wrapper).
- `ContextifyIngestionCLI` (new executable target)
  - Arg parsing via Swift Argument Parser.
  - Subcommands: `ingest`, `verify`, `schema`, `discover`.
  - Outputs: exit codes, JSON or text logs, optional summary report.

### Database Backend Strategy
**Option A — Keep GRDB everywhere (shortest path):**
- Pros: minimal refactor; consistent behavior with macOS app.
- Cons: portability risk; requires Linux/Windows CI to catch regressions; may need platform shims.
- Implementation: conditional compilation in `Package.swift`, CI gates on Linux/Windows builds.

**Option B — Abstract DB layer + SQLite C backend for non-Apple platforms (most robust):**
- Pros: guaranteed cross-platform behavior; control over C API usage.
- Cons: more engineering effort; migration of repository layer.
- Implementation: define a `DatabaseClient` protocol; keep GRDB adapter for Apple builds and add SQLite C adapter for Linux/Windows.

Recommendation: Start with Option A to validate feasibility, but design with an explicit DB abstraction so Option B remains viable without a rewrite.

### Ingestion Flow (CLI)
1. **Discovery**: resolve input roots to transcript files based on provider rules (Claude Code and Codex CLI). (See `build/docs/specifications/transcript-formats.md`.)
2. **Project identity**: get or create project rows using DB APIs and use `ActiveProjectContext.id` as the primary key.
3. **Transcript upsert**: insert/update `transcripts` rows and metadata.
4. **Hoover streaming**: parse JSONL line-by-line, write `transcript_entries`, update checkpoints, record `parse_errors`.
5. **Finalize**: update transcript status/ingest state; emit deterministic summary.

### Determinism Rules (Cross-Platform Parity)
- Normalize paths (separator, case normalization policy, Unicode normalization) before storage.
- Enforce deterministic ordering for file enumeration; never rely on filesystem order.
- Normalize timestamps to UTC; ensure monotonicity of stored timestamps for each transcript.
- Avoid non-deterministic SQL functions in schema or indexes; SQLite disallows them in partial indexes, expression indexes, and CHECK constraints. (SQLite deterministic functions docs.)

## CLI Surface
```
contextify-ingest ingest \
  --input <dir>... \
  --provider auto|claude|codex \
  --db <path> \
  [--full-rebuild] \
  [--since <timestamp>] \
  [--max-entries N] \
  [--workers N] \
  [--format json|text]

contextify-ingest verify --db <path> --input <dir>...
contextify-ingest schema dump --db <path>
contextify-ingest discover --input <dir>... --provider auto|claude|codex
```
- `--since` maps to transcript checkpoint logic (`last_processed_line` / `last_processed_entry_id`).
- `--max-entries` uses preview-style ingestion limits.
- `verify` compares counts, checks missing files, and reports parse errors.

## Scheduling (MVP)
Phase 1 assumes the CLI is run by an external scheduler (cron, systemd timer, Task Scheduler, CI, etc.). The ingestion engine does not decide its own polling interval in the MVP; it simply ingests incrementally based on checkpoints and exits. This keeps the core simple and portable while still enabling near-real-time usage via short intervals (e.g., 30–120s) chosen by the host system.

Future enhancement: an optional adaptive polling mode that increases cadence on activity and backs off when idle.

## Packaging & Distribution
- Build with SwiftPM on Linux/Windows using official Swift toolchains. (Swift.org install guides.)
- Provide prebuilt binaries for common distros and Windows x64/arm64.
- Document supported Swift versions and required system dependencies (SQLite runtime).

## Testing & Validation
- **Golden fixture suite**: same transcript fixtures ingested on macOS, Linux, Windows; compare schema version, row counts, and stable hashes of query outputs.
- **Parser conformance**: unit tests for Claude Code + Codex CLI JSONL edge cases (sidechains, tool_result matching, session_meta requirements).
- **Regression tests**: crash-recovery ingestion resuming from checkpoints.

## Risks & Mitigations
- **GRDB cross-platform support**: mitigate with CI and pinned versions, or provide SQLite C fallback.
- **Filesystem differences**: enforce deterministic normalization and sorting.
- **Timestamp semantics**: require strict monotonic timestamps; log and quarantine corrupt records.

## Implementation Phases
1. **Feasibility pass**: lift SwiftPM platform restriction, build `ContextifyCore` on Linux/Windows, identify macOS-only APIs.
2. **Core extraction**: isolate ingestion logic into a platform-neutral target and add CLI target.
3. **Determinism + normalization**: codify filesystem/timestamp rules and regression tests.
4. **DB backend decision**: keep GRDB with CI or add SQLite C adapter.
5. **Release**: ship CLI with docs and fixture-based validation.
