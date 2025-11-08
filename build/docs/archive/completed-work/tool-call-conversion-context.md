# Tool Call Conversion - Background Context

**Date:** 2025-10-24
**Status:** Planning phase
**Related Work:** Transcript converter (`scripts/convert_transcript.py`)

---

## Current State of Transcript Conversion

### What's Working (Completed 2025-10-24)

✅ **Bidirectional message conversion** - Claude Code ↔ Codex
✅ **Monotonic timestamps** - Proper timestamp generation (1ms increments)
✅ **parentUuid threading** - Conversation chain linking for Claude Code
✅ **Complete Codex structure** - All 5 required records per exchange
✅ **file-history-snapshot generation** - Claude Code snapshots created during conversion
✅ **Round-trip validation** - CC → Codex → CC → Codex tested successfully

**Key Achievement:** Basic conversational messages (user text, assistant text) convert perfectly between formats and maintain conversation integrity through multiple round-trips.

### What's Missing

❌ **Tool call conversion** - Currently skipped entirely during conversion
❌ **File backup/restore metadata** - `trackedFileBackups` not converted

**Impact:** When you convert a transcript with tool usage (shell commands, file edits, etc.), all that execution history is lost. The resumed conversation has no context about:
- What commands were tried
- What worked vs failed
- What files were modified
- What outputs informed decisions

---

## The Tool Call Problem

### Different Tool Architectures

**Codex Tools:**
- `shell` - Bash command execution
- Format: `function_call` + `function_call_output` pairs with `call_id` linking

**Claude Code Tools:**
- `Bash` - Shell command execution
- `Edit` - File editing with old/new string replacement
- `Write` - Create/overwrite files
- `Read` - Read file contents
- `Grep` - Search file contents (ripgrep)
- `Glob` - File pattern matching
- `Task` - Launch specialized agents
- `WebFetch`, `WebSearch`, `TodoWrite`, `AskUserQuestion`, etc.
- Format: `tool_use` content blocks in assistant messages + separate tool result messages

### Why This Matters

**User's Key Insight:**
> "Would a shell or bash tool call include syntax that does or does not work that might be useful later in the convo?"

**Answer:** YES! Tool calls contain:
- ✅ **Command that was executed** - Shows exactly what was tried
- ✅ **Exit code** - Whether it succeeded (0) or failed (non-zero)
- ✅ **Output** - stdout/stderr with errors, file paths, results
- ✅ **Working directory** - Context for relative paths
- ✅ **File modifications** - What was edited, created, or read

**Example valuable scenarios:**
1. "I tried `git push` and got error X" - preserved in tool output
2. "I ran tests and 3 failed" - exit code + output show exactly what happened
3. "I edited `TranscriptOrchestrator.swift` to fix the bug" - file path + changes preserved
4. "I searched for 'parentUuid' and found it in 5 files" - search pattern + results

---

## Conversion Strategy: Tiered Approach

### Tier 1: Direct Conversion (Non-Lossy)
**Tools with 1:1 mapping:**
- Codex `shell` ↔ Claude Code `Bash`

Both execute shell commands, arguments translate directly, output/exit codes map cleanly.

**Conversion approach:** Direct translation between `function_call`/`function_call_output` and `tool_use`/tool result records.

### Tier 2: Lossy Text Summary
**Tools without equivalents:**
- Claude Code only: `Edit`, `Write`, `Read`, `Grep`, `Glob`, etc.
- Codex only: (to be discovered)

**Conversion approach:** Extract key info and inject as assistant text message.

Example:
```
Original (Claude Code):
  tool_use: Edit(file="foo.py", old="bar", new="baz")
  tool_result: success

Converted to Codex:
  assistant message: "I edited `foo.py`, replacing 'bar' with 'baz'."
```

### Tier 3: Skip Entirely
**Tools that provide no conversational value:**
- Internal diagnostics
- Telemetry
- Things that don't inform future conversation

---

## Current Converter Behavior

**Location:** `scripts/convert_transcript.py`

**Claude Code → Codex:**
- Skips all `tool_use` content blocks
- Only converts `text` content blocks to `output_text`

**Codex → Claude Code:**
- Skips all `function_call` and `function_call_output` records
- Only converts `response_item` messages with text content

**Result:** Clean conversational flow, but complete loss of execution history.

---

## Why This Needs to Be Fixed

**Use Case:** A developer using Claude Code creates a session with:
1. 50 shell commands tried (some worked, some failed)
2. 20 files edited with specific changes
3. Test output showing which tests passed/failed
4. Search results finding the bug location

When they convert to Codex and resume:
- ❌ All that context is gone
- ❌ Can't reference "the command that failed earlier"
- ❌ Can't see "the files we already modified"
- ❌ Loses continuity about what was tried and what worked

**Goal:** Preserve enough context that the resumed conversation feels like a natural continuation, not a fresh start.

---

## Next Steps

See `tool-call-conversion-implementation-plan.md` for the detailed implementation plan.

**Immediate Task:** Audit real transcripts to document all unique tool types and their arguments/outputs.
