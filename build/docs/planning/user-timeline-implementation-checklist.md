# User Timeline Implementation - Critical Checks

**Purpose:** Red flags to resolve during implementation (not conceptual objections)

These are "if you get this wrong, things break" items. Treat as blockers to resolve, not redesign work.

---

## 1. JSON Schema Contract (P0 - Must Check)

**Risk:** If prompt JSON doesn't match `GuidedTimelineSummary`, decoding fails silently.

### What to Verify

The user prompt says the model returns:

```json
{
  "summary": String,
  "isCompletion": false,
  "disposition": String,
  "grounding": String,
  "confidence": Double
}
```

**You MUST confirm:**

✅ `GuidedTimelineSummary` struct has EXACTLY these fields with matching casing
✅ No extra REQUIRED fields in Swift type that prompt doesn't mention
✅ Field types match (String, Bool, Double)
✅ `isCompletion` is Bool (not optional) and prompt always says `false` for users

**Where to check:**
- `FoundationLLM.swift` around line 818-833
- Schema comment added in recent fix (commit 0d68c05) documents this

**If mismatch found:**
- Fix the PROMPT to match Swift type (don't change Swift type)
- Guided decoder will silently fail otherwise
- No timeline entries = broken feature

**Action items:**
1. Read schema comment in code (lines 807-817)
2. Verify prompt JSON matches exactly
3. Pay special attention to `isCompletion` - should always be `false` for users
4. Check no extra required fields sneaked in

---

## 2. `classifyUserIntent` Enum Values (P0 - Must Check)

**Risk:** If mapping from `UserIntent` enum to disposition strings is wrong, overrides fail or produce invalid data.

### What to Verify

The override code maps `UserIntent` enum to disposition strings:

```swift
switch autoIntent {
case .directive: return "directive"
case .question: return "question"
case .report: return "report"
case .affirmative: return "affirmative"
case .negative: return "negative"
case .unknown: return nil
}
```

**You MUST confirm:**

✅ `UserIntent` enum has ALL these cases (directive, question, report, affirmative, negative, unknown)
✅ No NEW cases exist in enum that aren't handled
✅ Disposition strings match what `GuidedTimelineSummary` expects
✅ `.unknown` correctly returns `nil` (lets LLM decide)

**Where to check:**
- Search for `enum UserIntent` in FoundationLLM.swift
- Should be defined somewhere around lines 200-250 (may vary)

**If enum different:**
- Update the switch statement to match actual enum
- Add new cases if they exist
- Map to correct disposition strings

**Action items:**
1. Find UserIntent enum definition
2. Verify all cases are in switch statement
3. Verify string mappings are correct
4. Handle any new enum cases appropriately

---

## 3. `TimelineSummaryResult` Initializer (P0 - Must Check)

**Risk:** If return statement doesn't match initializer signature, code won't compile.

### What to Verify

The return statement in the guide shows:

```swift
return TimelineSummaryResult(
    summary: summary,
    isCompletion: false,
    isDirective: directiveFlag,
    disposition: finalDisposition
)
```

**You MUST confirm:**

✅ `TimelineSummaryResult` struct has these exact parameters
✅ No additional REQUIRED parameters (like `grounding`, `confidence`)
✅ Parameter order matches (or use labeled parameters)
✅ `isCompletion: false` is correct type (Bool, not optional)

**Where to check:**
- Line 183-188 in FoundationLLM.swift
- Struct definition with 4 fields
- Recent comment (commit 0d68c05) explains why only 4 fields

**If signature different:**
- Adjust return statement to match actual signature
- Pass through any required fields from `payload`
- Don't drop fields silently

**Action items:**
1. Read TimelineSummaryResult struct (line 183-188)
2. Count parameters: should be 4 (summary, isCompletion, isDirective, disposition)
3. Verify no extra required params
4. Adjust return statement if needed

---

## 4. Variable Scope in `postProcess` (P0 - Must Check)

**Risk:** If variables aren't in scope, code won't compile.

### What to Verify

The override code uses these variables:

```swift
let autoIntent = classifyUserIntent(message)  // NEW: defined here
var finalDisposition = payload.disposition     // Uses: payload
let intentDisposition: String? = { ... }()     // No external deps
if let intentDisp = intentDisposition { ... }  // Uses: log, finalDisposition
return TimelineSummaryResult(
    summary: summary,                          // Uses: summary
    isCompletion: false,
    isDirective: directiveFlag,                // Uses: directiveFlag
    disposition: finalDisposition              // Uses: finalDisposition
)
```

**You MUST confirm:**

✅ `message` is available (function parameter)
✅ `payload` is available (function parameter)
✅ `summary` is defined earlier in `.user` block
✅ `directiveFlag` is defined earlier in `.user` block
✅ `log` is available (class property)
✅ `finalDisposition` is defined before return statement

**Where variables come from:**
- `message`, `payload`: function parameters (line ~1660)
- `summary`: defined early in function (line ~1774)
- `directiveFlag`: defined in `.user` block (line ~1930+)
- `log`: class property
- `finalDisposition`: YOU define it in override code

**If variable missing:**
- Check spelling and case
- Ensure override code inserted in right place (inside `.user` block)
- Define missing variables before use

**Action items:**
1. Verify override code is inside `else if kind == .user { ... }` block
2. Check `summary` exists before your code
3. Check `directiveFlag` calculation happens before return
4. Ensure `finalDisposition` defined before return statement

---

## 5. Disposition String Values (P1 - Should Check)

**Risk:** If disposition strings don't match what rest of codebase expects, display/filtering breaks.

### What to Verify

The prompt and override code use these exact strings:

- `"directive"`
- `"question"`
- `"report"`
- `"affirmative"`
- `"negative"`

**You SHOULD confirm:**

⚠️ These match what timeline UI expects
⚠️ These match what database schema allows
⚠️ These match what filtering/sorting logic uses
⚠️ No typos in strings (lowercase, no spaces)

**Where to check:**
- Timeline display code (look for disposition rendering)
- Database schema (check timeline_cache table)
- Any disposition-based filtering

**If mismatch found:**
- Use existing disposition strings (don't invent new ones)
- Check schema comment for allowed values (line 825)
- Verify consistency with assistant dispositions where overlap exists

**Action items:**
1. Check schema @Guide description (line 825) for allowed dispositions
2. Verify strings in prompt match schema
3. Verify strings in override code match schema
4. Look for any disposition-based filtering that might break

---

## 6. Prompt Length and Token Usage (P2 - Nice to Check)

**Risk:** If prompt is too long, it increases latency and cost.

### What to Verify

The new user prompt is significantly longer than the old one.

**You SHOULD check:**

⚠️ New prompt is <500 lines of text (guideline)
⚠️ Examples are concise but clear
⚠️ No unnecessary repetition
⚠️ Token count reasonable (<2000 tokens estimated)

**How to estimate:**
- Visual inspection: Is prompt reasonable length?
- Compare to assistant prompt: Should be 50-70% of assistant length
- Monitor latency after deployment

**If too long:**
- Compress examples (keep 2-3 per disposition, not 5)
- Combine similar guidance points
- Remove redundant explanations

**Action items:**
1. Visual scan of prompt - does it feel reasonable?
2. Compare to assistant prompt length - roughly half?
3. Plan to monitor latency in production
4. Optimize later if needed (not blocking)

---

## 7. `isCompletion` Always False for Users (P0 - Must Check)

**Risk:** If `isCompletion` is anything other than `false` for user messages, UI will show incorrect completion status.

### What to Verify

In THREE places, ensure `isCompletion` is hardcoded to `false`:

**Place 1: Prompt JSON example**
```json
{
  "summary": "...",
  "isCompletion": false,  // ← Must be false
  "disposition": "directive",
  ...
}
```

**Place 2: Prompt instructions**
```
Note: User messages never complete work themselves, so isCompletion is always false.
```

**Place 3: Return statement**
```swift
return TimelineSummaryResult(
    summary: summary,
    isCompletion: false,  // ← Must be false, with comment
    isDirective: directiveFlag,
    disposition: finalDisposition
)
```

**You MUST confirm:**

✅ Prompt example shows `false`
✅ Prompt explains WHY it's false
✅ Return statement uses `false` (not variable)
✅ Comment added explaining design decision

**Rationale:**
- Users REQUEST work, they don't COMPLETE it
- Only assistants complete work
- This is architectural, not a judgment call

**Action items:**
1. Check prompt JSON example (should say `isCompletion: false`)
2. Check prompt has explanatory note
3. Check return statement uses `false` not variable
4. Add comment if missing: "Users never complete work"

---

## 8. Existing Validation Code Still Works (P1 - Should Check)

**Risk:** If override code breaks existing validation, entries might be rejected incorrectly.

### What to Verify

The `.user` block has EXISTING validation after your override:

1. **Prefix validation** (recently fixed, commit 29dcac4)
   - Now accepts alternatives gracefully
   - Logs at debug level, doesn't throw

2. **Length validation**
   - Rejects summaries >140 chars
   - Throws Error.retryExhausted

3. **Leakage validation**
   - Checks introducedTopics count
   - Threshold: 6 tokens
   - Skips if high-confidence fast-path

**You SHOULD confirm:**

⚠️ Your override code doesn't interfere with these validations
⚠️ `finalDisposition` is used consistently after override
⚠️ Validations can still access necessary variables
⚠️ Return statement at END of block (after all validations)

**Where to check:**
- Lines 1917-1940 (validation code)
- Your return statement should be at very end

**Action items:**
1. Review existing validation code after your insertion point
2. Verify your code doesn't break anything
3. Ensure `finalDisposition` used everywhere (not `payload.disposition`)
4. Confirm return statement is at the very end

---

## 9. Logging is Appropriate (P2 - Nice to Check)

**Risk:** If logging is too verbose or at wrong level, it pollutes logs or hides important info.

### What to Verify

The override code logs at INFO level:

```swift
log.info("User disposition override: LLM=\(payload.disposition) → classifier=\(intentDisp)")
```

**You SHOULD check:**

⚠️ INFO is appropriate level (not DEBUG, not WARNING)
⚠️ Message is informative for monitoring
⚠️ Privacy annotations if needed (disposition strings are safe)
⚠️ Not logging on every message (only on override)

**Rationale:**
- INFO: Significant but not an error (overrides are expected behavior)
- Only logs when disagreement occurs (~10-15% of messages)
- Helps monitor LLM vs classifier accuracy

**If different level needed:**
- DEBUG: If overrides are very frequent (>30%)
- WARNING: Never (overrides are intentional, not errors)

**Action items:**
1. Verify log level is INFO
2. Check message format is clear
3. Confirm logging only happens on actual override
4. No privacy leaks in log message

---

## 10. `isDirective` Flag Calculation (P1 - Should Check)

**Risk:** If `isDirective` flag doesn't match disposition, UI filtering/display breaks.

### What to Verify

The existing code calculates `isDirective` based on disposition:

```swift
let directiveFlag: Bool
if kind == .user {
    let intent = classifyUserIntent(message)
    directiveFlag = intent == .directive || intent == .affirmative || intent == .negative
} else {
    directiveFlag = false
}
```

**After your changes, this should be:**

```swift
directiveFlag = (finalDisposition == "directive" ||
                finalDisposition == "affirmative" ||
                finalDisposition == "negative")
```

**You SHOULD confirm:**

⚠️ `directiveFlag` uses `finalDisposition` (not old intent-based calculation)
⚠️ Includes all three: directive, affirmative, negative
⚠️ Calculated AFTER override (so it uses updated disposition)
⚠️ Used in return statement

**Rationale:**
- Directives, affirmatives, and negatives are all "directive" for UI purposes
- Must use final disposition (after override) for consistency

**Action items:**
1. Find `directiveFlag` calculation in `.user` block
2. Update to use `finalDisposition` instead of `intent`
3. Verify calculation happens after override
4. Check it's used in return statement

---

## Implementation Checklist Summary

### P0 (Must Fix Before Merge)
- [ ] 1. JSON schema matches GuidedTimelineSummary exactly
- [ ] 2. UserIntent enum cases all mapped correctly
- [ ] 3. TimelineSummaryResult initializer signature matches
- [ ] 4. All variables in scope (no undefined references)
- [ ] 7. isCompletion always false (3 places)

### P1 (Should Fix Before Merge)
- [ ] 5. Disposition strings match codebase expectations
- [ ] 8. Existing validation code still works
- [ ] 10. isDirective flag uses finalDisposition

### P2 (Nice to Have, Can Fix Post-Merge)
- [ ] 6. Prompt length reasonable
- [ ] 9. Logging at appropriate level

---

## Quick Pre-Commit Checklist

**Before committing, verify:**

1. ✅ Code compiles with zero warnings
2. ✅ isCompletion is `false` in 3 places
3. ✅ finalDisposition defined and used in return
4. ✅ UserIntent enum mapping is correct
5. ✅ Return statement has all 4 parameters
6. ✅ Override code is inside `.user` block
7. ✅ Manual test cases pass (≥9/10)

**If ANY P0 item fails:**
- Stop and fix before committing
- These will cause runtime failures or silent bugs

**If P1 items fail:**
- Fix before merging to main
- These affect correctness and user experience

**If P2 items fail:**
- Note in commit message
- Create follow-up task
- Not blocking for merge

---

## Red Flags During Implementation

**If you see any of these, STOP and investigate:**

🚨 Build fails with "Use of unresolved identifier"
   → Variable scope issue (check #4)

🚨 Build fails with "Initializer expects X arguments, got Y"
   → TimelineSummaryResult signature mismatch (check #3)

🚨 LLM summaries accepted but dispositions all wrong
   → UserIntent mapping incorrect (check #2)

🚨 Timeline entries show "completed" for user messages
   → isCompletion not hardcoded to false (check #7)

🚨 Validation still rejecting messages
   → finalDisposition not used consistently (check #8)

🚨 isDirective flag doesn't match disposition
   → Flag calculation not updated (check #10)

---

## For the Implementing AI

**Check these items IN ORDER:**

1. Start with P0 items (1-4, 7) - MUST be correct
2. Then P1 items (5, 8, 10) - SHOULD be correct
3. Finally P2 items (6, 9) - NICE to have

**Don't proceed to next step if:**
- Any P0 item fails
- Code doesn't compile
- Variables are undefined

**Ask for clarification if:**
- Enum values don't match guide
- Struct signature is different
- Variable names have changed

**Trust but verify:**
- Guide is accurate as of commit 29dcac4
- Code may have evolved slightly
- Cross-check with actual code when in doubt
