# Technical Brief: Fix User Message Summarization Quality

**Date:** 2025-10-09
**Status:** Problem Identified, Solution Designed
**Priority:** High - Affects user experience quality
**Branch:** `feature/transcript-inventory` (or new branch)

---

## Problem Statement

User message summarization in the timeline is significantly less robust than assistant message summarization, resulting in incorrect classifications and misleading log entries.

### Examples of Incorrect Summaries

**Example 1: Imperative Command Misclassified**
- **User Input:** "Commit your changes with a note in the commit message that they are not related to the current branch work"
- **Current Output:** "You made your changes and noted they are not related to the current branch work."
- **Expected Output:** "You requested Claude to commit changes with a note that they are not related to the current branch work"
- **Issue:** Imperative verb "Commit" at start = directive, but LLM chose past action prefix ("You made") instead of request prefix

**Example 2: Nested Quote Content Extraction**
- **User Input:** Long message containing: "See if you can find discussion of this in /Users/rob/.claude/projects/-Users-rob-code-projects-contextify to get context..."
- **Current Output:** "You made a detailed implementation plan for converting existing files to /build/notes/current.md, replacing prior contents, and appending..."
- **Expected Output:** "You asked Claude to find discussion of the truncation issue in the project context"
- **Issue:** LLM extracted content from nested quoted text instead of the actual request. Contains directive pattern "see if you can"

### Root Causes

1. **Inadequate Prompt Guidance** - User message prompt doesn't explain HOW to detect directives, just lists the allowed prefixes
2. **No Directive Preprocessing** - Existing `directiveLexicon` (includes "commit", "can you", "please", etc.) exists but isn't passed to LLM as a hint
3. **Nested Quote Confusion** - No warning about ignoring quoted/nested content when summarizing
4. **Past Tense Bias** - "past tense" instruction biases toward "You made" even for requests
5. **Zero Validation** - Bad summaries pass through unchecked (postProcess only validates assistant messages)
6. **No Fast Paths** - Assistant messages have `isAck()` fast path; user messages have nothing

---

## Current Implementation Analysis

### User Message Processing Flow

**File:** `Contextify/Contextify/ConversationMonitor.swift:421-528`

1. Extract text from JSON message
2. Skip meta/command messages
3. Check if should use action hint (for "yes"/"no" responses)
4. Call `FoundationLLM.shared.summarizeTimeline(kind: .user, text: text, actionHint: actionHint)`
5. Create TimelineEntry with summary
6. **No validation of summary quality**

### Assistant Message Processing Flow

**File:** `Contextify/Contextify/ConversationMonitor.swift:530-593`

1. Extract text from JSON message
2. Call `FoundationLLM.shared.summarizeTimeline(kind: .assistant, text: text)`
3. Create TimelineEntry with summary
4. Summary goes through `postProcess()` validation (grounding, leakage checks)

### Key Differences: User vs Assistant

| Aspect | User Messages | Assistant Messages | Gap |
|--------|--------------|-------------------|-----|
| **Fast Paths** | None | `isAck()` detects acknowledgments | User gets no shortcuts |
| **Preprocessing** | Action hint for yes/no only | None needed | No directive detection |
| **LLM Prompt Quality** | Weak: lists prefixes, no detection guidance | Strong: explicit rules, tense guidance | User prompt needs work |
| **Validation** | None (`postProcess()` skips user messages) | Full grounding + leakage checks | User summaries unchecked |
| **Directive Detection** | `isDirective()` exists but only used for icons | N/A | Unused capability |
| **Error Handling** | Try/catch but no retry or fallback logic | Robust retry with backoff | User gives up faster |

---

## Detailed Code Comparison

### User Message Prompt (Current)

**File:** `Contextify/Contextify/FoundationLLM.swift:336-361`

```swift
case .user:
    return """
    You fill a TimelineSummary for a developer's message.

    summary rules:
    - ONE sentence, ≤140 chars, past tense.
    - Allowed prefixes:
      • "You made …" — user reports a completed action (e.g., "I updated the file").
      • "You asked …" — user asks a question (e.g., "Can you explain?").
      • "You requested Claude …" — user asks Claude to act (e.g., "Fix this", "Run tests").
    - Special cases:
      • Bare affirmative (yes/ok/sure/y/👍/go ahead/proceed/do it/please do/sgtm/roger):
        → "You requested Claude to proceed as proposed."
      • Bare negative (no/not now/hold off/stop/don't):
        → "You requested Claude not to proceed."
    - If ACTION_HINT is present, treat it as the action being approved or rejected.

    Fields:
    - summary: one sentence following the rules.
    - isCompletion: false.

    Input format:
    MESSAGE:
    <<<user text>>>
    Optional ACTION_HINT:
    <<<assistant proposal>>>
    """
```

**Issues:**
- ❌ No guidance on detecting directives (imperative verbs, request patterns)
- ❌ No warning about nested quotes/code blocks
- ❌ "past tense" is ambiguous (applies to summary verb, not intent classification)
- ❌ Examples are too simple (don't cover complex cases)

### Assistant Message Prompt (Current)

**File:** `Contextify/Contextify/FoundationLLM.swift:311-334`

```swift
case .assistant:
    return """
    You fill a TimelineSummary for an AI assistant response.

    Rules:
    - Output ONE sentence starting with "Claude", ≤140 chars.
    - Use only MESSAGE content; do not introduce topics absent from MESSAGE.
    - Tense:
      * Past when completion is explicitly reported (done/✅/completed/fixed/resolved/merged/wrote/saved).
      * Present continuous ONLY for clear in-progress execution (e.g., "is running the test suite").
      * Otherwise simple present ("explains/clarifies/confirms/proposes/asks/acknowledges").
    - Mention tools (Write/Edit/Read/Bash/etc.) ONLY if MESSAGE explicitly says they were executed.

    Fields:
    - summary: one sentence following the rules.
    - isCompletion: true only if MESSAGE explicitly indicates completion.
    - disposition: one of ack, completion, wip, analysis, proposal, question, refusal.
    - grounding: grounded | ungrounded | insufficient.
    - confidence: 0.0–1.0 (lower for short or ungrounded inputs).

    Input format:
    MESSAGE:
    <<<assistant text>>>
    """
```

**Strengths:**
- ✅ Explicit tense guidance
- ✅ Clear warning about not introducing topics
- ✅ Multiple validation fields (grounding, confidence)
- ✅ Disposition categorization

### Validation Comparison

**Assistant Validation (postProcess):**

**File:** `Contextify/Contextify/FoundationLLM.swift:168-217`

```swift
if kind == .assistant {
    let leaked = introducedTopics(message: message, summary: summary)
    let grounding = payload.grounding.lowercased()
    let isGrounded = grounding == "grounded"

    // Multi-factor acceptance decision with thresholds
    let goodConfidence = payload.confidence >= 0.6
    let okConfidence = payload.confidence >= 0.5
    let minimalConfidence = payload.confidence >= 0.4
    let excessiveLeakage = leaked.count >= 8

    let shouldAccept = goodConfidence ||
                       (okConfidence && !excessiveLeakage) ||
                       (isGrounded && minimalConfidence)

    if !shouldAccept {
        log.warning("timeline summary REJECTED...")
        throw Error.retryExhausted
    }
}
```

**User Validation:**

```swift
// NONE - postProcess skips user messages entirely
```

---

## Related Files

### Core Implementation Files

1. **`/Users/rob/code/projects/contextify/Contextify/Contextify/FoundationLLM.swift`**
   - Lines 31-197: `summarizeTimeline()` main function
   - Lines 59-63: Assistant ack fast path (user has none)
   - Lines 136-140: `isDirective()` function (unused for preprocessing)
   - Lines 146-155: `directiveLexicon` (unused for preprocessing)
   - Lines 168-217: `postProcess()` validation (skips user messages)
   - Lines 309-361: Prompt templates for user vs assistant
   - Lines 242-254: `sanitize()` applies to both user and assistant

2. **`/Users/rob/code/projects/contextify/Contextify/Contextify/ConversationMonitor.swift`**
   - Lines 421-528: `processUserMessage()` - user message handling
   - Lines 530-593: `processAssistantMessage()` and `addAssistantTextEntry()` - assistant handling
   - Lines 498-501: User message calls `summarizeTimeline()` with action hint
   - Lines 595-633: Action hint extraction logic (only for yes/no)

3. **`/Users/rob/code/projects/contextify/Contextify/ContextifyTests/FoundationLLMTests.swift`**
   - Lines 4-43: `FormattingTests` - basic sanitization tests
   - Lines 45-150: `GroundingTests` - assistant validation tests (no user tests)
   - Lines 152-166: `ActionHintTests` - tests for yes/no handling
   - **Missing:** Tests for user directive detection, nested quote handling

4. **`/Users/rob/code/projects/contextify/Contextify/Contextify/TimelineModels.swift`**
   - Defines `TimelineEntry` and `TimelineEntryKind`
   - Used by both user and assistant message processing

---

## Proposed Solution

### Phase 1: Improve User Message Prompt (HIGH IMPACT)

**File:** `Contextify/Contextify/FoundationLLM.swift:336-361`

**Changes:**

```swift
case .user:
    return """
    You fill a TimelineSummary for a developer's message.

    INTENT DETECTION (Critical):
    First determine the user's intent by checking for these patterns IN ORDER:

    1. DIRECTIVE (user asking Claude to act):
       - Imperative verbs at start: "Commit", "Fix", "Run", "Update", "Add", "Create", "Deploy", "Test"
       - Request patterns: "can you", "could you", "would you", "please", "see if you can"
       - Command phrases: "go ahead", "let's", "we should", "help me", "i want", "i need"
       → Use prefix: "You requested Claude to [action]"

    2. QUESTION (user asking for information):
       - Question words: "what", "why", "how", "when", "where", "which"
       - Question patterns: "can you explain", "tell me about", "what does"
       → Use prefix: "You asked [question]"

    3. REPORT (user stating completed action):
       - Past tense self-reports: "I updated", "I fixed", "I created", "I modified"
       → Use prefix: "You made [description of action]"

    CONTENT EXTRACTION:
    - Summarize ONLY the top-level user message, NOT quoted/nested content
    - Ignore triple-quoted code blocks (```) and triple-quoted text (\"\"\"...\"\"\"")
    - If message contains nested quotes, extract the user's direct statement

    SPECIAL CASES:
    - Bare affirmative (yes/ok/sure/👍/go ahead/proceed/do it/sgtm/roger):
      → "You requested Claude to proceed as proposed."
    - Bare negative (no/not now/hold off/stop/don't):
      → "You requested Claude not to proceed."
    - If ACTION_HINT is present, treat it as the action being approved/rejected

    OUTPUT FORMAT:
    - ONE sentence, ≤140 chars
    - Tense: Past tense for the summary verb ("You requested", "You asked", "You made")
    - Focus on user's INTENT, not implementation details

    Fields:
    - summary: one sentence following the rules above
    - isCompletion: false (users don't complete tasks, Claude does)
    - disposition: one of: directive, question, report, affirmative, negative
    - grounding: grounded | ungrounded | insufficient
    - confidence: 0.0–1.0 (higher when intent is clear)

    Input format:
    MESSAGE:
    <<<user text>>>
    Optional ACTION_HINT:
    <<<assistant proposal>>>
    """
```

**Key Improvements:**
- ✅ Explicit intent detection flowchart (DIRECTIVE → QUESTION → REPORT)
- ✅ Lists imperative verbs and request patterns
- ✅ Warning about nested quotes/code blocks
- ✅ Clarifies "past tense" applies to summary verb, not classification
- ✅ Adds validation fields (disposition, grounding, confidence)

### Phase 2: Add Directive Preprocessing (MEDIUM IMPACT)

**File:** `Contextify/Contextify/FoundationLLM.swift:93-102`

**Changes:**

```swift
let clamped = String(message.prefix(1200))
let payloadInput: String
if kind == .user {
    // Check if this is likely a directive
    let isLikelyDirective = isDirective(clamped)

    if let hint = actionHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
        let safeHint = String(hint.prefix(300))
        payloadInput = "MESSAGE:\n<<<\(clamped)>>>\nACTION_HINT:\n<<<\(safeHint)>>>\(isLikelyDirective ? "\nLIKELY_DIRECTIVE: true" : "")"
    } else {
        payloadInput = "MESSAGE:\n<<<\(clamped)>>>\(isLikelyDirective ? "\nLIKELY_DIRECTIVE: true" : "")"
    }
} else {
    payloadInput = "MESSAGE:\n<<<\(clamped)>>>"
}
```

**Rationale:** Gives LLM a strong hint about message intent using existing `isDirective()` function.

### Phase 3: Add User Message Validation (MEDIUM IMPACT)

**File:** `Contextify/Contextify/FoundationLLM.swift:168-217` (postProcess)

**Changes:**

```swift
func postProcess(
    kind: TimelineEntryKind,
    payload: GuidedTimelineSummary,
    message: String
) throws -> TimelineSummaryResult {
    let summary = sanitize(payload.summary, kind: kind)

    if kind == .assistant {
        // Existing assistant validation...
    } else if kind == .user {
        // NEW: User message validation
        let hasDirectivePattern = isDirective(message)
        let usedMadePrefix = summary.lowercased().hasPrefix("you made")

        // If message has directive patterns but summary uses "You made", warn
        if hasDirectivePattern && usedMadePrefix {
            log.warning("timeline summary may be misclassified: message has directive patterns but summary uses 'You made'")
            log.warning("message: \(String(message.prefix(100)), privacy: .public)")
            log.warning("summary: \(summary, privacy: .public)")
        }

        // Check for low confidence with high-stakes classification
        if payload.confidence < 0.5 {
            log.warning("timeline summary has low confidence (\(payload.confidence, privacy: .public)): \(summary, privacy: .public)")
        }
    }

    let completion = kind == .assistant
        ? (payload.isCompletion && hasCompletionToken(summary))
        : false

    return TimelineSummaryResult(summary: summary, isCompletion: completion, icon: nil)
}
```

**Rationale:** Catches obvious misclassifications and logs warnings for debugging.

### Phase 4: Add Fast Path for Obvious Directives (OPTIONAL)

**File:** `Contextify/Contextify/FoundationLLM.swift:58-63`

**Changes:**

```swift
guard !message.isEmpty else {
    log.info("[\(reqNum)] timeline: empty message, using fallback")
    return fallbackSummary(kind: kind, text: text)
}

// Fast paths to skip LLM call
if kind == .assistant, isAck(message) {
    log.info("[\(reqNum)] timeline: ack detected, skipping LLM")
    return TimelineSummaryResult(summary: "Claude acknowledges the request.", isCompletion: false, icon: nil)
} else if kind == .user, let directive = detectSimpleDirective(message) {
    // NEW: Fast path for obvious imperatives
    log.info("[\(reqNum)] timeline: simple directive detected, skipping LLM")
    return TimelineSummaryResult(summary: "You requested Claude to \(directive)", isCompletion: false, icon: "👉")
}
```

Add helper function:

```swift
func detectSimpleDirective(_ text: String) -> String? {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let firstWord = normalized.split(separator: " ").first?.lowercased()

    let imperatives: [String: String] = [
        "commit": "commit changes",
        "fix": "fix issues",
        "run": "run commands",
        "update": "update code",
        "add": "add features",
        "create": "create files",
        "test": "run tests",
        "build": "build the project",
        "deploy": "deploy changes"
    ]

    if let first = firstWord, let action = imperatives[String(first)] {
        return action
    }
    return nil
}
```

**Rationale:** Faster and more reliable for simple commands. Reduces LLM load.

### Phase 5: Add Test Coverage

**File:** `Contextify/ContextifyTests/FoundationLLMTests.swift`

**Add new test class:**

```swift
#if canImport(FoundationModels)
@available(macOS 26.0, *)
final class UserMessageTests: XCTestCase {
    func testImperativeDetectedAsDirective() async throws {
        // Test: "Commit your changes..."
        // Should produce: "You requested Claude to commit changes..."
    }

    func testRequestPatternDetectedAsDirective() async throws {
        // Test: "See if you can find..."
        // Should produce: "You asked Claude to find..."
    }

    func testNestedQuotesIgnored() async throws {
        // Test message with nested quotes
        // Should summarize outer message, not quoted content
    }

    func testPastTenseReportDetectedCorrectly() async throws {
        // Test: "I updated the configuration file"
        // Should produce: "You made updates to the configuration file"
    }

    func testQuestionDetectedCorrectly() async throws {
        // Test: "What does this function do?"
        // Should produce: "You asked what the function does"
    }
}
#endif
```

---

## Implementation Priority

**High Priority (Must Fix):**
1. ✅ Improve user message prompt (Phase 1) - **Highest impact, quick to implement**
2. ✅ Add directive preprocessing (Phase 2) - **Reinforces Phase 1**
3. ✅ Add user message validation (Phase 3) - **Catches errors**

**Medium Priority (Nice to Have):**
4. ⏳ Add fast path for directives (Phase 4) - **Performance optimization**
5. ⏳ Add test coverage (Phase 5) - **Prevents regressions**

---

## Testing Strategy

### Manual Testing

**Test Cases:**
1. "Commit your changes with a note"
   - Expected: "You requested Claude to commit changes with a note"

2. "See if you can find discussion in ~/.claude/projects"
   - Expected: "You asked Claude to find discussion in the project context"

3. "I've updated the configuration file"
   - Expected: "You made updates to the configuration file"

4. "What does the validateVenv function do?"
   - Expected: "You asked what the validateVenv function does"

5. Message with nested quotes: `"""Write a plan""" after that...`
   - Expected: Should ignore nested quotes, summarize the outer request

### Automated Testing

Add unit tests for:
- Imperative detection
- Request pattern detection
- Nested quote handling
- Question detection
- Past tense report detection

---

## Risks & Mitigations

**Risk:** Prompt changes might over-correct and misclassify edge cases
- **Mitigation:** Add validation logging, monitor for new false positives

**Risk:** Adding preprocessing might conflict with existing action hint logic
- **Mitigation:** Careful integration, test with action hint enabled/disabled

**Risk:** Fast paths might miss nuanced requests
- **Mitigation:** Make fast paths optional, fall back to LLM for complex cases

---

## Success Criteria

1. ✅ "Commit your changes" → "You requested Claude to commit"
2. ✅ "See if you can find" → "You asked Claude to find"
3. ✅ Nested quotes ignored in summarization
4. ✅ No more hallucinated summaries (extracting from wrong content)
5. ✅ User summaries as accurate as assistant summaries

---

## Estimated Effort

- **Phase 1 (Prompt improvement):** 30 minutes
- **Phase 2 (Preprocessing):** 20 minutes
- **Phase 3 (Validation):** 20 minutes
- **Phase 4 (Fast paths):** 30 minutes (optional)
- **Phase 5 (Tests):** 1 hour (optional)

**Total:** 1.5-2.5 hours depending on scope

---

## Related Commits

- `34091cf` - Fixed word-boundary truncation (unrelated but recent timeline work)
- `f1a7d5b` - Improved LLM summary acceptance and retry logic (assistant only)
- `7accd35` - Improved assistant summary prompts (didn't touch user prompts)

---

**Next Steps:** Implement Phase 1-3 (high priority), test with real conversation data, then evaluate need for Phase 4-5.
