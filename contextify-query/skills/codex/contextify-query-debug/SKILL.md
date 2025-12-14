---
name: contextify-query-debug
description: Diagnose why contextify-query cannot find the database, projects, entries, or features; provide deterministic troubleshooting steps and remediation prompts.
---

# Contextify query debugging (Codex)

## Quick triage

0) Confirm `contextify-query` exists:

```bash
command -v contextify-query
```

If missing:

- Explain that the skill requires the Contextify app (it builds and maintains the DB).
- Ask the user to install Contextify, then run Contextify → “Install/Repair CLI…”, then retry.

1) Check basic status:

```bash
contextify-query status --json
```

2) If the DB is missing (`dbNotFound`):

- Ask the user to open Contextify at least once (it creates/initializes the DB), then retry.

3) If project resolution fails:

```bash
contextify-query projects --json
```

- If the user is in a repo, prefer `--project .` when possible.

## Feature checks

If a command fails with `featureUnavailable`, describe the missing capability and suggest a fallback:

- If full-text search is unavailable, ask the user to use narrower queries (project-scoped + recent) or use `context` from known anchors.

## Data checks

If a specific entry id fails with `entryNotFound`:

- Re-run `search` with tighter query terms and confirm the returned `id` is used verbatim.

## CLI availability

If `contextify-query` is not found:

- Ask the user to run Contextify → “Install/Repair CLI…”, then retry.
