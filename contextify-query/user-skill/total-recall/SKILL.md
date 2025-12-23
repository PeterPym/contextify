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

1) Check CLI availability:

```bash
command -v contextify-query
```

2) If `contextify-query` is missing:

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
contextify-query status --json
```

If database not found, respond:
> Contextify database not found.
>
> Please open Contextify once to initialize the database.
>
> Download: https://contextify.sh/download

2) Search for an anchor:

```bash
contextify-query search "<query>" --project . --days 30 --limit 10 --json
```

Anchor selection guidance:

- If asking about earlier context (not "in this chat"), prefer anchors NOT from the active transcript.
- If `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID` is set, treat hits from that transcript as lower priority unless user explicitly wants current session.
- If transcript ID missing and multiple hits exist, avoid auto-selecting anchors from last 30 minutes.

3) Retrieve context around the anchor:

```bash
contextify-query context "<entry-uuid>" --before 10 --after 20 --project . --json
```

4) Format response:

> **Contextify Total Recall**
>
> **Found:** [brief summary of what was found]
>
> **From:** [date/time and project context]
>
> [Key excerpts with citations]
>
> **Entry ID:** `<uuid>` (for reference)

## Error handling

| Error | Response |
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
3. Use `contextify-query projects --json` to discover other projects
4. Ask user to clarify what they're looking for

## Delegating to researcher agent

For complex multi-query searches, delegate to `contextify-researcher` agent:

```
Use the contextify-researcher agent to thoroughly search for [topic]
```

The researcher agent will perform multiple searches and synthesize results.
