---
todo_id: P0-VALIDATION-FIX
title: Validation Confidence Bypass - Analysis
type: investigation
date: 2025-11-22
status: active
description: Detailed analysis of how LLM self-assessment creates circular validation
---

# Validation Confidence Bypass - Analysis

## The Circular Trap

### What We Thought

Apple FoundationModels API provides:
- Confidence Score (0.0-1.0) as metadata
- Grounding Assessment as metadata
- Summary Text as output

Validation could trust these metadata fields.

### Reality

**Prompt includes schema:**
```json
{
  "summary": String,
  "confidence": Double (0.0-1.0),
  "grounding": String (grounded | ungrounded | insufficient)
}
```

**LLM generates all fields as JSON output**

**Validation uses LLM's own fields to validate itself**

This is circular reasoning:
1. LLM generates summary + confidence + grounding
2. Validation checks if confidence >= 0.6
3. If yes, skip all other checks
4. LLM grades its own homework and always passes

## Evidence from Logs

### Pattern: Identical Hallucinations with High Confidence

**40+ entries with exact same text:**
"Claude Code analyzed the stack trace and identified the root cause"

**All entries:**
- confidence = 0.95 (exactly)
- grounding = "grounded"
- Original messages never mention "stack trace"

**Why 0.95?** That's the confidence value in the prompt example:
```json
{
  "summary": "Claude Code analyzed the stack trace...",
  "confidence": 0.95
}
```

### Behavior Pattern

**When LLM is uncertain:**
1. Doesn't have enough context (thinking block, minimal content)
2. Looks at prompt for guidance
3. Finds concrete example: "analyzed the stack trace..."
4. Copies example verbatim (including confidence value)
5. Validation sees confidence = 0.95 → bypass all checks
6. Hallucination accepted

## Why This Fails

### Fundamental Flaw: LLM Self-Assessment

**Problem:** Asking LLM to assess its own output quality is circular

**Analogy:** Student grading their own exam
- Student uncertain about answer
- Looks at example answer key
- Copies example verbatim
- Marks own answer as 95% confident
- Teacher accepts based on self-reported confidence

**This is not validation** - it's rubber-stamping

### Confidence Anchoring

**Problem:** Prompt example sets anchor at 0.95

**Behavior:**
- LLM sees high confidence in examples
- Interprets "this is what high confidence looks like"
- Generates similar values even when uncertain
- Confidence values cluster near prompt example values

**Evidence:** Most summaries have confidence 0.85-0.95, very few below 0.6

### Prompt Contamination Amplification

**Without confidence bypass:**
- Hallucination might be caught by leakage check (if enough prompt tokens)
- Or caught by grounding check (if obviously wrong)

**With confidence bypass:**
- High confidence → skip leakage check
- High confidence → skip grounding check
- Hallucination passes all gates

**Confidence bypass amplifies prompt contamination risk**

## The Fix

### Remove Circular Logic

**Don't use LLM-generated fields for validation:**
- ❌ confidence (LLM output)
- ❌ grounding (LLM output)

**Use objective metrics only:**
- ✅ Leakage count (token overlap with prompt)
- ✅ Example phrase detection (exact string matching)
- ✅ (Future) Embedding similarity (semantic distance)

### New Validation Logic

```swift
let excessiveLeakage = leaked.count >= 4
let hasExamplePhrase = containsPromptExample(summary)

let shouldAccept = !excessiveLeakage && !hasExamplePhrase
```

**No circular reasoning:**
- Metrics measured independently of LLM output
- String matching is objective
- Token counting is objective

## Expected Impact

### Rejection Rate

**Current:** ~0% (confidence bypass accepts everything)

**Expected:** 5-10%
- Thinking blocks with high leakage
- Summaries matching prompt examples
- Genuinely uncertain outputs

### False Positives

**Risk:** Rejecting legitimate summaries

**Mitigation:**
- Leakage threshold 4 (not too strict)
- Example phrases limited to known contamination
- Monitor logs for unexpected rejections

### Iteration

**After deployment:**
1. Monitor rejection rate
2. Review rejected summaries in logs
3. Adjust thresholds if needed
4. Add more example phrases if new patterns emerge

## Related Analysis

- Implementation plan: `build/notes/todo-support/P0-VALIDATION-FIX-plan.md`
- Comprehensive review: `/tmp/timeline-summarization-comprehensive-review-package.md`
- Colleague feedback: `/tmp/here-s-a-reflowed.md`
