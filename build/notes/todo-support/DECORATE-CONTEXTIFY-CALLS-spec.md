---
todo_id: DECORATE-CONTEXTIFY-CALLS
title: Decorate Contextify Agent and Skill Requests in Conversation Logs
type: spec
date: 2025-12-21
status: active
description: Identify Contextify skill/agent invocations and decorate conversation log entries with persistent icons.
---

# Contextify Skill/Agent Call Identification & Decoration

## Request Summary
- Determine whether Contextify can uniquely identify calls to the Contextify CLI made via skills and agents.
- Inspect:
  - Database entries from the last 12 hours for agent calls.
  - Claude Code transcripts from the last 60 minutes for skill calls.
- Known trigger strings:
  - Skill triggered by: "look in our convo history for discussion on using conditional logic to exclude it just like sparkle updater".
  - Agent call example in last 12 hours triggered by: "why aren't u using the agent to do this?".
- Identification must be based on call metadata/title/key, not conversational prompt text, to avoid false positives (e.g., unrelated skills mentioning "contextify" in prompts).
- Target identifiers:
  - Agent call: `query:contextify-researcher`.
  - Skill call: `/query:contextify-reinject`.
- Goal: decorate conversation log entry rows (same location as existing icons/"QUEUED" label) for:
  - Skill calls: Contextify icon.
  - Agent calls: detective emoji + Contextify icon.
- Decoration should apply to entries related to the call request (call + related work), not transient.
- Use official color scheme for any icon overlays; emoji should render as-is.
- If docs do not describe how to identify these calls in transcript files, propose doc changes.
- This is now treated as a feature spec + research; findings should be appended to this document.

## Scope
- Transcripts: Claude Code only.
- Database location: `/Users/rob/Library/Application Support/Contextify`.
- Lookbacks:
  - Skills: last 60 minutes (transcripts).
  - Agents: last 12 hours (database).

## Deliverables
1. Findings from transcript/database scans with recorded identifiers (file paths, timestamps, project IDs, transcript entry IDs, DB row IDs, etc.).
2. Proposed detection logic for both skill and agent calls (based on call metadata/title/key).
3. UI placement notes referencing existing "QUEUED"/entry decoration locations.
4. Optional model changes if needed to persist decoration state.
5. Documentation updates if current specs don’t cover identification rules.

## Open Questions
- None (ready to research).

## Research Findings (2025-12-21)

### Transcript Evidence (Claude Code)

#### Skill call: `query:contextify-reinject` (last 60 minutes)
- File: `/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/fd2f0d93-9aa0-4e32-a6f4-859fc90907fd.jsonl`
- Triggered by user string: "look in our convo history for discussion on using conditional logic to exclude it just like sparkle updater"
- Tool invocation record:
  - Line 175: assistant `tool_use` block
  - `name: "Skill"`
  - `input.skill: "query:contextify-reinject"`
  - `input.args: "contextify-query CLI exclusion App Store build conditional Sparkle"`
  - `uuid: 20a75e7b-c5b0-4e84-a52e-f633a99c12a2`
  - `timestamp: 2025-12-21T16:14:26.621Z`
- Tool result record:
  - Line 176: user `tool_result` block
  - `tool_use_id: "toolu_013ur8zicyj2QXVTTkP4CXFp"`
  - `content: "Launching skill: query:contextify-reinject"`
  - `toolUseResult.commandName: "query:contextify-reinject"`
  - `uuid: b0a76f6a-3956-4039-aca6-65e3a623c1ab`
  - `timestamp: 2025-12-21T16:14:26.681Z`
- Related meta entry:
  - Line 177: `isMeta: true`, `sourceToolUseID: "toolu_013ur8zicyj2QXVTTkP4CXFp"` (skill prompt and instructions)

#### Agent call: `query:contextify-researcher` (last 12 hours)
- File: `/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/286b5971-87b7-4f8c-ab20-42c553490f9a.jsonl`
- Tool invocation record:
  - Line 46: assistant `tool_use` block
  - `name: "Task"`
  - `input.subagent_type: "query:contextify-researcher"`
  - `input.prompt: ...` (multi-query retrieval prompt)
  - `uuid: 5218e0a9-0da4-4d67-a9ac-15fbf21ed4e6`
  - `timestamp: 2025-12-21T08:17:47.722Z`
- Tool result record:
  - Line 47: user `tool_result` block
  - `tool_use_id: "toolu_01D9iuaqbHmVd4SfhDPinMi4"`
  - `toolUseResult.status: "completed"`
  - `toolUseResult.agentId: "a54dafc"`
  - `uuid: 129a5e02-bd2f-45b3-be98-2e6e111e4367`
  - `timestamp: 2025-12-21T08:20:11.839Z`
- Sidechain transcript for agent:
  - File: `/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/agent-a54dafc.jsonl`
  - `agentId: "a54dafc"`, `isSidechain: true`
  - Contains the agent’s internal skill/tool use sequence.

### Database Evidence (last 12 hours)

#### Skill call entry
- `transcript_entries.id`: `20a75e7b-c5b0-4e84-a52e-f633a99c12a2`
- `project_id`: `71C07BC7-169B-4593-8B1B-4A1BBC8CD165`
- `transcript_id`: `C80937D4-3DCF-4EC1-A90A-B057DA793A8E`
- `session_id`: `fd2f0d93-9aa0-4e32-a6f4-859fc90907fd`
- `kind`: `assistant`
- `timestamp`: `2025-12-21 16:14:26`
- `content`: `[Tool: Skill]`

#### Agent call entry
- `transcript_entries.id`: `5218e0a9-0da4-4d67-a9ac-15fbf21ed4e6`
- `project_id`: `71C07BC7-169B-4593-8B1B-4A1BBC8CD165`
- `transcript_id`: `286b5971-87b7-4f8c-ab20-42c553490f9a`
- `session_id`: `286b5971-87b7-4f8c-ab20-42c553490f9a`
- `kind`: `assistant`
- `timestamp`: `2025-12-21 08:17:47`
- `content`: `[Tool: Task]`

**Observation:** The DB currently preserves only `[Tool: Skill]` / `[Tool: Task]` markers in `transcript_entries.content`, which is insufficient to uniquely identify `query:contextify-reinject` vs other skills or `query:contextify-researcher` vs other agents without re-reading the raw transcript.

### UI Placement Reference
- Conversation row decoration (QUEUED badge + directive/completion icons) is in `Contextify/Contextify/TimelineEntryRow.swift:160`.

---

## Proposed Identification Logic

### Skill calls (`/query:contextify-reinject`)
- Claude Code transcript `assistant.message.content[]` block:
  - `type: "tool_use"`
  - `name: "Skill"`
  - `input.skill == "query:contextify-reinject"` (exact match)
- Optional corroboration from the immediately following `user` record:
  - `tool_result` with `toolUseResult.commandName == "query:contextify-reinject"`

### Agent calls (`query:contextify-researcher`)
- Claude Code transcript `assistant.message.content[]` block:
  - `type: "tool_use"`
  - `name: "Task"`
  - `input.subagent_type == "query:contextify-researcher"` (exact match)
- Optional corroboration:
  - `tool_result.toolUseResult.agentId` present
  - sidechain transcript file `agent-<agentId>.jsonl` with `agentId` matching

### Related entries
- Use `sourceToolUseID` (skill meta entry) and `tool_use_id` on `tool_result` to mark related entries.
- For Task/agent, attach decoration to tool_use + tool_result entries in the main transcript; sidechain entries are `isSidechain: true` and currently excluded from timeline display.

---

## Gaps in Documentation
- Neither `build/docs/specifications/transcript-formats.md` nor `build/docs/specifications/claude-code-transcript-format.md` documents how to identify skill invocations (`name: "Skill"`, `input.skill`) or Task/subagent invocations (`name: "Task"`, `input.subagent_type`) or how `toolUseResult.commandName` and `toolUseResult.agentId` appear.

### Proposed Documentation Updates
Add a section like **“Skill and Agent Invocation Identification”** to both specs, covering:
- `tool_use` blocks for skills (`name: "Skill"`, `input.skill`, `input.args`).
- `tool_use` blocks for agents (`name: "Task"`, `input.subagent_type`, `input.prompt`, `input.description`).
- `tool_result.toolUseResult.commandName` for skills.
- `tool_result.toolUseResult.agentId` and sidechain `agent-<id>.jsonl` linkage for agents.
- Guidance to match on these fields instead of prompt text.

---

## Model/UI Change Proposal (Draft)

### Model changes (optional but recommended)
- Persist tool invocation metadata extracted from Claude Code transcripts so the UI can decorate without re-reading files:
  - Option A (new table): `tool_invocations` keyed by `entry_id`, with `tool_name`, `tool_kind` (Skill/Task), `tool_key` (skill name or subagent_type), `tool_use_id`, `related_entry_ids`.
  - Option B (columns on `transcript_entries`): `tool_name`, `tool_key`, `tool_use_id`, `tool_metadata_json`.
- Keep `project_id` as the primary query key (use `ActiveProjectContext.id`).
- Add database entries for skill/agent identifiers at ingestion time so historical data remains queryable without reparsing transcripts.

### UI changes
- Add a persistent badge/icon group in `TimelineEntryRow` adjacent to existing status icons (QUEUED/directive/completion):
  - Skill invocation: Contextify icon.
  - Agent invocation: detective emoji + Contextify icon.
- Ensure color treatment aligns with `build/design/brand/colors.md` (no ad hoc hues).
- Apply decoration to the tool_use entry and associated tool_result/meta entries (using `tool_use_id` / `sourceToolUseID`).
