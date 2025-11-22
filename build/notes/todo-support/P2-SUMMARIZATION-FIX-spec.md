# LLM Summarization Attribution Analysis

**Date:** 2025-11-21
**Issue:** Timeline summaries misrepresenting user requests as assistant explanations
**Priority:** P2 (Quality improvement)
**Related TODO:** #P2-SUMMARIZATION-FIX

## Problem Statement

LLM-generated summaries sometimes misrepresent the nature of user messages, particularly confusing action requests with explanatory responses. This creates misleading timeline entries where it appears the assistant explained something when the user actually requested the assistant to perform an action.

## Concrete Example

### Original Message
```json
{
  "entry_id": "f268414b-31ca-431a-b4e6-383898844de0",
  "timestamp": "2025-11-21T22:17:59Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/9479247c-e978-45ce-badd-d085f4428ae6.jsonl",
  "detail": "use an agent to add a p1 todo that checks on the setting and clearing of the unread count in project tabs. currently it seems not obvious how those numbers are calcluated nor that the clearing of them follows common ux behaviors"
}
```

### Incorrect Summary Generated
```
"You explained how to add a todo to check unread counts in project tabs."
```

### What's Wrong
1. **Attribution reversed**: User **requested** action → Summary says assistant **explained**
2. **Action changed to explanation**: "do X" became "explained how to do X"
3. **Outcome ignored**: Agent successfully completed the task (added #P1-UNREAD-COUNT), but summary implies only an explanation was given
4. **Who did what reversed**: User initiated, assistant executed → Summary implies assistant was teaching user

## Root Cause Analysis (Transcript Inspection)

### Timeline of Events

Analyzed transcript: `9479247c-e978-45ce-badd-d085f4428ae6.jsonl`

1. **Line 517** (22:17:59): User request
   - Type: `user`
   - UUID: `f268414b-31ca-431a-b4e6-383898844de0`
   - Content: "use an agent to add a p1 todo that checks on the setting and clearing of the unread count..."

2. **Line 518** (22:18:04): Assistant thinking
   - Type: `assistant`
   - UUID: `e2b60cae-4c12-4aa1-a4b7-58f272b3a2c1`
   - Content: Thinking block only, no text response

3. **Line 519** (22:18:10): Assistant spawns Task agent
   - Type: `assistant`
   - UUID: `67a79770-b31a-4abd-9a19-dc15f22e2a31`
   - Tool: `Task` with `subagent_type: "general-purpose"`
   - Prompt: "Add a new P1 todo to build/notes/TODOS.md about investigating unread count behavior..."

4. **Lines 520-521** (22:18:55 - 22:19:21): User queues new message
   - Type: `queue-operation`
   - Content: "i think the bee may bee too distracting..." (about emoji indicators)
   - Operation: `enqueue` then `remove`

5. **Line 522** (22:19:21): Agent completion (tool_result)
   - Type: `user` (tool_result from agent)
   - UUID: `70bbcb29-cbc1-4ea5-b8e7-db4dbe9f4187`
   - Content: Detailed summary of successful completion
   - **Key finding**: Agent successfully added #P1-UNREAD-COUNT with full specification

6. **Lines 523-526**: Assistant responses about emoji indicator
   - **Critical observation**: Assistant NEVER acknowledged the todo completion
   - Immediately pivoted to answering queued emoji question
   - No text response saying "I've added the todo" or similar

### Why the Summarizer Failed

The LLM summarizer likely:
1. Saw the user's request: "use an agent to add a p1 todo..."
2. Saw the assistant spawn a Task tool (but didn't process the tool_result)
3. Inferred that since the user asked about "adding a todo", the assistant must have "explained how to add a todo"
4. Never saw/processed the actual completion because the main assistant never relayed it in text

**Key insight**: The assistant's failure to acknowledge the agent's completion in conversational text meant the summarizer had no signal that the action was actually completed.

## Additional Reference Examples

These UUIDs from the same transcript show similar patterns and can be analyzed during implementation:

### Example 2: Adding a comment
- **UUID**: `a812952e-7a52-431a-8ef5-08b10e9faa23`
- **Timestamp**: 2025-11-21 21:57:58
- **Content**: "can you add a comment above that line explaining the resulting window dimension math?"
- **Pattern**: Direct action request ("add a comment")

### Example 3: Adding to task list
- **UUID**: `6abfcbdc-dbf2-40da-b33d-9dfc4ae46749`
- **Timestamp**: 2025-11-21 22:09:34
- **Content**: "add to our tasks so we can come back to it at end of our other work: it looks like the conversation log summarization only catches the viewport if the window is currently under focus"
- **Pattern**: Action request with context ("add to our tasks")

## Impact Assessment

### User Experience Impact
- **Timeline misleading**: Users scanning timeline can't understand what actions were actually taken
- **Attribution confusion**: Can't quickly determine who did what (user vs assistant)
- **Action tracking broken**: Summaries don't reflect completed tasks, making it hard to find when specific work was done
- **Trust erosion**: Inaccurate summaries reduce confidence in timeline as source of truth

### Data Quality Impact
- Summaries are primary navigation mechanism for timeline
- Bad summaries make search/filter features less useful
- Historical conversation review becomes unreliable
- Metadata extracted for future features (git activity, work stories) may inherit same attribution issues

## Proposed Solution

### 1. Prompt Engineering Improvements

**Current prompts** (location TBD - likely in `TimelineCacheMissGenerator.swift`):
- Need to be analyzed and documented

**Proposed additions**:
```
When summarizing user messages, clearly identify the nature of the interaction:

ACTION REQUESTS (user wants assistant to DO something):
- "User asked to [action]" or "User requested [action]"
- Examples: "User asked to add a comment", "User requested creating a P1 todo"

INFORMATION REQUESTS (user wants to LEARN something):
- "User asked about [topic]" or "User asked how to [action]"
- Examples: "User asked about unread count behavior", "User asked how to add comments"

ASSISTANT ACTIONS (what assistant DID):
- "Assistant [action]" or "Claude [action]"
- Examples: "Assistant added a comment", "Claude created P1 todo"

EXPLANATIONS (what assistant EXPLAINED):
- "Assistant explained [topic]"
- Examples: "Assistant explained unread count calculation"

CRITICAL RULES:
1. Never reverse attribution (if user requested action, don't say "assistant explained how to do it")
2. If user says "do X", summary should reflect "User asked to do X" or "User requested X"
3. If assistant completes a task, summary should say "Assistant did X", not "explained X"
4. Distinguish between requests and questions clearly
```

### 2. Tool Result Processing

**Issue**: When agents complete tasks via tool_result, the main assistant may not relay this in conversational text.

**Potential solutions**:
- Extract tool_result summaries and include in context for timeline summarization
- Add structured metadata field for "task_completed: true/false"
- Parse tool_use + tool_result pairs to detect completed actions

### 3. Testing Approach

**Validation dataset**:
1. Re-generate summary for entry `f268414b-31ca-431a-b4e6-383898844de0`
2. Test with UUIDs: `a812952e`, `6abfcbdc`
3. Batch test with 10-20 existing entries showing similar patterns
4. A/B comparison: old summaries vs. new summaries

**Success criteria**:
- Action requests correctly identified as "User asked to..." or "User requested..."
- No reversed attribution (user actions attributed to assistant or vice versa)
- Completed tasks reflected in summaries (not just requests)
- Information requests distinguished from action requests

### 4. Structured Output Consideration

Consider adding a `message_type` field to timeline entries:
```json
{
  "message_type": "action_request" | "info_request" | "assistant_action" | "explanation",
  "summary": "...",
  "detail": "..."
}
```

This would enable:
- Better filtering/search ("show me all my action requests")
- UI affordances (icon, color coding by message type)
- Validation (detect attribution mismatches automatically)

## Implementation Tasks

1. **Locate and document current prompts** (1-2 hours)
   - Find prompt templates in codebase
   - Document current instructions given to summarization LLM
   - Identify gaps in guidance about attribution

2. **Update prompts** (2-3 hours)
   - Add explicit attribution rules
   - Add examples of correct vs. incorrect summaries
   - Test with problematic examples

3. **Tool result processing** (1-2 hours)
   - Determine if tool_result content is available to summarizer
   - If not, add extraction logic
   - Test with agent-completed tasks

4. **Validation** (1 hour)
   - Re-generate summaries for test cases
   - Compare old vs. new
   - Document improvement metrics

**Total effort**: 4-6 hours

## Files to Review

Based on architecture knowledge:
- `Contextify/Contextify/TimelineCacheMissGenerator.swift` - Likely location of LLM prompts
- `Contextify/Contextify/LLMHealthCheck.swift` - If prompt templates stored here
- `app/Sources/ContextifyCore/Database/Models.swift` - TimelineEntry structure
- `build/docs/architecture/llm-processing.md` - LLM processing pipeline documentation

## Future Considerations

### Related Quality Issues
This investigation may inform solutions for:
- Git activity extraction (#79-83) - Similar attribution challenges
- Work story generation - Needs accurate action tracking
- Search/filter features - Relies on accurate summaries

### Broader Implications
- Should assistant be required to acknowledge tool completions in text?
- Should tool_result content be parsed separately from conversation flow?
- Could structured metadata reduce reliance on LLM summarization accuracy?

## References

- **Primary example transcript**: `9479247c-e978-45ce-badd-d085f4428ae6.jsonl`
- **Lines analyzed**: 517-526
- **Related TODO**: #P2-SUMMARIZATION-FIX in `build/notes/TODOS.md`
- **Investigation date**: 2025-11-21
- **Investigator**: Claude Code (ironic, given the subject matter)
