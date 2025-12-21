---
name: contextify-reinject
description: Search past conversations / decisions with Contextify (use contextify, search history, find where we discussed, what did we decide, look back in past sessions, remember when we talked about). Runs contextify-query to locate an anchor entry and retrieve nearby context for reinjection.
---

# Contextify reinjection (Codex)

## Trigger phrases

- "use contextify to..."
- "search our conversation history"
- "find where we discussed..."
- "look through past sessions"

## Preconditions

This skill depends on the Contextify app (it builds and maintains the database that `contextify-query` reads).

1) Check whether the CLI is available:

```bash
command -v contextify-query
```

2) If `contextify-query` is missing:

- If Contextify is installed: ask the user to run Contextify → “Install/Repair CLI…”, then retry.
- If Contextify is not installed: instruct the user to install Contextify first, then retry.

## Canonical loop

1) Confirm availability (especially if DB may not exist yet):

```bash
contextify-query status --json
```

2) Choose scope:

- If request is about the current repo: use `--project .`
- If request spans projects: omit `--project` or use an explicit project id/name

3) Find anchor entries:

```bash
contextify-query search "<query>" --project . --days 30 --limit 10 --json
```

- Each result has an `id` (a UUID string). Treat this as the anchor entry id.
- If snippets are truncated, do not assume you have full content.

4) Fetch a bounded neighborhood around the anchor:

```bash
contextify-query context "<entry-uuid>" --before 10 --after 20 --project . --json
```

5) Reinject:

- Provide a compact “Contextify Reinjection” block containing:
  - the anchor id
  - a short summary of the neighborhood
  - the most relevant excerpts (respect truncation flags)

## Error handling

- `dbNotFound`: ask the user to open Contextify at least once (or pass `--db-path` if supported) and retry.
- `dbProjectNotFound`: use `details.suggestions` if present; otherwise ask user which project.
- `featureUnavailable`: explain the missing capability (e.g., search index) and fall back to narrower methods.
- `entryNotFound`: treat anchor as stale; re-run search to find a new anchor.

## Budgeting defaults

- Default: `--before 10 --after 20`
- Only widen windows if the first neighborhood is insufficient.
- Prefer time scoping (`--days N`) over huge windows.
