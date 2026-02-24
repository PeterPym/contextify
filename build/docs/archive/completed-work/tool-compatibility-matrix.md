# Tool Compatibility Matrix

**Generated:** 2025-10-24
**Purpose:** Define conversion strategy for all Claude Code ↔ Codex tool/function mappings
**Status:** Phase 1 Discovery Complete

---

## Summary

This matrix defines how each tool type converts between Claude Code and Codex CLI formats. Tools are classified into three tiers:

- **Tier 1 (Direct):** 1:1 mapping, non-lossy conversion
- **Tier 2 (Lossy):** Text summary extraction, preserves context but not execution
- **Tier 3 (Skip):** No conversational value, omitted during conversion

---

## Conversion Matrix

### Tier 1: Direct Conversion (Non-Lossy)

| Claude Code Tool | Codex Function | Frequency | Conversion Complexity | Notes |
|------------------|----------------|-----------|----------------------|-------|
| **Bash** | **shell** | CC: 44%<br>Codex: 89% | **Medium** | Command unwrapping/wrapping required; exit code mapping; workdir inference |

**Implementation Priority:** ⭐️⭐️⭐️⭐️⭐️ **CRITICAL** - Accounts for 44% of Claude Code calls and 89% of Codex calls

---

### Tier 2: Lossy Text Summary

| Claude Code Tool | Codex Equivalent | Frequency | Summary Template | Context Value |
|------------------|------------------|-----------|------------------|---------------|
| **Edit** | *(none)* | 20% | `I edited \`{file}\`, replacing \`{old}\` with \`{new}\`.` | High - shows what changed |
| **Read** | *(none)* | 17% | `I read \`{file}\` ({line_count} lines).` | Medium - shows what was examined |
| **Grep** | *(none)* | 7% | `I searched for \`{pattern}\` and found {match_count} matches in {file_list}.` | High - shows search context |
| **Write** | *(none)* | 2% | `I created/overwrote \`{file}\` ({line_count} lines).` | High - shows file creation |
| **Glob** | *(none)* | 0.8% | `I found {file_count} files matching \`{pattern}\`: {file_list}.` | Medium - shows discovery |
| **BashOutput** | *(none)* | 0.4% | `I checked background shell #{bash_id} output.` | Low - references async state |

**Implementation Priority:** ⭐️⭐️⭐️⭐️ **HIGH** - Tier 2 tools account for 46.8% of all Claude Code calls

---

### Tier 3: Skip Entirely

| Claude Code Tool | Codex Equivalent | Frequency | Reason to Skip |
|------------------|------------------|-----------|----------------|
| **TodoWrite** | update_plan* | 9.7% | UI state, no code context |
| **WebSearch** | *(none)* | 0.2% | External research, not project-specific |
| **WebFetch** | *(none)* | 0.2% | External content fetch |
| **ExitPlanMode** | *(none)* | 0.2% | UI mode change |
| **KillShell** | *(none)* | <0.1% | Process management, no lasting context |
| **Task** | *(none)* | <0.1% | Sub-agent invocation metadata |
| **AskUserQuestion** | *(none)* | <0.1% | Interactive prompt (answered in next user message) |
| **SlashCommand** | *(none)* | <0.1% | Custom command invocation |

\* Codex `update_plan` is structurally different from Claude Code `TodoWrite` and also skipped.

**Implementation Priority:** ⭐️ **LOW** - These can be silently omitted without loss of code context

---

## Coverage Analysis

| Tier | Claude Code Tools | % of Total Calls | Codex Functions | % of Total Calls |
|------|-------------------|------------------|-----------------|------------------|
| Tier 1 | 1 tool (Bash) | 44.1% | 1 function (shell) | 88.6% |
| Tier 2 | 6 tools | 46.8% | 0 functions | 0% |
| Tier 3 | 8 tools | 9.1% | 1 function (update_plan) | 11.4% |

**Key Insight:** Implementing Tier 1 + Tier 2 conversion captures **90.9%** of Claude Code tool usage context.

---

## Detailed Conversion Specifications

### 1. Bash ↔ shell (Tier 1)

#### Claude Code → Codex

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

// Separate user message with tool result
{
  "type": "user",
  "message": {
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_abc123",
        "content": "On branch main\nnothing to commit",
        "is_error": false
      }
    ]
  }
}
```

**Output (Codex):**
```json
{
  "timestamp": "2025-10-24T10:00:00.000Z",
  "type": "response_item",
  "payload": {
    "type": "function_call",
    "name": "shell",
    "arguments": "{\"command\":[\"bash\",\"-c\",\"git status\"],\"workdir\":\"/Users/rob/code/projects/contextify\"}",
    "call_id": "call_abc123"
  }
}

{
  "timestamp": "2025-10-24T10:00:00.100Z",
  "type": "response_item",
  "payload": {
    "type": "function_call_output",
    "call_id": "call_abc123",
    "output": "{\"output\":\"On branch main\\nnothing to commit\",\"metadata\":{\"exit_code\":0,\"duration_seconds\":0.0}}"
  }
}
```

**Conversion Logic:**
1. Extract `input.command` from Claude Code
2. Wrap as `["bash", "-c", "<command>"]`
3. Infer `workdir` from session context (default to project root)
4. Generate or derive `call_id` from `tool_use.id` (e.g., `toolu_abc123` → `call_abc123`)
5. Map `is_error: false` → `exit_code: 0`; `is_error: true` → `exit_code: 1`
6. Use `duration_seconds: 0.0` as placeholder
7. Preserve timestamps (increment by 1ms if needed for monotonicity)

**Edge Cases:**
- Multi-line commands: Preserve newlines in JSON escaping
- Commands with quotes: Ensure proper JSON escaping
- Large outputs: Truncate if >100KB (document truncation in conversion log)

---

#### Codex → Claude Code

**Reverse mapping of above:**

1. Parse `arguments` JSON to extract `command` array
2. Unwrap `["bash", "-lc", "X"]` or `["bash", "-c", "X"]` to get command string
3. Create `tool_use` content block with `name: "Bash"`
4. Generate `tool_use.id` from `call_id` (e.g., `call_abc123` → `toolu_abc123`)
5. Create separate tool result message with `tool_use_id`
6. Parse `output` JSON to extract `output` string and `exit_code`
7. Map `exit_code != 0` → `is_error: true`
8. Discard `duration_seconds` (not representable)
9. Discard `workdir` (not representable)
10. Discard `input.description` (synthesize generic description or omit)

**Edge Cases:**
- `with_escalated_permissions`: Discard (Claude Code has no permission system)
- `justification`: Discard
- Commands not wrapped in bash: Handle gracefully (join array as string)

---

### 2. Edit (Tier 2)

**Claude Code → Codex:**

**Input:**
```json
{
  "type": "tool_use",
  "name": "Edit",
  "input": {
    "file_path": "/path/to/file.swift",
    "old_string": "foo",
    "new_string": "bar",
    "replace_all": false
  }
}
```

**Output (Codex assistant message):**
```json
{
  "timestamp": "2025-10-24T10:00:00.000Z",
  "type": "response_item",
  "payload": {
    "type": "message",
    "role": "assistant",
    "content": [
      {
        "type": "output_text",
        "text": "I edited `file.swift`, replacing `foo` with `bar`."
      }
    ]
  }
}
```

**Template:**
```
I edited `{basename(file_path)}`, replacing `{old_string_preview}` with `{new_string_preview}`.
```

**Preview Logic:**
- If string < 50 chars: show full string in backticks
- If string > 50 chars: show first 40 chars + "..." in backticks
- If string is multi-line: show first line + " (multiline)" indicator

**Result Handling:**
- If `is_error: false`: Use template above
- If `is_error: true`: "I attempted to edit `{file}` but encountered an error: {error_message}"

---

### 3. Read (Tier 2)

**Template:**
```
I read `{basename(file_path)}` ({line_count} lines).
```

**Line Count Calculation:**
```python
line_count = len([line for line in content.split('\n') if line.strip()])
```

**With offset/limit:**
```
I read `{basename(file_path)}` (lines {offset}-{offset+limit}).
```

---

### 4. Grep (Tier 2)

**Template:**
```
I searched for `{pattern}` and found {match_count} matches in {file_count} files.
```

**With file list (if < 5 files):**
```
I searched for `{pattern}` and found {match_count} matches in: {comma_separated_basenames}.
```

---

### 5. Write (Tier 2)

**Template:**
```
I created `{basename(file_path)}` ({line_count} lines).
```

**If file already existed:**
```
I overwrote `{basename(file_path)}` ({line_count} lines).
```

**Detection:** Cannot determine if file existed (Claude Code doesn't report this). Use "created/overwrote" phrasing or default to "created".

---

### 6. Glob (Tier 2)

**Template:**
```
I found {file_count} files matching `{pattern}`: {file_list_preview}.
```

**File List Preview:**
- If ≤ 5 files: show all basenames comma-separated
- If > 5 files: show first 5 basenames + "and {N} more"

---

### 7. BashOutput (Tier 2)

**Template:**
```
I checked background shell output.
```

*(Minimal context - just indicates the action occurred)*

---

## Implementation Guidelines

### Timestamp Management

**Rule:** Maintain monotonic timestamps. If source timestamps are out of order, increment by 1ms.

**Example:**
```python
def ensure_monotonic(timestamps: list[str]) -> list[str]:
    result = []
    last_ts = None
    for ts_str in timestamps:
        ts = datetime.fromisoformat(ts_str)
        if last_ts and ts <= last_ts:
            ts = last_ts + timedelta(milliseconds=1)
        result.append(ts.isoformat())
        last_ts = ts
    return result
```

### Call ID Mapping

**Claude Code → Codex:**
```python
def tool_use_id_to_call_id(tool_id: str) -> str:
    # toolu_abc123 → call_abc123
    if tool_id.startswith("toolu_"):
        return "call_" + tool_id[6:]
    return "call_" + tool_id
```

**Codex → Claude Code:**
```python
def call_id_to_tool_use_id(call_id: str) -> str:
    # call_abc123 → toolu_abc123
    if call_id.startswith("call_"):
        return "toolu_" + call_id[5:]
    return "toolu_" + call_id
```

### Error Handling

**Malformed Data:**
- Missing required fields: Log warning, use placeholder values
- Invalid JSON in arguments/output: Log warning, skip tool call
- Orphan tool results: Log warning, skip
- Orphan tool uses: Log warning, inject synthetic success result

**Large Outputs:**
- If output > 100KB: Truncate to first 50KB + last 50KB with "(truncated)" marker
- Log truncation to conversion report

### Conversion Report

After conversion, print:
```
✓ Converted Claude Code → Codex: output.jsonl

Statistics:
  Messages:              42 converted
  Tool calls:            15 total
    Tier 1 (Bash):       8 converted (direct)
    Tier 2 (Edit/Read):  5 summarized (lossy)
    Tier 3 (TodoWrite):  2 skipped

  Warnings:
    - 1 orphan tool result (skipped)
    - 2 large outputs truncated (>100KB)

  Timestamp adjustments:  3 (monotonicity)
  Call ID mappings:       15
```

---

## Testing Strategy

### Unit Tests

1. **Bash ↔ shell conversion:**
   - Simple command: `ls -la`
   - Command with quotes: `echo "hello world"`
   - Command with pipes: `ls | grep foo`
   - Multi-line command: `for i in 1 2 3; do echo $i; done`
   - Failed command (exit code != 0)
   - Large output (>100KB)

2. **Tier 2 summarization:**
   - Edit with short strings
   - Edit with multi-line strings
   - Read with offset/limit
   - Grep with multiple matches
   - Write with large file

3. **Edge cases:**
   - Orphan tool result
   - Orphan tool use
   - Out-of-order timestamps
   - Duplicate call IDs

### Integration Tests

1. **Round-trip conversion:**
   - CC → Codex → CC: Verify Bash calls preserved
   - Codex → CC → Codex: Verify shell calls preserved

2. **Real transcript conversion:**
   - Pick Claude Code session with 50+ Bash calls
   - Convert to Codex
   - Verify all Bash calls appear as shell functions
   - Verify Tier 2 summaries are readable
   - Verify Tier 3 tools are skipped

3. **Conversation coherence:**
   - Resume converted session in target CLI
   - Ask assistant to reference "the command we ran earlier"
   - Verify assistant can reference tool execution context

---

## Known Limitations

### 1. Lossy Tier 2 Conversion (Permanent Information Loss)
File operation details are **not preserved** in Codex conversion. Edit/Read/Write/Grep/Glob tools become text summaries only.

**Impact:** Cannot re-execute Edit operations or access exact old/new strings in converted transcript.
**Mitigation:** Summaries preserve enough context for conversation continuity. Use git for code history.

### 2. Claude Code /rewind Checkpoints Are Lost
Claude Code's `/rewind` feature relies on file snapshots stored in `file-history-snapshot` records and `trackedFileBackups` arrays. These are **not converted** during Claude Code → Codex conversion.

**Impact:**
- Users cannot use `/rewind` in converted sessions (neither Codex nor Claude Code after importing from Codex)
- Checkpoint-based code restoration is not available
- Particularly important: **Codex → Claude Code conversion cannot support /rewind** since Codex has no checkpoint mechanism

**Mitigation:**
- Use git version control for permanent checkpoints (`git commit` regularly)
- Bash tool calls for `git` commands ARE preserved (Tier 1), providing permanent history
- For active development, keep sessions in native CLI to retain rewind capability

**Technical detail:** The `/rewind` system depends on Claude Code's automatic file snapshots before each Edit/Write operation. Since Codex has no equivalent feature, Codex transcripts contain no checkpoint data. Therefore, any transcript passing through Codex format loses all rewind capability permanently.

### 3. Codex-Specific Metadata Discarded
When converting Codex → Claude Code, these fields are lost:
- `workdir` (working directory)
- `duration_seconds` (command execution time)
- `with_escalated_permissions` (permission requests)
- `justification` (permission reasoning)

**Impact:** Minor - these fields aren't critical for conversation context.

### 4. Timestamp Precision Normalization
Source transcripts may have varying timestamp precision (ms, μs). Converter normalizes to milliseconds.

**Impact:** Timing precision lost, but conversation ordering preserved.

---

## Next Steps (Phase 2)

1. ✅ Phase 1 Discovery complete
2. 🔄 Implement Tier 1 (Bash ↔ shell) conversion in `scripts/transcripts/convert_transcript.py`
3. 🔄 Add unit tests for Tier 1
4. 🔄 Implement Tier 2 (Edit, Read, Grep, Write, Glob) summarization
5. 🔄 Add integration tests with real transcripts
6. 🔄 Add conversion report output
7. 🔄 Document known limitations and edge cases

---

## References

- **Claude Code Tool Inventory:** `claude-code-tool-inventory.md`
- **Codex Tool Inventory:** `codex-tool-inventory.md`
- **Implementation Plan:** `/tmp/tool-call-conversion-implementation-plan.md`
- **Context Doc:** `/tmp/tool-call-conversion-context.md`
- **Transcript Format Reference:** `build/notes/archive/technical-briefing-local-history-claude-code-codex.md`
