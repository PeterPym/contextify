# Transcript Converter

Bidirectional converter for Claude Code ↔ Codex CLI transcript formats.

## Quick Start

```bash
# Make executable (if not already)
chmod +x scripts/convert_transcript.py

# Claude Code → Codex CLI
# IMPORTANT: Codex expects sessions in ~/.codex/sessions/YYYY/MM/DD/
./scripts/convert_transcript.py \
  --from claude-code \
  --to codex \
  ~/.claude/projects/-Users-rob-code-project/session-uuid.jsonl \
  ~/.codex/sessions/2025/10/19/converted-session-2025-10-19T14-00-00-<uuid>.jsonl

# The converter will show you exactly how to resume:
# ============================================================
# 📋 How to Resume This Conversation
# ============================================================
#
# 1. Navigate to the project directory:
#    cd /Users/rob/code/project
#
# 2. Resume the conversation with Codex CLI:
#    codex resume <session-id>
#    # OR use the picker:
#    codex resume
#
# 📍 Transcript location: ~/.codex/sessions/2025/10/19/converted-session-...jsonl
# 🆔 Session ID: <uuid>
# 📁 Project directory: /Users/rob/code/project
#
# ⚠️  If you used a different output path, the converter will warn you
# ============================================================

# Codex CLI → Claude Code
./scripts/convert_transcript.py \
  --from codex \
  --to claude-code \
  ~/codex-sessions/session.jsonl \
  ~/.claude/projects/-Users-rob-code-project/imported.jsonl

# Shows resume instructions for Claude Code:
# ============================================================
# 📋 How to Resume This Conversation
# ============================================================
#
# 1. Navigate to the project directory:
#    cd /Users/rob/code/project
#
# 2. Resume the conversation with Claude Code:
#    claude-code /resume imported
#
# 📍 Transcript location: ~/.claude/projects/-Users-rob-code-project/imported.jsonl
# 🆔 Session ID: imported
# 📁 Project directory: /Users/rob/code/project
# ============================================================
```

## Options

- `--from`: Source format (`claude-code` or `codex`)
- `--to`: Target format (`claude-code` or `codex`)
- `-v, --verbose`: Enable debug logging to stderr
- `input`: Input JSONL file path
- `output`: Output JSONL file path

## Features

### Automatic Resume Instructions

The converter automatically:
- ✅ **Extracts project directory** from transcript metadata (`cwd` field)
- ✅ **Identifies session ID** from filename (Claude Code) or generates one (Codex)
- ✅ **Prints exact commands** to resume the conversation in the target CLI
- ✅ **Shows file locations** so you know where the transcript was written

This means you don't have to guess where to `cd` or what command to run - just copy/paste!

## Testing Results

Tested with real Claude Code transcript (526 lines):

**Claude Code → Codex:**
- Input: 526 lines
- Converted: 150 messages
- Skipped: 376 (tool calls, snapshots, meta records)
- Errors: 0

**Codex → Claude Code (round-trip):**
- Input: 151 lines (150 messages + 1 session_meta)
- Converted: 150 messages
- Skipped: 1 (session_meta)
- Errors: 0

## Format Mapping

### Claude Code → Codex

| Claude Code | Codex CLI |
|-------------|-----------|
| `{uuid, type, message: {role, content}}` | `{timestamp, type: "response_item", payload: {role, content: [{type, text}]}}` |
| Per-message git context | Single `session_meta` at start |
| String or array content | Always array of `{type, text}` |

### Codex → Claude Code

| Codex CLI | Claude Code |
|-----------|-------------|
| `session_meta` | Git context extracted and added to all messages |
| `response_item` messages | User/assistant messages with UUIDs |
| Array content | Joined as string content |

## Known Limitations

1. **Tool calls**: Not converted in Phase 1 (skipped)
   - Claude Code: `tool_use` content blocks
   - Codex: `function_call` / `function_call_output` pairs

2. **Threading**: Lost when converting to Codex, regenerated for Claude Code
   - Claude Code: `parentUuid` chains
   - Codex: Temporal ordering only

3. **File snapshots**: Dropped (Claude Code specific)

4. **Encrypted reasoning**: Dropped (Codex specific)

5. **Event logs**: Dropped (Codex `event_msg` records)

## Validation

The converter preserves:
- ✅ All user and assistant messages
- ✅ Timestamps and chronological order
- ✅ Session context (git branch, cwd)
- ✅ Content fidelity (text messages)

Round-trip conversion successfully preserves all essential conversation data.

## Next Steps (Future Phases)

- **Phase 2**: Tool call conversion
- **Phase 3**: Comprehensive test suite
- **Phase 4**: UI integration in Contextify

## Related Documentation

- Feature spec: `todos.md` (Cross-CLI Transcript Converter)
- Format comparison: `build/notes/archive/technical-briefing-local-history-claude-code-codex.md`
- Current parsers: `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`
