# Bug: Status Bar Error Display is Sticky and Non-Actionable

**Status:** Active
**Priority:** P1 (User-facing UX issue)
**Reported:** 2025-10-28
**Component:** StatusBarView, StatusBarViewModel, TimelineCacheMissGenerator

## Problem Statement

The status bar displays "1 Error" (or "N errors") when LLM generation fails, but:

1. **Sticky errors**: The error count never auto-clears, even after successful processing resumes
2. **No actionable recovery**: User sees the error but doesn't know what to do about it
3. **Vague tooltip**: Hover shows error reason but no suggested action

## Current Behavior

**Status Bar Display:**
```
⚠️ 1 Error
```

**Tooltip (on hover):**
```
Recent LLM generation errors
```
or
```
timeline summary REJECTED (grounding=..., leaked=3, confidence=0.000000): code, output, provided.
```

**What happens:**
- Error counter increments when LLM generation fails
- Counter NEVER decrements
- Persists across successful generations
- Only clears when queue stream ends (generator shutdown)

## Root Cause

### Data Flow
```
TimelineCacheMissGenerator
  ↓ (emits QueueStats)
StatusBarViewModel.aggregateStats()
  ↓ (updates observable state)
StatusBarView (displays)
```

### Issue Location

**File:** `Contextify/Contextify/TimelineCacheMissGenerator.swift:517-524`

```swift
struct QueueStats: Sendable, Equatable {
    let pending: Int
    let isProcessing: Bool
    let currentBatchSize: Int
    let estimatedSecondsRemaining: Int
    let recentErrorCount: Int          // ❌ Never decrements!
    let topErrorReason: String?
}
```

**File:** `Contextify/Contextify/StatusBarViewModel.swift:140-141`

```swift
recentErrorCount = stats.recentErrorCount    // ❌ Just copies the sticky value
topErrorReason = stats.topErrorReason
```

**File:** `Contextify/Contextify/StatusBarView.swift:159-172`

```swift
} else if let viewModel, viewModel.recentErrorCount > 0 {
    // Error state
    HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
        Text("\(viewModel.recentErrorCount) error\(viewModel.recentErrorCount == 1 ? "" : "s")")
    }
    .help(viewModel.topErrorReason ?? "Recent LLM generation errors")  // ❌ No action suggested
}
```

## Expected Behavior

### Option A: Auto-Expiring Errors (Recommended)
Errors should **auto-clear after N successful generations**:

```
❌ Error occurs → Counter = 1
✅ Success → Counter = 1 (still showing)
✅ Success → Counter = 1 (still showing)
✅ Success → Counter = 0 (cleared after 2-3 successes)
```

### Option B: Time-Based Auto-Clear
Errors should **auto-clear after 30-60 seconds**:
- Show error immediately when it occurs
- Fade out after timeout
- Reset on new error

### Option C: Manual Dismissal
Add **click-to-dismiss** functionality:
```
⚠️ 1 Error [×]  ← Click X to dismiss
```

## Proposed Solution

**Recommended: Hybrid Approach (Option A + Better Tooltip)**

### 1. Add Success Counter to Clear Errors
```swift
// TimelineCacheMissGenerator.swift
private var consecutiveSuccesses: Int = 0
private let errorClearThreshold = 3  // Clear after 3 successes

func processSuccess() {
    consecutiveSuccesses += 1
    if consecutiveSuccesses >= errorClearThreshold {
        recentErrorCount = max(0, recentErrorCount - 1)
        if recentErrorCount == 0 {
            topErrorReason = nil
        }
        consecutiveSuccesses = 0
    }
}

func processError(reason: String) {
    consecutiveSuccesses = 0  // Reset success counter
    recentErrorCount += 1
    topErrorReason = reason
}
```

### 2. Improve Tooltip with Actionable Guidance

**Current:**
```
timeline summary REJECTED (grounding=..., leaked=3, confidence=0.000000): code, output, provided.
```

**Improved:**
```
LLM generation failed for 1 entry

Reason: Summary rejected (low quality)
Action: Errors will auto-clear after a few successes.
If errors persist, check Apple Intelligence in System Settings.
```

### 3. Add Severity Levels

```swift
enum ErrorSeverity {
    case transient   // Expected occasional failures (auto-clear)
    case persistent  // Multiple failures in a row (needs attention)
    case critical    // Apple Intelligence unavailable (needs action)
}
```

**Display:**
- Transient: Yellow warning ⚠️ "1 error (auto-clearing)"
- Persistent: Orange warning ⚠️ "3 errors (check logs)"
- Critical: Red error ⛔️ "AI unavailable (check settings)"

## Implementation Checklist

- [ ] Add `consecutiveSuccesses` counter to TimelineCacheMissGenerator
- [ ] Implement auto-clear logic (clear after 3 successes)
- [ ] Improve error tooltip with actionable guidance
- [ ] Add error severity classification (optional)
- [ ] Test with real LLM failures
- [ ] Update status bar documentation

## Testing Plan

### Manual Testing
1. Trigger LLM failure (use bad input that triggers rejection)
2. Verify error appears: "⚠️ 1 Error"
3. Generate 3 successful summaries
4. Verify error auto-clears to "0 errors" and disappears

### Error Scenarios to Test
- Single failure → 3 successes → clears
- Multiple failures → 3 successes → decrements by 1
- Apple Intelligence unavailable → persistent critical error
- Post-process rejection (grounding, leaking) → transient error

## Related Files

- `Contextify/Contextify/StatusBarView.swift` (UI display)
- `Contextify/Contextify/StatusBarViewModel.swift` (state aggregation)
- `Contextify/Contextify/TimelineCacheMissGenerator.swift` (error source)
- `Contextify/Contextify/TranscriptMetadataOrchestrator.swift` (also emits errors)

## References

- Status bar spec: `build/notes/feature-specs/status-bar/spec-final.md`
- LLM architecture: `build/notes/technical-reference/llm-processing-architecture.md`

## User Impact

**Current:** Confusing - user sees persistent error with no way to resolve
**After fix:** Clear feedback - errors auto-clear, user knows system is recovering
