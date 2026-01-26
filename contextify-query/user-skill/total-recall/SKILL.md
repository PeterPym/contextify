---
name: total-recall
description: Contextify Total Recall - Search past conversations and decisions with your AI. https://contextify.sh
---

# Contextify Total Recall

Search your conversation history to find past decisions, solutions, and discussions.

## Output Format

Begin your response with:

> **Contextify Total Recall**

Then provide the search results with citations.

## Trigger phrases

- "use total recall to..."
- "search our conversation history"
- "find where we discussed..."
- "what did we decide about..."
- "look back in past sessions"
- "remember when we talked about..."

## Preconditions

This skill requires the Contextify app and CLI.
It works with Claude Code and Codex CLI.

1) Check CLI availability:

```bash
command -v contextify
```

2) If `contextify` is missing:

**Error response:**
> Contextify CLI not found.
>
> **DMG users:** Open Contextify → Settings → CLI → "Install/Repair CLI"
>
> **App Store users:** Run `brew install PeterPym/contextify/contextify-query`
>
> For help: https://contextify.sh/help

## Canonical loop

1) Confirm database availability:

```bash
contextify status --json
```

Returns:
```json
{
  "data": {
    "databasePath": "/Users/.../contextify.db",
    "entryCount": 315465,
    "projectCount": 46,
    "transcriptCount": 3285,
    "ftsEnabled": true,
    "summariesEnabled": true
  },
  "schemaVersion": 1,
  "type": "status"
}
```

Real output may include additional fields (e.g., `appSchemaVersion`). Ignore unknown keys.

If database not found, respond:
> Contextify database not found.
>
> Please open Contextify once to initialize the database.
>
> Download: https://contextify.sh/download

2) Search for an anchor:

```bash
contextify search "<query>" --project . --days 30 --limit 10 --json
```

Search query syntax (FTS5): Use `OR`, `AND`, `NOT` operators and quoted phrases. Example: `"memory leak" OR "out of memory"`.

Returns:
```json
{
  "data": [
    {
      "id": "e897a104-...",
      "contentSnippet": "...matched text with context...",
      "contentTruncated": true,
      "kind": "assistant",
      "score": -12.34,
      "timestamp": 1769380895,
      "projectName": "my-project",
      "projectId": "AB12CD34-...",
      "transcriptId": "5F9816DE-...",
      "provider": "claude.code"
    }
  ],
  "metadata": { "hasMore": true, "limit": 10, "returned": 10 },
  "schemaVersion": 1,
  "type": "search"
}
```

**Important:** `data` is a flat array of results. Each result's `id` is the UUID you pass to the `context` command. `projectId` is an opaque string (format varies). `score` is an internal ranking value; treat it as opaque. Results are already returned in best-first order; do not re-sort. If `contentTruncated` is `true`, always fetch full content via `context` (preferred) or `entry`.

If `--project .` returns a `dbProjectNotFound` error, retry without `--project` (omit it entirely) to search all projects. If you need a specific project, run `contextify projects --json` which returns a `data` array of objects with `name` and `rootPath` fields, then pass `--project <name>`.

Anchor selection guidance:

- Prefer older transcripts unless the user asked about the current chat session.
- If `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID` is set, down-rank hits from that transcript unless the user explicitly wants current session results.

3) Retrieve context around the anchor:

```bash
contextify context "<entry-uuid>" --before 10 --after 20 --project . --json
```

Returns:
```json
{
  "data": {
    "before": [
      { "id": "...", "kind": "user", "content": "...", "timestamp": 1769380791 }
    ],
    "anchor": {
      "id": "e897a104-...", "kind": "assistant", "content": "full text here...",
      "timestamp": 1769380895, "transcriptId": "...", "projectId": "..."
    },
    "after": [
      { "id": "...", "kind": "user", "content": "...", "timestamp": 1769380900 }
    ],
    "meta": {
      "transcriptEntryCount": 75,
      "hasMoreBefore": true,
      "hasMoreAfter": false
    }
  },
  "schemaVersion": 1,
  "type": "context"
}
```

**Important:** `data` is an object with `before` (array), `anchor` (object), and `after` (array). The `before` array is in chronological order. Read the entries directly from the JSON; do not pipe through `jq` or write parsers.

4) If a snippet is too short and you need the full entry:

```bash
contextify entry "<entry-uuid>" --json
```

Returns:
```json
{
  "data": {
    "entry": {
      "id": "...", "kind": "assistant", "content": "full untruncated text...",
      "timestamp": 1769380895, "transcriptId": "...", "projectId": "..."
    },
    "projectName": "my-project"
  },
  "schemaVersion": 1,
  "type": "entry"
}
```

5) Format response:

> **Contextify Total Recall**
>
> **Found:** [brief summary of what was found]
>
> **From:** [date/time and project context]
>
> [Key excerpts with citations]
>
> **Entry ID:** `<uuid>` (for reference)

## Working with the JSON output

**Successful responses** return `{"data": ..., "schemaVersion": 1, "type": "..."}`. **Errors** return `{"type": "error", "code": "...", "message": "...", "details": ...}`. Read the JSON output directly. You do not need to pipe it through `python3`, `jq`, or any other tool. You are capable of reading and interpreting JSON natively.

- **search**: `data` is an **array** of result objects; pagination info in `metadata`
- **context**: `data` is an **object** with `before`, `anchor`, `after`; pagination info in `meta` (note: name differs from search)
- **entry**: `data` is an **object** with `entry` and `projectName`
- **status**: `data` is an **object** with database stats

Common entry fields: `id` (UUID), `kind` (user/assistant/system), `content`, `timestamp` (Unix), `projectId`, `transcriptId`, `provider` (claude.code/codex).

## Error handling

Error responses have `"type": "error"` and a `code` field:
```json
{
  "code": "dbNotFound",
  "details": null,
  "message": "Database not found at expected location",
  "type": "error"
}
```

`details` may be `null` or an object with additional context (e.g., `details.suggestions` for `dbProjectNotFound`).

Branch on `code`:

| `code` | Response |
|-------|----------|
| `dbNotFound` | "Contextify database not found. Open Contextify to initialize. https://contextify.sh/download" |
| `dbProjectNotFound` | Check `details.suggestions`, offer alternatives |
| `featureUnavailable` | Explain limitation clearly, do not imply workarounds |
| `entryNotFound` | Re-search for a new anchor |
| `cliNotFound` | "Contextify CLI not found. See https://contextify.sh/help for installation." |

## Expanding search

If search returns 0 results:
1. Widen `--days` (try 90 or 365)
2. If not clearly about current repo, retry without `--project .`
3. Run `contextify projects --json` to list available projects (returns `data` array with `name` fields)
4. Ask user to clarify what they're looking for

## Delegating to researcher agent

**Claude Code only:** For complex multi-query searches, delegate to `contextify-researcher` agent:

```
Use the contextify-researcher agent to thoroughly search for [topic]
```

The researcher agent will perform multiple searches and synthesize results.

**Codex CLI:** Agent delegation is not available. Instead, run multiple searches manually and synthesize results yourself.
