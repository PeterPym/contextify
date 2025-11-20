# User Timeline Summarization - Step-by-Step Implementation Guide

**For:** Clean implementation without prior context
**Primary document:** `build/docs/planning/user-timeline-summarization-improvement.md`
**This document:** Exact code locations and replacement instructions

---

## How to Use This Guide

1. **Read the problem analysis first:** `build/docs/planning/user-timeline-summarization-improvement.md`
   - Understand current issues
   - Review proposed solution approach
   - See expected outcomes

2. **Use this guide for implementation:**
   - Exact code to find and replace
   - Precise line numbers and context
   - Step-by-step instructions
   - Validation steps

3. **Priority order:**
   - Change 1: Update user prompt (PRIMARY)
   - Change 2: Integrate classifyUserIntent override (RECOMMENDED)
   - Change 3: Lexical seatbelts (OPTIONAL, P2 - can defer)

---

## Change 1: Update User Prompt

### Location

**File:** `Contextify/Contextify/FoundationLLM.swift`
**Function:** `instructionsForTimeline(kind:provider:)`
**Branch:** `case .user:` (search for this to find it)
**Lines:** Approximately 1520-1600 (will vary)

### Current Code Structure (TO BE REPLACED)

Search for:
```swift
case .user:
    return """
    You produce a ONE-sentence timeline summary (≤140 chars) for a developer message.
```

The current user prompt is much shorter than the assistant prompt and lacks:
- Explicit disposition definitions
- Clear summary phrasing templates
- Examples for each disposition type

### New Code (REPLACE WITH THIS)

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
    - "/review-prep" (slash commands are always directives)

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
    - For slash commands: "You requested Claude Code to execute the /[command] command"
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

    ### Mixed Messages

    If a message could be multiple dispositions:
    - "Can you explain why X is broken?" → **directive** (requesting action)
    - "Why is X broken?" → **question** (only seeking explanation)
    - When in doubt, prefer **directive** if any action is requested

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

### Implementation Steps

1. **Open file:** `Contextify/Contextify/FoundationLLM.swift`

2. **Search for:** `case .user:`
   - Should be around line 1520 (after the assistant case)

3. **Identify the return statement:**
   - Starts with `return """`
   - Contains user message instructions
   - Much shorter than assistant prompt

4. **Select entire prompt string:**
   - From `return """`
   - To closing `"""`
   - This is the entire user prompt

5. **Replace with new prompt:**
   - Delete old prompt
   - Paste new prompt code (from "New Code" section above)
   - Ensure indentation matches (should align with `return """`)

6. **Verify string interpolation:**
   - No `\(userName)` or similar in new prompt (we use "You" instead)
   - Just plain text, no variables

7. **Save the file**

---

## Change 2: Integrate classifyUserIntent Override

### Location

**File:** `Contextify/Contextify/FoundationLLM.swift`
**Function:** `postProcess(kind:payload:message:provider:)`
**Branch:** Inside `else if kind == .user { ... }` block
**Lines:** Approximately 1880-1930 (will vary)

### Context Around Insertion Point

**Find this code:**
```swift
} else if kind == .user {
    let autoIntent = classifyUserIntent(message)
    let s = summary.lowercased()

    // Validate prefix matches detected intent (with reasonable alternatives)
```

**INSERT NEW CODE AFTER:**
```swift
let autoIntent = classifyUserIntent(message)
```

**AND BEFORE:**
```swift
let s = summary.lowercased()
```

### Code to Insert

```swift
    // Override LLM disposition if classifyUserIntent has strong opinion
    var finalDisposition = payload.disposition

    // Map UserIntent enum to timeline disposition string
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

    // If classifier disagrees with LLM, trust the classifier
    if let intentDisp = intentDisposition, intentDisp != payload.disposition {
        log.info("User disposition override: LLM=\(payload.disposition) → classifier=\(intentDisp)")
        finalDisposition = intentDisp
    }
```

### Update Return Statement

**Find the return statement at the end of the `.user` block:**
```swift
return TimelineSummaryResult(
    summary: summary,
    isCompletion: completion,
    isDirective: directiveFlag,
    disposition: payload.disposition
)
```

**Change to:**
```swift
return TimelineSummaryResult(
    summary: summary,
    isCompletion: false,  // Users never complete work
    isDirective: directiveFlag,
    disposition: finalDisposition  // Use overridden disposition
)
```

### Implementation Steps

1. **Open file:** `Contextify/Contextify/FoundationLLM.swift`

2. **Search for:** `} else if kind == .user {`
   - Should be around line 1880

3. **Find:** `let autoIntent = classifyUserIntent(message)`
   - This is where we'll add override logic

4. **Insert override code:**
   - Place cursor at end of `let autoIntent = ...` line
   - Press Enter to create new line
   - Paste override code (from "Code to Insert" section above)

5. **Find the return statement:**
   - Scroll down to bottom of `.user` block
   - Look for `return TimelineSummaryResult(...)`

6. **Update return statement:**
   - Change `disposition: payload.disposition` to `disposition: finalDisposition`
   - Change `isCompletion: completion` to `isCompletion: false`
   - Add comment explaining why isCompletion is false

7. **Verify variables in scope:**
   - `autoIntent` - defined just above
   - `payload` - function parameter
   - `finalDisposition` - defined in inserted code
   - `summary` - defined earlier in function

8. **Save the file**

---

## Change 3: Optional Lexical Seatbelts (P2 - Can Defer)

**This is OPTIONAL and can be deferred to P2.**

If monitoring shows specific problematic patterns after Changes 1-2, add these simple rules:

### Location

**File:** Same as Change 2
**Position:** After the classifyUserIntent override, before prefix validation

### Optional Code

```swift
    // Optional lexical seatbelts (only if needed)
    let msgLower = message.lowercased()

    // Catch directives misclassified as questions
    let hasDirectiveCue = msgLower.hasPrefix("can you ") ||
                         msgLower.hasPrefix("could you ") ||
                         msgLower.hasPrefix("please ") ||
                         msgLower.hasPrefix("would you ")

    if finalDisposition == "question" && hasDirectiveCue {
        log.info("User disposition correction: question → directive (directive cue detected)")
        finalDisposition = "directive"
    }

    // Catch pure questions misclassified as directives
    let isPureQuestion = message.contains("?") &&
                        !hasDirectiveCue &&
                        (msgLower.hasPrefix("why ") ||
                         msgLower.hasPrefix("what ") ||
                         msgLower.hasPrefix("how "))

    if finalDisposition == "directive" && isPureQuestion {
        log.info("User disposition correction: directive → question (pure question pattern)")
        finalDisposition = "question"
    }
```

**Note:** Only implement this if you see specific patterns in production logs after deploying Changes 1-2. Keep it simple.

---

## Post-Implementation Verification

### Step 1: Verify Compilation

```bash
cd /Users/rob/code/projects/contextify
bash scripts/xc.sh build
```

**Expected:** Build succeeds with zero errors

**If build fails:**
- Check Swift string syntax (ensure `"""` are properly matched)
- Verify variable names (`finalDisposition` used consistently)
- Check that inserted code is inside `.user` block

### Step 2: Check for Warnings

```bash
bash scripts/xc.sh build 2>&1 | grep -i warning | grep -v appintents
```

**Expected:** Zero warnings in FoundationLLM.swift

### Step 3: Visual Code Review

Open `FoundationLLM.swift` and verify:

**For prompt change:**
- [ ] Prompt starts with "You are classifying a SINGLE user message"
- [ ] Five disposition definitions present (directive, question, report, affirmative, negative)
- [ ] "Summary Phrasing (CRITICAL)" section exists
- [ ] Special handling for slash commands documented
- [ ] Output format shows isCompletion: false

**For postProcess change:**
- [ ] Override code inserted after `let autoIntent = classifyUserIntent(message)`
- [ ] `finalDisposition` variable defined
- [ ] Return statement uses `finalDisposition` not `payload.disposition`
- [ ] Return statement has `isCompletion: false` with comment

---

## Manual Validation (Recommended)

### Test Cases

Run these 10 test cases through the code and verify disposition + summary:

**Directives (3 tests):**
1. "Add logging around the retry loop."
   - Expected disposition: `directive`
   - Expected summary: "You requested Claude Code to add logging..."

2. "Can you refactor this into two files?"
   - Expected disposition: `directive`
   - Expected summary: "You requested Claude Code to refactor..."

3. "/review-prep"
   - Expected disposition: `directive`
   - Expected summary: "You requested Claude Code to execute the /review-prep command."

**Questions (2 tests):**
4. "Why is this query so slow?"
   - Expected disposition: `question`
   - Expected summary: "You asked why the query is slow."

5. "What does this error mean?"
   - Expected disposition: `question`
   - Expected summary: "You asked what the error means."

**Reports (2 tests):**
6. "The app crashes when I click the timeline."
   - Expected disposition: `report`
   - Expected summary: "You reported crashes when clicking the timeline."

7. "CI is failing on the main branch."
   - Expected disposition: `report`
   - Expected summary: "You reported CI failures on main branch."

**Affirmative/Negative (2 tests):**
8. "Yes, that works."
   - Expected disposition: `affirmative`
   - Expected summary: "You confirmed..." or "You agreed..."

9. "No, that's not right."
   - Expected disposition: `negative`
   - Expected summary: "You rejected..." or "You disagreed..."

**Mixed case (1 test):**
10. "Can you explain why X is broken?"
    - Expected disposition: `directive` (requesting action to explain)
    - Expected summary: "You requested Claude Code to explain..."

### Success Criteria

- ≥9/10 correct dispositions
- ≥9/10 correct verb patterns
- Zero validation errors/retries
- classifyUserIntent and LLM agree ≥85% of time (check logs)

---

## Troubleshooting

### Issue: Build fails with "Expected expression"

**Cause:** Syntax error in multiline string or missing closing `"""`
**Fix:**
- Check that all `"""` are properly matched
- Verify no stray quotes inside the string
- Swift multiline strings don't need escaping for regular quotes

### Issue: Build fails with "Use of unresolved identifier 'finalDisposition'"

**Cause:** Variable defined in wrong scope or typo
**Fix:**
- Verify override code inserted inside `.user` block
- Check spelling: `finalDisposition` (camelCase)
- Ensure it's defined before the return statement

### Issue: Dispositions still incorrect after change

**Cause:** Prompt not being followed or classifyUserIntent not working
**Fix:**
1. Check logs for "User disposition override" messages
2. If many overrides: prompt needs refinement
3. If no overrides but still wrong: classifyUserIntent might need update
4. Add debug logging to see LLM raw output

### Issue: Validation still rejecting summaries

**Cause:** Prefix validation still too strict
**Fix:**
- Check recent validation fix is applied (commit 29dcac4)
- Verify prefix alternatives include "performed", "executed", etc.
- Consider adding more alternatives to list

---

## Monitoring After Deployment

### Week 1: Monitor Disposition Overrides

**Check logs for:**
```
User disposition override: LLM={X} → classifier={Y}
```

**Analysis:**
- If override rate <10%: Good, prompt working well
- If override rate >20%: Prompt needs refinement
- If specific pattern (e.g., always overriding "question" → "directive"): Add example to prompt

### Week 1: Check for Validation Rejections

**Check logs for:**
```
User summary prefix alternative: intent={X}, summary={Y}
```

**Analysis:**
- Should be at debug level (not warning)
- If frequent: Consider adding more prefix alternatives
- If specific pattern: Update prompt guidance

### Week 4: Manual Spot Check

**Randomly review 20 user timeline entries:**
- Do dispositions make sense?
- Are summaries using correct verbs?
- Any unexpected patterns?

---

## Next Steps After Implementation

1. **Commit with detailed message**
   - Reference this guide and problem analysis doc
   - List all changes made
   - Note validation results

2. **Deploy to test build**
   - Test with real user messages
   - Verify no regressions

3. **Monitor for 1 week**
   - Check override rates
   - Look for unexpected patterns
   - Gather feedback

4. **Consider P2 work if needed**
   - Add lexical seatbelts if specific patterns emerge
   - Refine prompt based on monitoring data
   - Update classifyUserIntent if needed

---

## Quick Reference

**Files modified:**
- `Contextify/Contextify/FoundationLLM.swift` (1 file, 2-3 changes)

**Functions modified:**
1. `instructionsForTimeline(kind:provider:)` - User prompt replaced (~100 lines)
2. `postProcess(kind:payload:message:provider:)` - Override logic added (~20 lines)
3. Optional: Lexical seatbelts (~15 lines, can defer)

**Build command:**
```bash
bash scripts/xc.sh build
```

**Validation priority:**
1. Build succeeds with zero warnings (REQUIRED)
2. Manual test cases pass ≥9/10 (HIGH)
3. Production monitoring week 1 (ONGOING)

---

## For the Implementing AI

**Read both documents:**
1. Problem analysis (why and what)
2. This guide (exactly how)

**Implementation order:**
1. Change 1: User prompt rewrite (PRIMARY)
2. Change 2: classifyUserIntent integration (RECOMMENDED)
3. Verify compilation and zero warnings
4. Manual validation with 10 test cases
5. Commit and deploy
6. Monitor for 1 week
7. Change 3: Optional seatbelts (DEFER unless needed)

**Do not:**
- Skip manual validation
- Add complex rule engines
- Over-engineer the solution
- Implement Change 3 unless monitoring shows need

**Do:**
- Follow exact code replacement instructions
- Keep changes simple and focused
- Verify zero warnings after build
- Document validation results
- Ask for clarification if unclear
