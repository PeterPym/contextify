# Contextify Query (Claude Code Plugin)

This plugin provides the Contextify Total Recall skill, a `query:contextify-researcher` subagent, and a `SessionStart` hook that captures the active Claude Code session metadata. Together they let Claude Code search your conversation history using `contextify`.

## How it is installed today

On macOS DMG builds, Contextify installs the plugin automatically when the shim and plugin cache are written:

- Plugin cache: `~/.claude/plugins/cache/contextify/query/<version>/` (contains `.claude-plugin/plugin.json`, `agents/contextify-researcher.md`, `hooks/hooks.json`, `scripts/session_start.py`).
- Plugin manifest: `~/.claude/plugins/installed_plugins.json` has a `query@contextify` entry pointing at the cache directory.
- User skill copy: `~/.claude/skills/total-recall/SKILL.md` (so `/total-recall` autocomplete keeps working even before the plugin is enabled).

On Homebrew / App Store installs, running `contextify install-plugin` performs the same actions. On Linux, `contextify install-skill` installs the user skill; the plugin cache is not used.

Claude Code requires a restart after plugin install or update.

## Effective agent name

Because the researcher agent is shipped through a plugin, its runtime name in Claude Code is `query:contextify-researcher`, not bare `contextify-researcher`. The Total Recall skill references the scoped name explicitly. A standalone `~/.claude/agents/contextify-researcher.md` file is not required. Its absence is not a failure as long as the plugin is installed and visible to Claude Code (verify with `claude agents` or `contextify doctor`).

## Requirements

- Contextify app installed and has ingested transcripts (builds and maintains the DB).
- `contextify` available on `PATH` (install via Contextify -> "Install/Repair CLI...", or via Homebrew for App Store builds).

## Session metadata

The `SessionStart` hook captures the active Claude Code session metadata (including the current transcript path) and persists it as environment variables for use in subsequent tool calls:

- `CONTEXTIFY_CLAUDE_SESSION_ID`
- `CONTEXTIFY_CLAUDE_TRANSCRIPT_PATH`
