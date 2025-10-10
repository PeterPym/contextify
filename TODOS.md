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

#### Conversation Switch: New Logs Not Displayed
**Status:** Backlog
**Priority:** High
**Reported:** 2025-10-10

When switching to a new Claude Code conversation, the system message indicating the switch appears correctly, but no new conversation logs are displayed after that system message entry. The timeline stops updating even though the file watcher should be monitoring the new conversation file.

**Symptoms:**
- System message "Switched to Claude Code conversation" appears
- No subsequent timeline entries are added
- File watcher appears to be set up correctly
- Issue occurs after provider switch

**Investigation areas:**
- Check if `lastProcessedLine` is being reset correctly in `switchToSession()`
- Verify file watcher is properly attached to new conversation file
- Check if `seenMessageUUIDs` needs to be cleared on switch
- Verify `processConversationFile()` is being triggered after switch

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

##### 2. Task Duration Tracking
**Status:** Backlog
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
