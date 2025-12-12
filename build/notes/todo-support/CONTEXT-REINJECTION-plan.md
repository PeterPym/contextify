---
todo_id: CONTEXT-REINJECTION
title: Context reinjection implementation plan
type: plan
date: 2025-12-12
status: active
description: Medium-level implementation plan and expected commit series for implementing CONTEXT-REINJECTION-spec.md.
---

# Context Re-injection + `contextify-query` Implementation Plan

Implement the contract in `build/notes/todo-support/CONTEXT-REINJECTION-spec.md` as a sequence of small, reviewable commits with tests and zero warnings.

## Constraints

- Read-only DB access from the CLI.
- Deterministic ordering and stable JSON schema.
- No compiler warnings.
- Avoid breaking existing CLI output/behavior unless explicitly versioned.

## Expected Commit Series

This is the intended commit shape; it can deviate if implementation realities demand it.

### 1) CLI plumbing: output + errors + exit codes

- Add a small shared output layer for JSON envelopes:
  - success: `{ type, schemaVersion, data, meta? }`
  - error: `{ type: "error", code, message }`
- Implement exit-code mapping (`0/1/2/3/64`) consistently.
- Keep default output human-readable; `--json` forces JSON.
- Add unit tests for envelope formatting and exit code mapping.

### 2) Time parsing utilities (`--since/--until/--days`)

- Implement timestamp parsing supporting:
  - Unix seconds
  - ISO8601 date/time
  - `--days N` → compute `since = now - N days` (UTC)
- Use a single internal representation (e.g., unix seconds `Int`) for query filtering.
- Add unit tests for parsing and boundary conditions.

### 3) Project resolution by path + `projects`

- Implement `--project <path|.|current>` → resolve to project id via `projects.root_path`:
  - symlink canonicalization (`resolvingSymlinksInPath()`)
  - locale-stable case-insensitive match (POSIX)
  - longest-prefix match wins
  - strict error on no match and on ties
- Add `projects` command:
  - default exclude hidden
  - `--include-hidden`
  - `--limit`
  - include `lastViewedTs` and best-effort `lastActivityTs`
- Add tests for longest match, case-insensitivity, tie handling, hidden exclusion.

### 4) Transcript discovery (`transcripts`)

- Add `transcripts` command requiring project selection:
  - `--project-id` or `--project`
  - `--limit` (default 50)
  - time filters (`--since/--until/--days`)
- Join/derive `title?` from summaries when available (nullable).
- Add tests with seeded DB fixtures.

### 5) Anchor + neighborhood retrieval (`entry`, `context`)

- Add `entry <entry-id>`:
  - returns `content` or `null` with `--no-content`
  - includes `projectName?` and `transcriptTitle?`
- Add `context <entry-id>`:
  - `--before/--after` with caps and `--max-window`
  - `--include-hidden`
  - `--kinds csv`
  - `--no-content` (content null)
  - `--full-content` disables truncation
  - meta boundary markers (`firstEntryId`, `lastEntryId`, `hasMoreBefore/After`)
- Truncation:
  - threshold: 2KB UTF-8 bytes
  - never split code points
  - include `contentTruncated` + `contentFullSize` when truncated
- Add tests for not-found errors, filters, truncation safety, deterministic ordering.

### 6) Activity filtering (`activity`)

- Extend `activity`:
  - accept `--project-id` / `--project`
  - add time filters (`--since/--until/--days`)
  - implement `--no-content`
- Add tests for time filtering and `--no-content`.

### 7) Status command (`status`)

- Add `status`:
  - resolves and opens DB
  - returns schema/capabilities
  - returns counts (projects/transcripts/entries) best-effort
  - includes resolved db path
- Add tests for “db not found” / “can open” behavior.

### 8) Feedback inbox (`feedback`)

- Implement `feedback "<summary>"` capture to App Support inbox.
- Support enrichment flags, `--edit`, and JSON stdin.
- Implement triage: list/show/export/dismiss/archive/clear.
- Implement guardrails:
  - duplicate detection warning (hash `summary + intent`)
  - soft rate limit warning
  - storage cap + archive
- Add tests using an injectable storage root (temp directory).

### 9) Hardening / validation pass

- Ensure featureUnavailable errors are consistent (FTS missing).
- Ensure all commands conform to `schemaVersion` in envelopes.
- Verify:
  - `swift test`
  - `bash scripts/xc.sh build` (zero warnings)

## Notes

- `schemaVersion` in envelopes is the CLI response schema version (not the DB schema).
- Time filtering should operate on entry timestamps; transcripts derive first/last entry timestamps.
- When a derived field is expensive to compute, omit it or keep it nullable.

