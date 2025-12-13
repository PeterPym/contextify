---
todo_id: CONTEXT-REINJECTION
title: Context reinjection and query CLI contract
type: spec
date: 2025-12-12
status: active
description: Define the `contextify-query` contract (search/entry/context/activity, discovery, output/errors, guardrails) and include the `feedback` inbox for capturing CLI improvement requests during dogfooding.
---

# Context Re-injection + `contextify-query` Spec

This spec defines the contract for retrieving context from the Contextify database for reinjection into external tools (Claude Code, Codex CLI, etc.), plus a feedback inbox mechanism to capture friction while dogfooding the CLI.

## Goals

- Let an external CLI/tool start from a search hit (`entryId`) and retrieve deterministic surrounding context.
- Keep the query surface read-only and safe (no DB writes).
- Provide stable JSON output suitable for automation.
- Capture CLI gaps via a low-friction feedback inbox (`contextify-query feedback …`).

## Non-goals

- Running LLMs from the CLI.
- Writing to the Contextify database.
- Building a stateful pagination service (v1 stays stateless; repeated calls expand windows).

---

## Data Model (Consumer-Facing)

### Entry (required fields)

- `id` (entry id)
- `projectId`
- `transcriptId`
- `provider`
- `kind`
- `timestamp`
- `content` (may be truncated; see Guardrails)

### Ordering

All multi-entry results are ordered deterministically:

1) `timestamp ASC`
2) `createdAt ASC` (when available)
3) `id ASC`

Search is a ranked list:

- `search` results are ordered by relevance (`score` ascending for BM25), then tie-broken deterministically by:
  1) `timestamp DESC`
  2) `createdAt DESC` (when available)
  3) `id ASC`

### Entry id format

In practice, `Entry.id` values are UUID strings (e.g., `5224db66-b1b1-4a10-ac13-dd0b2929f782`).

---

## CLI Commands (Retrieval)

All commands accept discovery options:

- `--db-path <path>`
- `--db-dir <dir>`

All commands support machine output:

- `--json`

### `status`

Purpose: quick sanity check (discovery + open + counts + capabilities) before running deeper queries.

Includes:

- resolved database path (if available)
- schema/capabilities snapshot
- project/transcript/entry counts (best-effort)

### `projects`

Purpose: discover available projects and ids without relying on the UI.

Options:

- `--include-hidden` (default: exclude)
- `--limit <n>` (default: all)

Returns (per project, minimum):

- `id`
- `name?`
- `rootPath`
- `hidden`
- `lastViewedTs?`
- `lastActivityTs?` (best-effort; derived)
- `transcriptCount?`
- `entryCount?`

### `transcripts`

Purpose: discover available transcripts (conversation units) for a project.

Options:

- project selection: `--project-id <id>` or `--project <path|.|current>` (required)
- `--limit <n>` (default: 50)
- time filtering (see Time Filters): `--since`, `--until`, `--days`

Returns (per transcript, minimum):

- `id`
- `projectId`
- `provider`
- `entryCount?`
- `firstEntryTs?`, `lastEntryTs?` (best-effort; derived)
- `title?` (from summaries when available; nullable)

### `version`

Purpose: DB/schema visibility and feature availability.

### `search <query>`

Purpose: find candidate anchor entries via FTS.

Options:

- `--limit <n>` (default 50; max 500)

Required output per hit (at minimum):

- `id` (entry id)
- `projectId`, `projectName?`
- `transcriptId`, `transcriptTitle?` (from summaries if available)
- `provider`, `kind`, `timestamp`
- `score` (BM25)
- `contentSnippet` (~500 chars) and `contentTruncated` boolean

Scoping options (v1):

- `--project-id <id>`
- `--project <path|.|current>` (resolves to project id; see Project Resolution)
- `--transcript-id <id>`

Time filtering (optional; see Time Filters):

- `--since <ts|iso8601>`
- `--until <ts|iso8601>`
- `--days <n>` (shorthand; equivalent to `--since now - n days`)

Notes:

- If FTS is missing, `search` fails with `featureUnavailable`.
- `--no-content` does not apply to `search` (snippets are the product); warn and ignore if provided.

### `entry <entry-id>`

Purpose: fetch one canonical anchor entry.

Returns the full entry fields plus best-effort disambiguation:

- `projectName?`
- `transcriptTitle?` (nullable; from transcript summaries when available)

Supports:

- `--no-content` (returns `content: null`)

### `context <entry-id>`

Purpose: fetch a neighborhood around an anchor entry.

Flags:

- `--before <n>` (default 10; capped)
- `--after <n>` (default 20; capped)
- `--include-hidden` (removes `display_in_timeline` filter)
- `--kinds <csv>` (default: all)
- `--full-content` (disables truncation)
- `--no-content` (returns `content: null`)
- `--max-window <n>` (bounded override; default cap 200 total entries)

Response shape:

- `anchor` (the anchor entry)
- `before[]`
- `after[]`
- `meta` boundary markers:
  - `firstEntryId`, `lastEntryId`
  - `hasMoreBefore`, `hasMoreAfter`
  - `transcriptEntryCount?`

Stateless expansion:

- To fetch more “before”, call `context` again with a larger `--before` and/or anchor on `firstEntryId` and `--after 0` as needed.

### `activity`

Purpose: resume workflow (“what happened recently?”).

Options:

- `--project-id <id>` or `--project <path|.|current>`
- `--limit <n>`
- `--no-content`
- time filtering (see Time Filters): `--since`, `--until`, `--days`

Returns recent entries including `id` values to feed into `context`.

### `summaries` / `stats`

Optional (nice-to-have for reinjection); existing behavior remains.

---

## Time Filters

Some commands support time filtering (`search`, `activity`, `transcripts`).

Supported input formats:

- Unix timestamp seconds (e.g., `1702234567`)
- ISO 8601 (e.g., `2025-12-12`, `2025-12-12T14:30:00Z`)

Shorthand:

- `--days <n>` sets `--since` to “now minus N days” (integer days).

Non-goal (v1):

- Natural-language parsing (`yesterday`, `3 days ago`) is deferred.

---

## Discovery / Project Resolution

### Database discovery

The CLI resolves the DB by:

1. explicit `--db-path` / `--db-dir`
2. preferences / default locations
3. sidecar discovery (`.state/state.json`) including sandbox container probing

### Project resolution (`--project <path>`)

- Match against `projects.root_path` only.
- Longest matching root wins (most specific).
- Canonicalize via `resolvingSymlinksInPath()` on both sides.
- Match case-insensitively using locale-stable folding (POSIX).
- If no match: error (no fallback to global).
- If tie: error (data integrity problem).

If no project selection flag is provided, `search/activity` run unscoped.

On project-not-found errors:

- Include up to 10 known (non-hidden) projects, sorted by `lastViewedTs` desc.
- Include `totalProjectCount`.

---

## Output Contract

Keep existing camelCase output; do not mix styles.

### Success envelope

```json
{ "type": "<command>", "schemaVersion": 1, "data": { ... }, "meta": { ... } }
```

### Error envelope

```json
{ "type": "error", "code": "<code>", "message": "<message>" }
```

Suggested codes:

- `entryNotFound`
- `dbNotFound`
- `dbProjectNotFound`
- `featureUnavailable`
- `invalidArgs`

### Exit Codes

- `0` success
- `1` `entryNotFound`
- `2` `dbNotFound` / `dbProjectNotFound`
- `3` `featureUnavailable`
- `64` `invalidArgs`

### Default Output Mode

- Default output is human-readable.
- `--json` forces JSON output for all commands.

---

## Guardrails

### Content truncation

- Default: truncate any entry whose `content` exceeds 2KB UTF-8 bytes.
- Truncation must not split multi-byte scalars (valid UTF-8 always).
- When truncated, include:
  - `contentTruncated: true`
  - `contentFullSize: <bytes>`
- `--full-content` disables truncation.

### `--no-content`

- For `entry`, `context`, `activity`: return `content: null`.
- For `search`: warn and ignore; snippets remain.

---

## Feedback Inbox (`contextify-query feedback …`)

The feedback inbox records “CLI gaps” while dogfooding, without touching git or the DB.

### Capture (one-liner)

```bash
contextify-query feedback "search within transcript not supported"
```

Optional enrichment:

- `--intent`, `--gap`, `--workaround`, `--proposal`
- `--edit` opens `$EDITOR`
- piping JSON to stdin is supported

### Triage

- `feedback list`, `feedback show <id>`
- `feedback export <id> --format md|todo|json`
- `feedback dismiss <id>`
- `feedback archive` / `feedback clear --all`

Dismiss semantics:

- `dismiss` removes the item from the inbox and archives it under `feedback/archive/dismissed/`.

### Storage

- Inbox: `~/Library/Application Support/Contextify/feedback/`
- Archive: `~/Library/Application Support/Contextify/feedback/archive/`
- IDs: `fb_<YYYYMMDD>_<NNN>` with per-day sequence, zero-padded.

### Guardrails

- Duplicate detection (hash `summary + intent`) with warning; override with `--force`.
- Soft rate-limit warning if > 5 feedback items in last hour.
- Storage cap: keep last 100; archive older.
- Never touch git.

---

## References

- Search architecture: `build/docs/architecture/search.md`
- Entry-anchored retrieval addendum: `build/docs/architecture/search-cli-entry-anchored-retrieval.md`
- Implementation plan: `build/notes/todo-support/CONTEXT-REINJECTION-plan.md`
- Manual QA runner: `build/notes/todo-support/CONTEXT-REINJECTION-qa-runner.sh`
