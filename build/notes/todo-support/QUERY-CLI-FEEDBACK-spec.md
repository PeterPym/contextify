---
todo_id: QUERY-CLI-FEEDBACK
title: CLI feedback inbox for contextify-query
type: spec
date: 2025-12-12
status: active
description: Add a low-friction `contextify-query feedback` command family that records CLI gaps to an App Support inbox for later triage, without modifying the database or repo by default.
---

# CLI Feedback Inbox for `contextify-query`

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

JSON stdin:

```bash
cat feedback.json | contextify-query feedback --stdin --json
```

### Triage

```bash
contextify-query feedback list [--json]
contextify-query feedback show <feedback-id> [--json]
contextify-query feedback export <feedback-id> --format md|todo-line [--json]
contextify-query feedback dismiss <feedback-id>
```

## Storage Model

Default inbox directory:

- `~/Library/Application Support/Contextify/feedback/`

Files:

- `fb_<YYYYMMDD>_<NNN>.json`

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
- Soft rate limit: warn if > 5 feedback items in last hour.
- Storage cap: keep last 100 items; archive older ones.
- Never touch git.

## Repo Workflow

`feedback export --format todo-line` prints a ready-to-paste TODO bullet that links the exported Markdown.

The CLI prints content but does not edit `build/notes/TODOS.md`.

