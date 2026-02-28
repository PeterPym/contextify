# Codex Session Requirements (Source Code Analysis)

## Critical Requirements for Sessions to Appear in `codex resume`

Based on deep analysis of `/Users/rob/code/open-source/codex/codex-rs/core/src/rollout/list.rs`:

### 1. File Location & Naming

**Directory structure (REQUIRED):**
```
~/.codex/sessions/YYYY/MM/DD/
```

**Filename format (REQUIRED):**
```
rollout-YYYY-MM-DDTHH-MM-SS-<uuid>.jsonl
```

**Example:**
```
~/.codex/sessions/2025/10/19/rollout-2025-10-19T13-47-01-0199fe39-c07c-71d0-9ceb-9315a0946d34.jsonl
```

**Code evidence (list.rs:174-180):**
```rust
let mut day_files = collect_files(day_path, |name_str, path| {
    if !name_str.starts_with("rollout-") || !name_str.ends_with(".jsonl") {
        return None;  // SKIPPED if not "rollout-*.jsonl"
    }
    parse_timestamp_uuid_from_filename(name_str)
```

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
{"type":"session_meta","payload":{"id":"0199fe39-c07c-71d0-9ceb-9315a0946d34",...}}
                                        └─────────────────────────────────┘
                                                    MUST MATCH
```

### 3. Session Source Filter (REQUIRED)

**Code evidence (list.rs:204-210):**
```rust
if !allowed_sources.is_empty()
    && !summary.source.is_some_and(|source| allowed_sources.iter().any(|s| s == &source))
{
    continue;  // SKIPPED if source not in allowed list
}
```

**Allowed sources (mod.rs:7-8):**
```rust
pub const INTERACTIVE_SESSION_SOURCES: &[SessionSource] =
    &[SessionSource::Cli, SessionSource::VSCode];
```

**MUST use one of:**
- `"source": "cli"` ← Use this for converted sessions
- `"source": "vscode"`

**DO NOT use:**
- `"source": "conversion"` ❌ (will be filtered out)
- `"source": "api"` ❌
- Any other value ❌

### 4. Required Records (REQUIRED)

**Code evidence (list.rs:211-212):**
```rust
// Apply filters: must have session meta and at least one user message event
if summary.saw_session_meta && summary.saw_user_event {
```

**Must have BOTH:**

#### A. `session_meta` record (line 1)
```json
{
  "timestamp": "2025-10-19T20:47:01.764Z",
  "type": "session_meta",
  "payload": {
    "id": "0199fe39-c07c-71d0-9ceb-9315a0946d34",
    "timestamp": "2025-10-19T20:47:01.756Z",
    "cwd": "/private/tmp/test-project",
    "originator": "codex_cli_rs",
    "cli_version": "0.47.0",
    "instructions": null,
    "source": "cli"
  }
}
```

#### B. At least one `event_msg` with `type: "user_message"`

**Code evidence (list.rs:381-385):**
```rust
RolloutItem::EventMsg(ev) => {
    if matches!(ev, EventMsg::UserMessage(_)) {
        summary.saw_user_event = true;  // REQUIRED for session to appear
    }
}
```

**Format:**
```json
{
  "timestamp": "2025-10-19T20:47:19.291Z",
  "type": "event_msg",
  "payload": {
    "type": "user_message",
    "message": "this is a test convo rob made at 147pm pst on 10-19-25",
    "kind": "plain"
  }
}
```

### 5. Message Records

**User messages:**
```json
{
  "timestamp": "2025-10-19T20:47:01.764Z",
  "type": "response_item",
  "payload": {
    "type": "message",
    "role": "user",
    "content": [
      {
        "type": "input_text",
        "text": "<environment_context>...</environment_context>"
      }
    ]
  }
}
```

**Assistant messages:**
```json
{
  "timestamp": "2025-10-19T20:47:05.123Z",
  "type": "response_item",
  "payload": {
    "type": "message",
    "role": "assistant",
    "content": [
      {
        "type": "output_text",
        "text": "Response text here"
      }
    ]
  }
}
```

**Note:** Use `"output_text"` for assistant, `"input_text"` for user.

## Complete Minimal Valid Session

```jsonl
{"timestamp":"2025-10-19T20:47:01.764Z","type":"session_meta","payload":{"id":"0199fe39-c07c-71d0-9ceb-9315a0946d34","timestamp":"2025-10-19T20:47:01.756Z","cwd":"/tmp/test-project","originator":"codex_cli_rs","cli_version":"0.47.0","instructions":null,"source":"cli"}}
{"timestamp":"2025-10-19T20:47:01.764Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}
{"timestamp":"2025-10-19T20:47:01.764Z","type":"event_msg","payload":{"type":"user_message","message":"Hello","kind":"plain"}}
{"timestamp":"2025-10-19T20:47:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hi there!"}]}}
```

Saved as: `~/.codex/sessions/2025/10/19/rollout-2025-10-19T20-47-01-0199fe39-c07c-71d0-9ceb-9315a0946d34.jsonl`

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
   - `event_msg` with `type: "user_message"`, `message: "..."`, `kind: "plain"`

5. **For EACH assistant message:**
   - `response_item` with `role: "assistant"`, `content: [{type: "output_text", text: "..."}]`

6. **JSON formatting:**
   - Compact (no spaces): `{"key":"value"}` not `{"key": "value"}`
   - One record per line (JSONL)

## Why Our Tests Failed

| Test | Issue | Fix |
|------|-------|-----|
| `test-sed-*.jsonl` | Filename doesn't start with `rollout-` | Rename to `rollout-*` |
| `test-copy-*.jsonl` | Filename doesn't start with `rollout-` | Rename to `rollout-*` |
| `test-proper-*.jsonl` | Filename doesn't start with `rollout-` | Rename to `rollout-*` |
| `test-nospace-*.jsonl` | Filename doesn't start with `rollout-` | Rename to `rollout-*` |
| `test-claude-converted-*.jsonl` | `source: "conversion"` filtered out | Change to `source: "cli"` |

**All test files had valid content but wrong filename prefix!**

## Validation Checklist

- [ ] Filename starts with `rollout-`
- [ ] Filename ends with `.jsonl`
- [ ] Filename UUID matches `session_meta.payload.id`
- [ ] Located in `~/.codex/sessions/YYYY/MM/DD/`
- [ ] Has `session_meta` record (line 1)
- [ ] `session_meta.payload.source` is `"cli"` or `"vscode"`
- [ ] Has at least one `event_msg` with `type: "user_message"`
- [ ] Has at least one `response_item` user message
- [ ] JSON is compact (no spaces after colons/commas)
- [ ] Each line is valid JSON

## Source Code References

- Session listing: `codex-rs/core/src/rollout/list.rs`
- Resume picker: `codex-rs/tui/src/resume_picker.rs`
- Session sources: `codex-rs/core/src/rollout/mod.rs:7-8`
- Filename parsing: `codex-rs/core/src/rollout/list.rs:314-329`
- Required filters: `codex-rs/core/src/rollout/list.rs:204-228`
