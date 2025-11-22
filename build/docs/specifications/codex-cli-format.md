# Codex CLI Transcript Format - Technical Reference

**Status:** Technical Analysis (2025-11-21)
**Source:** Local analysis of Codex CLI transcripts + Contextify parser implementation
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
- **No message queueing:** Synchronous turn-based interaction model

---

## Concurrent Input Handling

### No Queue Mechanism

Unlike Claude Code, **Codex CLI does not implement message queueing**. This represents a fundamental architectural difference in how user input is handled during tool execution.

**Verification:**
```bash
$ grep -h '"type":"queue-operation"' ~/.codex/sessions/*/*/*/*.jsonl
[No results]
```

**Result:** Zero instances of `queue-operation` records across all Codex transcripts.

### Architectural Difference

| Feature | Claude Code | Codex CLI |
|---------|-------------|-----------|
| **Queue mechanism** | Yes (4 operations: enqueue, remove, popAll, dequeue) | No |
| **User input during tool execution** | Queued for later processing | Unknown (likely blocked or buffered) |
| **Message ordering** | Guaranteed (FIFO queue) | Linear (no queueing needed) |
| **Turn interruption** | Not supported (queue instead) | Unknown |
| **User experience** | Asynchronous (send anytime) | Synchronous (turn-based) |

### Design Philosophy

**Hypothesis 1: Synchronous Turn Model**
- Codex may enforce strict turn-taking (user waits for completion)
- Input during tool execution may be blocked until turn completes
- Simpler concurrency model (no queue state management)

**Hypothesis 2: Different Tool Execution Model**
- Codex tools may be faster/atomic (no need for queueing)
- Long-running operations may be handled differently
- Less emphasis on concurrent user input

**Hypothesis 3: CLI Architecture Constraint**
- Codex CLI may use blocking I/O for user input
- Rust-based CLI may have different threading model
- Terminal interface may naturally enforce turn-taking

### Testing Needed

To validate these hypotheses:
1. Send message during Codex tool execution and observe behavior
2. Check if Codex transcript shows any indication of delayed processing
3. Compare tool execution patterns (long-running tools in Codex?)
4. Measure time between user input and tool completion

### Implications for Contextify

**Parser Implementation:**
- No queue-operation parsing needed for Codex
- Simpler timeline construction (no queue state tracking)
- Linear message display (no queue badges)

**UI Display:**
- No "QUEUED" badges for Codex transcripts
- Simple chronological timeline
- No queue status tooltips

**Performance:**
- Lighter weight parsing (no queue state overhead)
- No transient queue state management
- Faster timeline rendering for Codex sessions

**Code Example:**
```swift
enum TranscriptProvider {
    case claudeCode  // Has queueing
    case codex       // No queueing
}

func supportsQueueing(provider: TranscriptProvider) -> Bool {
    switch provider {
    case .claudeCode:
        return true
    case .codex:
        return false
    }
}
```

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
| **Message queueing** | Yes (queue-operation records) | No |
| **Concurrent user input** | Supported (messages queued during tool execution) | Unknown (likely blocked) |
| **Queue state management** | Required (transient state tracking) | Not applicable |
| **Turn interruption** | Not supported (queue instead) | Unknown |

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
| **Queue operations** | `type: "queue-operation"` | **Not present** |

### Content Blocks

| Content Type | Claude Code | Codex CLI |
|--------------|-------------|-----------|
| **User text** | `message.content: string` OR `{type: "text"}` | `{type: "input_text", text: "..."}` |
| **Assistant text** | `{type: "text", text: "..."}` | `{type: "output_text", text: "..."}` |
| **Display text** | `message.content` (for user) OR `text` block (for assistant) | `event_msg.payload.type = "agent_message"` |

**Important:** Codex timeline display should use `agent_message` events, not `response_item` assistant messages.

---

## Queue Operations (Not Applicable)

Codex CLI does not implement message queueing. See [Claude Code Queue Operations](./claude-code-transcript-format.md#queue-operations) for comparison.

**Summary:**
- ❌ No `enqueue` operation
- ❌ No `remove` operation
- ❌ No `popAll` operation
- ❌ No `dequeue` operation
- ❌ No queue state tracking needed
- ✅ Simpler parser implementation
- ✅ Linear timeline display

---

## Parser Implementation

For Codex transcript parsing in Contextify, see:
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` (CodexParser)
- `build/docs/specifications/transcript-formats.md` (Codex CLI section)

**Key Parsing Rules:**
1. **Project association:** Extract `cwd` from `session_meta.payload.cwd`
2. **Session identity:** Use `session_meta.payload.id` for session tracking
3. **Display text:** Use `agent_message` events, not assistant `response_item`
4. **No queue handling:** Skip queue operation parsing entirely
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

Codex CLI uses a **synchronous, turn-based interaction model** without message queueing. This architectural decision results in:
- ✅ **Simpler implementation:** No queue state management
- ✅ **Lighter weight:** Fewer record types to parse
- ✅ **Linear timeline:** Straightforward chronological display
- ❌ **Less flexibility:** Users may not be able to send messages during tool execution
- ❓ **Unknown UX impact:** Unclear how this affects user experience in practice

For Contextify, this means:
- No queue-operation parsing for Codex transcripts
- No queue badges in UI for Codex sessions
- Simpler timeline construction
- Potential performance advantage (less parsing overhead)

**Recommendation:** Monitor Codex architecture evolution. If queueing is added in future versions, update parser and UI accordingly.
