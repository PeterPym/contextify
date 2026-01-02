# Codex CLI Transcript Format - Complete Technical Reference

**Last Updated:** 2025-12-31
**Related:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

---

## Overview

Codex CLI stores conversation history in **JSONL** (JSON Lines) format with a different record taxonomy than Claude Code. Focused on agent/tool interactions with first-class function calls and reasoning.

**Storage Location:**
- `~/.codex/sessions/YYYY/MM/DD/<session-name-timestamp-uuid>.jsonl`
- Hierarchical date structure (Year/Month/Day subdirectories)
- All projects stored in same global directory (not per-project like Claude Code)

**Key Characteristics:**
- **Global storage:** All sessions for all projects in single directory tree
- **Project detection:** Extract `cwd` from `session_meta.payload.cwd` field
- **Tool-focused:** First-class `function_call` / `function_call_output` records
- **Agent reasoning:** Encrypted `reasoning` records for internal thoughts
- **Session context:** Explicit `session_meta` with environment/git/instructions

---

## Storage Location & Discovery

### Directory Structure (REQUIRED)

Codex CLI stores sessions in a **specific directory structure** that MUST be followed for sessions to appear in `codex resume`:

```
~/.codex/sessions/YYYY/MM/DD/
```

**Example:**
```
~/.codex/
├── sessions/
│   └── 2025/
│       └── 10/
│           └── 19/
│               ├── rollout-2025-10-19T13-47-01-0199fe39-c07c-71d0-9ceb-9315a0946d34.jsonl
│               ├── rollout-2025-10-19T13-46-54-0199fe39-a5fe-79a2-922d-7845a60aae42.jsonl
│               └── test-converted-<timestamp>-<uuid>.jsonl
├── auth.json
├── config.toml
├── history.jsonl
└── version.json
```

### Filename Format (REQUIRED)

```
rollout-YYYY-MM-DDTHH-MM-SS-<uuid>.jsonl
```

**Components:**
- **prefix**: Must be `rollout-` (other prefixes are ignored by `codex resume`)
- **timestamp**: ISO 8601 format `YYYY-MM-DDTHH-MM-SS`
- **session-uuid**: UUID from `session_meta.payload.id` (MUST MATCH)
- **extension**: `.jsonl`

**Example:**
```
rollout-2025-10-19T14-02-00-01234567-89ab-cdef-0123-456789abcdef.jsonl
```

**Code evidence (codex-rs/core/src/rollout/list.rs:174-180):**
```rust
let mut day_files = collect_files(day_path, |name_str, path| {
    if !name_str.starts_with("rollout-") || !name_str.ends_with(".jsonl") {
        return None;  // SKIPPED if not "rollout-*.jsonl"
    }
```

---

## Critical Requirements for Session Discovery

For a session to appear in `codex resume`, ALL of these must be true:

### 1. Filename Must Start with `rollout-`

**NOT accepted:**
- `test-*.jsonl` ❌
- `converted-*.jsonl` ❌
- `session-*.jsonl` ❌
- Any other prefix ❌

### 2. UUID Consistency (REQUIRED)

**The UUID in the filename MUST match the UUID in `session_meta.payload.id`**

**Filename:**
```
rollout-2025-10-19T13-47-01-0199fe39-c07c-71d0-9ceb-9315a0946d34.jsonl
                              └─────────────────────────────────┘
                                          UUID
```

**Inside file (line 1):**
```json
{"payload":{"id":"0199fe39-c07c-71d0-9ceb-9315a0946d34",...}}
                  └─────────────────────────────────┘
                              MUST MATCH
```

### 3. Session Source Filter (REQUIRED)

**Code evidence (codex-rs/core/src/rollout/list.rs:204-210):**
```rust
if !allowed_sources.is_empty()
    && !summary.source.is_some_and(|source| allowed_sources.iter().any(|s| s == &source))
{
    continue;  // SKIPPED if source not in allowed list
}
```

**Allowed sources (codex-rs/core/src/rollout/mod.rs:7-8):**
```rust
pub const INTERACTIVE_SESSION_SOURCES: &[SessionSource] =
    &[SessionSource::Cli, SessionSource::VSCode];
```

**Source values recognized by Codex:**
- `"source": "cli"` - Interactive CLI sessions (appears in `codex resume`)
- `"source": "vscode"` - VS Code extension sessions (appears in `codex resume`)
- `"source": "exec"` - Non-interactive `codex exec` runs (does NOT appear in `codex resume`, but Contextify ingests these)

**For converted sessions, use:** `"source": "cli"`

**DO NOT use:**
- `"source": "conversion"` (will be filtered out of `codex resume`)
- Any arbitrary value (may be filtered)

### 4. Must Have session_meta Record (REQUIRED)

**Must be line 1:**
```json
{
  "timestamp": "2025-10-19T20:47:01.764Z",
  "type": "session_meta",
  "payload": {
    "id": "01234567-89ab-cdef-0123-456789abcdef",
    "timestamp": "2025-10-19T20:47:01.756Z",
    "cwd": "/tmp/test-project",
    "originator": "codex_cli_rs",
    "cli_version": "0.47.0",
    "instructions": null,
    "source": "cli"
  }
}
```

### 5. Must Have At Least One event_msg with type="user_message" (REQUIRED)

**Code evidence (codex-rs/core/src/rollout/list.rs:381-385, 211-212):**
```rust
RolloutItem::EventMsg(ev) => {
    if matches!(ev, EventMsg::UserMessage(_)) {
        summary.saw_user_event = true;  // REQUIRED for session to appear
    }
}
```

```json
{
  "timestamp": "2025-10-19T20:47:01.764Z",
  "type": "event_msg",
  "payload": {
    "type": "user_message",
    "message": "text",
    "images": []
  }
}
```

Without this, the session is filtered out even if everything else is correct.

### 6. JSON Must Be Compact (No Spaces)

**Correct:**
```json
{"type":"session_meta","payload":{"id":"abc"}}
```

**Wrong:**
```json
{"type": "session_meta", "payload": {"id": "abc"}}
          ^           ^              ^
        Spaces after colons
```

**Use:** `json.dumps(obj, separators=(',', ':'))` in Python

---

## System-Injected Messages

**Background:** Codex CLI automatically injects context at the start of every conversation. These appear as `response_item` records with `role: "user"` but were never actually sent by the user.

### Injected Messages

1. **AGENTS.md Instructions** - Project's AGENTS.md file wrapped in `<INSTRUCTIONS>` tags
2. **Environment Context** - Session environment details in `<environment_context>` XML

### Record Structure

Both injected messages appear as standard `response_item` records with `payload.role: "user"`:

```json
{"timestamp":"2025-11-21T16:51:57.131Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions for /path/to/project\n\n<INSTRUCTIONS>\n...\n</INSTRUCTIONS>"}]}}
{"timestamp":"2025-11-21T16:51:57.131Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>\n  <cwd>/path/to/project</cwd>\n  <approval_policy>never</approval_policy>\n  ...\n</environment_context>"}]}}
```

### Detection Pattern

**Key difference:** Real user messages have a companion `event_msg` record with `payload.type: "user_message"`. System-injected messages do NOT.

| Message Type | `response_item` (role=user) | Companion `event_msg` (type=user_message) |
|--------------|----------------------------|------------------------------------------|
| System-injected | Yes | **No** |
| Real user input | Yes | **Yes** (1ms later) |

**Example - System-injected message (no companion event_msg):**
```json
{"timestamp":"2025-11-21T16:51:57.131Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions for /path/to/project\n\n<INSTRUCTIONS>\n...\n</INSTRUCTIONS>"}]}}
```

**Example - Real user message (has both records):**
```json
{"timestamp":"2025-11-21T16:54:24.205Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}
{"timestamp":"2025-11-21T16:54:24.206Z","type":"event_msg","payload":{"type":"user_message","message":"Hello","images":[]}}
```

### Implementation

**Strategy:** Parse user messages from `event_msg` records (with `payload.type == "user_message"`) instead of `response_item` records. This automatically excludes system-injected messages since they lack companion `event_msg` records.

**Code:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`
- `CodexLineParser.parse()` - Handles `event_msg` vs `response_item` routing
- `CodexLineParser.parseUserMessageFromEventMsg()` - Extracts user messages from event_msg records

### Timestamp Characteristics

System-injected messages share identical timestamps (within 1ms of `session_meta`). Real user messages appear later with natural timing gaps. However, timestamp proximity alone is not a reliable filter - the companion `event_msg` pattern is the canonical detection method.

### Verification

The pattern is consistent across all examined transcripts: there are always exactly 2 more `response_item` user messages than `event_msg` user_message records, corresponding to the two system-injected messages.

---

## Record Types

### `session_meta` (Session Header)

Declares session-level context at the start. **Contains project path in `payload.cwd`**.

**Fields:**
- `timestamp` (ISO) — **MUST BE STRICTLY INCREASING**
- `type` (string) — Always `"session_meta"`
- `payload` (object):
  - `id` (uuid) — **REQUIRED:** Session identifier
  - `timestamp` (ISO)
  - `cwd` (string) — **Current working directory (PROJECT PATH)**
  - `originator` (string) — `"codex_cli_rs"` for interactive, `"codex_exec"` for exec runs
  - `cli_version` (string)
  - `instructions` (nullable string) — May be large, multiline (AGENTS.md content)
  - `source` (string) — **REQUIRED:** `"cli"`, `"vscode"`, or `"exec"` (only cli/vscode appear in `codex resume`)
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

### `response_item` (Conversational Turns)

Canonical conversation messages with structured content array.

**Fields:**
- `timestamp` (ISO) — **MUST BE STRICTLY INCREASING**
- `type` (string) — Always `"response_item"`
- `payload` (object):
  - `type` (string) — `"message"`, `"function_call"`, `"function_call_output"`, or `"reasoning"`
  - `role` (string) — `"user"` or `"assistant"` (for type=message)
  - `content` (array) — Array of content blocks (for type=message)

**User message example:**
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

**Assistant message example:**
```json
{
  "timestamp": "2025-11-03T17:50:47.123Z",
  "type": "response_item",
  "payload": {
    "type": "message",
    "role": "assistant",
    "content": [
      {
        "type": "output_text",
        "text": "I'll fix the parser by..."
      }
    ]
  }
}
```

**Note:** Content uses `input_text` for user, `output_text` for assistant (vs Claude Code's `text` type).

### `event_msg` (Telemetry/UX Events)

Varies by `payload.type`. Telemetry/UX stream separate from core messages.

**Important event types:**

#### `user_message` - Real User Input

**CRITICAL:** This event marks REAL user messages (vs system-injected). Required for session discovery.

```json
{
  "timestamp": "2025-11-03T17:54:24.206Z",
  "type": "event_msg",
  "payload": {
    "type": "user_message",
    "message": "Fix the parser bug",
    "images": []
  }
}
```

#### `agent_message` - Assistant Response (CLI Display)

**Note:** This is what Codex CLI displays to the user when resuming sessions, **NOT** the `response_item` with `role=assistant`.

```json
{
  "type": "event_msg",
  "payload": {
    "type": "agent_message",
    "message": "I've fixed the parser by..."
  }
}
```

#### `agent_reasoning` - High-Level Reasoning

```json
{
  "type": "event_msg",
  "payload": {
    "type": "agent_reasoning",
    "text": "**Reading AGENTS.md and TODOS.md files**"
  }
}
```

#### `token_count` - Usage/Limits

```json
{
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

### `turn_context` (Turn Boundary Markers)

Marks conversation turn boundary. Appears after `user_message` event and before agent reasoning/response. **Required for proper conversation structure.**

**Fields:**
- `timestamp` (ISO)
- `type` (string) — Always `"turn_context"`
- `payload` (object):
  - `cwd` (string)
  - `approval_policy` (string, e.g., `"on-request"`)
  - `sandbox_policy` (object)
  - `model` (string, e.g., `"gpt-5-codex"`)
  - `summary` (string, e.g., `"auto"`)

### `function_call` / `function_call_output` (Tool Invocations)

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

### `reasoning` (Internal Thoughts)

Stores internal chain-of-thought in an encrypted payload.

**Fields:**
- `timestamp` (ISO)
- `type` (string) — Always `"response_item"`
- `payload` (object):
  - `type` (string) — Always `"reasoning"`
  - `summary` (array) — `[{ "type": "summary_text", "text": "..." }]`
  - `content` (null)
  - `encrypted_content` (string) — Opaque encrypted blob

---

## Message Linking

- **Tool calls:** `call_id` pairs function calls to outputs
- **Conversation grouping:** Implied by file and `session_meta.payload.id`
- **Temporal cohesion:** Via timestamps
- **No global sessionId:** Unlike Claude Code, no sessionId field on each record

---

## Critical Requirement: Monotonic Timestamps

**Same as Claude Code:** Codex requires monotonically increasing timestamps for proper session resumption.

**Rule:** Every record must have `timestamp` > all previous records.

**Impact:**
- Session display breaks with duplicate timestamps
- Conversion/generation must ensure monotonicity
- Even 1ms difference is sufficient

---

## Complete Minimal Valid Session

**Filename:** `~/.codex/sessions/2025/10/19/rollout-2025-10-19T20-47-01-01234567-89ab-cdef-0123-456789abcdef.jsonl`

**Contents:**
```jsonl
{"timestamp":"2025-10-19T20:47:01.764Z","type":"session_meta","payload":{"id":"01234567-89ab-cdef-0123-456789abcdef","timestamp":"2025-10-19T20:47:01.756Z","cwd":"/tmp/test","originator":"codex_cli_rs","cli_version":"0.47.0","instructions":null,"source":"cli"}}
{"timestamp":"2025-10-19T20:47:01.764Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}
{"timestamp":"2025-10-19T20:47:01.764Z","type":"event_msg","payload":{"type":"user_message","message":"Hello","images":[]}}
{"timestamp":"2025-10-19T20:47:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hi there!"}]}}
```

---

## Converter Requirements Summary

To convert Claude Code → Codex, the converter MUST:

1. **Generate proper filename:**
   - Prefix: `rollout-`
   - Timestamp format: `YYYY-MM-DDTHH-MM-SS`
   - UUID: Match `session_meta.payload.id`
   - Extension: `.jsonl`

2. **Create directory structure:**
   - `~/.codex/sessions/YYYY/MM/DD/` (from conversion date)

3. **Generate session_meta:**
   - `type: "session_meta"`
   - `payload.id`: UUID (same as filename)
   - `payload.source`: `"cli"` (NOT "conversion")
   - `payload.cwd`: Extracted from Claude Code transcript
   - `payload.originator`: `"codex_cli_rs"` or similar

4. **For EACH user message, generate TWO records:**
   - `response_item` with `role: "user"`, `content: [{type: "input_text", text: "..."}]`
   - `event_msg` with `type: "user_message"`, `message: "..."`, `images: []`

5. **For EACH assistant message:**
   - `response_item` with `role: "assistant"`, `content: [{type: "output_text", text: "..."}]`

6. **JSON formatting:**
   - Compact (no spaces): `{"key":"value"}` not `{"key": "value"}`
   - One record per line (JSONL)

---

## Validation Checklist

- [ ] Filename starts with `rollout-`
- [ ] Filename ends with `.jsonl`
- [ ] Filename contains valid UUID (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
- [ ] Filename format: `rollout-YYYY-MM-DDTHH-MM-SS-<uuid>.jsonl`
- [ ] UUID in filename matches `session_meta.payload.id` exactly
- [ ] `session_meta.payload.source` is `"cli"` or `"vscode"`
- [ ] Located in `~/.codex/sessions/YYYY/MM/DD/`
- [ ] Has `session_meta` record (line 1)
- [ ] Has at least one `event_msg` with `payload.type="user_message"`
- [ ] Has at least one `response_item` user message
- [ ] JSON is compact (no spaces after colons/commas)
- [ ] Each line is valid JSON
- [ ] Timestamps are monotonically increasing

---

## Why Sessions Don't Appear in Picker

| Issue | Symptom | Fix |
|-------|---------|-----|
| Filename doesn't start with `rollout-` | Skipped during scan | Rename to `rollout-*` |
| UUID mismatch | Pagination fails | Ensure UUIDs match |
| `source` not `"cli"` or `"vscode"` | Filtered out of picker | Change to `"cli"` (note: `"exec"` sessions are valid but don't appear in picker) |
| No `event_msg` with `user_message` | Filtered out | Add for each user message |
| JSON has spaces | May not parse correctly | Use `separators=(',', ':')` |
| Wrong directory structure | Not found during discovery | Move to `~/.codex/sessions/YYYY/MM/DD/` |

---

## Related Documentation

- **Format comparison:** `build/docs/specifications/transcript-formats.md`
- **Claude Code format:** `build/docs/specifications/claude-code-transcript-format.md`
- **Parser implementation:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

---

## Source Code References

These requirements were discovered by analyzing Codex CLI source code:

- Session listing: `codex-rs/core/src/rollout/list.rs`
- Resume picker: `codex-rs/tui/src/resume_picker.rs`
- Session sources: `codex-rs/core/src/rollout/mod.rs:7-8`
- Filename parsing: `codex-rs/core/src/rollout/list.rs:314-329`
- Required filters: `codex-rs/core/src/rollout/list.rs:204-228`
