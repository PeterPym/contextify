---
todo_id: P2-SUMM-PARSING-BACKLOG
title: Summarization Parsing Backlog Examples
type: reference
date: 2025-11-24
status: active
description: Catalog of transcript entries that produce unparseable or malformed summaries. Most issues now have fallback handling; remaining entries require prompt improvements.
---

# Summarization Parsing Backlog

This document collects examples of wonky summaries that need prompt improvements (not fallback-solvable). The original backlog had 17 examples; 14 are now handled by the `TimelineSummaryFallback` utility with rule-based fallbacks.

**Resolved (removed from this document):**
- Examples 1, 15: Markdown table output - handled by `detectFormatIssue`
- Examples 2, 3, 6, 17: Echo/passthrough - handled by `detectEchoPattern` + fallback generators
- Example 4: CSS token parse error - handled by `detectFormatIssue`
- Examples 8, 11: Pronoun confusion - handled by `detectPronounIssue`
- Example 9: Raw markup echo - handled by `detectFormatIssue`
- Example 10: Suggestion as request - handled by postProcess validation
- Example 13: Multi-clause imperative - handled by postProcess validation
- Example 14: Duplicate attribution - handled by `detectEchoPattern`
- Example 16: File path as command - handled by postProcess validation

**Remaining issues (require prompt improvements):**

---

## Example 5: Misattributed Action as Question

**Date Added:** 2025-12-03
**Category:** attribution error
**Transcript:** `abc5d89b-7e3b-4cd1-93f0-44a03e3a0ce7.jsonl`

**Entry:**
```json
{
  "detail": "Committed. Now let me find how the codebase detects App Store vs DMG builds:",
  "entry_id": "e99f247e-42f0-425f-a762-94ed5cc5538d",
  "summary": "Claude Code asked how the codebase detects App Store vs DMG builds.",
  "timestamp": "2025-12-03T22:41:59Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify-worker-bee/abc5d89b-7e3b-4cd1-93f0-44a03e3a0ce7.jsonl"
}
```

**Problem:**
The summary says Claude "asked" something, but the detail shows Claude stating an action ("Committed. Now let me find..."). Claude isn't asking a question - it's announcing what it's about to do. The colon at the end indicates Claude is about to perform a search, not pose a question.

**Expected Summary:**
- "Claude Code committed changes and searched for how App Store vs DMG builds are detected."
- Or: "Claude Code investigated build distribution detection logic."

**Root Cause (suspected):**
- The phrase "how the codebase detects" was interpreted as a question rather than the object of the verb "find"
- Prompt may not distinguish between "asking" (dialogue) and "investigating" (action)
- The colon at end may be stripped, losing context that output follows

**Fix Approach:**
1. Adjust prompt to distinguish dialogue questions ("Can you help?") from investigation statements ("Let me find X")
2. Recognize patterns like "let me find/check/see how..." as actions, not questions
3. Consider the full sentence structure: "Let me find how X" = investigation action

---

## Example 7: Nested JSON Content Misinterpreted

**Date Added:** 2025-12-03
**Category:** context confusion (nested content)
**Transcript:** `c7ba294f-3ef9-4cae-8947-d5d1d489bf5e.jsonl`

**Entry:**
```json
{
  "detail": "this too seems poorly summarized:\n {\n  \"detail\" : \"Found the document. Adding the new example:\",\n  \"entry_id\" : \"3983abd4-2fd4-40a9-88ba-34c2eec0a029\",\n  \"summary\" : \"Claude Code Found the document. Adding the new example:\",\n  ...\n}",
  "entry_id": "c4b1523f-998a-428c-90cd-591f947367d0",
  "summary": "You mentioned adding the new example.",
  "timestamp": "2025-12-03T22:49:12Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/c7ba294f-3ef9-4cae-8947-d5d1d489bf5e.jsonl"
}
```

**Problem:**
The user's message was "this too seems poorly summarized:" followed by a JSON blob as evidence. The summary says "You mentioned adding the new example" - which is a fragment from the *nested* JSON content, not the user's actual intent. The LLM confused the outer message with the quoted inner content.

**Expected Summary:**
- "You reported another poorly summarized entry for the bloopers document."
- Or: "You submitted a second summarization blooper example."

**Root Cause (suspected):**
- Nested JSON/quoted content confuses the LLM about what's the "real" message vs. quoted data
- The phrase "Adding the new example" in the nested JSON was misattributed to the user
- No instruction to treat JSON blobs as quoted/referenced content rather than user speech

**Fix Approach:**
1. Pre-process: detect JSON blobs in user messages and mark them as "quoted content" or strip for summarization
2. Add prompt instruction: "When the message contains JSON or code blocks, summarize the user's framing text, not the quoted content"
3. Look for patterns like "this [adjective]:" followed by code/JSON as a "reporting" pattern

---

## Example 12: Future Work Claimed as Complete

**Date Added:** 2025-12-08
**Category:** attribution error
**Transcript:** `0f26de49-a33e-460a-b29e-fa17d021f76a.jsonl`

**Entry:**
```json
{
  "detail": "The feature branch `feat/website-cache-busting` already exists and you're on it. The branch was created with the recent commit:\n\n```\n7e0e586d chore(todo): add P1 for website cache busting\n```\n\n**Todo Summary:**\n- **Item:** `#P1-WEBSITE-CACHE-BUSTING` - Implement cache-busting for CSS/JS on website\n- **Problem:** Browser caching prevents users from seeing updated styles after deployments\n- **Recommended approach:** Query string versioning (e.g., `style.css?v=abc123`) automated in the deploy script\n\n**Files to modify:**\n- `website/index.html` - stylesheet/script links\n- `scripts/deploy-website.sh` - add version injection\n\nReady to implement when you are.",
  "entry_id": "c35b76a2-f853-4146-babc-8bffbe69c0fd",
  "summary": "Claude Code implemented cache-busting for CSS/JS on website.",
  "timestamp": "2025-12-08T20:04:37Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/0f26de49-a33e-460a-b29e-fa17d021f76a.jsonl"
}
```

**Problem:**
The summary claims Claude "implemented" cache-busting, but the detail shows Claude only found an existing feature branch and described the planned work. The phrase "Ready to implement when you are" explicitly indicates no implementation has occurred yet.

**Expected Summary:**
- "Claude Code found the cache-busting feature branch and described the implementation plan."
- Or: "Claude Code confirmed the feature branch exists and outlined the todo items."

**Root Cause (suspected):**
- LLM saw technical keywords (cache-busting, CSS/JS, website) and assumed implementation
- Describing an implementation plan was conflated with actually implementing it
- No recognition of "Ready to implement when you are" as a signal that work hasn't started

**Fix Approach:**
1. Add prompt instruction: distinguish between "describing/planning work" and "completing work"
2. Look for phrases like "Ready to implement", "when you are ready", "let me know" as signals of pending (not completed) work
3. Check for actual file modifications or command executions before using past-tense completion verbs

---

## Template for New Examples

```markdown
## Example N: [Brief Description]

**Date Added:** YYYY-MM-DD
**Category:** [markdown output | attribution error | format issue | truncation | other]
**Transcript:** `[transcript-id].jsonl`

**Entry:**
\`\`\`json
{
  "entry_id": "...",
  "summary": "...",
  ...
}
\`\`\`

**Problem:**
[What went wrong with the summary]

**Expected Summary:**
[What the summary should have been]

**Root Cause (suspected):**
[Best guess at why this happened]

**Fix Approach:**
[Suggested fix]
```
