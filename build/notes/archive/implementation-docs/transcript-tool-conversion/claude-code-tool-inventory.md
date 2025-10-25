# Claude Code Tool Inventory

**Generated:** 2025-10-24
**Source:** Contextify project transcripts (`~/.claude/projects/-Users-rob-code-projects-contextify/*.jsonl`)
**Purpose:** Document all tool types used in Claude Code for transcript conversion planning

---

## Summary Statistics

Total tool calls analyzed from Contextify project:

| Tool | Count | % of Total |
|------|-------|------------|
| Bash | 3,305 | 44.1% |
| Edit | 1,474 | 19.7% |
| Read | 1,264 | 16.9% |
| TodoWrite | 725 | 9.7% |
| Grep | 534 | 7.1% |
| Write | 159 | 2.1% |
| Glob | 59 | 0.8% |
| BashOutput | 30 | 0.4% |
| WebSearch | 17 | 0.2% |
| WebFetch | 12 | 0.2% |
| ExitPlanMode | 12 | 0.2% |
| KillShell | 4 | <0.1% |
| Task | 3 | <0.1% |
| AskUserQuestion | 2 | <0.1% |
| SlashCommand | 1 | <0.1% |
| **TOTAL** | **7,601** | **100%** |

---

## Tool Definitions

### 1. Bash (44.1% of calls)

**Purpose:** Execute shell commands

**Input Structure:**
```json
{
  "type": "tool_use",
  "id": "toolu_01CM2Z4i2mJWWpZH26Q2zXp2",
  "name": "Bash",
  "input": {
    "command": "find /Users/rob/code/projects/contextify -name \"*.swift\" | head -20",
    "description": "Locate key files to modify"
  }
}
```

**Output Structure:**
```json
{
  "tool_use_id": "toolu_01CM2Z4i2mJWWpZH26Q2zXp2",
  "type": "tool_result",
  "content": "/Users/rob/.../ConversationMonitor.swift\n/Users/rob/.../FoundationLLM.swift",
  "is_error": false
}
```

**Key Fields:**
- `input.command` (string): Shell command to execute
- `input.description` (string, optional): Human-readable description of what the command does
- `content` (string): stdout/stderr output
- `is_error` (boolean): Whether command failed (exit code != 0)

**Notes:**
- Most common tool (44% of all calls)
- Direct equivalent to Codex `shell` function
- Critical for conversion - high context value

---

### 2. Edit (19.7% of calls)

**Purpose:** Replace text in existing files using exact string matching

**Input Structure:**
```json
{
  "type": "tool_use",
  "id": "toolu_01Hy522DKMNC8ET4uRuyFDS9",
  "name": "Edit",
  "input": {
    "file_path": "/Users/rob/.../ConversationMonitor.swift",
    "old_string": "import Foundation\nimport Observation",
    "new_string": "import Foundation\nimport Observation\nimport OSLog",
    "replace_all": false
  }
}
```

**Output Structure:**
```json
{
  "tool_use_id": "toolu_01Hy522DKMNC8ET4uRuyFDS9",
  "type": "tool_result",
  "content": "File edited successfully at /Users/rob/.../ConversationMonitor.swift",
  "is_error": false
}
```

**Key Fields:**
- `input.file_path` (string): Absolute path to file
- `input.old_string` (string): Exact text to find and replace
- `input.new_string` (string): Replacement text
- `input.replace_all` (boolean, optional): Replace all occurrences vs first match

**Notes:**
- No Codex equivalent
- Second most common tool (20% of calls)
- Lossy conversion: summarize as "Edited `{file}` replacing X with Y"
- Contains critical context about what was changed

---

### 3. Read (16.9% of calls)

**Purpose:** Read file contents

**Input Structure:**
```json
{
  "type": "tool_use",
  "id": "toolu_01Sru35PXQDoHuukRFez1bhe",
  "name": "Read",
  "input": {
    "file_path": "/Users/rob/code/projects/contextify/Contextify/Contextify/ConversationMonitor.swift",
    "offset": 0,
    "limit": 100
  }
}
```

**Output Structure:**
```json
{
  "tool_use_id": "toolu_01Sru35PXQDoHuukRFez1bhe",
  "type": "tool_result",
  "content": "     1→import Foundation\n     2→import Observation\n...",
  "is_error": false
}
```

**Key Fields:**
- `input.file_path` (string): Absolute path to file
- `input.offset` (integer, optional): Start line number
- `input.limit` (integer, optional): Max lines to read
- `content` (string): File contents with line numbers

**Notes:**
- No Codex equivalent
- Third most common (17%)
- Lossy conversion: "Read `{file}` ({N} lines)"
- Context value: moderate (shows what agent examined)

---

### 4. TodoWrite (9.7% of calls)

**Purpose:** Update task tracking list

**Input Structure:**
```json
{
  "type": "tool_use",
  "id": "toolu_01WsNcdicMm7P7zVAc9jGEP8",
  "name": "TodoWrite",
  "input": {
    "todos": [
      {
        "content": "Audit Claude Code tool usage",
        "activeForm": "Auditing Claude Code tool usage",
        "status": "in_progress"
      }
    ]
  }
}
```

**Output Structure:**
```json
{
  "tool_use_id": "toolu_01WsNcdicMm7P7zVAc9jGEP8",
  "type": "tool_result",
  "content": "Todos have been modified successfully."
}
```

**Notes:**
- UI/planning tool, not file modification
- Tier 3: Skip entirely (no conversational value for resumed session)

---

### 5. Grep (7.1% of calls)

**Purpose:** Search file contents using regex patterns

**Input Structure:**
```json
{
  "type": "tool_use",
  "id": "toolu_016wS33eTfaftoLZPWrr26EU",
  "name": "Grep",
  "input": {
    "pattern": "await db\\.read",
    "path": "/Users/rob/code/projects/contextify/app/Sources",
    "output_mode": "content",
    "-n": true,
    "-i": false
  }
}
```

**Output Structure:**
```json
{
  "tool_use_id": "toolu_016wS33eTfaftoLZPWrr26EU",
  "type": "tool_result",
  "content": "path/to/file.swift:42: await db.read(...)\npath/to/other.swift:108: await db.read(...)",
  "is_error": false
}
```

**Key Fields:**
- `input.pattern` (string): Regex pattern
- `input.path` (string): Directory or file to search
- `input.output_mode` (string): "content" | "files_with_matches" | "count"
- `input.-n` (boolean): Show line numbers

**Notes:**
- No Codex equivalent
- Lossy conversion: "Searched for `{pattern}` and found {N} matches"

---

### 6. Write (2.1% of calls)

**Purpose:** Create or overwrite files

**Input Structure:**
```json
{
  "type": "tool_use",
  "id": "toolu_019QBUaCY5JUb1UFq3AG2sEU",
  "name": "Write",
  "input": {
    "file_path": "/Users/rob/code/projects/contextify/build/notes/phase-2.md",
    "content": "# Phase 2: Implementation\n\n..."
  }
}
```

**Output Structure:**
```json
{
  "tool_use_id": "toolu_019QBUaCY5JUb1UFq3AG2sEU",
  "type": "tool_result",
  "content": "File written successfully",
  "is_error": false
}
```

**Key Fields:**
- `input.file_path` (string): Absolute path
- `input.content` (string): Full file contents

**Notes:**
- No Codex equivalent
- Lossy conversion: "Created/overwrote `{file}` ({N} lines)"

---

### 7. Glob (0.8% of calls)

**Purpose:** Find files matching glob patterns

**Input Structure:**
```json
{
  "type": "tool_use",
  "id": "toolu_01DikfLCJ9w1he7Hin413DJs",
  "name": "Glob",
  "input": {
    "pattern": "*Settings*.swift",
    "path": "/Users/rob/code/projects/contextify/Contextify"
  }
}
```

**Output Structure:**
```json
{
  "tool_use_id": "toolu_01DikfLCJ9w1he7Hin413DJs",
  "type": "tool_result",
  "content": "/path/to/Settings.swift\n/path/to/UserSettings.swift"
}
```

**Notes:**
- Could be converted to Bash (`find ... -name "pattern"`)
- Or lossy: "Searched for files matching `{pattern}`"

---

### 8. WebSearch (0.2% of calls)

**Purpose:** Search the web

**Input Structure:**
```json
{
  "type": "tool_use",
  "id": "toolu_01MYnti9B3ZzkV42xn53aqyj",
  "name": "WebSearch",
  "input": {
    "query": "Swift 6 actor isolation best practices 2025"
  }
}
```

**Notes:**
- No Codex equivalent
- Tier 3: Skip (not relevant to code context)

---

### 9. Low-Frequency Tools

**BashOutput** (0.4%): Read output from background bash shells
**WebFetch** (0.2%): Fetch URL contents
**ExitPlanMode** (0.2%): Exit planning mode
**KillShell** (<0.1%): Terminate background shell
**Task** (<0.1%): Launch sub-agents
**AskUserQuestion** (<0.1%): Prompt user for decisions
**SlashCommand** (<0.1%): Execute custom slash commands

All are **Tier 3** (skip) except:
- **BashOutput**: Could summarize as "Checked background shell output"

---

## Conversion Priority Ranking

### Tier 1: Direct Conversion (Non-Lossy)
1. **Bash** (44%) → Codex `shell`

### Tier 2: Lossy Text Summary
1. **Edit** (20%) - "Edited `{file}` replacing {old} with {new}"
2. **Read** (17%) - "Read `{file}` ({N} lines)"
3. **Grep** (7%) - "Searched for `{pattern}` and found {N} matches in {files}"
4. **Write** (2%) - "Created/overwrote `{file}` ({N} lines)"
5. **Glob** (0.8%) - "Found {N} files matching `{pattern}`"

### Tier 3: Skip Entirely
- TodoWrite (9.7%) - UI state, not conversation context
- WebSearch, WebFetch, ExitPlanMode, KillShell, Task, AskUserQuestion, SlashCommand (all <1%)

---

## Implementation Notes

**Coverage:** Tier 1 + Tier 2 tools account for **90.8%** of all tool calls. Implementing these ensures minimal context loss.

**Tool Result Linking:** All tool results include `tool_use_id` that matches the `tool_use.id` field. This is critical for pairing calls with results during conversion.

**Error Handling:** The `is_error` field indicates command/operation failure. This should be preserved in conversion (e.g., as non-zero exit code for Bash → shell).

**Timestamps:** Tool use and tool result appear in separate messages with their own timestamps. Maintain ordering during conversion.
