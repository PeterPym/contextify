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

Anchor selection guidance:

- If the user is asking about earlier context (not “in this chat”), prefer anchors that are not from the active transcript.
- If `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID` is set, treat hits from that transcript as lower priority unless the user explicitly confirms they want the current session.
- If `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID` is missing and there are multiple plausible hits, avoid auto-selecting anchors from the last 30 minutes unless the user explicitly confirms the active session is relevant.

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
- `featureUnavailable`: explain the missing capability; do not imply that the CLI can “search anyway” if search is unavailable.
- `entryNotFound`: re-search for a new anchor.

## Common branch fixes

- Search returns 0 results:
  - widen `--days` (for example 90 or 365)
  - if the user’s request is not clearly about the current repo, retry without `--project .`
  - use `contextify-query projects --json` to discover known projects and explicitly pick one
