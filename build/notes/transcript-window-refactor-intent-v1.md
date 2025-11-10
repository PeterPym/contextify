# Transcript Window Refactoring - Intent Document v1

**Date:** 2025-11-09
**Status:** Initial Understanding (Pre-Research)

## Problem Statement

TranscriptInventoryView.swift is currently 1516 lines (target: ~300 lines). This refactoring aims to reduce complexity while improving summarization behavior and error handling.

## Primary Goals

### 1. Code Size Reduction
- **Current:** 1516 lines
- **Target:** ~300 lines
- **Approach:** Extract components, factor out common elements

### 2. Summarization Behavior Alignment
- Make transcript window summarization behavior **mirror** the conversation log
- Conversation log has working, proven summarization UX
- Transcript window should adopt the same patterns

### 3. Fix Summarization Failures
- **Current Issue:** Failed summarization leaves transcripts with UUID as title
- **Root Cause:** Unknown (needs investigation)
- **Likely Areas:**
  - Prompt construction
  - Error handling/recovery
  - Default state management
- **Impact:** Poor UX - UUID titles are not human-readable

### 4. Queue Management Strategy
- **Current:** Status reported to main window status bar
- **Options:**
  1. **Shared Queue (Preferred):**
     - Single queue for both windows
     - Each window manages its own queue items
     - Viewport changes can prune items from either window
     - Central reporting in main window status bar
     - Errors clearly labeled by source (transcript vs. conversation)
  2. **Separate Queues:**
     - Independent queues per window
     - Separate status bars
     - More complex coordination

### 5. Error Reporting
- Transcript window errors displayed in main window status bar
- Error UI (info icon) must clearly indicate "transcript-based error" vs. conversation error
- Maintain consistency with conversation log error patterns

## Key Constraints

### Critical: Don't Break Conversation Log
- Conversation log is **working and stable**
- Refactoring must NOT destabilize it
- **Strategy:** It's acceptable to duplicate code initially
  1. Factor out common elements
  2. Transcript window adopts refactored components first
  3. Validate thoroughly
  4. Integrate conversation log later (only after validation)

### Code Duplication is Acceptable (Temporarily)
- Prioritize stability over DRY principle during transition
- Common code can be extracted after both windows are validated

## Research Questions (Pre-Research)

1. How does ConversationTimelineView currently handle summarization?
2. What is the exact flow of TimelineCacheMissGenerator?
3. What causes summarization to fail and leave UUID titles?
4. How does TranscriptMetadataOrchestrator differ from TimelineCacheMissGenerator?
5. What is the current structure of TranscriptInventoryView (1516 lines)?
6. How are errors currently propagated to the status bar?
7. What are the viewport management patterns in conversation log?

## Success Criteria

- [ ] TranscriptInventoryView reduced to ~300 lines
- [ ] Summarization behavior matches conversation log UX
- [ ] No transcripts with UUID titles (proper error recovery)
- [ ] Clear error attribution (transcript vs. conversation)
- [ ] Conversation log remains stable (no regressions)
- [ ] Shared queue properly manages items from both windows
- [ ] Status bar correctly reports unified queue state

## Next Steps

1. Research conversation log implementation (detailed code inspection)
2. Research current transcript window implementation
3. Identify exact failure modes for UUID titles
4. Write technical implementation plan with options
5. Get approval before proceeding with code changes
