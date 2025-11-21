# Codex CLI Session Storage Format

## Critical Discovery

Codex CLI stores sessions in a **specific directory structure** that MUST be followed for sessions to appear in `codex resume`:

```
~/.codex/sessions/YYYY/MM/DD/filename-timestamp-uuid.jsonl
```

---

## System-Injected Messages

**Background:** Codex CLI automatically injects context at the start of every conversation. These appear as `response_item` records with `role: "user"` but were never actually sent by the user.

### Injected Messages

1. **AGENTS.md Instructions** - Project's AGENTS.md file wrapped in `<INSTRUCTIONS>` tags
2. **Environment Context** - Session environment details in `<environment_context>` XML

### Detection Pattern

**Key difference:** Real user messages have a companion `event_msg` record with `payload.type == "user_message"`. System-injected messages do NOT.

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

**Implementation:** Parser extracts user messages from `event_msg` records (with `payload.type == "user_message"`) instead of `response_item` records. This automatically excludes system-injected messages since they lack companion `event_msg` records.

**See:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` - `CodexLineParser.parseUserMessageFromEventMsg()`

---

## Examples

Real Codex sessions found on the system:
```
~/.codex/sessions/2025/10/19/rollout-2025-10-19T13-47-01-0199fe39-c07c-71d0-9ceb-9315a0946d34.jsonl
~/.codex/sessions/2025/10/19/rollout-2025-10-19T13-46-54-0199fe39-a5fe-79a2-922d-7845a60aae42.jsonl
```

## Filename Format

```
<prefix>-<timestamp>-<session-uuid>.jsonl
```

Components:
- **prefix**: Arbitrary name (e.g., `rollout`, `converted`, `test`)
- **timestamp**: ISO 8601 format `YYYY-MM-DDTHH-MM-SS`
- **session-uuid**: UUID from `session_meta.payload.id`
- **extension**: `.jsonl`

## Directory Structure

```
~/.codex/
├── sessions/
│   └── 2025/
│       └── 10/
│           └── 19/
│               ├── rollout-2025-10-19T13-47-01-<uuid>.jsonl
│               ├── rollout-2025-10-19T13-46-54-<uuid>.jsonl
│               └── test-converted-<timestamp>-<uuid>.jsonl
├── auth.json
├── config.toml
├── history.jsonl
└── version.json
```

## Why This Matters for Conversion

When converting **Claude Code → Codex**, the output file MUST be placed in:
```
~/.codex/sessions/<current-year>/<current-month>/<current-day>/
```

Otherwise, `codex resume` **will not find it** in the picker.

## Correct Conversion Command

**Wrong (will not appear in picker):**
```bash
./convert_transcript.py \
  --from claude-code --to codex \
  input.jsonl \
  ~/codex-output/session.jsonl  # ❌ Wrong location
```

**Right (will appear in picker):**
```bash
./convert_transcript.py \
  --from claude-code --to codex \
  input.jsonl \
  ~/.codex/sessions/2025/10/19/converted-2025-10-19T14-00-00-abc123.jsonl  # ✅ Correct
```

## Converter Auto-Detection

The updated converter now:
1. ✅ **Detects** if output path is NOT in `~/.codex/sessions/`
2. ✅ **Warns** you with the correct path
3. ✅ **Suggests** the exact `mkdir` and `cp` commands to fix it
4. ✅ **Prints** the session UUID for `codex resume <uuid>`

## Example Output

```bash
$ ./convert_transcript.py --from claude-code --to codex input.jsonl /tmp/output.jsonl

⚠️  WARNING: Codex expects sessions in ~/.codex/sessions/YYYY/MM/DD/
   For Codex to find this session, copy it to:
   ~/.codex/sessions/2025/10/19/output-2025-10-19T14-00-00-abc123.jsonl

   Quick fix:
   mkdir -p ~/.codex/sessions/2025/10/19
   cp /tmp/output.jsonl ~/.codex/sessions/2025/10/19/output-2025-10-19T14-00-00-abc123.jsonl
```

## Resume Instructions

After placing the file in the correct location:

```bash
cd /path/to/project  # From transcript metadata
codex resume abc123-def456-...  # Use the UUID
# OR
codex resume  # Pick from the list
```

## Source

This format was discovered by examining actual Codex sessions:
```bash
$ ls -1 ~/.codex/sessions/2025/10/19/
rollout-2025-10-19T13-47-01-0199fe39-c07c-71d0-9ceb-9315a0946d34.jsonl
rollout-2025-10-19T13-46-54-0199fe39-a5fe-79a2-922d-7845a60aae42.jsonl
...
```

## Updated Converter Behavior

The converter now:
1. Generates a proper Codex filename with timestamp and UUID
2. Suggests creating it in today's date directory
3. Warns if user provided a custom path
4. Provides copy-paste commands to fix the location

This ensures converted sessions **actually work** with `codex resume`.
