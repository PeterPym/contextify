# Show HN: Contextify – Resume AI conversations across Claude Code and Codex CLI

## The Problem

You're working on a project with Claude Code. Midway through, you want to try Codex CLI's different approach. But switching means losing your conversation history. You start from scratch, re-explaining context the AI already understood.

## What Contextify Does

**Contextify** is a macOS app that monitors and manages your AI coding assistant conversations. It lets you **resume conversations across different AI CLIs** without losing context.

### Core Features

1. **Unified Timeline**: View conversation history from both Claude Code and Codex CLI in one place, chronologically ordered with color-coded provider icons.

2. **Cross-CLI Transcript Conversion**: Convert transcripts between Claude Code and Codex CLI formats. Pick up a Claude Code conversation in Codex, or vice versa.

3. **Intelligent Summaries**: Uses Apple Intelligence (macOS 26+) to generate readable summaries of each message, with smart classification (directives, questions, completions).

4. **Multi-Project Discovery**: Automatically discovers all your projects using Claude Code or Codex CLI, indexes conversations in a local SQLite database.

5. **Session Management**: Browse all conversations, switch between sessions, see which files were modified, track token usage and costs.

## How It Works

**Database Layer**: Contextify continuously monitors your Claude Code and Codex CLI transcript directories (`~/.claude/projects/`, `~/.codex/sessions/`). It parses the JSONL files and stores everything in a local SQLite database with full-text search.

**Transcript Conversion**: Bidirectional Python CLI tool (`convert_transcript.py`) translates between formats:
- Normalizes message content (string vs array format)
- Extracts/generates session metadata (git branch, CWD, timestamps)
- Preserves conversation threading where possible
- Auto-generates proper filenames and directory structure for target CLI

**UI Integration**: SwiftUI app shows unified timeline with provider-specific icons, lets you browse sessions, and (soon) export conversations with one click.

## Current State

**What works:**
- ✅ Parses both Claude Code and Codex CLI transcript formats
- ✅ Unified timeline showing conversations from both providers
- ✅ Standalone converter script (command-line tool)
- ✅ Real-time monitoring with file watchers
- ✅ On-device LLM summaries (Apple Intelligence)
- ✅ Multi-project discovery and indexing

**What's coming:**
- 🚧 UI menu actions for one-click conversion ("Export to Codex CLI")
- 🚧 Tool call preservation (currently skips tool_use blocks)
- 🚧 Direct resume workflow (convert + open in target CLI)

**Known Limitations:**
- Basic message conversion only (no tool calls yet)
- Requires Python 3 for converter script
- macOS 26+ for LLM summaries (fallback to basic display on older macOS)

## Why This Matters

**Interoperability**: AI coding assistants are proliferating (Claude Code, Codex CLI, Cursor, Aider, etc.). Being locked into one tool's conversation format creates friction. Contextify treats conversations as portable data you own.

**Context Preservation**: Starting fresh every time you switch tools means wasting tokens and time re-establishing context. Cross-CLI resumption lets you continue where you left off.

**Unified History**: Your project's development story is scattered across multiple transcript directories. Contextify gives you one timeline showing what happened, when, and with which tool.

## Tech Stack

- **SwiftUI** (macOS 14+ target, built on macOS 26 SDK)
- **GRDB** (SQLite with Swift, WAL mode for concurrent access)
- **Apple FoundationModels** (on-device LLM for summaries)
- **DispatchSource** (file system monitoring)
- **Python 3** (transcript converter)

## Try It

The converter script is available now as a standalone tool (requires Claude Code or Codex CLI installed):

```bash
# Clone repo
git clone https://github.com/banagale/contextify.git
cd contextify

# Convert Claude Code session to Codex CLI
./scripts/convert_transcript.py \
  --from claude-code \
  --to codex \
  ~/.claude/projects/-Users-you-code-project/session.jsonl \
  ~/.codex/sessions/2025/10/24/rollout-2025-10-24T14-00-00-<uuid>.jsonl

# Resume in Codex CLI
cd ~/code/project && codex continue <uuid>
```

Full app build requires Xcode 16 (beta) and macOS 26 SDK. Detailed build instructions in `AGENTS.md`.

## Roadmap

**Near-term (1-2 weeks):**
- UI integration for converter (one-click export from app)
- Tool call preservation (map tool_use ↔ function_call)
- Preview/validation before conversion

**Medium-term (1-2 months):**
- Batch conversion (multiple sessions at once)
- Direct CLI resumption ("Export and Open in Codex")
- Support for more AI assistants (Cursor, Aider)

**Long-term:**
- Cloud backup integration (iCloud Drive, Dropbox)
- Semantic search across all conversations
- RAG-powered project insights ("What features did we abandon?")

## Questions for HN

1. **Which AI coding assistants do you use?** Curious what combination of tools people are switching between.

2. **How do you manage conversation history?** Do you keep transcripts? Search through them? Ignore them entirely?

3. **Tool call conversion:** Is preserving tool execution history critical, or are the text messages sufficient for context?

4. **Security:** Would you want transcript encryption, or is local-only storage sufficient?

## Links

- **GitHub**: https://github.com/banagale/contextify
- **Converter branch**: https://github.com/banagale/contextify/tree/feature/transcript-converter
- **Format docs**: `build/notes/technical-reference/claude-code-transcript-format.md`

---

Built this because I kept losing context when experimenting with different AI assistants. Figured others might have the same problem.

Open to feedback, especially on what conversions you'd find most useful!
