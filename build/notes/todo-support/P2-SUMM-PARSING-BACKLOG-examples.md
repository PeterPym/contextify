---
todo_id: P2-SUMM-PARSING-BACKLOG
title: Summarization Parsing Backlog Examples
type: reference
date: 2025-11-24
status: active
description: Catalog of transcript entries that produce unparseable or malformed summaries. Each entry records the raw output, expected behavior, and diagnostic context.
---

# Summarization Parsing Backlog

This document collects examples of wonky summaries - messages that fail summarization parsing or produce unhelpful output. Use this to identify patterns and batch-fix root causes in the parser, prompts, or post-processing logic.

## How to Add Examples

When you encounter a summary that doesn't parse correctly:

1. Copy the full JSON entry (or relevant fields) below
2. Note what the expected summary should be
3. Identify the likely root cause if known
4. Tag with category (markdown output, attribution error, format issue, etc.)

---

## Example 1: Seed Script Markdown Table Output

**Date Added:** 2025-11-24
**Category:** Markdown table in summary output
**Transcript:** `ac2c5189-55de-4e7f-9dd4-52c58eae4a57.jsonl`

**Entry:**
```json
{
  "detail": "From the seed script:\n\n| # | Kind | Summary (timeline_cache) |\n|---|------|--------------------------|\n| 1 | user | You requested dark mode support for the settings panel |\n| 2 | assistant | Claude Code updated color tokens and fixed sidebar contrast |\n| 3 | assistant | Claude Code completed dark mode implementation |\n| 4 | user | You requested to run the test suite |\n| 5 | assistant | Claude Code confirmed all 47 tests passing |\n\nThese match the fake terminal output in `fake-claude-session.sh`.",
  "entry_id": "4453e484-da84-4bd0-971a-f1d93eb219a1",
  "summary": "From the seed script:\n\n| # | Kind | Summary (timeline_cache) |\n|---|------|-------------------------...",
  "timestamp": "2025-11-25T05:30:30Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/ac2c5189-55de-4e7f-9dd4-52c58eae4a57.jsonl"
}
```

**Problem:**
The LLM output a markdown table instead of a prose summary. This appears to be from a fake/seed transcript used for screenshots, where the LLM may have echoed the structured input format.

**Expected Summary:**
Should be a single-sentence prose summary like:
- "Claude Code implemented dark mode and confirmed all tests passing."
- Or similar concise description of the session activity.

**Root Cause (suspected):**
- Seed script content may include structured data that the LLM echoes
- Prompt may not explicitly prohibit markdown tables in output
- Post-processing doesn't detect/reject table-formatted output

**Fix Approach:**
1. Add explicit instruction to prompts: "Output a single prose sentence, not tables or lists"
2. Add post-processing check: if summary contains `|---|` or similar table markers, regenerate
3. Review seed script content to ensure it doesn't trigger table echoing

---

## Example 2: Echo/Passthrough Summary

**Date Added:** 2025-11-25
**Category:** attribution error
**Transcript:** `56a12863-8c40-4c50-a9b7-8219d9a3f59a.jsonl`

**Entry:**
```json
{
  "detail": "you run it",
  "entry_id": "01e59f33-b9bd-45c4-8645-ac1566452e6b",
  "summary": "You said: \"you run it\"",
  "timestamp": "2025-11-25T18:41:56Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/56a12863-8c40-4c50-a9b7-8219d9a3f59a.jsonl"
}
```

**Problem:**
The summary is essentially an echo of the input with "You said:" prepended. For short user messages, this pattern provides no summarization value - it's just restating the literal message.

**Expected Summary:**
For very short/simple user messages, either:
- Skip summarization entirely (display the raw message)
- Provide meaningful context: "You asked Claude to run something"

**Root Cause (suspected):**
- Short messages may not trigger meaningful summarization
- The "You said:" prefix pattern may be a fallback when no summarization is needed
- Prompt may not distinguish between messages that need summarization vs passthrough

**Fix Approach:**
1. Add length/complexity threshold: messages under N chars or N words skip LLM summarization
2. If message is already concise, use it directly without "You said:" wrapper
3. Consider context-aware summarization that looks at surrounding entries

---

## Example 3: "Claude Code" Prefix on Short Response

**Date Added:** 2025-11-26
**Category:** attribution error
**Transcript:** `e922b8f3-1fe5-4453-944f-c7f7adbe7391.jsonl`

**Entry:**
```json
{
  "detail": "Done.",
  "entry_id": "df9deda1-91de-4a49-b6ec-7bf21bd2b250",
  "summary": "Claude Code Done.",
  "timestamp": "2025-11-26T22:39:41Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify-worker-bee/e922b8f3-1fe5-4453-944f-c7f7adbe7391.jsonl"
}
```

**Problem:**
Summary is "Claude Code Done." for content "Done." - unnecessarily prepending "Claude Code" to a one-word response.

**Expected Summary:**
For very short responses like "Done.", either:
- Use the raw message directly: "Done."
- Or if attribution needed: "Claude Code confirmed completion"

**Root Cause (suspected):**
- LLM prompt may instruct to always include "Claude Code" attribution
- No logic to skip attribution for trivially short messages
- Similar to Example 2 where short messages get unhelpful wrappers

**Fix Approach:**
1. Add length threshold: responses under N chars skip attribution prefix
2. Or adjust prompt to say "only add 'Claude Code' attribution when it adds clarity"
3. Post-processing: detect when summary is just "[Attribution] + [literal content]" pattern

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
