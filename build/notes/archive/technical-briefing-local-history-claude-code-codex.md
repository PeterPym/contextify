# Technical Brief — Compare & Contrast of Local History Formats
**Subjects:** Claude Code (per-project JSONL) vs Codex/AI CLI (session JSONL)  
**Date:** 2025-10-06

---

## Scope
Side-by-side, implementation-oriented comparison of the **on-disk JSONL transcripts** produced by:
- **Claude Code** — confirmed sample path on this machine:
  `/Users/rob/.claude/projects/-Users-rob-code-contextify/ce6e090b-603e-484a-977e-546214573964.jsonl`
- **Codex/AI CLI** — sample JSONL lines captured from a Codex/agent session (includes tool calls, outputs, and internal events).

Focus: **file layout, record shapes, linking/IDs, and semantics**. Excludes product narratives and opinions.

---

## Storage & Retention

### Location
- **Claude Code**
  - **Per-project** directory under `~/.claude/projects/<project-key>/`.
  - Filename is a **session UUID** with `.jsonl` extension (ex: `ce6e090b-...-546214573964.jsonl`).
  - `<project-key>` mirrors the project path with `/` replaced by `-` (ex: `-Users-rob-code-contextify`).

- **Codex/AI CLI**
  - Session logs are **per run** and written as JSONL. (In practice these are typically placed under a CLI data/home directory; the exact path is implementation/config dependent and not present in the provided sample.)

### Retention
- **Claude Code:** local cleanup is **configurable** (e.g., a retention/cleanup period is supported in product settings; defaults depend on build/config).  
- **Codex/AI CLI:** no automatic cleanup was observed/documented in the sample; logs accumulate unless you rotate/remove them.

> Operational note: Regardless of tool, expect **one JSON object per line** (JSONL), enabling streaming ingestion and append-only writes.

---

## File-Level Structure & Ordering

- **Both:** Append-only **JSONL**, ISO8601 timestamps, mixed record types.
- **Claude Code:** Interleaves **content messages** with **file snapshot events**. Heavy emphasis on `file-history-snapshot` records that enumerate **tracked file backups**.
- **Codex/AI CLI:** Interleaves **high-level messages** with **agent/tool events**:
  - Tool calls (`function_call`) and results (`function_call_output`)
  - Internal counters/telemetry (`event_msg` with `token_count`)
  - **Encrypted internal reasoning** records (`type: "reasoning"`, `encrypted_content: "gAAAAA..."`)
  - Typed user/assistant messages under `response_item`.

---

## Record Types (non-exhaustive but representative)

### Claude Code (from the provided file)

- `file-history-snapshot`
  - **Fields:**  
    - `messageId` (string) — identifier for the snapshot  
    - `snapshot` (object)
      - `messageId` (string)  
      - `trackedFileBackups` (map of file path → `{ backupFileName, version, backupTime }`)  
      - `timestamp` (ISO string)
    - `isSnapshotUpdate` (bool)
  - **Semantics:** Periodic capture of file backup states. When present, `trackedFileBackups` enumerates versioned backups per file.

- `user` (metadata and commands)
  - **Fields (top level):**
    - `parentUuid` (nullable string) — **REQUIRED FOR THREADING:** Links to previous assistant message UUID, or `null` for first message
    - `isSidechain` (bool)
    - `userType` (e.g., `"external"`)
    - `cwd` (string)
    - `sessionId` (uuid)
    - `version` (semver, e.g., `"2.0.26"`)
    - `gitBranch` (string)
    - `type: "user"`
    - `message` (object) with `{ role: "user", content: "<string>" }` - **CONTENT MUST BE STRING, NOT ARRAY**
    - `uuid` (uuid)
    - `timestamp` (ISO string) — **MUST BE STRICTLY INCREASING** (see Monotonic Timestamps section)
    - `thinkingMetadata` (object: `{ level: "none", disabled: true, triggers: [] }`)
  - **Semantics:** Captures terminal/user-originated messages and metadata (including **cwd**, **git branch**, **tool version**, **session**).

- Assistant messages (tool's model output)
  - **Fields (top level):**
    - `parentUuid` (uuid) — **REQUIRED FOR THREADING:** Links to previous user message UUID
    - `isSidechain` (bool)
    - `userType` (e.g., `"external"`)
    - `cwd` (string)
    - `sessionId` (uuid)
    - `version` (semver, e.g., `"2.0.26"`)
    - `gitBranch` (string)
    - `message` (object):
      - `model` (string, e.g., `"claude-sonnet-4-5-20250929"`)
      - `id` (string, e.g., `"msg_..."`)
      - `type: "message"`
      - `role: "assistant"`
      - `content` (array of `{ type: "text", text: "..." }`)
      - `stop_reason` (nullable)
      - `stop_sequence` (nullable)
      - `usage` (object with token counts)
    - `requestId` (string, e.g., `"req_..."`)
    - `type: "assistant"`
    - `uuid` (uuid)
    - `timestamp` (ISO string) — **MUST BE STRICTLY INCREASING** (see Monotonic Timestamps section)
  - **Note:** Assistant `message.content` is an array, user `message.content` is a string.

> **Linking:** Messages use `uuid` and **parentUuid** to form a conversation chain (singly-linked list). First message has `parentUuid=null`, each subsequent message links to its predecessor. Snapshots use **messageId**. `sessionId` ties entries to a session.

### **CRITICAL REQUIREMENT: Monotonic Timestamps**

**Verified:** Claude Code requires strictly increasing timestamps across all records. Records with identical timestamps cause only the first message to display.

**Rule:** Every record must have `timestamp` > all previous records.

**Implementation (1ms increments):**
```python
from datetime import datetime, timezone, timedelta

base = datetime.now(timezone.utc).replace(microsecond=0)
def next_ts():
    nonlocal base
    base = base + timedelta(milliseconds=1)
    return base.isoformat().replace('+00:00', 'Z')
```

**Validation:**
```bash
# Check for duplicates (should be empty)
jq -r 'if .timestamp then .timestamp else .snapshot.timestamp end' file.jsonl | uniq -d
```

**Impact without monotonic timestamps:**
- Only first user message displays
- All assistant responses hidden
- Session appears truncated when resumed

**Note:** Codex also requires monotonically increasing timestamps for proper session resumption.

---

### Codex/AI CLI (from the provided sample)

- `session_meta`
  - **Fields:**
    - `timestamp` (ISO) — **MUST BE STRICTLY INCREASING**
    - `type: "session_meta"`
    - `payload` (object) with:
      - `id` (uuid) — **REQUIRED:** session identifier, used in resume picker
      - `timestamp` (ISO)
      - `cwd` (string)
      - `originator` (e.g., `"codex_cli_rs"` or `"claude_code_converter"`)
      - `cli_version` (string)
      - `instructions` (nullable string; may be large, multiline)
      - `source` (string) — **REQUIRED:** Must be `"cli"` or `"vscode"` to appear in session picker
      - `git` (optional object: `{ commit_hash, branch, repository_url }`)
  - **Semantics:** Declares **session-level context** at the start (env, git, instruction preamble).

- `response_item`
  - **Fields:**
    - `timestamp` (ISO) — **MUST BE STRICTLY INCREASING**
    - `type: "response_item"`
    - `payload` → typed message: `{ type: "message", role: "user"|"assistant", content: [ { type: "input_text"|"output_text", text }, … ] }`
  - **Semantics:** Canonical **conversational turns** with **structured content array**.
  - **Note:** Content uses `input_text` for user, `output_text` for assistant (vs Claude Code's `text` type).

- `turn_context`
  - **Fields:**
    - `timestamp` (ISO)
    - `type: "turn_context"`
    - `payload` (object) with:
      - `cwd` (string) — current working directory
      - `approval_policy` (e.g., `"on-request"`)
      - `sandbox_policy` (object: `{ mode, network_access, exclude_tmpdir_env_var, exclude_slash_tmp }`)
      - `model` (string, e.g., `"gpt-5-codex"`)
      - `summary` (string, e.g., `"auto"`)
  - **Semantics:** **Marks conversation turn boundary**. Appears after `user_message` event and before agent reasoning/response. Required for proper conversation structure.

- `event_msg`
  - **Varies by `payload.type`**, e.g.:
    - `token_count` — usage/limits snapshot
    - `agent_reasoning` — high-level reason string (not the encrypted content)
    - `user_message` — echoes user input (appears after user `response_item`)
    - `agent_message` — **CRITICAL FOR DISPLAY:** Contains assistant response text shown in CLI
  - **Fields for `agent_message`:**
    - `payload.type: "agent_message"`
    - `payload.message` (string) — The actual assistant response text displayed to user
  - **Semantics:** Telemetry/UX stream separate from core messages. **Note:** `agent_message` events are what Codex CLI displays to the user when resuming sessions, NOT the `response_item` with role=assistant.

- `function_call` / `function_call_output`
  - **Fields:**  
    - `name` (tool name, e.g., `"shell"`), `arguments` (JSON string), `call_id`
    - Matching `function_call_output` includes **stdout/stderr** and **exit metadata**; shares the same `call_id`.
  - **Semantics:** **First-class tool invocation trace** with **request/response pairing** via `call_id`.

- `reasoning`
  - **Fields:** summary plus `encrypted_content` (opaque blob)
  - **Semantics:** Stores **internal chain-of-thought** in an encrypted payload.

> **Linking:** `call_id` pairs tool calls to outputs. Temporal cohesion via timestamps; no global `sessionId` in each record (the session is implied by the file and by `session_meta.id`).

---

## Field/Shape Comparison

| Aspect | Claude Code | Codex/AI CLI |
|---|---|---|
| **Message linking** | `uuid` + `parentUuid` (threading, **REQUIRED**), `sessionId` | `call_id` for tools; conversation grouping implied by file; `session_meta.payload.id` is the session anchor |
| **CWD / Repo** | `cwd` per message; `gitBranch` at message-level | `session_meta.payload.cwd`; `payload.git.{commit_hash,branch,repository_url}` |
| **Record taxonomy** | `file-history-snapshot`, `user`, assistant messages; strong **file backup** focus | `session_meta`, `response_item`, `event_msg`, `function_call`, `function_call_output`, `reasoning`; strong **tooling/agent** focus |
| **Content envelope** | `message: { role, content }` (string for user, array for assistant) | `payload.message: { role, content: [ {type, text}|… ] }` (typed segments) |
| **Snapshots** | Yes — `trackedFileBackups` per path with versions/timestamps | No equivalent (tool outputs/logs instead) |
| **Internal thoughts** | Not present; may include `thinkingMetadata` flags | Present as `type: "reasoning"` with `encrypted_content` |
| **Tool I/O** | Not explicit in the sample (outside of assistant messages) | First-class: `function_call` / `function_call_output` with arguments, stdout, exit codes |
| **Session preamble** | Implicit via early `user` meta and snapshots | Explicit `session_meta` with all environment/git/instructions |
| **Timestamps** | ISO strings (**MUST BE MONOTONIC**) on each record; also inside `snapshot` | ISO strings (**MUST BE MONOTONIC**) on each record; also within `session_meta.payload` |
| **Display logic** | Messages display directly | `event_msg` with `type: "agent_message"` controls display; `response_item` stores canonical data |

**Note on requirements:** Fields marked **REQUIRED** or **MUST** are empirically verified through round-trip conversion testing (2025-10-24). Some requirements (e.g., exact field order) were initially suspected but not confirmed—monotonic timestamps and `parentUuid` threading proved to be the critical factors.

---

## JSON Shape Snippets (normalized)

### Claude Code — `file-history-snapshot`
```json
{
  "type": "file-history-snapshot",
  "messageId": "…",
  "snapshot": {
    "messageId": "…",
    "trackedFileBackups": {
      "path/to/file.ext": {
        "backupFileName": "abcdef@v2",
        "version": 2,
        "backupTime": "2025-10-03T06:36:22.090Z"
      }
    },
    "timestamp": "2025-10-03T06:36:22.076Z"
  },
  "isSnapshotUpdate": false
}
````

### Codex/AI CLI — `function_call` + `function_call_output`

```json
{
  "timestamp": "2025-10-06T16:42:01.644Z",
  "type": "function_call",
  "name": "shell",
  "arguments": "{\"command\":[\"bash\",\"-lc\",\"nl -ba ~/.zshrc\"],\"workdir\":\"/Users/rob/code/contextify\"}",
  "call_id": "call_FWrFIvteK8J6c76kHBPtbRrw"
}
```

```json
{
  "type": "function_call_output",
  "call_id": "call_FWrFIvteK8J6c76kHBPtbRrw",
  "output": "{\"output\":\"…\",\"metadata\":{\"exit_code\":0,\"duration_seconds\":0.0}}"
}
```

---

## Bidirectional Conversion Requirements

### Claude Code → Codex (Verified Working)

**Required transformations:**
1. **Content format:** `message.content` (string) → `content: [{ type: "input_text"|"output_text", text }]` (array)
2. **Record expansion:** Each user→assistant exchange requires 5 Codex records:
   - `response_item` (user)
   - `event_msg` (type: "user_message")
   - `turn_context`
   - `event_msg` (type: "agent_message") — **what displays to user**
   - `response_item` (assistant)
3. **Session header:** Generate `session_meta` with `id`, `cwd`, `source: "cli"`, `originator`, `cli_version`
4. **Timestamps:** Maintain monotonic ordering (can reuse Claude Code timestamps or generate fresh)

### Codex → Claude Code (Verified Working)

**Required transformations:**
1. **Content format:** `content: [{ type: "input_text", text }]` → `message.content` (string for user, array for assistant)
2. **Threading:** Track previous message UUID and set `parentUuid` for each message (null for first)
3. **Snapshots:** Generate `file-history-snapshot` after each user message
4. **Record consolidation:** Convert 5-record Codex exchanges to 3-record Claude Code exchanges:
   - `response_item` (user) + `event_msg` (user_message) → `type: "user"` message
   - `file-history-snapshot` (generated)
   - `event_msg` (agent_message) + `response_item` (assistant) → `type: "assistant"` message
5. **Timestamps:** Generate fresh monotonic timestamps (cannot reuse Codex timestamps as multiple records share same timestamp)

**Critical fields for Claude Code:**
- `parentUuid`: Must form valid chain (user→asst→user→asst...)
- `uuid`: Unique per message, used as link target for next message's `parentUuid`
- `sessionId`: Must match filename (e.g., `8a066329-...jsonl` contains `"sessionId": "8a066329-..."`)
- `thinkingMetadata`: Required on user messages
- Field types: User content = string, assistant content = array

**Skip these Codex records during conversion:**
- `session_meta` (extract session context, don't convert)
- `event_msg` with non-message types (token_count, reasoning, etc.)
- `turn_context` (used for extraction only)
- `function_call` / `function_call_output` (no Claude Code equivalent in basic conversion)

---

## Required Conversation Structure (Codex)

**CRITICAL:** For Codex CLI to properly display conversation history when resuming, the following record sequence is required for each user→assistant exchange:

```
1. response_item (type: "message", role: "user")
2. event_msg (type: "user_message") — echoes user input
3. turn_context — marks conversation turn boundary
4. event_msg (type: "agent_message", message: "<assistant response>") — DISPLAYS to user
5. response_item (type: "message", role: "assistant") — canonical data
```

**Why this matters:**
- The `agent_message` event (step 4) is what Codex CLI actually **displays** to the user
- The `response_item` with role=assistant (step 5) contains canonical message data but does NOT display on its own
- Missing `turn_context` or `agent_message` will cause assistant responses to be invisible when resuming

**Example minimal conversation:**
```json
{"type":"session_meta","payload":{"id":"uuid",...}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Hello"}]}}
{"type":"event_msg","payload":{"type":"user_message","message":"Hello"}}
{"type":"turn_context","payload":{"cwd":"/path","model":"gpt-5-codex",...}}
{"type":"event_msg","payload":{"type":"agent_message","message":"Hi there!"}}
{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hi there!"}]}}
```

---

## Practical Parsing/Indexing Notes

* **Claude Code**

  * Treat `file-history-snapshot` as a **time-series** keyed by `messageId` and `snapshot.timestamp`.
  * The **backups map** is sparse by design; reconcile versions by `(path, version)` ascending by `backupTime`.
  * Use `uuid`/`parentUuid` to reconstruct conversational threads; `sessionId` scopes a file.

* **Codex/AI CLI**

  * Use `session_meta` as the **session header**; persist `payload.id` as **session key**.
  * Pair tools by `call_id`; parse `arguments` and `output` JSON strings to structured objects.
  * `response_item.payload.content` is an array — support multiple segment types (not just `input_text`).
  * `reasoning.encrypted_content` is **opaque**; don’t attempt to interpret.

---

## Operational Details (previously omitted — now included)

* **Storage locations**

  * Claude Code: `~/.claude/projects/<project-key>/<session-uuid>.jsonl` (confirmed example above).
  * Codex/AI CLI: per-run JSONL in the CLI’s data/home; **path is configurable/implementation-specific** (no absolute path present in the sample).

* **Retention**

  * Claude Code: supports **configurable cleanup** of local transcripts (e.g., a cleanup/retention period).
  * Codex/AI CLI: no auto-purge behavior evident in the sample; manage via ops/rotation.

* **Aux history/config**

  * Claude Code: maintains **per-project** history; may also keep a small rolling local config/history store depending on build/settings.
  * Codex/AI CLI: typically has a user config file (models, behaviors, paths); exact path/name depends on the specific build of the CLI.

* **Operational note**

  * Codex/AI CLI sessions can be reconstructed by **opening the latest JSONL** for a run and replaying `session_meta` → `response_item`/`event_msg` → `function_call`/`function_call_output` in order.

---

## Summary: Core Contrast

* **Claude Code** optimizes for **developer workspace provenance**: file snapshots with **versioned backups**, plus conversational/meta messages bound to a **project+session**.
* **Codex/AI CLI** optimizes for **agent traceability**: **session preamble**, rich **tool call**/result pairs, telemetry, and a separate **encrypted reasoning** stream; conversation is a series of typed payloads with explicit tool wiring.

---

## Tool Call Threading & Aggregation (2025-10-06)

### Problem
Timeline displays every individual tool call as a separate entry, creating noise. Example: A single assistant turn with 4 tool calls + 1 completion text results in 5 separate timeline entries.

### Claude Code Observation
Tool calls arrive as **separate assistant messages**, each with a single `tool_use` content block:
- Each tool call is an independent message with its own `uuid` and `timestamp`
- Messages have `parentUuid` but tool calls in the same "batch" may not share the same parent
- Completion text (if any) arrives as a **separate assistant message** with `type: "text"` content

**Example sequence:**
```
{ type: "assistant", uuid: "abc123", content: [{ type: "tool_use", name: "Bash" }] }
{ type: "assistant", uuid: "def456", content: [{ type: "tool_use", name: "Edit" }] }
{ type: "assistant", uuid: "ghi789", content: [{ type: "tool_use", name: "Bash" }] }
{ type: "assistant", uuid: "jkl012", content: [{ type: "text", text: "✅ Committed!" }] }
```

### Aggregation Strategy Implemented
1. **Buffer tool calls** as they arrive instead of immediately creating timeline entries
2. **Flush buffer** when:
   - A text message arrives → create single entry with tools + completion text
   - Time threshold exceeded (>10s since last tool call) → flush standalone tools
3. **Entry format:**
   - If 1 tool: "Used Bash"
   - If multiple: "Used 4 tools: Bash, Edit, Bash, Bash"
   - Detail shows completion text (if present) or tool summary
   - Timestamp uses earliest tool in the group

**Result:** 4 tool calls + 1 text = 1 timeline entry with meaningful summary

### Codex/AI CLI Considerations
Unlike Claude Code's separate messages per tool, Codex uses **paired records**:
- `function_call` with `call_id`
- `function_call_output` with matching `call_id`

For Codex aggregation:
- Group consecutive `function_call` records within a time window
- Match with their corresponding `function_call_output` records via `call_id`
- Detect completion by next `response_item` with role "assistant"
- Create single timeline entry summarizing the tool sequence + response

**Key difference:** Codex's `call_id` pairing is explicit, while Claude Code requires temporal/sequential grouping.

