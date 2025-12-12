---
todo_id: P1-USER-PROMPT-REWORK
title: User Message Summarization Quality Improvement - Phase 2 Spec
type: spec
date: 2025-11-27
status: active
description: Phase 2 implementation spec for user message summarization improvements with permission response handling
related:
  - build/docs/planning/user-timeline-summarization-improvement.md (original planning doc)
  - P2-SUMMARIZATION-FIX (attribution issues - separate)
---

# P1-USER-PROMPT-REWORK: Phase 2 Implementation Spec

## Status Summary

- **Phase 1:** SHIPPED (commit `a8577a9`) - Expanded negative word list in `classifyUserIntent`
- **Phase 2:** Ready to implement (this spec)
- **Effort:** 5-7 hours

## Scope

**Original scope (3-6 hours):** User prompt quality improvement only
**v2 coordinated scope (5-7 hours):** User prompt quality + permission response handling + bug fixes

**Scope growth justified:**
- Tracks with original intent (improve user summarization quality)
- More comprehensive (handles permission response edge cases + prevents bugs)
- Mirrors assistant-side SOTA patterns (disposition taxonomy, structured prompts)
- Fixes active bugs (broken "Nevermind" summaries, prefixPolicy conflicts)

## Implementation Tasks

### 1. User Prompt Rewrite (2-3 hours)

See `build/docs/planning/user-timeline-summarization-improvement.md` for full prompt structure.

Additional requirements for Phase 2:
- Add `permission_response` disposition to taxonomy
- Add summary phrasing template: "You responded to permission request: [response]"

### 2. prefixPolicy Update (15 min)

**File:** `Contextify/Contextify/FoundationLLM.swift`

Add "You responded" to allowed prefixes to prevent double-prefix bug:

```swift
// In prefixPolicy or equivalent validation
let allowedPrefixes = [
    "You requested",
    "You asked",
    "You reported",
    "You confirmed",
    "You disagreed",
    "You rejected",
    "You responded",  // NEW - for permission responses
    // ... existing prefixes
]
```

### 3. postProcess Integration (1 hour)

**File:** `Contextify/Contextify/FoundationLLM.swift`

- Add `classifyUserIntent` override logic
- Log disagreements between LLM and classifier
- Exception: preserve `permission_response` (LLM has special context)
- Update `isDirective` calculation to include `permission_response`

```swift
// isDirective should include permission_response
let directiveFlag = (finalDisposition == "directive" ||
                    finalDisposition == "affirmative" ||
                    finalDisposition == "negative" ||
                    finalDisposition == "permission_response")
```

### 4. Disposition Enum (15 min)

**File:** `app/Sources/ContextifyCore/Database/Models.swift`

Add `Disposition.permissionResponse` enum case:

```swift
enum Disposition: String, Codable {
    case directive
    case question
    case report
    case affirmative
    case negative
    case permissionResponse = "permission_response"
    // ... existing cases
}
```

Audit all switch statements for exhaustiveness.

### 5. Optional: Permission Fast Path (1 hour)

Add `detectPermissionResponse()` helper with cue-word heuristic:

```swift
func detectPermissionResponse(_ message: String) -> Bool {
    // Detect responses to Claude Code permission dialogs
    let cueWords = ["nevermind", "pause", "wait", "stop", "cancel", "instead", "later"]
    let lower = message.lowercased().trimmingCharacters(in: .whitespaces)

    // Short messages with cue words likely permission responses
    if message.count < 50 && cueWords.contains(where: { lower.contains($0) }) {
        return true
    }
    return false
}
```

Prevents false positives: "Thanks", "Cool", "Got it" should NOT be `permission_response`.

Can be deferred to Phase 3 if complexity concerns.

### 6. Validation (1-2 hours)

Run 15 test cases, verify:
- Disposition accuracy >= 90%
- No double-prefix bugs
- No false positive permission responses

## Bug Fixes (from colleague review)

1. Fix `UserIntent` enum references (`.other` -> `.unknown`)
2. Align with `prefixPolicy` to prevent "You requested Claude Code You..." bug
3. Add `Disposition` enum case for proper type safety
4. Include `permission_response` in directive flag calculation

## Test Cases

### Directives (3)

| Input | Expected Output |
|-------|-----------------|
| "Add logging around retry loop." | "You requested Claude Code to add logging..." |
| "Can you refactor this?" | "You requested Claude Code to refactor..." |
| "/review-prep" | "You requested Claude Code to execute the /review-prep command." |

### Questions (2)

| Input | Expected Output |
|-------|-----------------|
| "Why is this slow?" | "You asked why this is slow." |
| "What does this error mean?" | "You asked what the error means." |

### Reports (2)

| Input | Expected Output |
|-------|-----------------|
| "App crashes when clicking timeline." | "You reported crashes..." |
| "CI is failing." | "You reported CI failures." |

### Affirmative/Negative (2)

| Input | Expected Output |
|-------|-----------------|
| "Yes, that works." | "You confirmed the approach works." |
| "No, that's not right." | "You disagreed with..." OR "You requested Claude Code not to proceed." |

### Permission Responses (5)

| Input | Expected Output |
|-------|-----------------|
| "Nevermind" | "You requested Claude Code not to proceed." (Phase 1 fast path) |
| "pause a moment" | "You responded to permission request: pause a moment" |
| "do X instead" | "You responded to permission request: do X instead" |
| "THIS IS A TEST" | "You responded to permission request: THIS IS A TEST" |
| "maybe later" | "You responded to permission request: maybe later" |

### Edge Cases (3) - Must NOT be permission_response

| Input | Expected Disposition |
|-------|---------------------|
| "Thanks" | affirmative OR unknown |
| "Cool" | affirmative OR unknown |
| "Got it" | affirmative |

## Success Criteria

- User prompt quality matches assistant (symmetry)
- Disposition accuracy >= 90%
- `classifyUserIntent` vs LLM agreement >= 85%
- Zero double-prefix bugs ("You requested Claude Code You...")
- Zero false positive permission responses
- All test cases pass (>= 13/15)

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking existing summaries | Test on recent transcripts first |
| classifyUserIntent disagrees with LLM | Log disagreements, monitor patterns |
| Permission heuristic false positives | Tightened with cue words, can defer |
| prefixPolicy conflicts | Explicitly addressed by adding "You responded" |

## Files Modified

- `Contextify/Contextify/FoundationLLM.swift`
  - User prompt (`instructionsForTimeline` case `.user`)
  - `prefixPolicy` (add "You responded")
  - Optional: `detectPermissionResponse()` helper
  - `postProcess` user block (`classifyUserIntent` override)
- `app/Sources/ContextifyCore/Database/Models.swift`
  - Add `Disposition.permissionResponse` enum case
- Optional: `Contextify/Contextify/TimelineEntryRow.swift`
  - UI styling for `permission_response` disposition

## Decision Points

1. **Include permission fast path?** Recommended: YES with cue words (safe, handles edge cases)
2. **Parser metadata (future)?** Defer to Phase 3 if false positives emerge
3. **Defer lexical seatbelts?** YES - Phase 1 + improved prompt should be sufficient

## References

- **Original planning doc:** `build/docs/planning/user-timeline-summarization-improvement.md`
- **Phase 1 commit:** `a8577a9` (negative word list expansion)
- **Related commits:** Permission dialog option 3 parsing (`204f12e`, `a8577a9`)
- **Related:** `#P2-SUMMARIZATION-FIX` (attribution issues - separate PR)
