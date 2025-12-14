# Contextify Query (Claude Code Plugin)

This plugin provides skills that teach Claude Code how to use `contextify-query` for context reinjection.

## Install

```text
claude plugin marketplace add <repo-or-path>
claude plugin install query@contextify
```

Claude Code requires a restart after plugin install/update.

## Requirements

- Contextify app installed and has ingested transcripts (builds/maintains the DB).
- `contextify-query` available (install via Contextify → “Install/Repair CLI…”).

