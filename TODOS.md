# Contextify TODOs

This document tracks feature ideas, enhancements, and known issues for future development.

## Active Development

### P0 - In Progress
- Transcript inventory with worktree support (feature/transcript-inventory)
- Line number tracking for narrative composition

### P1 - Next Up
- Session switching from transcript inventory UI
- Narrative composition from selected timeline entries

## Backlog

### Bugs

#### Timeline Entry Tense Inconsistency
**Status:** Backlog
**Priority:** Medium

Timeline entries are generated immediately when messages arrive, using present tense ("Claude proposes...", "Claude implements..."). This looks odd because they're historical log entries that should use past tense ("Claude proposed...", "Claude implemented...").

**The Challenge:**
- Entries are created as messages arrive (present moment)
- They should look like past events once logged
- Ideally, "in-progress" entries could flip to past tense once completed
- But we don't want to re-compute summaries (expensive LLM calls)

**Possible Solutions:**

1. **Simple fix:** Just use past tense in LLM instructions
   - Pro: Easy, one-line change
   - Con: "Claude proposed..." for in-progress work feels weird
   - Con: No distinction between active vs completed work

2. **Smart tense with completion detection:**
   - Use present continuous for in-progress ("Claude is implementing...")
   - Use past tense only when isCompletion=true ("Claude implemented...")
   - Pro: Natural language feel
   - Con: Still doesn't "flip" existing entries

3. **Post-completion tense flip** (requires caching):
   - Generate in present tense initially
   - When completion detected, update previous entry to past tense
   - Pro: Most natural, shows progression
   - Con: Requires cached summaries + entry mutation

**Related:** Timeline Summary Caching (see below)

#### Conversation Switch: Excessive System Messages + Missing User Messages
**Status:** Active Investigation
**Priority:** Critical
**Reported:** 2025-10-10

Multiple related issues with timeline display:
1. Too many system "provider switch" messages appearing
2. User messages not showing up at all in timeline

**Symptoms:**
- Tons of system messages (likely repeated "Switched to..." messages)
- User messages completely absent from timeline
- File watcher may be functioning but messages aren't being added

**Root cause hypothesis:**
- `refreshActiveConversation()` polling loop (every 10s) may be repeatedly detecting "provider change" even when conversation hasn't changed
- This causes repeated `emitProviderSwitchEntry()` calls
- OR: LLM summarization for user messages is failing silently and returning early
- OR: User messages being filtered by meta/command-wrapper checks

**Investigation areas:**
- Check if `refreshActiveConversation()` properly detects when session hasn't changed (line 151-154)
- Add logging to see why user messages aren't making it through `processUserMessage()`
- Check if `switchToSession()` is being called too frequently
- Verify `seenMessageUUIDs` prevents duplicate system messages

### Performance

#### Timeline Summary Caching
**Status:** Backlog
**Priority:** High
**Related:** Transcript metadata system

Currently, timeline entries are re-generated from scratch on every app launch by re-parsing the entire JSONL transcript and calling the LLM for each message. This is slow and expensive.

**Current Flow:**
1. App starts, reads `conversation.jsonl`
2. For each JSONL line: parse → LLM summarize → create TimelineEntry
3. On refresh: repeat the entire process
4. No persistence of generated summaries

**Problems:**
- Expensive: LLM calls for every message on every launch
- Slow: Summarization takes ~150ms per message minimum
- Wasteful: Re-computing the same summaries repeatedly
- Blocks future features: Can't do tense-flipping without cached summaries

**Proposed Solution:**
Similar to transcript metadata system (`TranscriptMetadata.json`), create a timeline cache:

**File structure:** `~/Library/Application Support/Contextify/timeline-cache/{project-hash}/`
- `timeline-entries.json` - Cached TimelineEntry objects
- `summary-cache.json` - Map of message UUID → summary metadata

**Cache entry format:**
```json
{
  "messageUUID": "abc-123",
  "summary": "Claude proposed fixing the refresh logic",
  "disposition": "proposal",
  "isCompletion": false,
  "isDirective": false,
  "generatedAt": "2025-10-10T12:15:00Z",
  "schemaVersion": 1
}
```

**Implementation:**
1. Check cache before calling LLM
2. Only summarize new/unseen message UUIDs
3. Persist cache after each summarization
4. Invalidate cache on schema version changes
5. Support cache migration/upgrade

**Benefits:**
- Fast startup: Only summarize new messages
- Enables tense-flipping: Can mutate cached summaries
- Enables summary editing: User could manually fix bad summaries
- Foundation for offline mode: Work without LLM available

**Challenges:**
- Cache invalidation: When to regenerate summaries?
- Storage management: Prune old entries
- Migration: Handle schema changes gracefully

### Features

#### Conversation Log Enhancements

##### 1. Reduce Assistant Entry Density
**Status:** Active Development
**Priority:** High
**Branch:** feature/timeline-completion-improvements

The conversation log shows too many assistant entries for a single directive/response cycle (e.g., 14 entries before a completion marker). This creates excessive noise and makes it hard to follow the conversation flow.

**Root cause:**
Claude Code generates many small text blocks as the assistant works, each becoming a timeline entry. This includes acknowledgements, progress updates, and intermediate thoughts.

**Proposed solutions:**
1. **Disposition-based filtering** (recommended): Use the LLM's `disposition` field to filter entries:
   - Always show: `completion`, `proposal`, `question`, `refusal`
   - Sometimes show: `analysis` (if >100 chars or first in sequence)
   - Suppress: `ack`, `wip` (work-in-progress)

2. **Time-based throttling**: Suppress assistant entries within N seconds of the previous one (unless completion)

3. **Content-based suppression**: Skip very short assistant messages (<50 chars) unless they're completions

**Implementation approach:**
Add filtering logic in `addAssistantTextEntry()` based on `disposition` from `GuidedTimelineSummary`.

##### 2. Avoid Sequential Completed Entries
**Status:** Completed (2025-10-10)
**Priority:** Medium

~~The conversation log currently can show multiple sequential "completed" entries, which creates redundancy and clutters the timeline.~~

**Example of redundancy:**
```
✓ Claude marks the final todo as completed.
---
Perfect! The build succeeded with no errors. Let me mark the final todo as completed.

✓ Claude successfully converted the Transcript Inventory to an independent window...
---
## Implementation Complete!
I've successfully converted the Transcript Inventory from a modal sheet to an independent window...
```

**Proposed Solution:**
When processing timeline entries marked as "completed":
1. Check if the previous entry is also marked as "completed"
2. If so, merge or suppress the second completion entry
3. Consider consolidating the summaries or only showing the more detailed one
4. Possibly use a different indicator (e.g., "Progress: ..." vs "✓ Completed")

**Implementation considerations:**
- May need to distinguish between "task completed" vs "subtask completed"
- Could use confidence scoring on completion detection
- Should preserve important context even when merging

##### 2. Timeline Verbosity Settings
**Status:** Backlog
**Priority:** Medium

Add user-configurable verbosity control for timeline entries to balance detail vs clarity.

**Proposed UI:**
- Settings panel with a slider control
- 4 verbosity levels from minimal to verbose
- Real-time preview showing what gets filtered at each level
- Persisted preference in UserDefaults

**Verbosity Levels:**

| Level | Name | Suppressed Dispositions | Kept Dispositions | Est. Entries/Cycle |
|-------|------|------------------------|-------------------|-------------------|
| 0 | Minimal | ack, wip, analysis, proposal | completion, question, refusal | 1-2 |
| 1 | Balanced (Default) | ack, wip, analysis | completion, proposal, question, refusal | 3-5 |
| 2 | Detailed | ack, wip | completion, analysis, proposal, question, refusal | 6-8 |
| 3 | Verbose | (none) | (all) | 10-14 |

**Implementation:**
- Add `TimelineVerbosity` enum with levels 0-3
- Store preference in `MonitorConfig` or `HUDPreferences`
- Update `addAssistantTextEntry()` to check verbosity level
- Add settings UI in ConversationTimelineView menu or separate preferences window

**Current Implementation:**
Level 1 (Balanced) is hard-coded in `ConversationMonitor.swift:630`

##### 3. Task Duration Tracking
**Status:** Completed (2025-10-10)
**Priority:** Medium
**Depends on:** Enhancement #1 (completed entry detection)

Once we can reliably identify completed entries, show the elapsed time from the user's request to completion.

**Proposed UI:**
- Show duration next to completed entries (e.g., "✓ Completed in 2m 34s")
- Add small arrow icon (↑) next to completed entries
- Clicking arrow scrolls to and highlights the original request in the log
- Hovering shows timestamp of request and completion

**Implementation considerations:**
- Need to track correlation between user requests and completion events
- Store request UUID with each task
- Calculate duration from first relevant assistant message to completion marker
- Handle cases where tasks span multiple timeline entries

#### Transcript Migration UI
**Status:** Backlog
**Priority:** Super Low (manual script works fine, edge case)
**Related:** `scripts/migrate-transcripts.sh`

When users move their project to a new directory (e.g., `~/code/contextify` → `~/code/projects/contextify`), Claude Code creates a new transcript directory. Old transcripts remain at the old location with outdated paths in content.

**Current Solution:**
Manual script at `scripts/migrate-transcripts.sh` that:
- Backs up old transcripts
- Copies to new location
- Rewrites all path references to new location

**Future Enhancement:**
Wrap the script in UI:
- Detect when project path has changed
- Offer to migrate old transcripts
- Show preview of what will be migrated
- One-click migration with progress indicator
- Automatic backup before migration

---

## Completed
- ✅ Timeline monitoring with JSONL parsing
- ✅ LLM-based timeline summarization
- ✅ Multi-source transcript providers (Claude Code)
- ✅ Git repository and worktree detection
- ✅ Security-scoped bookmarks for sandboxed access
- ✅ Real-time file watching with DispatchSource
