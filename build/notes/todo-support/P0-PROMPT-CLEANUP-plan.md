---
todo_id: P0-PROMPT-CLEANUP
title: Prompt Example Contamination - Cleanup Plan
type: plan
date: 2025-11-22
status: active
description: Remove specific technical phrases from prompt examples to prevent contamination
---

# Prompt Example Contamination - Cleanup Plan

## Problem

Prompt contains: "Claude Code analyzed the stack trace and identified the root cause"

LLM copies this when uncertain → 40+ identical hallucinations

## Why This Happens

### Generic Technical Examples

**Current prompt examples use concrete technical scenarios:**
- "analyzed the stack trace" (debugging scenario)
- "added logging around the authentication flow" (implementation scenario)
- "proposed creating a helper script" (planning scenario)

**Problem:** These are broadly applicable
- Many conversations involve debugging
- Stack traces are common in software development
- When LLM uncertain, these seem plausible

**Behavior:** LLM pattern-matches thinking blocks to prompt examples
- Thinking block mentions investigation → "stack trace" seems relevant
- LLM uncertain about actual content → uses example as template
- Copies example verbatim (including confidence value)

### Confidence Anchoring

**Current prompt example:**
```json
{
  "summary": "Claude Code analyzed the stack trace and identified the root cause.",
  "confidence": 0.95
}
```

**Problem:** Sets anchor at 0.95 (very high confidence)

**Behavior:**
- LLM interprets 0.95 as "this is what good summaries look like"
- Generates similar confidence values even when uncertain
- High confidence → triggers validation bypass

## Solution

### Replace Concrete Examples with Variable Templates

**OLD (line ~1541):**
```
**For ANALYSIS:**
- Use analysis verbs: "explained", "analyzed", "noted", "identified"
- Example: "Claude Code analyzed the stack trace and identified the root cause."
```

**NEW:**
```
**For ANALYSIS:**
- Use analysis verbs: "explained", "analyzed", "noted", "identified"
- Example format: "Claude Code [verb] the [subject] and [verb] [outcome]."
- Concrete example: "Claude Code explained the authentication logic and identified retry timing."
```

**Changes:**
1. Show template structure explicitly
2. Use less generic scenario (authentication timing, not stack traces)
3. Variable markers `[verb]`, `[subject]`, `[outcome]` show pattern

### Lower Confidence Anchor

**OLD (line ~1552):**
```json
{
  "summary": "...",
  "confidence": 0.95
}
```

**NEW:**
```json
{
  "summary": "...",
  "confidence": 0.75
}
```

**Impact:**
- Moderate confidence value (not maximal)
- LLM less likely to anchor at 0.95
- Still high enough to indicate "good summary"

## Implementation

**File:** `Contextify/Contextify/FoundationLLM.swift`
**Lines:** ~1541 (analysis example), ~1552 (example confidence)

**Scope:** ~10 lines changed

## Impact

### Reduces Prompt Contamination Risk

**Before:**
- Generic "stack trace" phrase appears in ~40 summaries
- All identical, all wrong

**After:**
- Specific scenario less broadly applicable
- Variable template shows structure, not literal text
- Diversity in summary phrasing increases

### Lowers Confidence Anchor

**Before:**
- Most summaries cluster at 0.85-0.95
- Few below 0.6 threshold

**After:**
- More variation in confidence values
- LLM less likely to default to 0.95

### Works with Validation Fix

**Combined effect:**
1. Prompt cleanup reduces contamination generation
2. Example phrase blacklist catches contamination if it happens
3. Lower confidence anchor reduces bypass rate
4. Stricter leakage threshold catches template copying

**Defense in depth:** Multiple layers prevent hallucinations

## Evidence of Current Problem

**Database query:**
```sql
SELECT content, confidence, grounding
FROM timeline_summaries
WHERE content LIKE '%analyzed the stack trace%';
```

**Results:** 40+ entries
- All identical text
- All confidence = 0.95
- All grounding = "grounded"
- All from thinking blocks

**Cause:** LLM copying prompt example when uncertain

## Success Criteria

- [ ] No new summaries matching old prompt examples
- [ ] Increased diversity in summary phrasing
- [ ] Confidence values more varied (not all 0.95)
- [ ] Combined with validation fix: zero "stack trace" hallucinations

## Rollback

**Single-commit revert:**
```bash
git revert <prompt-cleanup-commit-hash>
```

**Note:** Should bump generator signature to regenerate existing summaries:
```swift
"v2-filter-and-validation-fixes-2025-11-22"
```

## Related

- Validation fix: `build/notes/todo-support/P0-VALIDATION-FIX-plan.md`
- Analysis: `build/notes/todo-support/P0-VALIDATION-FIX-analysis.md`
- Comprehensive review: `/tmp/timeline-summarization-comprehensive-review-package.md`
