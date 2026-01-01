# Transcript Formats - Claude Code & Codex CLI

**Complete technical specification for conversation transcript formats**

---

## Claude Code

### Storage Location

**Default path:** `~/.claude/projects/<project-hash>/<session-uuid>.jsonl`

**Structure:**
```
~/.claude/projects/
├── -Users-rob-code-projects-contextify/
│   ├── ce6e090b-603e-484a-977e-546214573964.jsonl
│   ├── A31F3D0A-4820-41AB-8121-0C81AC8533C4.jsonl
│   └── ...
├── -Users-rob-Documents-other-project/
│   └── ...
└── ...
```

**Project hash format:** Project path with `/` replaced by `-` (e.g., `/Users/rob/code/projects/contextify` → `-Users-rob-code-projects-contextify`)

**Session files:** JSONL (JSON Lines) format
- One record per line
- Append-only (new records added as session progresses)
- Filename is session UUID with `.jsonl` extension

### Sidechain/Subagent Transcripts

When Claude Code spawns subagents (via the Task tool), each subagent creates its own transcript file with a distinct naming pattern.

**Filename convention:**
- **Main session:** `{sessionId}.jsonl` (UUID format, e.g., `343a0493-bc8b-43de-8ca6-5ae9c7394fa2.jsonl`)
- **Subagent:** `agent-{agentId}.jsonl` (e.g., `agent-10bae299.jsonl`)

**Structure:**
```
~/.claude/projects/-Users-rob-code-projects-example/
├── 343a0493-bc8b-43de-8ca6-5ae9c7394fa2.jsonl  # Main conversation (31KB)
├── agent-10bae299.jsonl                         # Subagent sidechain (851 bytes)
├── agent-30cc28b5.jsonl                         # Subagent sidechain (851 bytes)
├── agent-4ff1bfb1.jsonl                         # Subagent sidechain (851 bytes)
└── ...
```

**Identification (inside the file):**
- `agentId` field matches the filename suffix (e.g., `"agentId": "10bae299"`)
- `sessionId` points to the parent main session UUID
- `isSidechain: true` on all records

**Content characteristics:**
- Typically 1 line (single assistant response from the spawned subagent)
- Contains `isSidechain: true` marker
- Should be excluded from timeline display (filtered during parsing)
- May be useful for debugging/auditing subagent behavior

**Example sidechain file content:**
```json
{
  "agentId": "10bae299",
  "sessionId": "343a0493-bc8b-43de-8ca6-5ae9c7394fa2",
  "isSidechain": true,
  "type": "assistant",
  "message": { "role": "assistant", "content": [...] }
}
```

**Discovery implications:**
- Sidechain files should be deprioritized during ingestion (they produce 0 timeline entries)
- Main session files contain the user-visible conversation
- FastPath ingestion prioritizes non-`agent-*` files first

### Format Overview

Claude Code stores conversation history in **JSONL** (JSON Lines) format, with one record per line. Each transcript file represents a single session and contains mixed record types: conversation messages, file snapshots, system events, and metadata.

**Key Characteristics:**
- **Append-only:** New records appended as session progresses
- **Mixed types:** Conversation, metadata, snapshots, system events
- **Self-contained:** Each record is independent and parseable
- **Streaming-friendly:** Can be processed line-by-line without loading entire file
- **Threading:** Uses `uuid` + `parentUuid` to link messages into conversation chain

### Record Types

#### `user` (User Messages)

User-originated messages with metadata.

**Fields:**
- `parentUuid` (nullable string) — **REQUIRED FOR THREADING:** Links to previous assistant message UUID, or `null` for first message
- `isSidechain` (bool) — `true` for subagent/sidechain messages and warmup/initialization contexts (see [Sidechain/Subagent Transcripts](#sidechainsubagent-transcripts))
- `userType` (string, e.g., `"external"`)
- `cwd` (string) — Current working directory
- `sessionId` (uuid) — Session identifier
- `version` (string, semver, e.g., `"2.0.26"`)
- `gitBranch` (string) — Current git branch
- `type` (string) — Always `"user"`
- `message` (object) — `{ role: "user", content: "<string>" }` - **CONTENT MUST BE STRING, NOT ARRAY**
- `uuid` (uuid) — Unique message identifier
- `timestamp` (ISO string) — **MUST BE STRICTLY INCREASING**
- `thinkingMetadata` (object) — `{ level: "none", disabled: true, triggers: [] }`

**Example:**
```json
{
  "parentUuid": "8d5c2f1e-...",
  "isSidechain": false,
  "userType": "external",
  "cwd": "/Users/rob/code/projects/contextify",
  "sessionId": "ce6e090b-...",
  "version": "2.0.26",
  "gitBranch": "main",
  "type": "user",
  "message": {
    "role": "user",
    "content": "Fix the bug in the parser"
  },
  "uuid": "a1b2c3d4-...",
  "timestamp": "2025-11-11T10:30:00.000Z",
  "thinkingMetadata": { "level": "none", "disabled": true, "triggers": [] }
}
```

#### `assistant` (Assistant Messages)

Model-generated responses.

**Fields:**
- `parentUuid` (uuid) — **REQUIRED FOR THREADING:** Links to previous user message UUID
- `isSidechain` (bool)
- `userType` (string)
- `cwd` (string)
- `sessionId` (uuid)
- `version` (string)
- `gitBranch` (string)
- `message` (object):
  - `model` (string, e.g., `"claude-sonnet-4-5-20250929"`)
  - `id` (string, e.g., `"msg_..."`)
  - `type` (string) — Always `"message"`
  - `role` (string) — Always `"assistant"`
  - `content` (array) — Array of content blocks (see Content Block Types below)
  - `stop_reason` (nullable string)
  - `stop_sequence` (nullable)
  - `usage` (object) — Token usage metadata (see Usage Metadata below)
- `requestId` (string, e.g., `"req_..."`)
- `type` (string) — Always `"assistant"`
- `uuid` (uuid)
- `timestamp` (ISO string) — **MUST BE STRICTLY INCREASING**

**Note:** Assistant `message.content` is always an **array**. User `message.content` is usually a string for plain text input, but Claude Code CLI (v2.0+) emits tool call relays as **arrays** where each block has `type: "tool_result"` referencing an earlier assistant `tool_use` ID.

#### Content Block Types

Assistant messages contain typed content blocks:

**`text` Block:**
```json
{
  "type": "text",
  "text": "Here's the fix for the parser..."
}
```

**`tool_use` Block:**
```json
{
  "type": "tool_use",
  "id": "toolu_...",
  "name": "bash",
  "input": {
    "command": "ls -la",
    "restart": false
  }
}
```

**Skill and Agent Invocation Identification (Claude Code):**
- **Skill calls:** `tool_use` block with `name: "Skill"` and `input.skill` set to the skill key (e.g., `query:contextify-reinject`).
- **Agent calls (Task tool):** `tool_use` block with `name: "Task"` and `input.subagent_type` set to the agent key (e.g., `query:contextify-researcher`).
- **Tool result linkage:** The following `user` record includes `tool_result` blocks and may include `toolUseResult.agentId` (for Task) and `toolUseResult.commandName` (for Skill). Use these fields to link tool results to invocations rather than parsing prompt text.

**`tool_result` Block:**
```json
{
  "type": "tool_result",
  "tool_use_id": "toolu_...",
  "content": "total 48\ndrwxr-xr-x  12 rob  staff   384 Nov 11 22:45 .\n...",
  "is_error": false
}
```

**Tool Call Handshake (Claude Code CLI):**

1. Assistant emits a `tool_use` block with a unique `id`.
2. CLI runs the tool locally.
3. User record immediately follows with `message.content` = array of `tool_result` blocks, each referencing the originating `tool_use_id`.
4. Parser must treat these user `tool_result` entries as part of the same logical turn.

Corruption only occurs when a `tool_result` references an ID that never appeared in the transcript (e.g., teleporting from Claude Code Web and losing the assistant line).

**`thinking` Block:**
```json
{
  "type": "thinking",
  "thinking": "Let me analyze the error message..."
}
```

**`image` Block:**
```json
{
  "type": "image",
  "source": {
    "type": "base64",
    "media_type": "image/png",
    "data": "iVBORw0KGgoAAAANSU..."
  }
}
```

#### Usage Metadata

Present in all assistant messages:

```json
{
  "input_tokens": 1234,
  "cache_creation_input_tokens": 0,
  "cache_read_input_tokens": 5678,
  "output_tokens": 456
}
```

**Fields:**
- `input_tokens` — Tokens in request (non-cached)
- `cache_creation_input_tokens` — Tokens used to create new cache entries
- `cache_read_input_tokens` — Tokens read from cache (cheaper)
- `output_tokens` — Tokens in response

#### `file-history-snapshot` (File Snapshots)

Periodic capture of file backup states.

**Fields:**
- `type` (string) — Always `"file-history-snapshot"`
- `messageId` (uuid) — Links to associated message
- `timestamp` (ISO string)
- `snapshot` (object):
  - `timestamp` (ISO string)
  - `trackedFileBackups` (object) — Map of file paths to backup arrays

**Example:**
```json
{
  "type": "file-history-snapshot",
  "messageId": "a1b2c3d4-...",
  "timestamp": "2025-11-11T10:30:00.000Z",
  "snapshot": {
    "timestamp": "2025-11-11T10:30:00.000Z",
    "trackedFileBackups": {
      "app/parser.ts": [
        {
          "path": "app/parser.ts",
          "version": 1,
          "timestamp": "2025-11-11T10:25:00.000Z",
          "content": "export function parse() { ... }"
        }
      ]
    }
  }
}
```

#### `system` (System Events)

System-level events like command execution.

**Fields:**
- `type` (string) — Always `"system"`
- `timestamp` (ISO string)
- `systemType` (string) — Event type (e.g., `"command"`)
- `data` (object) — Event-specific data

#### `summary` (Session Summaries)

Session-level summaries generated by Claude Code.

**Fields:**
- `type` (string) — Always `"summary"`
- `timestamp` (ISO string)
- `summary` (string) — Summary text

### Message Threading

Messages use `uuid` and `parentUuid` to form a conversation chain (singly-linked list):
- First message has `parentUuid=null`
- Each subsequent message links to its predecessor
- `sessionId` ties all entries to a session

### Critical Requirement: Monotonic Timestamps

**Verified:** Claude Code requires strictly increasing timestamps across all records. Records with identical timestamps cause only the first message to display.

**Rule:** Every record must have `timestamp` > all previous records.

**Impact:**
- Session display breaks with duplicate timestamps
- Conversion/generation must ensure monotonicity
- Even 1ms difference is sufficient

### Transcript Corruption (Claude Code Web)

**Affects:** Claude Code Web "teleport" feature (session transfer from web to CLI)
**Impact:** Some teleported transcripts contain structural corruption that can cause API 400 errors

**Background:** Claude Code Web includes a "Send to CLI" teleport feature. When a web session freezes, users can click "Send to CLI" which downloads the web transcript to the local `~/.claude/projects/` directory. However, the teleport process frequently creates **corrupted transcript files** where the web session's frozen/hung state results in malformed JSONL records.

**Common Corruption Patterns:**

1. **Orphaned `tool_result` blocks** - `tool_result` without matching `tool_use`
2. **Mismatched `stop_reason`** - Message has `stop_reason: "end_turn"` but contains `tool_use` blocks
3. **Broken parent chains** - Messages with invalid `parentUuid` references
4. **Duplicate UUIDs** - Multiple messages with same UUID
5. **Missing required fields** - Records missing `timestamp`, `uuid`, or `parentUuid`

**Detection:**
```bash
python3 scripts/transcript-repair/repair_transcript.py <transcript> --dry-run
```

**Repair:**
```bash
python3 scripts/transcript-repair/repair_transcript.py <transcript>
# Creates backup: <transcript>.backup
```

**References:**
- Full guide: `build/docs/operations/transcript-corruption-detection.md`
- Script README: `scripts/transcript-repair/README.md`

---

## Codex CLI

### Storage Location

**Default path:** `~/.codex/sessions/YYYY/MM/DD/<session-name-timestamp-uuid>.jsonl`

**Structure:**
```
~/.codex/sessions/
├── 2025/
│   ├── 10/
│   │   ├── 19/
│   │   │   ├── rollout-2025-10-19T14-30-00-019a123...jsonl
│   │   │   └── ...
│   │   ├── 23/
│   │   └── 24/
│   └── 11/
│       ├── 03/
│       │   ├── rollout-2025-11-03T09-49-46-019a4ad...jsonl
│       │   └── ...
│       ├── 04/
│       └── ...
└── ...
```

**Hierarchical date structure:** Year/Month/Day subdirectories

**Session files:** JSONL (JSON Lines) format
- One record per line
- Filename: `<session-name>-<timestamp>-<uuid>.jsonl`
- All projects stored in same global directory (not per-project like Claude Code)
- Project association via `cwd` field in `session_meta` record
- **Discovery use:** Contextify's Codex discovery parses `session_meta.payload.cwd` **and** `session_meta.payload.id` to build the global project index, so both properties MUST remain present and accurate or projects will disappear from the UI.

### Format Overview

Codex CLI stores conversation history in **JSONL** format with a different record taxonomy than Claude Code. Focused on agent/tool interactions with first-class function calls and reasoning.

**Key Characteristics:**
- **Global storage:** All sessions for all projects in single directory tree
- **Project detection:** Extract `cwd` from `session_meta.payload.cwd` field
- **Tool-focused:** First-class `function_call` / `function_call_output` records
- **Agent reasoning:** Encrypted `reasoning` records for internal thoughts
- **Session context:** Explicit `session_meta` with environment/git/instructions

### Record Types

#### `session_meta` (Session Header)

Declares session-level context at the start. **Contains project path in `payload.cwd`**.

**Fields:**
- `timestamp` (ISO) — **MUST BE STRICTLY INCREASING**
- `type` (string) — Always `"session_meta"`
- `payload` (object):
  - `id` (uuid) — **REQUIRED:** Session identifier, used in resume picker
  - `timestamp` (ISO)
  - `cwd` (string) — **Current working directory (PROJECT PATH)**
  - `originator` (string, e.g., `"codex_cli_rs"` or `"claude_code_converter"`)
  - `cli_version` (string)
  - `instructions` (nullable string) — May be large, multiline
  - `source` (string) — **REQUIRED:** Must be `"cli"` or `"vscode"` to appear in session picker
  - `git` (optional object):
    - `commit_hash` (string)
    - `branch` (string)
    - `repository_url` (string)

**Example:**
```json
{
  "timestamp": "2025-11-03T17:49:46.915Z",
  "type": "session_meta",
  "payload": {
    "id": "019a4ad6-de05-7181-a69c-f3fbb763a5a4",
    "timestamp": "2025-11-03T17:49:46.885Z",
    "cwd": "/Users/rob/code/projects/contextify",
    "originator": "codex_cli_rs",
    "cli_version": "0.48.0",
    "instructions": "# Repository Guidelines\n\n...",
    "source": "cli",
    "git": {
      "commit_hash": "ccb37c4d313423f9d849ee011e668b879e0889d7",
      "branch": "feature/quick-wins-ui-consistency",
      "repository_url": "git@github.com:banagale/contextify.git"
    }
  }
}
```

#### `response_item` (Conversational Turns)

Canonical conversation messages with structured content array.

**Fields:**
- `timestamp` (ISO) — **MUST BE STRICTLY INCREASING**
- `type` (string) — Always `"response_item"`
- `payload` (object):
  - `type` (string) — Always `"message"`
  - `role` (string) — `"user"` or `"assistant"`
  - `content` (array) — Array of content blocks (see Codex Content Types below)

**Note:** Content uses `input_text` for user, `output_text` for assistant (vs Claude Code's `text` type).

**Example:**
```json
{
  "timestamp": "2025-11-03T17:49:46.916Z",
  "type": "response_item",
  "payload": {
    "type": "message",
    "role": "user",
    "content": [
      {
        "type": "input_text",
        "text": "Fix the parser bug"
      }
    ]
  }
}
```

#### Codex Content Types

**User content:** `input_text`
```json
{
  "type": "input_text",
  "text": "Fix the parser bug"
}
```

**Assistant content:** `output_text`
```json
{
  "type": "output_text",
  "text": "I'll fix the parser by..."
}
```

#### `turn_context` (Turn Boundary Markers)

Marks conversation turn boundary. Appears after `user_message` event and before agent reasoning/response. **Required for proper conversation structure.**

**Fields:**
- `timestamp` (ISO)
- `type` (string) — Always `"turn_context"`
- `payload` (object):
  - `cwd` (string) — Current working directory
  - `approval_policy` (string, e.g., `"on-request"`)
  - `sandbox_policy` (object):
    - `mode` (string)
    - `network_access` (bool)
    - `exclude_tmpdir_env_var` (bool)
    - `exclude_slash_tmp` (bool)
  - `model` (string, e.g., `"gpt-5-codex"`)
  - `summary` (string, e.g., `"auto"`)

#### `event_msg` (Telemetry/UX Events)

Varies by `payload.type`. Telemetry/UX stream separate from core messages.

**Common event types:**

**`token_count`** - Usage/limits snapshot:
```json
{
  "timestamp": "2025-11-03T17:50:47.431Z",
  "type": "event_msg",
  "payload": {
    "type": "token_count",
    "info": {
      "total_token_usage": {
        "input_tokens": 8777,
        "output_tokens": 104
      }
    },
    "rate_limits": { ... }
  }
}
```

**`agent_reasoning`** - High-level reason string:
```json
{
  "type": "event_msg",
  "payload": {
    "type": "agent_reasoning",
    "text": "**Reading AGENTS.md and TODOS.md files**"
  }
}
```

**`user_message`** - Echoes user input (appears after user `response_item`):
```json
{
  "type": "event_msg",
  "payload": {
    "type": "user_message",
    "message": "Fix the parser bug",
    "images": []
  }
}
```

**`agent_message`** - **CRITICAL FOR DISPLAY:** Contains assistant response text shown in CLI:
```json
{
  "type": "event_msg",
  "payload": {
    "type": "agent_message",
    "message": "I've fixed the parser by..."
  }
}
```

**Note:** `agent_message` events are what Codex CLI displays to the user when resuming sessions, **NOT** the `response_item` with `role=assistant`.

#### `function_call` / `function_call_output` (Tool Invocations)

First-class tool invocation trace with request/response pairing via `call_id`.

**`function_call`:**
```json
{
  "timestamp": "2025-11-03T17:50:53.494Z",
  "type": "response_item",
  "payload": {
    "type": "function_call",
    "name": "shell",
    "arguments": "{\"command\":[\"bash\",\"-lc\",\"cat AGENTS.md\"]}",
    "call_id": "call_06kcl6SwfYJMu3qGqDbiWUgZ"
  }
}
```

**`function_call_output`:**
```json
{
  "timestamp": "2025-11-03T17:50:53.494Z",
  "type": "response_item",
  "payload": {
    "type": "function_call_output",
    "call_id": "call_06kcl6SwfYJMu3qGqDbiWUgZ",
    "output": "{\"output\":\"...\",\"metadata\":{\"exit_code\":0}}"
  }
}
```

#### `reasoning` (Internal Thoughts)

Stores internal chain-of-thought in an encrypted payload.

**Fields:**
- `timestamp` (ISO)
- `type` (string) — Always `"response_item"`
- `payload` (object):
  - `type` (string) — Always `"reasoning"`
  - `summary` (array) — `[{ "type": "summary_text", "text": "..." }]`
  - `content` (null)
  - `encrypted_content` (string) — Opaque encrypted blob

### Message Linking

- **Tool calls:** `call_id` pairs function calls to outputs
- **Conversation grouping:** Implied by file and `session_meta.payload.id`
- **Temporal cohesion:** Via timestamps
- **No global sessionId:** Each record (unlike Claude Code)

### System-Injected Messages

Codex CLI automatically injects context (AGENTS.md + environment) at conversation start. These appear as `response_item` with `role: "user"` but lack companion `event_msg` records.

**Detection:** Real user messages have companion `event_msg` with `payload.type == "user_message"`. System-injected messages do NOT.

**See:** `build/docs/specifications/codex-cli-transcript-format.md` - Complete format specification

### Critical Requirement: Monotonic Timestamps

**Same as Claude Code:** Codex also requires monotonically increasing timestamps for proper session resumption.

---

## Format Comparison

| Aspect | Claude Code | Codex CLI |
|---|---|---|
| **Storage** | `~/.claude/projects/<project-hash>/` | `~/.codex/sessions/YYYY/MM/DD/` |
| **Project grouping** | Directory per project | Global directory, `cwd` in `session_meta` |
| **Message linking** | `uuid` + `parentUuid` (threading), `sessionId` | `call_id` for tools; conversation by file; `session_meta.payload.id` for session |
| **CWD / Repo** | `cwd` per message; `gitBranch` at message-level | `session_meta.payload.cwd`; `payload.git.{commit_hash,branch,repository_url}` |
| **Record taxonomy** | `user`, `assistant`, `system`, `summary`, `file-history-snapshot`, `queue-operation`, `timeline-state`, `queue-operation-result` | `session_meta`, `response_item` (subtypes: `message`, `function_call`, `function_call_output`, `reasoning`), `event_msg`, `turn_context` |
| **Content envelope** | `message: { role, content }` (string for user, array for assistant) | `payload: { type, role, content: [ {type, text} ] }` (typed segments) |
| **Content block types** | `text`, `tool_use`, `tool_result`, `thinking`, `image` | `input_text` (user), `output_text` (assistant) |
| **File snapshots** | Yes — `trackedFileBackups` per path with versions/timestamps | No equivalent (tool outputs/logs instead) |
| **Internal thoughts** | `thinking` blocks in assistant messages | `reasoning` records with `encrypted_content` |
| **Tool I/O** | `tool_use` / `tool_result` blocks in assistant messages | First-class: `function_call` / `function_call_output` records |
| **Session preamble** | Implicit via early `user` meta and snapshots | Explicit `session_meta` with all environment/git/instructions |
| **Timestamps** | ISO strings (**MUST BE MONOTONIC**) on each record | ISO strings (**MUST BE MONOTONIC**) on each record |

---

## Generating Transcripts Programmatically

For automated testing, sample data generation, or scripted workflows, both CLIs support non-interactive modes:

**Claude Code:**
```bash
claude -p --dangerously-skip-permissions "your message"                    # Single message
claude --resume "$session_id" -p --dangerously-skip-permissions "followup" # Continue session
```

**Codex CLI:**
```bash
codex exec -C "/path/to/project" --dangerously-bypass-approvals-and-sandbox "message"
codex exec resume "$session_id" --dangerously-bypass-approvals-and-sandbox "followup"
```

**Reference implementations:**
- `appstore-metadata/review-materials/generate-transcripts.sh` - Full sample data generation workflow
- `scripts/qa/tests/QA-03-codex-discovery.sh` - QA test using Codex exec
- `scripts/qa/tests/QA-04-claude-discovery.sh` - QA test using Claude print mode

---

## Implementation References

**Parsers:**
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` - JSONL parsing for both formats

**Database:**
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` - Schema definitions
- `app/Sources/ContextifyCore/Database/HooverEngine.swift` - Streaming ingestion

**Discovery:**
- Claude Code: Scan `~/.claude/projects/` subdirectories
- Codex: Parse `~/.codex/sessions/**/*.jsonl` files, extract `session_meta.payload.cwd`

---

## Related Documentation

**Detailed format specifications:**
- **Claude Code:** `build/docs/specifications/claude-code-transcript-format.md`
- **Codex CLI:** `build/docs/specifications/codex-cli-transcript-format.md`

**Operations:**
- **Corruption detection:** `build/docs/operations/transcript-corruption-detection.md`
- **Repair scripts:** `scripts/transcript-repair/README.md`
- **Classification workflow:** See CLAUDE.md "Transcript Analysis Workflow" section
