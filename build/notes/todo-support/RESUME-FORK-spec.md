---
todo_id: P2-RESUME-FORK
title: Resume and Fork Conversations from Search
type: spec
date: 2025-12-06
status: active
description: Epic specification for resuming and forking Claude Code/Codex conversations from Contextify search results, positioning Contextify as "git log for agentic coding sessions"
---

# Epic: Conversation Resume & Fork from Search

**Status:** Draft Specification
**Created:** 2025-12-06

---

## Executive Summary

Contextify is evolving from a passive conversation viewer to an active participant in the agentic coding workflow. This epic introduces the ability to resume or fork Claude Code and Codex CLI conversations directly from search results, positioning Contextify as the **"git log for agentic coding sessions."**

---

## Philosophical Foundation

### The Shift: Observer to Participant

Contextify began as a HUD - a heads-up display that monitors and summarizes CLI AI sessions. It watches the action without participating in it.

This epic changes that posture. When Contextify can:
- Fork conversations at arbitrary points
- Create new transcript artifacts
- Inject its own system messages into the timeline
- Log its operations alongside Claude/Codex actions

...it becomes a **workflow orchestrator**, not just a viewer.

### "Git Log for Agentic Coding Sessions"

Git doesn't write your code. It tracks commits. But `git log` is essential to understanding how a project evolved.

Similarly, Contextify doesn't run your prompts. But it captures:
- What Claude did
- What Codex did
- **Where the human intervened** (via Contextify)
- **How the workflow branched**

That human decision layer - "I forked here to try a different approach" - is otherwise invisible and lost. Contextify makes it explicit and searchable.

### First-Class Participant

With this epic, Contextify's brandmark appears in the conversation timeline alongside Claude and Codex icons. Not claiming equal importance to foundation models, but marking: **"Here's where the human made a decision via Contextify."**

This is a different category of event - but one worth logging. The audit trail of agentic coding sessions should include the orchestration decisions, not just the AI outputs.

---

## Current State

### Existing Resume Functionality

Resume command generation **already exists** in Contextify, but only in the transcript export flow:

**Location:** `Contextify/Contextify/TranscriptInventoryView.swift:746-814`

**Current behavior:**
1. User right-clicks transcript → "Export to..." (Claude ↔ Codex conversion)
2. On success, dialog shows resume command
3. "Copy Command" button copies to clipboard
4. Commands generated:
   - Claude: `cd <projectDir> && claude --resume <sessionId>`
   - Codex: `cd <projectDir> && codex resume <sessionId>`

**What's missing:**
- No resume option in search results
- No resume from main timeline view
- No fork-from-midpoint capability
- No Contextify system messages in timeline
- Feature may be undertested (QA needed)

### CLI Resume Capabilities

| Tool | Resume Most Recent | Resume by ID | Fork/Branch |
|------|-------------------|--------------|-------------|
| **Claude Code** | `claude --continue` | `claude --resume <uuid>` | `--fork-session` flag |
| **Codex CLI** | `codex resume --last` | `codex resume <uuid>` | Esc-Esc to walk back, Enter to fork |

**Session storage:**
- Claude Code: `~/.claude/projects/<project>/sessions/`
- Codex CLI: `~/.codex/sessions/YYYY/MM/DD/`

---

## Feature Specification

### User Stories

#### Story 1: Resume Transcript from Search Results
**As a** developer reviewing past sessions
**I want to** right-click a transcript in search results and resume it
**So that** I can continue a previous conversation without manually finding the session ID

**Acceptance Criteria:**
- Right-click transcript in search results shows "Resume this conversation" option
- Clicking copies resume command to clipboard
- Toast notification confirms: "Resume command copied to clipboard"
- Works for both Claude Code and Codex CLI transcripts
- Command includes `cd` to correct project directory

---

#### Story 2: Fork Transcript from End
**As a** developer who wants to try a different approach
**I want to** fork a conversation from its final state
**So that** I can branch without affecting the original session

**Acceptance Criteria:**
- Right-click transcript shows "Fork this conversation" option
- For Codex: uses built-in fork behavior
- For Claude Code: uses `--fork-session` flag if available, else documents limitation
- Toast confirms action with command copied
- (Stretch) Contextify logs the fork action in timeline

---

#### Story 3: Fork from Specific Entry (Mid-Conversation)
**As a** developer reviewing a long session
**I want to** fork from a specific message, not just the end
**So that** I can "rewind" to an earlier decision point and try a different path

**Acceptance Criteria:**
- Right-click entry (message) in search results or main timeline
- Shows "Fork original conversation from here" option
- Contextify creates a **trimmed transcript** containing only messages up to that point
- Trimmed transcript written to appropriate location (new session)
- Resume command for trimmed session copied to clipboard
- Toast confirms: "Forked conversation created. Resume command copied."

**Technical Notes:**
- Requires creating new transcript file with truncated content
- Must preserve valid JSONL/JSON structure
- New session ID generated
- Original transcript unchanged

---

#### Story 4: Contextify System Messages
**As a** developer reviewing my workflow history
**I want to** see Contextify actions logged in the timeline
**So that** I have a complete audit trail of my agentic coding sessions

**Acceptance Criteria:**
- Fork/resume actions inject a Contextify system message into the timeline
- Message includes: timestamp, action type, resume command
- Contextify brandmark/icon displayed alongside Claude/Codex icons
- Right-click system message → "Copy command" available
- System messages stored in Contextify's database (not modifying original transcripts)

**Technical Notes:**
- Requires new message type: `ContextifySystemMessage` or similar
- May build on prior system message work (needs investigation)
- Messages are Contextify-authored, distinct from transcript content
- Displayed inline in timeline at appropriate position

---

#### Story 5: Resume Action in Main Timeline
**As a** developer viewing the current session
**I want to** access resume/fork options from the main timeline, not just search
**So that** I have consistent access regardless of how I navigated to the conversation

**Acceptance Criteria:**
- Right-click context menu in main timeline includes resume/fork options
- Behavior matches search results context menu
- Available on transcript header and individual entries

---

### QA Requirements

**Existing functionality to verify:**
- [ ] Export → Resume flow works for Claude Code transcripts
- [ ] Export → Resume flow works for Codex CLI transcripts
- [ ] Generated commands are correct and executable
- [ ] Copy to clipboard works reliably

**Add to release QA if not already covered.**

---

## Technical Architecture

### Trimmed Transcript Creation (Story 3)

For mid-conversation forks, Contextify must:

1. **Read original transcript** from filesystem
2. **Parse and truncate** to selected entry position
3. **Generate new session ID** (UUID)
4. **Write new transcript file** to appropriate location:
   - Claude: `~/.claude/projects/<project>/sessions/<new-uuid>.jsonl`
   - Codex: `~/.codex/sessions/YYYY/MM/DD/<new-uuid>.jsonl`
5. **Preserve structure** - valid JSONL with all required fields
6. **Return resume command** for new session

**Considerations:**
- Sandbox builds need `accessProvider.withAccess()` for file operations
- Must handle both transcript formats (see `build/docs/specifications/transcript-formats.md`)
- Error handling for permission issues, missing transcripts

### Contextify Message Schema

New database entity or extension:

```swift
struct ContextifyAction {
    let id: UUID
    let timestamp: Date
    let actionType: ActionType  // .fork, .resume, .export
    let sourceTranscriptId: String
    let targetTranscriptId: String?  // for forks
    let command: String  // the resume command
    let projectId: UUID
}

enum ActionType {
    case fork
    case resume
    case export
}
```

Display in timeline requires:
- New row type in timeline view
- Contextify icon/brandmark asset
- Distinct visual styling (system message appearance)

### Context Menu Additions

**TranscriptInventoryView / Search Results:**
```
[Transcript Row]
  → Resume this conversation
  → Fork this conversation

[Entry Row]
  → Fork original conversation from here
  → Copy message text (existing?)
```

**ConversationMonitor / Main Timeline:**
```
[Transcript Header]
  → Resume this conversation
  → Fork this conversation

[Entry Row]
  → Fork from here
```

---

## Implementation Phases

### Phase 1: Resume from Search (MVP)
- Add context menu to search results
- Resume command generation (leverage existing code)
- Toast notifications
- QA existing export→resume flow

### Phase 2: Fork from End
- Fork option in context menu
- Handle Claude `--fork-session` vs Codex Esc-Esc behavior
- Document any limitations

### Phase 3: Fork from Midpoint
- Transcript parsing and truncation
- New session file creation
- Session ID generation
- File system operations (with sandbox handling)

### Phase 4: Contextify System Messages
- Database schema for Contextify actions
- Timeline display integration
- Icon/brandmark in timeline
- Right-click to copy from system messages

### Phase 5: Main Timeline Integration
- Context menus in main timeline view
- Consistent UX with search results

---

## Open Questions

1. **Where should forked transcripts live?**
   - Alongside originals in `~/.claude/` or `~/.codex/`?
   - In Contextify's own storage with symlinks?
   - Temporary location?

2. **Should forks track parent relationship?**
   - Store "forked from transcript X at entry Y" in database?
   - Enables "show fork history" feature later

3. **Codex fork limitations:**
   - Codex's Esc-Esc fork is interactive only
   - Can we create trimmed transcript for non-interactive fork?
   - Need to verify Codex accepts externally-created session files

4. **Prior system message code:**
   - ✅ **YES - infrastructure exists!**
   - `SystemEvent` model: `Models.swift:540` - database-backed entity with subtype, level, content
   - `appendSystemEntry()`: `ConversationMonitor.swift:3139` - appends `TimelineEntry(kind: .system, ...)` to timeline
   - `TimelineEntry` already has `.system` kind enum case
   - **Work needed:** extend for fork/resume actions, add Contextify branding, ensure persistence

---

## References

### CLI Documentation
- Claude Code resume: `claude --resume <session-id>`, `claude --continue`
- Codex CLI resume: `codex resume <session-id>`, `codex resume --last`

### Contextify Code
- Existing resume logic: `TranscriptInventoryView.swift:746-814`
- Transcript converter: `app/Sources/ContextifyCore/TranscriptConverter.swift`
- Transcript formats: `build/docs/specifications/transcript-formats.md`

### External Sources
- Claude Code docs: https://docs.anthropic.com/en/docs/claude-code/cli-usage
- Codex CLI docs: https://developers.openai.com/codex/cli/reference/
- CCManager (multi-session manager): https://github.com/kbwo/ccmanager

---

## Appendix: Resume Command Reference

### Claude Code

```bash
# Resume most recent
claude --continue

# Resume specific session
claude --resume <session-id>

# Resume + immediate prompt (non-interactive)
claude --continue --print "Continue with my task"
claude --resume <session-id> --print "Fix the tests"

# Fork session (creates new ID)
claude --resume <session-id> --fork-session
```

### Codex CLI

```bash
# Interactive picker
codex resume

# Resume most recent
codex resume --last

# Resume specific session
codex resume <session-id>

# Resume with directory override
codex resume <session-id> --cd /path/to/project

# Interactive fork (in-session only)
# Press Esc twice to walk back, Enter to fork
```

---

*This document captures the vision and specification for the Resume & Fork epic. It should be refined as implementation progresses and questions are resolved.*
