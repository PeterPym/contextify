---
todo_id: QUERY-CLI-FEEDBACK
title: CLI feedback inbox for contextify-query
type: spec
date: 2025-12-12
status: obsolete
description: Obsolete standalone spec; integrated into CONTEXT-REINJECTION-spec.md.
---

# CLI Feedback Inbox for `contextify-query`

This spec is obsolete. Use `build/notes/todo-support/CONTEXT-REINJECTION-spec.md` as the single consolidated spec.

## Goal

`contextify-query` supports context reinjection and external tooling. The feedback inbox captures “the CLI should support X” moments while the CLI is being used, without interrupting work.

This inbox is not a bug tracker and does not replace `build/notes/TODOS.md`.

## Constraints

- The CLI remains read-only with respect to the Contextify database.
- Feedback storage is separate from the database and separate from the git repo by default.
- The CLI does not auto-edit `build/notes/TODOS.md`.

## Commands

### Capture

Minimal one-liner (primary UX):

```bash
contextify-query feedback "search within transcript not supported"
```

Optional enrichment:

```bash
contextify-query feedback \
  --summary "search within transcript not supported" \
  --intent "Find auth mentions in one conversation" \
  --gap "search only supports global/project scope" \
  --workaround "Did global search, filtered client-side" \
  --proposal "Add --transcript-id filter to search"
```

Editor-based capture:

```bash
contextify-query feedback --edit
```

JSON stdin (auto-detects when piped; `--stdin` forces stdin parsing even if TTY):

```bash
cat feedback.json | contextify-query feedback --json
```

### Triage

```bash
contextify-query feedback list [--json]
contextify-query feedback show <feedback-id> [--json]
contextify-query feedback export <feedback-id> --format md|todo|json [--json]
contextify-query feedback dismiss <feedback-id>
contextify-query feedback archive [--older-than-days <n>]
contextify-query feedback clear --all
```

## Storage Model

Default inbox directory:

- `~/Library/Application Support/Contextify/feedback/`

Files:

- `fb_<YYYYMMDD>_<NNN>.json`

ID rules:

- Sequence is per-day and resets at `001`.
- Sequence is always zero-padded (e.g., `001`) so lexicographic sorting works.

Archive directory:

- `~/Library/Application Support/Contextify/feedback/archive/`

Dismissed items:

- `dismiss` moves the item into `feedback/archive/dismissed/` (keeps history).

## Feedback Item Schema

```json
{
  "id": "fb_20251212_001",
  "summary": "search within transcript not supported",
  "intent": "Find auth mentions in one conversation",
  "gap": "search only supports global/project scope",
  "workaround": "Did global search, filtered client-side",
  "proposal": "Add --transcript-id filter to search",
  "context": {
    "timestamp": "2025-12-12T11:34:56Z",
    "cliVersion": "<git/semver>",
    "schemaVersion": 28,
    "capabilities": ["fts_search", "summaries"]
  }
}
```

Rules:

- Required: `id`, `summary`, `context.timestamp`, `context.cliVersion`.
- Optional: `intent`, `gap`, `workaround`, `proposal`.
- Optional (opt-in capture): `cwd`, `resolvedDbPath`.

## Output Contract

Success (capture):

```json
{
  "type": "feedbackRecorded",
  "id": "fb_20251212_001",
  "path": "~/Library/Application Support/Contextify/feedback/fb_20251212_001.json",
  "summary": "search within transcript not supported"
}
```

List:

```json
{
  "type": "feedbackList",
  "items": [
    { "id": "fb_20251212_001", "summary": "...", "timestamp": "..." }
  ],
  "count": 1
}
```

Errors follow the CLI’s JSON error envelope.

## Guardrails

- Duplicate detection: hash `summary + intent`; warn if similar exists in last 7 days; allow override via `--force`.
- Soft rate limit: warn if > 5 feedback items in last hour and suggest consolidating; allow override via `--force`.
- Storage cap: keep last 100 items; archive older ones.
- Never touch git.

## Repo Workflow

`feedback export --format todo` prints a ready-to-paste TODO bullet that links the exported Markdown.

`feedback export --format md` writes the Markdown to stdout; `--output <path>` optionally writes to a file.

The CLI prints content but does not edit `build/notes/TODOS.md`.
