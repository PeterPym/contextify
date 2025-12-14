---
name: contextify-query-debug
description: Diagnose missing DB/projects/features for contextify-query and provide deterministic remediation steps.
---

# Contextify query debugging (Claude Code)

## Status and discovery

```bash
contextify-query status --json
contextify-query projects --json
```

## Common failures

- `dbNotFound`: ask the user to open Contextify at least once and retry.
- `dbProjectNotFound`: pick from `details.suggestions` if present; otherwise ask user.
- `featureUnavailable`: explain the missing capability and suggest a narrower fallback.
- `entryNotFound`: re-run `search` and use the returned `id` verbatim.

## CLI not found

If `contextify-query` is not found on PATH:

- Ask the user to run Contextify → “Install/Repair CLI…”, then retry.
