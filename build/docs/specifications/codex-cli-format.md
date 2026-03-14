# Codex CLI Transcript Format - Technical Reference

**Status:** Technical Analysis (2026-03-14)
**Source:** Local analysis of Codex CLI transcripts, upstream `openai/codex` source, and Contextify parser implementation
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
- **Queued-input UI exists:** Upstream TUI shows queued follow-up messages and lets the user edit the last queued draft
- **No documented transcript queue signal:** Current local JSONL transcripts do not expose a queue-specific record or field

---

## Concurrent Input Handling

### Queueing Exists in the TUI

Codex CLI now implements queued input in the open-source TUI, but the queue currently appears to live in widget state rather than in the JSONL transcript format Contextify ingests.

**Source anchors:**
- `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`
- `codex-rs/tui/src/chatwidget.rs`
- `codex-rs/tui/src/app.rs`
- `codex-rs/protocol/src/protocol.rs`

**Observed upstream behavior:**
- The bottom pane renders:
  - `Messages to be submitted after next tool call`
  - `Queued follow-up messages`
  - `edit last queued message`
- `chatwidget.rs` stores queued drafts in `queued_user_messages: VecDeque<UserMessage>`
- `queue_user_message()` appends to that queue while a task is running, while the session is not configured, or while review mode is active
- `maybe_send_next_queued_input()` submits exactly one queued message when the turn becomes idle
- The `edit last queued message` keybinding pops the last queued draft back into the composer instead of emitting a transcript event
- `ThreadInputState` captures `queued_user_messages` only for in-memory thread switching and replay inside the TUI
- `UserMessageEvent` in `codex-rs/protocol/src/protocol.rs` contains the committed user message text and attachments, but no queue flag or queue status field

**Local transcript verification:**
```bash
rg -n -i 'queued|queue|next tool call|follow-up' ~/.codex/sessions/*/*/*/*.jsonl
```

**Result:** No queue-specific JSONL records or fields were found in local transcripts captured with Codex CLI `0.114.0`.

### Current Architectural Difference

| Feature | Claude Code | Codex CLI |
|---------|-------------|-----------|
| **Queue mechanism** | Yes (4 operations: enqueue, remove, popAll, dequeue) | Yes in TUI state; no transcript record documented yet |
| **User input during tool execution** | Queued for later processing | Queued in `queued_user_messages` while a turn is active |
| **Message ordering** | Guaranteed (FIFO queue) | FIFO in widget state, then committed as normal user messages |
| **Turn interruption** | Not supported (queue instead) | Pending steers can interrupt; queued follow-ups wait for next idle turn |
| **User experience** | Asynchronous (send anytime) | Asynchronous in TUI, but queue is not yet transcript-visible |

### Implications for Contextify

**Parser Implementation:**
- Do not invent queue parsing for Codex until a real machine-readable signal is confirmed
- Current Contextify ingestion sees only committed Codex user messages
- Queue badges for Codex are unsupported today because no transcript-visible queue state has been observed

**UI Display:**
- Keep Codex timeline display chronological based on committed transcript events
- Do not show a synthetic `QUEUED` badge for Codex without confirmed source data

**Performance:**
- Parsing remains lighter than Claude queue handling because Contextify has no Codex queue records to ingest today

---

## Record Types

For detailed record type specifications, see `build/docs/specifications/transcript-formats.md` (Codex CLI section).

**Key Record Types:**
- `session_meta`: Session header with `cwd`, `git`, `instructions`
- `response_item`: Conversational turns (user/assistant messages)
- `turn_context`: Turn boundary markers
- `event_msg`: Telemetry/UX events (`agent_message`, `token_count`, etc.)
- `function_call` / `function_call_output`: Tool invocations
- `reasoning`: Internal thoughts (encrypted)

**Critical for Contextify:**
- `session_meta.payload.cwd` - **REQUIRED** for project association
- `session_meta.payload.id` - **REQUIRED** for session identification
- `event_msg.payload.type = "agent_message"` - Contains assistant response text for display

---

## Message Ordering

Unlike Claude Code's explicit parent chaining (`uuid` + `parentUuid`), Codex uses:
- **Temporal ordering:** Timestamps determine message sequence
- **Tool call pairing:** `call_id` links function calls to outputs
- **File grouping:** All records in same file belong to same session
- **Session identity:** `session_meta.payload.id` ties records together

**No explicit threading:** Messages are ordered by file position and timestamp.

**No queue state:** All messages are processed in order without queueing.

---

## Comparison with Claude Code

### Storage Model

| Aspect | Claude Code | Codex CLI |
|--------|-------------|-----------|
| **Directory structure** | Per-project (`~/.claude/projects/<project-hash>/`) | Global (`~/.codex/sessions/YYYY/MM/DD/`) |
| **Project grouping** | Directory per project | All projects in shared tree |
| **Session files** | `<session-uuid>.jsonl` | `<name>-<timestamp>-<uuid>.jsonl` |
| **Discovery** | Scan directories, hash matches project path | Parse all files, extract `cwd` from `session_meta` |

### Concurrency Model

| Feature | Claude Code | Codex CLI |
|---------|-------------|-----------|
| **Message queueing** | Yes (queue-operation records) | Yes in open-source TUI state |
| **Concurrent user input** | Supported (messages queued during tool execution) | Supported in TUI via queued follow-up messages |
| **Queue state management** | Required (transient state tracking) | Required in TUI, but not exposed in observed transcripts |
| **Turn interruption** | Not supported (queue instead) | Pending steers can interrupt active turns |

### Record Taxonomy

| Record Purpose | Claude Code | Codex CLI |
|----------------|-------------|-----------|
| **User messages** | `type: "user"` | `type: "response_item"`, `role: "user"` |
| **Assistant messages** | `type: "assistant"` | `type: "response_item"`, `role: "assistant"` |
| **Tool calls** | `content: [{type: "tool_use"}]` | `type: "response_item"`, `payload.type: "function_call"` |
| **Tool results** | `content: [{type: "tool_result"}]` | `type: "response_item"`, `payload.type: "function_call_output"` |
| **Internal thoughts** | `content: [{type: "thinking"}]` | `type: "response_item"`, `payload.type: "reasoning"` |
| **Session metadata** | Implicit in early messages | Explicit `type: "session_meta"` |
| **File snapshots** | `type: "file-history-snapshot"` | No equivalent |
| **System events** | `type: "system"` | `type: "event_msg"` (various subtypes) |
| **Queue operations** | `type: "queue-operation"` | No queue record documented in observed JSONL |

### Content Blocks

| Content Type | Claude Code | Codex CLI |
|--------------|-------------|-----------|
| **User text** | `message.content: string` OR `{type: "text"}` | `{type: "input_text", text: "..."}` |
| **Assistant text** | `{type: "text", text: "..."}` | `{type: "output_text", text: "..."}` |
| **Display text** | `message.content` (for user) OR `text` block (for assistant) | `event_msg.payload.type = "agent_message"` |

**Important:** Codex timeline display should use `agent_message` events, not `response_item` assistant messages.

---

## Queue Operations (Transcript Status Unknown)

Codex CLI now implements queued-input behavior in the open-source TUI, but no queue-specific JSONL operation has been confirmed in local transcripts so far. See [Claude Code Queue Operations](./claude-code-transcript-format.md#queue-operations) for the richer transcript-visible model that Contextify already supports.

**Current status:**
- ✅ Queued follow-up messages exist in TUI state
- ✅ The UI exposes `edit last queued message`
- ❌ No confirmed Codex `enqueue` transcript record
- ❌ No confirmed Codex `remove` transcript record
- ❌ No confirmed Codex `popAll` transcript record
- ❌ No confirmed Codex `dequeue` transcript record
- ❌ No machine-readable queue lifecycle for Contextify to ingest yet

---

## Parser Implementation

For Codex transcript parsing in Contextify, see:
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` (CodexParser)
- `build/docs/specifications/transcript-formats.md` (Codex CLI section)

**Key Parsing Rules:**
1. **Project association:** Extract `cwd` from `session_meta.payload.cwd`
2. **Session identity:** Use `session_meta.payload.id` for session tracking
3. **Display text:** Use `agent_message` events, not assistant `response_item`
4. **Queue handling:** Skip Codex queue parsing until a real transcript or sidecar signal is confirmed
5. **Monotonic timestamps:** Validate timestamp ordering (same as Claude Code)

---

## Related Documentation

- **Format comparison:** `build/docs/specifications/transcript-formats.md`
- **Claude Code format:** `build/docs/specifications/claude-code-transcript-format.md`
- **Parser implementation:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`
- **Database schema:** `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`

---

## Future Investigation

**Open Questions:**
1. How does Codex handle user input during long-running tool execution?
2. Can users interrupt tool execution in Codex CLI?
3. What happens if user sends message during Bash command execution?
4. Is there buffering or blocking of user input?
5. Are there any mechanisms similar to queueing but not recorded in transcript?

**Testing Approach:**
1. Start Codex session with long-running tool (e.g., `sleep 60`)
2. Send user message during execution
3. Observe CLI behavior (blocked input? queued? error?)
4. Check transcript for any queue-related records
5. Document findings

---

## Conclusion

Codex CLI now has visible queued-input behavior in the open-source TUI, but Contextify still lacks a confirmed machine-readable queue signal to ingest. In current local evidence:

- queued follow-up messages are managed in TUI memory
- the transcript records only committed user messages
- no Codex queue lifecycle record has been observed in JSONL

For Contextify, this means:
- do not ship heuristic queue detection for Codex
- keep Codex queue support explicitly unsupported until a real source signal exists
- keep watching upstream transcript and protocol changes

**Recommendation:** Treat transcript capture as the gate. Once Codex emits queue state in JSONL or another supported local artifact, add parser support and queue badges then.
