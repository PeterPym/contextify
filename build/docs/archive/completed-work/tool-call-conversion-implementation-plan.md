# Tool Call Conversion - Implementation Plan

**Date:** 2025-10-24
**Status:** Planning
**Prerequisites:** Read `tool-call-conversion-context.md` first
**Related:** `scripts/convert_transcript.py`, `build/notes/archive/technical-briefing-local-history-claude-code-codex.md`

---

## Overview

Implement tool call conversion for the transcript converter to preserve execution history and context when converting between Claude Code and Codex formats.

**Approach:** Tiered conversion strategy
- **Tier 1:** Direct conversion for compatible tools (Bash/shell)
- **Tier 2:** Lossy text summary for incompatible tools (Edit, Read, etc.)
- **Tier 3:** Skip tools with no conversational value

---

## Phase 1: Discovery & Documentation

### 1.1 Audit Claude Code Tool Usage

**Goal:** Document all unique Claude Code tools and their actual usage patterns

**Tasks:**
1. Scan recent Claude Code transcripts for tool_use content blocks
2. For each tool type found, extract:
   - Tool name
   - Input parameters structure
   - Output structure
   - Frequency of use
   - Example use cases

**Commands:**
```bash
# Find all tool names used
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name' \
  ~/.claude/projects/-Users-rob-code-projects-contextify/*.jsonl 2>/dev/null | \
  sort | uniq -c | sort -rn

# Extract full tool_use examples for a specific tool (e.g., Bash)
jq 'select(.type=="assistant") | .message.content[] | select(.type=="tool_use" and .name=="Bash")' \
  ~/.claude/projects/-Users-rob-code-projects-contextify/*.jsonl | head -5
```

**Deliverable:** `build/notes/research/claude-code-tool-inventory.md`
- Table of tools with frequency, parameters, output format
- Representative examples for each tool type

### 1.2 Audit Codex Tool Usage

**Goal:** Document all unique Codex function_call types

**Tasks:**
1. Scan recent Codex transcripts for function_call records
2. For each function type found, extract same info as 1.1

**Commands:**
```bash
# Find all function names used
jq -r 'select(.type=="function_call") | .name' \
  ~/.codex/sessions/2025/10/*/*.jsonl 2>/dev/null | \
  sort | uniq -c | sort -rn

# Extract full function_call + output pairs
jq -s '[.[] | select(.type=="function_call" or .type=="function_call_output")] |
  group_by(.call_id // "none")' \
  ~/.codex/sessions/2025/10/19/*.jsonl | head -3
```

**Deliverable:** `build/notes/research/codex-tool-inventory.md`

### 1.3 Create Tool Compatibility Matrix

**Goal:** Map which tools can convert directly, which need lossy conversion, which get skipped

**Deliverable:** `build/notes/research/tool-compatibility-matrix.md`

```markdown
| Claude Code Tool | Codex Equivalent | Conversion Type | Notes |
|------------------|------------------|-----------------|-------|
| Bash | shell | Direct (Tier 1) | Command, workdir, exit code map 1:1 |
| Edit | (none) | Lossy (Tier 2) | Summarize as "Edited X replacing Y with Z" |
| Read | (none) | Lossy (Tier 2) | Summarize as "Read X (N lines)" |
| ... | ... | ... | ... |
```

---

## Phase 2: Tier 1 Implementation (Direct Conversion)

### 2.1 Bash → shell (Claude Code to Codex)

**Input (Claude Code):**
```json
{
  "type": "assistant",
  "message": {
    "content": [
      {
        "type": "tool_use",
        "id": "toolu_abc123",
        "name": "Bash",
        "input": {
          "command": "git status",
          "description": "Check git status"
        }
      }
    ]
  }
}

// Separate message with tool result
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_abc123",
        "content": "On branch main\nnothing to commit, working tree clean",
        "is_error": false
      }
    ]
  }
}
```

**Output (Codex):**
```json
{
  "timestamp": "...",
  "type": "function_call",
  "name": "shell",
  "arguments": "{\"command\":[\"bash\",\"-c\",\"git status\"],\"workdir\":\"/path\"}",
  "call_id": "call_abc123"
}

{
  "type": "function_call_output",
  "call_id": "call_abc123",
  "output": "{\"output\":\"On branch main\\nnothing to commit, working tree clean\",\"metadata\":{\"exit_code\":0,\"duration_seconds\":0.0}}"
}
```

**Implementation notes:**
- Extract command from Claude Code `input.command`
- Generate unique `call_id` (or derive from `tool_use.id`)
- Wrap command as `["bash", "-c", "<command>"]`
- Use current `cwd` from session context for `workdir`
- Parse `is_error` flag to determine exit code (0 vs non-zero)
- Inject `duration_seconds: 0.0` (not available in Claude Code format)

### 2.2 shell → Bash (Codex to Claude Code)

**Reverse mapping of 2.1**

**Implementation notes:**
- Parse `arguments` JSON to extract command
- Unwrap `["bash", "-c", "X"]` to get actual command
- Create `tool_use` content block
- Create matching `tool_result` in separate user message
- Parse `exit_code` from output to set `is_error` flag
- Generate or preserve `tool_use_id` for linking

### 2.3 Test Cases

**Create test fixtures:**
1. Claude Code transcript with multiple Bash calls (success and failure)
2. Codex transcript with multiple shell calls
3. Round-trip test: CC → Codex → CC → verify tool calls preserved

**Validation:**
- Tool calls appear in converted transcript
- Commands execute equivalently (if re-run)
- Exit codes preserved
- Output content matches
- Conversation remains coherent

---

## Phase 3: Tier 2 Implementation (Lossy Conversion)

### 3.1 Define Summarization Templates

**For each incompatible tool, define a text template:**

```python
TOOL_SUMMARIES = {
    "Edit": "I edited `{file_path}`, replacing `{old_string}` with `{new_string}`.",
    "Write": "I created/overwrote `{file_path}` ({line_count} lines).",
    "Read": "I read `{file_path}` ({line_count} lines).",
    "Grep": "I searched for `{pattern}` and found {match_count} matches.",
    "Glob": "I searched for files matching `{pattern}` and found {file_count} files.",
    # ... etc
}
```

### 3.2 Implement Summarization Functions

```python
def summarize_tool_use(tool_name: str, tool_input: dict, tool_result: dict) -> str:
    """Convert tool_use to human-readable summary"""
    if tool_name not in TOOL_SUMMARIES:
        return f"I used the {tool_name} tool."  # Generic fallback

    template = TOOL_SUMMARIES[tool_name]
    # Extract params from input/result
    # Format template
    return summary

def inject_tool_summary_as_text(converter, tool_summary: str, timestamp: str):
    """Add tool summary as assistant text message in Codex format"""
    # Create event_msg with agent_message type
    # Create response_item with output_text
    # Maintain monotonic timestamps
```

### 3.3 Integration Points

**In Claude Code → Codex converter:**
- When encountering `tool_use` that's not Tier 1 (Bash):
  - Call `summarize_tool_use()`
  - Call `inject_tool_summary_as_text()`
  - Continue processing

**In Codex → Claude Code converter:**
- (Codex likely doesn't have tools we don't know about, but keep extensible)

### 3.4 Test Cases

1. Claude Code transcript with Edit, Read, Write calls
2. Verify summaries appear as assistant text in Codex
3. Verify conversation remains coherent
4. Verify no crashes on unknown tool types

---

## Phase 4: Error Handling & Edge Cases

### 4.1 Malformed Tool Data

**Scenarios:**
- Missing required fields (command, file_path, etc.)
- Invalid JSON in arguments/output
- Mismatched tool_use_id / call_id
- Tool results without matching tool_use

**Handling:**
- Log warning with line number
- Generate best-effort summary
- Don't fail conversion
- Track skipped tools in stats

### 4.2 Large Outputs

**Scenario:** Tool output is 10MB of log data

**Handling:**
- Truncate output to reasonable size (e.g., first 1000 chars + last 1000 chars)
- Add note: "(output truncated, {size} total)"
- Preserve exit code and metadata

### 4.3 Special Characters

**Scenario:** Output contains special JSON characters, null bytes, etc.

**Handling:**
- Proper JSON escaping
- Replace null bytes with placeholder
- Ensure valid UTF-8

---

## Phase 5: Testing & Validation

### 5.1 Unit Tests

Create `tests/test_tool_conversion.py`:
- Test each Tier 1 conversion function
- Test summarization templates
- Test error handling paths
- Test round-trip integrity

### 5.2 Integration Tests

Use real transcripts:
1. Find Claude Code session with heavy tool usage
2. Convert to Codex
3. Manually verify:
   - Tool calls appear and make sense
   - Conversation flows naturally
   - Key context preserved
4. Convert back to Claude Code
5. Resume in both CLIs and validate UX

### 5.3 Performance Testing

- Large transcripts (1000+ tool calls)
- Measure conversion time
- Verify memory usage reasonable
- Check for memory leaks

---

## Phase 6: Documentation & Polish

### 6.1 Update Technical Brief

Add section to `technical-briefing-local-history-claude-code-codex.md`:
- Tool call conversion strategy
- Tier definitions
- Example conversions
- Known limitations

### 6.2 Update Converter Help

Add to `convert_transcript.py` docstring:
- Tool conversion behavior
- Which tools convert directly
- Which are lossy
- How to interpret results

### 6.3 Add Conversion Report

When conversion completes, print summary:
```
✓ Converted Claude Code → Codex: output.jsonl

Statistics:
  Messages:           42 converted
  Tool calls:         15 total
    - Direct (Bash):  8 converted
    - Lossy (Edit):   5 summarized
    - Skipped:        2
```

---

## Success Criteria

✅ **Tier 1 (Bash/shell):** Direct conversion works in both directions
✅ **Round-trip:** CC with tools → Codex → CC preserves tool context
✅ **Tier 2:** Common file operations get meaningful summaries
✅ **Robust:** Handles malformed data without crashing
✅ **Tested:** Unit tests + integration tests passing
✅ **Documented:** Users understand what gets converted and how

---

## Timeline Estimate

- **Phase 1 (Discovery):** 2-3 hours
- **Phase 2 (Tier 1):** 4-6 hours
- **Phase 3 (Tier 2):** 3-4 hours
- **Phase 4 (Error Handling):** 2-3 hours
- **Phase 5 (Testing):** 3-4 hours
- **Phase 6 (Documentation):** 1-2 hours

**Total:** ~15-22 hours of implementation work

---

## Open Questions

1. **Tool result timing:** Claude Code has separate messages for tool results. How do we maintain timestamp ordering?
2. **Batch tool calls:** If Claude Code sends 5 tool calls at once, should they become 5 separate Codex function_calls or be batched somehow?
3. **Error propagation:** If a tool fails in Claude Code, should the Codex conversion show exit_code=1 or use a different signal?
4. **Unknown tools:** Should we fail loudly on unknown tools or silently summarize?

---

## Next Steps

1. **Start Phase 1.1:** Run the tool inventory commands on real transcripts
2. **Document findings:** Create the inventory markdown files
3. **Review with user:** Validate the tiered strategy makes sense for their use case
4. **Implement Tier 1:** Focus on Bash/shell conversion first (highest value)
5. **Iterate:** Add Tier 2 tools based on frequency of use
