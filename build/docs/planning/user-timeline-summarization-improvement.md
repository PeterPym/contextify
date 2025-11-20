# User Timeline Summarization Improvement (P1)

**Status:** Planning - Implementation Ready
**Priority:** P1 (High - Post-Release)
**Related:** Assistant-side fix completed (feature/timeline-summarization-disposition-fix)
**Effort:** Medium (2-4 hours implementation + 1-2 hours validation)

---

## Executive Summary

Improve user message timeline summarization to match the quality and disposition accuracy of the assistant-side fix. The assistant prompt was significantly improved with explicit disposition guidance and verb-tense rules; the user side deserves similar treatment.

**Current State:** User prompt is basic, lacks explicit disposition definitions, and relies heavily on post-validation rather than upfront LLM guidance.

**Goal:** Mirror the assistant-side improvements:
- Explicit disposition taxonomy with examples
- Clear summary phrasing guidance tied to disposition
- Lightweight postProcess seatbelt using existing `classifyUserIntent`
- Maintain simplicity (no complex rule engine)

**Success Criteria:**
- User summaries consistently use appropriate verbs for disposition
- Fewer prefix validation mismatches (currently causing retry failures)
- Improved alignment between `classifyUserIntent` and LLM disposition

---

## Problem Statement

### Current User Prompt (Simplified)

The existing `.user` case in `instructionsForTimeline()` provides basic guidance but lacks:
1. Explicit disposition definitions with examples
2. Clear verb-tense guidance for each disposition type
3. Parity with the rich assistant-side prompt

**Example Issues:**

**Issue 1: Directive vs Question Confusion**
```
Message: "Can you refactor this into two files?"
Current: Might classify as "question" (has "?")
Desired: Should be "directive" (requesting work, not asking for info)
```

**Issue 2: Inconsistent Verb Choice**
```
Message: "/review-prep" (slash command)
Current: "You performed the following command: /review-prep"
Desired: "You requested Claude Code to execute the /review-prep command"
Note: Recent fix accepts "performed" but prompt should guide to preferred form
```

**Issue 3: Report vs Directive**
```
Message: "The app crashes when I click the timeline"
Current: Could be classified as directive
Desired: Should be "report" (informing, not requesting specific action)
```

### Impact

**Low-Medium Severity:**
- User summaries less polished than assistant summaries (inconsistency)
- Occasional validation mismatches (now gracefully handled post-fix)
- Timeline clarity could be better for project retrospectives

**Not Urgent Because:**
- Recent validation fix prevents user-visible errors
- `classifyUserIntent` provides reasonable fallback
- User messages less frequent than assistant in typical sessions

---

## Proposed Solution

### Three-Layer Approach (Simple, Effective)

**Layer 1: Strengthen Prompt** (Primary improvement)
- Add explicit disposition taxonomy with examples
- Provide summary phrasing templates for each disposition
- Make verb choice predictable and consistent

**Layer 2: Trust `classifyUserIntent`** (Leverage existing code)
- If `classifyUserIntent` disagrees with LLM, prefer classifier
- Log disagreements for monitoring
- No complex lexical rules (keep it simple)

**Layer 3: Minimal Lexical Seatbelts** (Optional, P2)
- Only 1-2 simple rules to catch obvious errors
- Example: "Can you..." with "?" → directive, not question
- Don't build a full rule engine

---

## User Disposition Taxonomy

Based on existing `UserIntent` enum and schema:

### Primary Dispositions (5 types)

**directive** - User is telling or asking assistant to DO something
- Linguistic cues: "Can you", "Please", "Would you", imperatives, slash commands
- Examples:
  - "Add logging around the retry loop."
  - "Can you refactor this into two files?"
  - "/review-prep" (slash command)
- Summary template: "You requested Claude Code to [action]"

**question** - User asking for information/clarification, NOT requesting work
- Linguistic cues: Why/What/How questions, explanatory requests
- Examples:
  - "Why is this query so slow?"
  - "What does this error mean?"
  - "How does WAL mode work?"
- Summary template: "You asked why/what/how [subject]"

**report** - User reporting observation, bug, or status
- Linguistic cues: Declarative statements about problems/state
- Examples:
  - "The app crashes when I open the timeline."
  - "I merged the branch but CI is red."
  - "The logs are full of SQLITE_BUSY errors."
- Summary template: "You reported [observation]" or "You noted [status]"

**affirmative** - User confirming or agreeing
- Linguistic cues: "Yes", "Exactly", "That works", confirmations
- Examples:
  - "Yes, that works."
  - "Exactly."
  - "That's what I wanted."
- Summary template: "You confirmed [what]" or "You agreed [with what]"

**negative** - User rejecting or correcting
- Linguistic cues: "No", "That's not right", corrections
- Examples:
  - "No, that's not right."
  - "That's not what I meant."
  - "I don't want to change the schema."
- Summary template: "You disagreed [with what]" or "You rejected [what]"

---

## Implementation Approach

### Change 1: Rewrite User Prompt

**File:** `Contextify/Contextify/FoundationLLM.swift`
**Function:** `instructionsForTimeline(kind:provider:)`
**Location:** `case .user:` branch (around line 1520+)

**New Structure:**
```swift
case .user:
    return """
    You are classifying a SINGLE user message for a developer timeline.

    Your job:
    1. Decide the **disposition** of this user message
    2. Write a short summary suitable for a project activity timeline

    ### Dispositions

    Choose ONE primary disposition:

    **"directive"** - User is telling or asking the assistant to DO something.
    Examples:
    - "Add logging around the retry loop."
    - "Can you refactor this into two files?"
    - "Please write a unit test for this."

    **"question"** - User is asking for information or clarification, not requesting work.
    Examples:
    - "Why is this query so slow?"
    - "What does this error mean?"
    - "How does WAL mode work?"

    **"report"** - User is reporting an observation, bug, or status.
    Examples:
    - "The app crashes when I open the timeline."
    - "I merged the branch but CI is red."
    - "The logs are full of SQLITE_BUSY errors."

    **"affirmative"** - User confirming or agreeing.
    Examples:
    - "Yes, that works."
    - "Exactly."
    - "That's what I wanted."

    **"negative"** - User rejecting or correcting.
    Examples:
    - "No, that's not right."
    - "That's not what I meant."
    - "I don't want to change the schema."

    ### Summary Phrasing (CRITICAL)

    Match your wording to the disposition. Always start with "You":

    **For DIRECTIVE:**
    - Use: "You requested Claude Code to [action]"
    - Use: "You asked Claude Code to [action]"
    - Example: "You requested Claude Code to refactor the retry logic."

    **For QUESTION:**
    - Use: "You asked why/what/how [subject]"
    - Example: "You asked why the query is slow."

    **For REPORT:**
    - Use: "You reported [observation]"
    - Use: "You noted [status]"
    - Example: "You reported crashes when opening the timeline."

    **For AFFIRMATIVE:**
    - Use: "You confirmed [what]"
    - Use: "You agreed [with what]"
    - Example: "You confirmed the approach was correct."

    **For NEGATIVE:**
    - Use: "You disagreed [with what]"
    - Use: "You rejected [proposal]"
    - Example: "You rejected the schema change proposal."

    ### Special Cases

    **Slash commands (e.g., "/review-prep"):**
    - Disposition: "directive"
    - Template: "You requested Claude Code to execute the /[command-name] command"
    - Example: "You requested Claude Code to execute the /review-prep command."

    **Mixed messages (e.g., "Can you explain why X is broken?"):**
    - If requesting action: "directive"
    - If only seeking explanation: "question"
    - Prefer "directive" when in doubt

    ### Output Format

    Return a JSON object with these exact keys:

    {
      "summary": "One sentence (≤140 chars) starting with 'You'",
      "isCompletion": false,
      "disposition": "directive",
      "grounding": "grounded",
      "confidence": 0.95
    }

    Note: User messages never complete work themselves, so isCompletion is always false.

    Input format:
    MESSAGE:
    <<<user text>>>
    """
```

**Key Improvements:**
1. ✅ Explicit disposition definitions with real examples
2. ✅ Summary phrasing guidance (CRITICAL section) - mirrors assistant
3. ✅ Special case handling (slash commands, mixed messages)
4. ✅ Hardcodes isCompletion: false (users don't complete work)
5. ✅ Clear precedence rules for ambiguous cases

---

### Change 2: Trust `classifyUserIntent` in postProcess

**File:** `Contextify/Contextify/FoundationLLM.swift`
**Function:** `postProcess(kind:payload:message:provider:)`
**Location:** Inside `else if kind == .user { ... }` block (around line 1880+)

**Current Logic:**
- Validates prefix matches intent
- Throws error on mismatch (recently fixed to accept alternatives)

**New Logic:**
- Trust `classifyUserIntent` when it disagrees with LLM
- Log disagreements for monitoring
- Accept LLM disposition if classifier is `.unknown`

**Implementation:**
```swift
else if kind == .user {
    let autoIntent = classifyUserIntent(message)
    let s = summary.lowercased()

    // CHANGE: Trust classifyUserIntent as source of truth
    var finalDisposition = payload.disposition

    // Map UserIntent to timeline disposition string
    let intentDisposition: String? = {
        switch autoIntent {
        case .directive: return "directive"
        case .question: return "question"
        case .report: return "report"
        case .affirmative: return "affirmative"
        case .negative: return "negative"
        case .unknown: return nil  // Let LLM decide
        }
    }()

    // Override if classifier has strong opinion
    if let intentDisp = intentDisposition, intentDisp != payload.disposition {
        log.info("User disposition override: LLM said '\(payload.disposition)', classifyUserIntent said '\(intentDisp)' - using classifier")
        finalDisposition = intentDisp
    }

    // Existing validation code continues...
    // (Prefix validation, length check, leakage check)

    // Return with final disposition
    let directiveFlag = (finalDisposition == "directive" ||
                        finalDisposition == "affirmative" ||
                        finalDisposition == "negative")

    return TimelineSummaryResult(
        summary: summary,
        isCompletion: false,  // Users never complete work
        isDirective: directiveFlag,
        disposition: finalDisposition
    )
}
```

**Why This Works:**
- `classifyUserIntent` uses deterministic lexical rules
- Already battle-tested in prefix validation
- No need to build parallel rule system
- Simple, maintainable, leverages existing code

---

### Change 3: Optional Lexical Seatbelts (P2, Can Defer)

**Only if needed after monitoring:**

Two simple rules to catch obvious misclassifications:

```swift
// Optional: Catch obvious directive patterns misclassified as questions
let msgLower = message.lowercased()
let hasDirectiveCue = msgLower.hasPrefix("can you ") ||
                      msgLower.hasPrefix("could you ") ||
                      msgLower.hasPrefix("please ") ||
                      msgLower.hasPrefix("would you ")

if finalDisposition == "question" && hasDirectiveCue {
    log.info("User disposition correction: question → directive (has directive cue)")
    finalDisposition = "directive"
}

// Catch pure questions misclassified as directives
let isPureQuestion = message.contains("?") &&
                    !hasDirectiveCue &&
                    (msgLower.hasPrefix("why ") || msgLower.hasPrefix("what ") || msgLower.hasPrefix("how "))

if finalDisposition == "directive" && isPureQuestion {
    log.info("User disposition correction: directive → question (pure question pattern)")
    finalDisposition = "question"
}
```

**Note:** Defer this to P2. The prompt + `classifyUserIntent` should be sufficient.

---

## Expected Outcomes

### Quantitative Improvements

**Before (Current State):**
- User summaries: Inconsistent verb choice
- Prefix mismatches: ~5-10% (estimated, now gracefully handled)
- Disposition accuracy: ~80% (estimated, no baseline data)

**After (Target):**
- User summaries: Consistent verb choice matching disposition
- Prefix mismatches: <2% (improved prompt guidance)
- Disposition accuracy: ≥90% (parity with assistant side)

### Qualitative Improvements

**User Experience:**
- Timeline entries more readable and consistent
- Clear distinction between requests, questions, and reports
- Better project retrospectives (know what you asked vs what assistant did)

**Developer Experience:**
- Less cognitive load interpreting timeline
- Symmetry between user and assistant summarization quality
- Fewer validation edge cases to debug

---

## Validation Plan

### Manual Test Cases (5-10 Examples)

**Directives:**
1. "Add logging around the retry loop." → "You requested Claude Code to add logging..."
2. "Can you refactor this into two files?" → "You requested Claude Code to refactor..."
3. "/review-prep" → "You requested Claude Code to execute the /review-prep command."

**Questions:**
1. "Why is this query so slow?" → "You asked why the query is slow."
2. "What does this error mean?" → "You asked what the error means."

**Reports:**
1. "The app crashes when I click timeline." → "You reported crashes when clicking timeline."
2. "CI is failing on the main branch." → "You reported CI failures on main branch."

**Affirmative/Negative:**
1. "Yes, that works." → "You confirmed the approach works."
2. "No, that's not right." → "You rejected the proposed solution."

### Success Criteria

- ≥9/10 test cases produce expected disposition
- ≥9/10 test cases use expected verb pattern
- Zero validation rejections (all accepted gracefully)
- classifyUserIntent and LLM agree ≥85% of time

---

## Risks & Mitigation

### Risk 1: Breaking Existing Behavior

**Likelihood:** Low-Medium
**Impact:** Medium (could change existing timeline entries)
**Mitigation:**
- Test on recent session transcripts before deployment
- Monitor logs for disposition changes in first week
- Rollback plan: revert to previous prompt if accuracy drops

### Risk 2: classifyUserIntent Disagrees with LLM

**Likelihood:** Medium (expected in 10-15% of cases)
**Impact:** Low (we choose classifier, log disagreement)
**Mitigation:**
- Log all disagreements for monitoring
- If pattern emerges, refine prompt or classifier
- Accept that some disagreement is normal

### Risk 3: Prompt Gets Too Long

**Likelihood:** Low
**Impact:** Low (slight latency increase)
**Mitigation:**
- Keep examples concise
- Total prompt should be <50% of assistant prompt length
- Monitor token usage, compress if needed

---

## Implementation Checklist

### Pre-Implementation
- [ ] Review current user prompt (case .user in instructionsForTimeline)
- [ ] Review classifyUserIntent implementation and enum values
- [ ] Collect 10-15 real user messages for testing
- [ ] Verify GuidedTimelineSummary schema (already correct)

### Phase 1: Prompt Rewrite
- [ ] Replace user prompt with new structure
- [ ] Add disposition definitions with examples
- [ ] Add summary phrasing guidance (CRITICAL section)
- [ ] Add special case handling (slash commands)
- [ ] Verify Swift multiline string syntax

### Phase 2: postProcess Integration
- [ ] Add classifyUserIntent override logic
- [ ] Log disagreements between LLM and classifier
- [ ] Ensure isCompletion always false for users
- [ ] Update isDirective calculation
- [ ] Keep existing validation (prefix, length, leakage)

### Phase 3: Validation
- [ ] Run 10 manual test cases through code
- [ ] Verify disposition accuracy ≥90%
- [ ] Verify verb pattern consistency
- [ ] Check logs for LLM vs classifier disagreements
- [ ] No validation rejections

### Phase 4: Deployment
- [ ] Build with zero warnings
- [ ] Commit changes with detailed message
- [ ] Monitor first 100 user messages in production
- [ ] Document any unexpected patterns
- [ ] Adjust if needed

---

## Effort Estimate

**Total: 3-6 hours**

- Prompt rewriting: 1-2 hours
- postProcess integration: 1 hour
- Manual validation: 1-2 hours
- Documentation and commit: 30 min
- Monitoring and adjustment (post-deploy): 30-60 min

**Priority:** P1 (do after release, before next major feature)

---

## References

**Related Documents:**
- Assistant-side fix analysis: `/tmp/timeline-summarization-fix-final.md`
- Assistant-side implementation guide: `/tmp/timeline-fix-implementation-guide.md`
- Colleague feedback: `/private/tmp/yes-i-ve-got-colleague-c-user-facing-prompt-rework.md`

**Related Code:**
- `FoundationLLM.swift` lines 1520+ (user prompt)
- `FoundationLLM.swift` lines 1880+ (user postProcess)
- `classifyUserIntent()` function (existing implementation)

**Related Commits:**
- Assistant fix: b88794e, 8007f04, 0d68c05
- User validation fix: 29dcac4

---

## Notes for Implementation

1. **Keep it simple** - Don't over-engineer. Prompt + classifyUserIntent should handle 90%+ of cases.

2. **Defer lexical seatbelts** - Only add if monitoring shows specific problematic patterns.

3. **Trust existing code** - classifyUserIntent is battle-tested, use it.

4. **Monitor disagreements** - Log LLM vs classifier mismatches to identify prompt refinement needs.

5. **Maintain symmetry** - User and assistant prompts should feel similar in structure and quality.

6. **Test with real data** - Use actual user messages from recent sessions, not synthetic examples.
