# Search CLI Addendum: Entry-Anchored Retrieval

Defines a CLI-facing retrieval surface that starts from a known `transcript_entries.id` and expands outward to produce “RAG-ready” context blocks.

**Status:** Proposed (not yet shipped)
**Last Updated:** 2025-12-12

---

## Why This Exists

Search results and UI timelines identify a specific message via `entry_id`. Once a user selects a hit, that id becomes the most stable handle to:

- re-fetch the exact record later,
- build a deterministic “neighborhood” around it (for context reinjection),
- run constrained search near it (to avoid global noise),
- iterate expansion until a token/character budget is met.

This addendum describes commands and response shapes intended to be shared with other CLIs (Claude Code, Codex CLI, etc.) so they can rely on the same retrieval contract before deeper integrations are built.

## Scope

This spec covers retrieval-only behavior:

- No LLM calls.
- No database writes.
- No UI coupling.
- Outputs are stable JSON (via `--json`) plus a human-readable mode.

## Terms

- **Anchor entry**: a `transcript_entries` row identified by `entry_id`.
- **Neighborhood**: messages surrounding an anchor, returned in stable order.
- **Scope**:
  - `transcript`: only the anchor’s transcript.
  - `project`: all transcripts within the anchor’s project.
- **Direction**:
  - `before`: earlier messages than the anchor.
  - `after`: later messages than the anchor.

---

## Command: `entry`

Fetches a single entry by id.

### Syntax

```
contextify-query entry <entry-id> [--json]
```

### JSON Response

Envelope:

```json
{
  "type": "entry",
  "data": {
    "entry": {
      "id": "e1",
      "projectId": "p1",
      "transcriptId": "t1",
      "provider": "claude.code",
      "kind": "assistant",
      "timestamp": 1234567890,
      "content": "..."
    },
    "transcript": {
      "id": "t1",
      "filePath": "/path/to/transcript.jsonl",
      "provider": "claude.code"
    },
    "project": {
      "id": "p1",
      "name": "Contextify"
    }
  }
}
```

Notes:

- `entry` fields reflect the canonical database row.
- `transcript` and `project` are best-effort convenience joins; consumers must tolerate missing `name`.

---

## Command: `context`

Returns a bounded neighborhood around an anchor entry.

### Syntax

```
contextify-query context --entry-id <entry-id> [options]
```

### Options

- `--before <n>`: maximum entries returned before the anchor (default `10`)
- `--after <n>`: maximum entries returned after the anchor (default `20`)
- `--scope transcript|project`: neighborhood scope (default `transcript`)
- `--include timeline|all`: include only `display_in_timeline=1` or include all entries (default `timeline`)
- `--kinds <csv>`: filter by entry kinds (e.g., `user,assistant`) (default `user,assistant`)
- `--json`: emit JSON output

### Ordering

The response is stable and chronological within the selected scope:

1. Entries are ordered by `(timestamp ASC, created_at ASC, id ASC)`.
2. The anchor is included exactly once.

### JSON Response

```json
{
  "type": "context",
  "data": {
    "anchorEntryId": "e1",
    "scope": "transcript",
    "before": 10,
    "after": 20,
    "entries": [
      {
        "id": "e0",
        "timestamp": 123,
        "kind": "user",
        "content": "..."
      },
      {
        "id": "e1",
        "timestamp": 124,
        "kind": "assistant",
        "content": "..."
      }
    ],
    "cursors": {
      "before": "opaque-cursor",
      "after": "opaque-cursor"
    }
  }
}
```

Cursor semantics:

- `cursors.before` expands earlier messages relative to the current window.
- `cursors.after` expands later messages relative to the current window.
- Cursors are opaque; consumers pass them back to request additional pages.

### Pagination / Expansion

To support iterative retrieval until a budget is reached, `context` supports cursor-based expansion:

```
contextify-query context --entry-id <entry-id> --cursor-before <cursor> --before 20
contextify-query context --entry-id <entry-id> --cursor-after <cursor> --after 20
```

Rules:

- Expanding `before` never returns ids already returned in the same direction.
- Expanding `after` never returns ids already returned in the same direction.
- Consumers dedupe by `entry.id` if multiple windows are merged.

---

## Command: `context-search`

Runs search constrained to an anchor neighborhood.

### Why This Matters

A downstream CLI often wants to start from an anchor entry and then find nearby supporting details (variable names, error logs, decisions) without searching the entire database.

### Syntax

```
contextify-query context-search --entry-id <entry-id> <query> [options]
```

### Options

- All `context` options are supported (`--before`, `--after`, `--scope`, `--include`, `--kinds`).
- `--limit <n>` caps results (default `20`).
- `--json` emits JSON.

### Query Semantics

`context-search` constrains search to the same neighborhood definition as `context` and returns ranked hits within that window.

### JSON Response

```json
{
  "type": "context-search",
  "data": {
    "anchorEntryId": "e1",
    "query": "unread count",
    "scope": "transcript",
    "hits": [
      {
        "entryId": "e2",
        "rank": 0.123,
        "entry": {
          "id": "e2",
          "timestamp": 125,
          "kind": "assistant",
          "content": "..."
        }
      }
    ]
  }
}
```

---

## Error Handling Contract

Errors are user-actionable and fall into a small set:

- Anchor missing: `entry-id` not found.
- Capability missing: FTS table is absent for search commands.
- Invalid flags: negative limits, unknown scope/include values.
- Discovery failure: database path cannot be resolved.

Consumers treat non-zero exit codes as failure and parse JSON only on success.

---

## Intended Integration Pattern (For Other CLIs)

The minimal, composable “RAG-from-entry-id” flow:

1. `search "<query>" --json` → collect `entry_id` candidates.
2. `entry <entry-id> --json` → fetch the exact anchor record and metadata.
3. `context --entry-id <id> --before 10 --after 20 --json` → build an initial neighborhood.
4. Optional: `context-search --entry-id <id> "<refine query>" --json` → pull nearby supporting evidence.
5. Expand with cursors until a budget is reached.

This pattern keeps the retrieval decision-making in the downstream CLI (budgeting, ranking, summarization) while giving it stable primitives to fetch exactly the data it needs.

