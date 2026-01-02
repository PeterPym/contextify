---
todo_id: P2-BACKGROUND-SUMM
title: Background LLM Summarization Design
type: design
date: 2025-11-27
status: active
description: Re-implement background LLM summarization for would-be-visible entries when app is backgrounded
---

# P2-BACKGROUND-SUMM: Background LLM Summarization

## Problem Statement

Currently, when app is backgrounded (user switches away), LLM summary generation is completely disabled. The log message is confusing: "App resigned active - background processing DISABLED". This is a policy decision, not a bug, but it's a missed opportunity.

## Previous Implementation

Background summarization used to exist but was removed at some point. Worth investigating git history to see:
- Why it was removed (performance? battery? user feedback?)
- What the implementation looked like
- Any useful code/patterns to reuse

### Git History Investigation Commands

```bash
git log --all --grep="background.*summar" -i
git log --all --grep="resign.*active" -i -- "**/ConversationMonitor.swift"
git log -S "background processing" --all
```

## Proposed Behavior

When app goes to background, continue summarizing entries that would be "visible" if the user scrolled back in timeline. This would:
- Pre-populate summaries for entries user is likely to see
- Make timeline feel more responsive when app returns to foreground
- Avoid wasted work (only summarize what user might actually view)

## Implementation Approach

### 1. Define "Would-Be-Visible" Scope (1 hour)

Options to consider:
- Current viewport + N entries above/below scroll position
- All entries within last X hours/days
- Based on user's typical scroll depth
- Consider: How far back do users typically scroll?

### 2. Background Task Management (2-3 hours)

- Implement low-priority background LLM queue
- Respect system resource constraints (low battery, thermal pressure)
- Pause during active calls, media playback
- Cancel if app terminated

### 3. Smart Prioritization (1 hour)

- Prioritize recent entries over old ones
- Skip entries already summarized
- Deprioritize if user never scrolls back

### 4. Logging & Observability (30 min)

- Update confusing log message to explain policy clearly
- Log when background processing starts/stops
- Track: summaries generated while backgrounded, battery impact

## Files

- `Contextify/Contextify/ConversationMonitor.swift` - `handleAppResignActive()` function (line numbers drift; search for function name)
- LLM queue management code
- Timeline cache/priority logic

## Acceptance Criteria

- Background summarization generates summaries for would-be-visible entries
- Respects system resource constraints (battery, thermal)
- Logs clearly explain background processing status
- No performance degradation when app returns to foreground
- User doesn't notice lag when scrolling to pre-summarized content

## Related

- Confusing log message: "App resigned active - background processing DISABLED"
- Should clarify: This is intentional policy, not a bug
