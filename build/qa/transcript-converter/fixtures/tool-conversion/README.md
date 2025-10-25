# Tool Conversion Test Fixtures

**Purpose:** Real-world transcripts for testing tool call conversion

**Added:** 2025-10-24
**Related:** Phase 2a (Tier 1: Bash↔shell) and Phase 2b (Tier 2: lossy text summaries)

---

## Fixtures

### 1. `cc-with-bash-tools.jsonl`

**Source:** Claude Code transcript `c118da1a-84e7-49b6-b631-967f48bae4bc.jsonl`

**Characteristics:**
- **Size:** 47 lines
- **Tool calls:** 7 Bash tool_use blocks with corresponding tool_result blocks
- **Content:** Real Contextify development session
- **Format:** Claude Code JSONL format

**Use cases:**
- Test Claude Code → Codex conversion with tool calls
- Verify function_call records are generated correctly
- Check command wrapping (command → `["bash", "-c", "command"]`)
- Verify exit code mapping (`is_error` → `exit_code`)

**Example tool_use structure:**
```json
{
  "type": "assistant",
  "message": {
    "content": [
      {"type": "text", "text": "Let me check..."},
      {
        "type": "tool_use",
        "id": "toolu_...",
        "name": "Bash",
        "input": {
          "command": "git status",
          "description": "Check repository status"
        }
      }
    ]
  }
}
```

**Expected output (Codex):**
- 7 `function_call` records with `name: "shell"`
- 7 `function_call_output` records with exit codes
- Proper call_id linking (`toolu_xxx` → `call_xxx`)

---

### 2. `codex-with-shell-tools.jsonl`

**Source:** Codex transcript `rollout-2025-10-19T13-34-08-0199fe2d-f20c-7c20-86f1-97dc9f502de4.jsonl`

**Characteristics:**
- **Size:** ~76KB (larger transcript)
- **Tool calls:** Multiple shell function_call/output pairs
- **Content:** Real Codex development session
- **Format:** Codex CLI JSONL format

**Use cases:**
- Test Codex → Claude Code conversion with tool calls
- Verify tool_use blocks are generated correctly
- Check command unwrapping (`["bash", "-lc", "command"]` → `"command"`)
- Verify exit code mapping (`exit_code` → `is_error`)

**Example function_call structure:**
```json
{
  "timestamp": "2025-10-19T20:37:17.754Z",
  "type": "response_item",
  "payload": {
    "type": "function_call",
    "name": "shell",
    "arguments": "{\"command\":[\"bash\",\"-lc\",\"codex -r\"],\"workdir\":\"/Users/rob/code/projects\"}",
    "call_id": "call_O101hvF6IitbzQvo8upQmWP5"
  }
}
```

**Expected output (Claude Code):**
- tool_use blocks with `name: "Bash"`
- tool_result blocks in user messages
- Proper tool_use_id linking (`call_xxx` → `toolu_xxx`)

---

## Testing Workflow

### Basic Conversion Test

**Claude Code → Codex:**
```bash
./scripts/convert_transcript.py \
  --from claude-code \
  --to codex \
  -v \
  build/qa/transcript-converter/fixtures/tool-conversion/cc-with-bash-tools.jsonl \
  /tmp/test-cc-to-codex.jsonl

# Verify function_call records
grep '"type":"function_call"' /tmp/test-cc-to-codex.jsonl | wc -l
# Expected: 7

# Check first function_call
grep '"type":"function_call"' /tmp/test-cc-to-codex.jsonl | head -1 | jq .
```

**Codex → Claude Code:**
```bash
./scripts/convert_transcript.py \
  --from codex \
  --to claude-code \
  -v \
  build/qa/transcript-converter/fixtures/tool-conversion/codex-with-shell-tools.jsonl \
  /tmp/test-codex-to-cc.jsonl

# Verify tool_use blocks
grep '"name":"Bash"' /tmp/test-codex-to-cc.jsonl | wc -l

# Check first tool_use
jq 'select(.message.content[]?.name == "Bash") | .message.content[] | select(.name == "Bash")' \
  /tmp/test-codex-to-cc.jsonl | head -20
```

### Round-Trip Test

**Claude Code → Codex → Claude Code:**
```bash
# First conversion
./scripts/convert_transcript.py \
  --from claude-code --to codex \
  build/qa/transcript-converter/fixtures/tool-conversion/cc-with-bash-tools.jsonl \
  /tmp/intermediate.jsonl

# Second conversion
./scripts/convert_transcript.py \
  --from codex --to claude-code \
  /tmp/intermediate.jsonl \
  /tmp/roundtrip.jsonl

# Compare tool counts
echo "Original Bash calls:"
grep -c '"name":"Bash"' build/qa/transcript-converter/fixtures/tool-conversion/cc-with-bash-tools.jsonl

echo "Round-trip Bash calls:"
grep -c '"name":"Bash"' /tmp/roundtrip.jsonl

# Should match: 7 = 7
```

---

## Validation Checks

### After Conversion to Codex

**Must verify:**
- [ ] All Bash tool_use blocks converted to shell function_call
- [ ] function_call has proper `arguments` JSON with command array
- [ ] function_call_output has matching `call_id`
- [ ] exit_code correctly reflects success/failure
- [ ] Commands are wrapped: `"git status"` → `["bash", "-c", "git status"]`

**Check script:**
```bash
CODEX_OUTPUT="/tmp/test-cc-to-codex.jsonl"

echo "=== Function Calls ==="
grep '"type":"function_call"' "$CODEX_OUTPUT" | wc -l

echo "=== Function Call Outputs ==="
grep '"type":"function_call_output"' "$CODEX_OUTPUT" | wc -l

echo "=== Sample function_call ==="
grep '"type":"function_call"' "$CODEX_OUTPUT" | head -1 | \
  jq '.payload | {name, call_id, args: .arguments | fromjson}'
```

### After Conversion to Claude Code

**Must verify:**
- [ ] All shell function_call converted to Bash tool_use
- [ ] tool_use appears in assistant message content array
- [ ] tool_result appears in user message content array
- [ ] tool_use_id matches tool_result.tool_use_id
- [ ] is_error correctly reflects exit_code != 0
- [ ] Commands are unwrapped: `["bash", "-lc", "cmd"]` → `"cmd"`

**Check script:**
```bash
CC_OUTPUT="/tmp/test-codex-to-cc.jsonl"

echo "=== Bash tool_use blocks ==="
grep '"name":"Bash"' "$CC_OUTPUT" | wc -l

echo "=== tool_result blocks ==="
grep '"type":"tool_result"' "$CC_OUTPUT" | wc -l

echo "=== Sample tool_use ==="
jq 'select(.type=="assistant") | .message.content[] | select(.name=="Bash")' \
  "$CC_OUTPUT" | head -20
```

---

## Known Issues & Edge Cases

### 1. Empty tool results
Some tool calls may have empty output (e.g., successful command with no stdout).
**Expected:** tool_result should have `content: ""` and `is_error: false`

### 2. Multi-line commands
Some Bash commands may span multiple lines.
**Expected:** Preserved as-is in JSON escaping

### 3. Special characters
Commands may contain quotes, pipes, redirects.
**Expected:** Proper JSON escaping maintained

### 4. Large outputs
Some tool results may have >100KB output.
**Current behavior:** Not truncated (TODO: implement truncation if needed)

---

## Future Additions

**Planned fixtures:**
- [ ] `cc-with-edit-tools.jsonl` - Edit/Read/Write for Tier 2 testing
- [ ] `minimal-bash.jsonl` - Minimal 10-line example for quick tests
- [ ] `edge-cases.jsonl` - Malformed tool calls, orphan results, etc.

---

## Maintenance

**When updating:**
1. Keep original transcripts in `~/.claude/` and `~/.codex/` (don't modify)
2. Copy to fixtures with descriptive names
3. Update this README with characteristics
4. Add to version control (fixtures are safe to commit - no sensitive data)

**File size guidelines:**
- Prefer transcripts < 100 lines for basic tests
- Keep at least one larger transcript (>1000 lines) for performance testing
- Include variety: simple commands, complex commands, errors, edge cases
