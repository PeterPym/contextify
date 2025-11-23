---
todo_id: P0-VALIDATION-FIX
title: Validation Confidence Bypass - Implementation Plan
type: plan
date: 2025-11-22
status: active
description: Remove LLM self-assessment from validation, use only objective metrics
---

# Validation Confidence Bypass - Implementation Plan

## Overview

**Problem:** Validation uses `confidence >= 0.6` to bypass all checks

**Root cause:** Confidence is LLM-generated output, not Apple API metadata

**Evidence:** 40+ hallucinations all have confidence = 0.95 (copied from prompt)

## Implementation

### Step 1: Add Helper Function

**File:** `Contextify/Contextify/FoundationLLM.swift`
**Location:** Before validation logic (around line 1799)

**Add:**
```swift
private func containsPromptExample(_ summary: String) -> Bool {
    let examples = [
        "analyzed the stack trace and identified the root cause",
        "added logging around the authentication flow",
        "proposed creating a helper script with presets"
    ]
    return examples.contains { summary.localizedCaseInsensitiveContains($0) }
}
```

### Step 2: Replace Validation Logic

**File:** `Contextify/Contextify/FoundationLLM.swift`
**Location:** Validation logic around lines 1799-1807

**OLD (BROKEN):**
```swift
let goodConfidence = payload.confidence >= 0.6
let okConfidence = payload.confidence >= 0.5
let minimalConfidence = payload.confidence >= 0.4
let excessiveLeakage = leaked.count >= 8

let shouldAccept = goodConfidence ||  // ← Bypasses everything!
                   (okConfidence && !excessiveLeakage) ||
                   (isGrounded && minimalConfidence)
```

**NEW (OBJECTIVE):**
```swift
let excessiveLeakage = leaked.count >= 4  // Stricter threshold
let hasExamplePhrase = containsPromptExample(summary)

let shouldAccept = !excessiveLeakage && !hasExamplePhrase

// Log rejections for monitoring
if !shouldAccept {
    log.warning("Timeline summary REJECTED: leakage=\(leaked.count), hasExample=\(hasExamplePhrase)")
    if excessiveLeakage {
        log.debug("Leaked tokens: \(leaked.joined(separator: ", "))")
    }
}
```

## Impact

**Changes:**
- ~30 lines changed in FoundationLLM.swift
- Removes confidence bypass entirely
- Adds prompt example blacklist
- Stricter leakage threshold (4 instead of 8)

**Expected behavior:**
- Rejection rate increases from ~0% to 5-10%
- Zero new "stack trace" hallucinations
- Legitimate summaries still accepted

## Testing

### Unit Tests

Add to `ContextifyTests/`:

```swift
func testValidationRejectsPromptExamples() async throws {
    let summary = "Claude Code analyzed the stack trace and identified the root cause."
    let leaked: [String] = []  // No leakage

    // Should reject because it's a prompt example
    let result = try await validateSummary(summary: summary, leaked: leaked)
    XCTAssertFalse(result, "Should reject prompt example phrase")
}

func testValidationRejectsHighLeakage() async throws {
    let summary = "Claude Code investigated unknown things with weird tokens."
    let leaked = ["investigated", "unknown", "weird", "tokens"]  // 4+ leaked tokens

    // Should reject because excessive leakage
    let result = try await validateSummary(summary: summary, leaked: leaked)
    XCTAssertFalse(result, "Should reject excessive leakage")
}

func testValidationAcceptsGoodSummary() async throws {
    let summary = "Claude Code explained the authentication logic and identified retry timing."
    let leaked = ["explained", "retry"]  // 2 leaked tokens (acceptable)

    // Should accept - no prompt examples, low leakage
    let result = try await validateSummary(summary: summary, leaked: leaked)
    XCTAssertTrue(result, "Should accept valid summary")
}
```

### Manual Testing

**Test scenario: Validation rejection monitoring**
1. Trigger summarization of thinking block
2. Check logs for "Timeline summary REJECTED"
3. Verify rejection reasons logged (leakage count, example phrase)
4. Verify timeline shows fallback or regenerates

**Test scenario: No false positives**
1. Create normal conversation with visible entries
2. Verify legitimate summaries are generated correctly
3. Check that rejection rate is reasonable (5-10%, not 50%+)
4. Verify no valid summaries blocked

## Success Criteria

- [ ] Zero new "stack trace" hallucinations
- [ ] Rejection rate 5-10% (was ~0%)
- [ ] No legitimate summaries rejected excessively
- [ ] Logs show rejection reasons clearly
- [ ] Timeline still functions normally

## Rollback

**Single-commit revert:**
```bash
git revert <validation-commit-hash>
```

No schema changes, no data migration needed.
