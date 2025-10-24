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
    - `parentUuid` (nullable), `isSidechain` (bool), `userType` (e.g., `"external"`), `cwd` (string),  
      `sessionId` (uuid), `version` (semver), `gitBranch` (string), `type: "user"`, `uuid` (uuid), `timestamp`
    - `message` (object) with `{ role: "user", content: "<…>" }`
    - Optional `isMeta: true` (to mark guidance/caveat messages)
  - **Semantics:** Captures terminal/user-originated messages and metadata (including **cwd**, **git branch**, **tool version**, **session**).

- Assistant messages (tool’s model output)
  - Appears as a message object (role `"assistant"`) with model/version/usage details, sometimes accompanied by **thinking metadata** (e.g., `thinkingMetadata: { disabled: true }`).

> **Linking:** Messages use `uuid` and **parentUuid** to form chains. Snapshots use **messageId**. `sessionId` ties entries to a session.

---

### Codex/AI CLI (from the provided sample)

- `session_meta`
  - **Fields:**  
    - `timestamp` (ISO)  
    - `type: "session_meta"`  
    - `payload` (object) with:
      - `id` (uuid), `timestamp` (ISO), `cwd` (string)
      - `originator` (e.g., `"codex_cli_rs"`), `cli_version` (string)
      - `instructions` (string; may be large, multiline)
      - `source` (e.g., `"cli"`)
      - `git` (object: `{ commit_hash, branch, repository_url }`)
  - **Semantics:** Declares **session-level context** at the start (env, git, instruction preamble).

- `response_item`
  - **Fields:**  
    - `timestamp`, `type: "response_item"`, `payload`
    - `payload` → typed message: `{ type: "message", role: "user"|"assistant", content: [ { type: "input_text", text }, … ] }`
  - **Semantics:** Canonical **conversational turns** with **structured content array**.

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
| **Message linking** | `uuid` + `parentUuid` (threading), `sessionId` | `call_id` for tools; conversation grouping implied by file; `session_meta.payload.id` is the session anchor |
| **CWD / Repo** | `cwd` per message; `gitBranch` at message-level | `session_meta.payload.cwd`; `payload.git.{commit_hash,branch,repository_url}` |
| **Record taxonomy** | `file-history-snapshot`, `user`, assistant messages; strong **file backup** focus | `session_meta`, `response_item`, `event_msg`, `function_call`, `function_call_output`, `reasoning`; strong **tooling/agent** focus |
| **Content envelope** | `message: { role, content }` (string content) | `payload.message: { role, content: [ {type, text}|… ] }` (typed segments) |
| **Snapshots** | Yes — `trackedFileBackups` per path with versions/timestamps | No equivalent (tool outputs/logs instead) |
| **Internal thoughts** | Not present; may include `thinkingMetadata` flags | Present as `type: "reasoning"` with `encrypted_content` |
| **Tool I/O** | Not explicit in the sample (outside of assistant messages) | First-class: `function_call` / `function_call_output` with arguments, stdout, exit codes |
| **Session preamble** | Implicit via early `user` meta and snapshots | Explicit `session_meta` with all environment/git/instructions |
| **Timestamps** | ISO strings on each record; also inside `snapshot` | ISO strings on each record; also within `session_meta.payload` |

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

