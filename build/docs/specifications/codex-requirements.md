# Codex Session Requirements - DEFINITIVE

## The 6 Critical Requirements

For a session to appear in `codex resume`, ALL of these must be true:

### 1. Filename Must Start with `rollout-`

**Format:** `rollout-YYYY-MM-DDTHH-MM-SS-<uuid>.jsonl`

**Example:** `rollout-2025-10-19T14-02-00-01234567-89ab-cdef-0123-456789abcdef.jsonl`

**NOT:**
- `test-*.jsonl` ❌
- `converted-*.jsonl` ❌
- `session-*.jsonl` ❌
- Any other prefix ❌

**Source:** `codex-rs/core/src/rollout/list.rs:174-180`

### 2. UUID in Filename Must Match session_meta.payload.id

**Filename:**
```
rollout-2025-10-19T14-02-00-01234567-89ab-cdef-0123-456789abcdef.jsonl
                              └──────────────────────────────────────┘
```

**session_meta (line 1):**
```json
{"payload":{"id":"01234567-89ab-cdef-0123-456789abcdef"}}
                  └──────────────────────────────────────┘
                                 MUST MATCH
```

### 3. source Must Be "cli" or "vscode"

```json
{
  "type": "session_meta",
  "payload": {
    "source": "cli"    ← MUST be "cli" or "vscode"
  }
}
```

**NOT:**
- `"source": "conversion"` ❌
- `"source": "api"` ❌
- Any other value ❌

**Source:** `codex-rs/core/src/rollout/mod.rs:7-8` and `list.rs:204-210`

### 4. Must Have session_meta Record

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

### 5. Must Have At Least One event_msg with type="user_message"

```json
{
  "timestamp": "2025-10-19T20:47:01.764Z",
  "type": "event_msg",
  "payload": {
    "type": "user_message",    ← REQUIRED
    "message": "text",
    "kind": "plain"
  }
}
```

**Source:** `codex-rs/core/src/rollout/list.rs:381-385, 211-212`

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

**Use:** `json.dumps(obj, separators=(',', ':'))`

## Complete Minimal Valid Session

**Filename:** `~/.codex/sessions/2025/10/19/rollout-2025-10-19T20-47-01-01234567-89ab-cdef-0123-456789abcdef.jsonl`

**Contents:**
```jsonl
{"timestamp":"2025-10-19T20:47:01.764Z","type":"session_meta","payload":{"id":"01234567-89ab-cdef-0123-456789abcdef","timestamp":"2025-10-19T20:47:01.756Z","cwd":"/tmp/test","originator":"codex_cli_rs","cli_version":"0.47.0","instructions":null,"source":"cli"}}
{"timestamp":"2025-10-19T20:47:01.764Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}
{"timestamp":"2025-10-19T20:47:01.764Z","type":"event_msg","payload":{"type":"user_message","message":"Hello","kind":"plain"}}
```

## Converter Requirements

The converter MUST:

1. **Parse output filename to extract UUID, OR generate proper filename**
2. **Ensure session_meta.payload.id matches filename UUID**
3. **Set source to "cli"** (not "conversion")
4. **Use compact JSON** (`separators=(',', ':')`)
5. **Generate event_msg for every user message**
6. **Use `input_text` for user, `output_text` for assistant**

## Validation Script

```python
import json
import re
import os

def validate_codex_session(file_path):
    # 1. Check filename starts with 'rollout-'
    basename = os.path.basename(file_path)
    if not basename.startswith('rollout-'):
        return False, "Filename must start with 'rollout-'"

    # 2. Extract UUID from filename (CRITICAL - must have valid UUID)
    uuid_match = re.search(r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$', basename)
    if not uuid_match:
        return False, "Filename must end with valid <uuid>.jsonl (e.g., rollout-2025-10-19T14-00-00-01234567-89ab-cdef-0123-456789abcdef.jsonl)"
    filename_uuid = uuid_match.group(1)

    # 3. Read session_meta
    with open(file_path) as f:
        first_line = f.readline()
        session_meta = json.loads(first_line)

    # 4. Check UUID match
    meta_uuid = session_meta['payload']['id']
    if filename_uuid != meta_uuid:
        return False, f"UUID mismatch: filename={filename_uuid}, meta={meta_uuid}"

    # 5. Check source
    source = session_meta['payload']['source']
    if source not in ['cli', 'vscode']:
        return False, f"source must be 'cli' or 'vscode', got '{source}'"

    # 6. Check JSON compact
    if ': ' in first_line:
        return False, "JSON must be compact (no spaces)"

    # 7. Check for user_message event
    with open(file_path) as f:
        for line in f:
            rec = json.loads(line)
            if rec.get('type') == 'event_msg' and rec.get('payload', {}).get('type') == 'user_message':
                return True, "Valid"

    return False, "Missing event_msg with type='user_message'"
```

## Testing Checklist

- [ ] Filename starts with `rollout-`
- [ ] **Filename contains valid UUID** (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
- [ ] Filename format: `rollout-YYYY-MM-DDTHH-MM-SS-<uuid>.jsonl`
- [ ] UUID in filename matches `session_meta.payload.id` exactly
- [ ] `session_meta.payload.source` is `"cli"` or `"vscode"`
- [ ] Has `session_meta` record (line 1)
- [ ] Has at least one `event_msg` with `payload.type="user_message"`
- [ ] JSON is compact (no spaces after `:` or `,`)
- [ ] File is in `~/.codex/sessions/YYYY/MM/DD/`
- [ ] Each line is valid JSON

## Why Sessions Don't Appear

| Issue | Symptom | Fix |
|-------|---------|-----|
| Filename doesn't start with `rollout-` | Skipped during scan | Rename to `rollout-*` |
| UUID mismatch | Pagination fails | Ensure UUIDs match |
| `source` not `"cli"` or `"vscode"` | Filtered out | Change to `"cli"` |
| No `event_msg` with `user_message` | Filtered out | Add for each user message |
| JSON has spaces | May not parse correctly | Use `separators=(',', ':')` |

## History.jsonl (NOT Required for Picker)

**`~/.codex/history.jsonl` is written by Codex itself when users send messages.**

The converter does NOT need to write to this file. The session will appear in the picker based on the 6 requirements above.

History.jsonl is only for search/autocomplete functionality within active sessions.
