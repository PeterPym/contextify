---
name: contextify-reinject
description: Find and reinject relevant Contextify conversation history using contextify-query. Use when the user asks to search past conversations, find where something was discussed, look through prior sessions, or says “use Contextify to…”. Also use when debugging a missing memory or confirming prior decisions.
---

# Contextify Reinject

Use Contextify to retrieve precise historical context and reinject it into the current conversation. Prioritize relevance, minimize noise, and preserve source attribution.

## Quick Start
- Determine scope (project, time window, keywords).
- Use `contextify-query search` to find candidate entries.
- Select the best entry by relevance.
- Fetch surrounding context for that entry.
- Summarize and reinject with citation to entry IDs and timestamps.

If the skill does not auto-trigger, ask the user to run `/contextify-reinject` or explicitly say “use contextify to search history”.

## Guardrails
- Do not fabricate results. If the query returns empty, say so and adjust the query.
- Keep excerpts short. Prefer a brief summary plus a small quoted snippet.
- Always include entry IDs and timestamps when reinjecting.
- If the project or time window is unclear, ask one short clarifying question.

## Suggested Trigger Phrases
- "use contextify to"
- "search our conversation history"
- "find where we discussed"
- "look through past sessions"
- "what did we decide about"

## Workflow (Flexible with Fallback)
Use your best judgment for search strategy. If results are weak, follow the fallback:
1) Tighten scope (project + 30-90 days).
2) Use FTS5 operators (OR/AND/NOT) or quotes for exact phrases.
3) Re-run with narrower `--kinds` (user vs assistant).

## Examples

### Example 1: Basic search
```bash
contextify-query search "decision log" --days 30 --limit 10 --json
```

### Example 2: FTS5 OR syntax
```bash
contextify-query search "architecture OR design OR schema" --days 90 --limit 20 --json
```

### Example 3: Filter by kind
```bash
contextify-query search "rollback plan" --days 60 --kinds user --limit 10 --json
```

## Expected Output Pattern
When reinjecting, format like:

- Summary: 1-2 sentences
- Evidence: short quote (1-3 lines)
- Citation: entry IDs + timestamps

Example:

Summary: We agreed to prioritize the App Store build for onboarding testing and defer DMG polish.
Evidence: "Let’s do App Store first, then circle back to DMG release polish."
Citation: entry_id=abc123, timestamp=2025-12-11T18:22:09Z

## Troubleshooting
- Empty results: loosen query terms, expand days, remove `--kinds`, or switch to exact phrases.
- Too many results: add quotes, add AND terms, reduce days, or reduce limit.
- Invalid query: remove special characters like `|`; use FTS5 OR syntax instead.
