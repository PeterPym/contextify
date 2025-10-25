# Codex CLI Tool Inventory

**Generated:** 2025-10-24
**Source:** Codex session transcripts (`~/.codex/sessions/2025/10/*/*.jsonl`)
**Purpose:** Document all function_call types used in Codex CLI for transcript conversion planning

---

## Summary Statistics

Total function calls analyzed from October 2025 Codex sessions:

| Function | Count | % of Total |
|----------|-------|------------|
| shell | 31 | 88.6% |
| update_plan | 4 | 11.4% |
| **TOTAL** | **35** | **100%** |

**Note:** Sample size is much smaller than Claude Code (35 vs 7,601 calls). Codex appears to be used less frequently or has fewer tool types.

---

## Function Definitions

### 1. shell (88.6% of calls)

**Purpose:** Execute shell commands in a bash environment

**Record Structure (function_call):**
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

**Record Structure (function_call_output):**
```json
{
  "timestamp": "2025-10-19T20:37:17.754Z",
  "type": "response_item",
  "payload": {
    "type": "function_call_output",
    "call_id": "call_O101hvF6IitbzQvo8upQmWP5",
    "output": "{\"output\":\"error: unexpected argument '-r' found\\n...\",\"metadata\":{\"exit_code\":2,\"duration_seconds\":0.1}}"
  }
}
```

**Key Fields:**

**In `arguments` (JSON string):**
- `command` (array of strings): Shell command as `["bash", "-lc", "<actual_command>"]` or `["bash", "-c", "<command>"]`
- `workdir` (string): Working directory for command execution
- `with_escalated_permissions` (boolean, optional): Whether elevated privileges are requested
- `justification` (string, optional): Reason for requesting escalated permissions

**In `output` (JSON string):**
- `output` (string): Combined stdout/stderr
- `metadata.exit_code` (integer): Command exit code (0 = success)
- `metadata.duration_seconds` (float): Execution time

**Notes:**
- Most common Codex function (89%)
- **Direct equivalent to Claude Code `Bash` tool**
- Command is wrapped in bash invocation: `["bash", "-lc", "actual_command"]`
- `-lc` flag loads login shell configuration, `-c` does not
- Exit code explicitly tracked (Claude Code uses `is_error` boolean)
- Duration tracked (not available in Claude Code)

**Conversion Strategy:**
- **Codex → Claude Code:** Unwrap `["bash", "-lc", "X"]` to get command string; map `exit_code != 0` to `is_error: true`
- **Claude Code → Codex:** Wrap command as `["bash", "-c", "<command>"]`; derive exit code from `is_error`

---

### 2. update_plan (11.4% of calls)

**Purpose:** Update the agent's task planning state

**Record Structure (function_call):**
```json
{
  "timestamp": "2025-10-19T20:35:00.123Z",
  "type": "response_item",
  "payload": {
    "type": "function_call",
    "name": "update_plan",
    "arguments": "{\"plan\":[{\"status\":\"in_progress\",\"step\":\"Update documentation\"},{\"status\":\"pending\",\"step\":\"Add tracked .zshrc reference\"}]}",
    "call_id": "call_9BCMtUlVp9fVhIEBB4UWtiYb"
  }
}
```

**Arguments Structure (parsed JSON):**
```json
{
  "plan": [
    {
      "status": "in_progress" | "pending" | "completed",
      "step": "Human-readable task description"
    }
  ]
}
```

**Notes:**
- No Claude Code equivalent (Claude Code uses `TodoWrite` tool, but different structure)
- UI/planning tool, not file modification
- **Tier 3: Skip entirely** (no conversational value for resumed session)
- Similar to Claude Code's `TodoWrite` in purpose

---

## Comparison with Claude Code

| Codex Function | Claude Code Equivalent | Conversion Type |
|---------------|------------------------|-----------------|
| shell | Bash | Direct (Tier 1) |
| update_plan | TodoWrite (different structure) | Skip (Tier 3) |

**Key Insight:** Codex has **far fewer tool types** than Claude Code (2 vs 15). This suggests:
1. Codex delegates more operations to shell commands
2. Or Codex has not been used for complex file editing tasks in these sessions
3. Or Codex tools are named differently and not represented in this sample

---

## Codex-Specific Features

### 1. Escalated Permissions
Codex can request elevated permissions for shell commands:
```json
{
  "command": ["bash", "-lc", "codex resume"],
  "workdir": "/Users/rob/code/projects",
  "with_escalated_permissions": true,
  "justification": "Need to check whether codex has a resume command for the user"
}
```

**Conversion:** Claude Code has no permission system. Skip `with_escalated_permissions` and `justification` fields during conversion.

### 2. Login Shell Flag
Codex uses `-lc` (login shell) vs Claude Code which would use `-c` (non-login):
```bash
# Codex:
["bash", "-lc", "codex -r"]

# Claude Code equivalent:
["bash", "-c", "codex -r"]
```

**Conversion:** Use `-c` when converting to Claude Code; use `-lc` when converting to Codex (preserves environment setup).

### 3. Duration Tracking
Codex records `duration_seconds` in metadata. Claude Code does not.

**Conversion:**
- Codex → Claude Code: Discard duration (not representable)
- Claude Code → Codex: Use `0.0` as placeholder

---

## Record Format Differences

### Codex Nesting
Function calls are nested: `response_item.payload.type = "function_call"`

### Claude Code Flat Structure
Tool uses are direct content blocks: `message.content[].type = "tool_use"`

### Linking
- **Codex:** `call_id` links `function_call` to `function_call_output`
- **Claude Code:** `tool_use.id` links to `tool_result.tool_use_id`

Both use string identifiers with format `call_XXXX` (Codex) or `toolu_XXXX` (Claude Code).

---

## Implementation Notes

### High-Priority Conversion
**shell ↔ Bash** accounts for **89% of Codex calls** and **44% of Claude Code calls**. This is the **highest-value conversion target**.

### Command Parsing
When converting Codex → Claude Code:
```python
def parse_shell_command(codex_args: dict) -> str:
    \"\"\"Extract actual command from Codex shell arguments.\"\"\"
    cmd_array = json.loads(codex_args)["command"]
    # cmd_array is ["bash", "-lc", "actual_command"]
    if len(cmd_array) >= 3 and cmd_array[0] == "bash":
        return cmd_array[2]  # The actual command
    return " ".join(cmd_array)  # Fallback
```

When converting Claude Code → Codex:
```python
def wrap_bash_command(claude_cmd: str, workdir: str) -> str:
    \"\"\"Wrap Claude Code command for Codex shell function.\"\"\"
    args = {
        "command": ["bash", "-c", claude_cmd],
        "workdir": workdir
    }
    return json.dumps(args)
```

### Working Directory
Claude Code `Bash` tool does not specify a working directory. During conversion:
- **Claude Code → Codex:** Use session context CWD or fallback to `"/Users/rob/code/projects"`
- **Codex → Claude Code:** Discard `workdir` (not representable)

### Exit Code Mapping
```python
# Codex → Claude Code
is_error = (exit_code != 0)

# Claude Code → Codex
exit_code = 1 if is_error else 0
```

---

## Testing Recommendations

1. **Round-trip shell commands:** Ensure `shell` → `Bash` → `shell` preserves:
   - Command string
   - Exit code (success/failure)
   - Output content

2. **Command unwrapping:** Test edge cases:
   - Commands with quotes: `bash -c "echo 'hello'"`
   - Commands with pipes: `bash -c "ls | grep foo"`
   - Multi-line commands

3. **update_plan skipping:** Verify these are silently omitted without breaking conversation flow

---

## Open Questions

1. **Are there other Codex functions not in this sample?** Sample size is small (35 calls from Oct 2025). Need to check:
   - Older sessions
   - Different project transcripts
   - Codex documentation for full tool list

2. **Does Codex have file editing tools?** No evidence of `edit`, `write`, `read` equivalents in this sample. How does Codex handle file modifications?

3. **Metadata preservation:** Should we preserve `duration_seconds` as a comment in converted transcripts?

---

## Next Steps

1. ✅ Document shell ↔ Bash conversion (highest priority)
2. 🔄 Search broader Codex transcript corpus for other function types
3. 📋 Create tool compatibility matrix
4. 🔨 Implement Tier 1 (shell/Bash) conversion in `convert_transcript.py`
