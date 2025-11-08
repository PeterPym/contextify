# Tier 1 Implementation Progress

**Date:** 2025-10-24
**Status:** In Progress
**Branch:** feature/swift-cli-converter (or create feature/tool-call-conversion)

---

## Completed ✅

### 1. Helper Functions Added to `convert_transcript.py`

**Location:** Lines 55-231

**Functions implemented:**
- `tool_use_id_to_call_id(tool_id)` - Convert `toolu_abc` → `call_abc`
- `call_id_to_tool_use_id(call_id)` - Convert `call_abc` → `toolu_abc`
- `bash_to_shell(tool_use_block, tool_result_block, timestamp, workdir)` - Full Bash → shell conversion
- `shell_to_bash(function_call_payload, function_output_payload, timestamp)` - Full shell → Bash conversion

**Features:**
- ✅ Command wrapping/unwrapping (`["bash", "-c", "cmd"]` ↔ `"cmd"`)
- ✅ Call ID mapping with collision avoidance
- ✅ Exit code mapping (`is_error` ↔ `exit_code`)
- ✅ Workdir inference (uses `self.project_dir` or `/` fallback)
- ✅ Timestamp incrementing for tool outputs (+1ms)
- ✅ Error handling for malformed JSON
- ✅ Duration placeholder (0.0 seconds for Claude Code → Codex)

### 2. Stats Tracking Enhanced

Added to `self.stats`:
```python
'tool_calls_direct': 0,      # Tier 1: Bash ↔ shell
'tool_calls_summarized': 0,  # Tier 2: Edit, Read, etc.
'tool_calls_skipped': 0      # Tier 3: TodoWrite, etc.
```

---

## Next Steps (In Progress) 🔄

### 3. Integrate Tool Conversion into `claude_to_codex()`

**Current behavior:** Only processes `text` content blocks, skips `tool_use`/`tool_result`

**Required changes:**

#### A. Process Tool Blocks in Assistant Messages

**Location:** `claude_to_codex()` around line 348-369

**Current code:**
```python
elif isinstance(content, list):
    # Already array, normalize type field
    content_array = []
    text_parts = []
    for block in content:
        if isinstance(block, dict) and block.get('text'):
            content_array.append({
                "type": content_type,
                "text": block['text']
            })
            text_parts.append(block['text'])
    text_for_event = '\n'.join(text_parts)
```

**New logic needed:**
```python
elif isinstance(content, list):
    content_array = []
    text_parts = []
    tool_uses = []  # Collect tool_use blocks

    for block in content:
        block_type = block.get('type')

        if block_type == 'text':
            # Text block
            text = block.get('text', '')
            if text:
                content_array.append({"type": content_type, "text": text})
                text_parts.append(text)

        elif block_type == 'tool_use':
            # Tool use block - collect for processing
            tool_uses.append(block)

    text_for_event = '\n'.join(text_parts)
```

#### B. Process Tool Result Blocks in User Messages

**Location:** Same loop, handle `tool_result` type

**New logic needed:**
```python
elif block_type == 'tool_result':
    # Collect tool results (will be matched with tool_uses)
    tool_results.append(block)
```

#### C. Write Function Calls to Output

After writing the assistant message, write function_call records:

```python
if record_type == "assistant" and tool_uses:
    # Process tool_use blocks
    for tool_use in tool_uses:
        tool_name = tool_use.get('name')

        if tool_name == 'Bash':
            # Tier 1: Direct conversion
            # Need to find matching tool_result (will be in next user message)
            # For now, write function_call without output
            func_call, _ = self.bash_to_shell(
                tool_use,
                None,  # Result comes later
                record['timestamp'],
                workdir=record.get('cwd')
            )
            if func_call:
                outfile.write(json.dumps(func_call, separators=(',', ':')) + '\n')
                self.stats['tool_calls_direct'] += 1

        # Tier 2/3 handling (TODO: Phase 2b/2c)
```

#### D. Write Function Call Outputs

When processing user messages with tool_result blocks:

```python
if record_type == "user" and tool_results:
    # Process tool_result blocks
    for tool_result in tool_results:
        tool_use_id = tool_result.get('tool_use_id')
        call_id = self.tool_use_id_to_call_id(tool_use_id)

        # Build function_call_output
        content = tool_result.get('content', '')
        is_error = tool_result.get('is_error', False)
        exit_code = 1 if is_error else 0

        output_data = {
            "output": content,
            "metadata": {
                "exit_code": exit_code,
                "duration_seconds": 0.0
            }
        }

        func_output = {
            "timestamp": record['timestamp'],
            "type": "response_item",
            "payload": {
                "type": "function_call_output",
                "call_id": call_id,
                "output": json.dumps(output_data, separators=(',', ':'))
            }
        }
        outfile.write(json.dumps(func_output, separators=(',', ':')) + '\n')
```

---

### 4. Integrate Tool Conversion into `codex_to_claude()`

**Current behavior:** Only processes `message` response_items, skips `function_call`/`function_call_output`

**Required changes:**

#### A. Track Function Calls

Add to method state:
```python
function_calls = {}  # call_id → (function_call_payload, timestamp)
```

#### B. Process function_call Records

```python
if record_type == 'response_item':
    payload = record.get('payload', {})
    payload_type = payload.get('type')

    if payload_type == 'function_call':
        # Store for later pairing with output
        call_id = payload.get('call_id')
        function_calls[call_id] = (payload, record['timestamp'])
        self.log(f"Line {line_num}: Stored function_call {call_id}")
        continue  # Don't write yet

    elif payload_type == 'function_call_output':
        # Pair with function_call and convert
        call_id = payload.get('call_id')
        if call_id in function_calls:
            func_payload, func_ts = function_calls.pop(call_id)
            func_name = func_payload.get('name')

            if func_name == 'shell':
                # Tier 1: Direct conversion
                tool_use, tool_result = self.shell_to_bash(
                    func_payload,
                    payload,
                    func_ts
                )
                # Add to assistant message content (need to buffer these)
                # ... (complex logic needed)
                self.stats['tool_calls_direct'] += 1
```

---

## Challenge: Message Structure Differences

### Problem: Tool Calls Are Embedded in Messages

**Claude Code:**
```json
{
  "type": "assistant",
  "message": {
    "content": [
      {"type": "text", "text": "Let me check..."},
      {"type": "tool_use", "id": "toolu_abc", "name": "Bash", ...}
    ]
  }
}

// Separate user message with result
{
  "type": "user",
  "message": {
    "content": [
      {"type": "tool_result", "tool_use_id": "toolu_abc", ...}
    ]
  }
}
```

**Codex:**
```json
{
  "type": "response_item",
  "payload": {"type": "function_call", "call_id": "call_abc", ...}
}

{
  "type": "response_item",
  "payload": {"type": "function_call_output", "call_id": "call_abc", ...}
}
```

### Solution: Buffering Strategy

**For Claude → Codex:**
1. When processing assistant message, collect all `tool_use` blocks
2. After writing assistant text message, write function_call records
3. When processing next user message, collect all `tool_result` blocks
4. Before writing user text message, write function_call_output records

**For Codex → Claude:**
1. Buffer function_call and function_call_output records by call_id
2. When building assistant message, inject tool_use blocks into content array
3. When building user message, inject tool_result blocks into content array

This requires **significant refactoring** of both methods.

---

## Alternative Approach: Two-Pass Processing

Instead of inline conversion, use two passes:

### Pass 1: Collect All Records
```python
records = []
for line in infile:
    record = json.loads(line)
    records.append(record)
```

### Pass 2: Convert with Full Context
```python
for i, record in enumerate(records):
    # Can look ahead/behind for tool results/uses
    next_record = records[i+1] if i+1 < len(records) else None

    # Convert with full context
    ...
```

**Pros:**
- Easier to pair tool_use with tool_result
- Can look ahead to find matching records
- Cleaner logic

**Cons:**
- Loads entire transcript into memory
- Slower for large files
- Breaks streaming processing

**Recommendation:** Use two-pass for Tier 1 implementation, optimize later if needed.

---

## Recommendation: Pause for User Feedback

Before proceeding with the large refactoring, recommend:

1. **Commit current progress** (helper functions added)
2. **Show user the two approaches** (inline vs two-pass)
3. **Get approval** on which strategy to use
4. **Create test fixtures** before implementing integration
5. **Then proceed** with full integration

**Estimated effort:**
- Inline approach: 3-4 hours (complex buffering logic)
- Two-pass approach: 2-3 hours (simpler but higher memory)

---

## Testing Plan (Phase 2a)

Once integration is complete:

### Unit Tests

**File:** `tests/test_tool_conversion.py` (create new)

```python
def test_bash_to_shell_simple():
    converter = TranscriptConverter()
    tool_use = {
        "type": "tool_use",
        "id": "toolu_abc123",
        "name": "Bash",
        "input": {"command": "ls -la"}
    }
    tool_result = {
        "type": "tool_result",
        "tool_use_id": "toolu_abc123",
        "content": "file1.txt\nfile2.txt",
        "is_error": False
    }

    func_call, func_output = converter.bash_to_shell(
        tool_use, tool_result, "2025-10-24T10:00:00.000Z"
    )

    assert func_call['payload']['name'] == 'shell'
    assert func_call['payload']['call_id'] == 'call_abc123'
    # ... more assertions
```

### Integration Test

**File:** `tests/fixtures/claude-code-with-bash.jsonl` (create)

Sample transcript with:
- 2 user messages
- 2 assistant messages with Bash tool calls
- Corresponding tool results

**Test:** Convert to Codex, verify function_call/output records exist

---

## Files Modified

1. ✅ `scripts/convert_transcript.py` - Added helper functions (lines 55-231)
2. 🔄 `scripts/convert_transcript.py` - Integrate into claude_to_codex (pending)
3. 🔄 `scripts/convert_transcript.py` - Integrate into codex_to_claude (pending)
4. 🔄 `tests/test_tool_conversion.py` - Create unit tests (pending)
5. 🔄 `tests/fixtures/` - Create test transcripts (pending)

---

## Next Action

**RECOMMEND:** Ask user:
1. Approve two-pass vs inline approach?
2. Should we create test fixtures first?
3. Proceed with full integration now or break into smaller PRs?

The helper functions are complete and working. The integration is the complex part.
