---
name: contextify-reinject
description: Use contextify-query to locate an anchor entry and retrieve a bounded neighborhood from Contextify's read-only database for reinjection.
---

# Contextify reinjection (Claude Code)

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

1) Confirm availability:

```bash
contextify-query status --json
```

2) Search for an anchor:

```bash
contextify-query search "<query>" --project . --days 30 --limit 10 --json
```

3) Use the selected result’s `id` (UUID) as the anchor:

```bash
contextify-query context "<entry-uuid>" --before 10 --after 20 --project . --json
```

4) Reinject a compact “Contextify Reinjection” block with:

- anchor id
- brief summary of the neighborhood
- key excerpts (respect truncation flags)

## Error handling

- `dbNotFound`: ask the user to open Contextify and retry.
- `dbProjectNotFound`: consult `details.suggestions` if present.
- `featureUnavailable`: explain missing capability and fall back to narrower methods.
- `entryNotFound`: re-search for a new anchor.

