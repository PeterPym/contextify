# Contextify Query (Claude Code Plugin)

This plugin provides skills and a researcher subagent that teach Claude Code how to use `contextify-query` for context reinjection.

## Install

```text
claude plugin marketplace add <repo-or-path>
claude plugin install query@contextify
```

Claude Code requires a restart after plugin install/update.

## Requirements

- Contextify app installed and has ingested transcripts (builds/maintains the DB).
- `contextify-query` available (install via Contextify → “Install/Repair CLI…”).

## Session metadata

This plugin registers a `SessionStart` hook that captures the active Claude Code session metadata (including the current transcript id) and persists it as environment variables for use in subsequent tool calls:

- `CONTEXTIFY_CLAUDE_SESSION_ID`
- `CONTEXTIFY_CLAUDE_TRANSCRIPT_PATH`
- `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID`
