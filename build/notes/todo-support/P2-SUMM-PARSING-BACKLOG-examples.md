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

## Example 4: Parse Error on CSS Token Content

**Date Added:** 2025-12-03
**Category:** format issue (parse error)
**Transcript:** `99fb88c7-8c81-4ea9-98a8-8b2eb09a0187.jsonl`

**Entry:**
```json
{
  "detail": "Done. Added all missing tokens for full parity:\n\n**Light mode additions:**\n- `--contextify-info: #4A7BA7`\n- `--contextify-info-light: #E8F0F7`\n- `--text-disabled: var(--slate-300)`\n- `--bg-overlay: rgba(0, 0, 0, 0.5)`\n- `--border-focus: var(--contextify-primary)`\n- `--link-active: var(--contextify-primary-hover)`\n\n**Dark mode additions:**\n- `--contextify-info: #6A9BC7`\n- `--contextify-info-light: #1A2838`\n- `--text-disabled: var(--slate-600)`\n- `--bg-overlay: rgba(0, 0, 0, 0.7)`\n- `--border-focus: var(--contextify-primary)`\n- `--link-active: #7AABDA`\n\nThe CSS now has 100% parity with `build/design/brand/colors.md`. Refresh the browser to verify nothing broke visually.",
  "entry_id": "01dd3975-4c18-46ce-82b8-51086e60f555",
  "summary": "Done. Added all missing tokens for full parity:\n\n**Light mode additions:**\n- `--contextify-info: #4A…",
  "timestamp": "2025-12-03T21:03:07Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/99fb88c7-8c81-4ea9-98a8-8b2eb09a0187.jsonl"
}
```

**Error Message:**
> "The AI generated a response in an unexpected format that could not be parsed. This is usually caused by malformed system output (bash commands, git output, etc.) in the conversation. The entry remains accessible without a summary."

**Problem:**
Summarization threw a parse error. The summary field shows truncated content, but this is likely fallback behavior after the error. The actual failure was the AI response couldn't be parsed.

**Expected Summary:**
A concise prose summary like:
- "Claude Code added 6 missing CSS color tokens (info, disabled, overlay, focus, active) to both light and dark modes for full parity with the design system."

**Root Cause (suspected):**
- CSS variable syntax (`--contextify-info`, `var(--slate-300)`, `rgba(0, 0, 0, 0.5)`) may be interpreted as code/commands
- Inline code backticks with dashes and parentheses may trigger format detection heuristics
- The combination of markdown bold (`**`), bullet lists, and code spans may produce output the parser doesn't expect

**Fix Approach:**
1. Pre-process content to escape or strip CSS-like patterns before summarization
2. Catch parse errors and retry with a simpler prompt or stripped content
3. Investigate what "unexpected format" means in the parser - is it JSON structure, markdown, or something else?
4. Consider marking entries with heavy code content for a different summarization path

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

## Example 6: Literal Echo with Attribution Prefix

**Date Added:** 2025-12-03
**Category:** attribution error (echo/passthrough)
**Transcript:** `c7ba294f-3ef9-4cae-8947-d5d1d489bf5e.jsonl`

**Entry:**
```json
{
  "detail": "Found the document. Adding the new example:",
  "entry_id": "3983abd4-2fd4-40a9-88ba-34c2eec0a029",
  "summary": "Claude Code Found the document. Adding the new example:",
  "timestamp": "2025-12-03T22:47:53Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/c7ba294f-3ef9-4cae-8947-d5d1d489bf5e.jsonl"
}
```

**Problem:**
The summary is just "Claude Code" + the exact detail text verbatim. No summarization occurred - it's a literal echo with attribution slapped on. Also grammatically awkward: "Claude Code Found" (capital F carried over).

**Expected Summary:**
- "Claude Code located the target document and added a new entry."
- Or simply use the detail as-is without the prefix (it's already concise).

**Root Cause (suspected):**
- Similar to Examples 2 and 3: short/simple messages trigger passthrough behavior
- LLM may have decided the content is already concise enough and just echoed it
- No post-processing to detect "summary == prefix + detail" pattern

**Fix Approach:**
1. Detect echo pattern: if `summary.removePrefix("Claude Code ") == detail`, skip the prefix entirely
2. For transitional phrases ("Found X. Doing Y:"), summarize the action not the announcement
3. Add instruction to prompt: "If the content is already concise, use it directly without adding attribution"

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

## Example 8: Subject Misattribution in Question

**Date Added:** 2025-12-04
**Category:** attribution error
**Transcript:** `24bbc369-4035-4afa-bfeb-294eb1177212.jsonl`

**Entry:**
```json
{
  "detail": "are you stuck?",
  "entry_id": "a1b7e57b-3bcb-4a9f-a1c3-8646a0b4ac85",
  "summary": "You asked Claude Code if you were stuck.",
  "timestamp": "2025-12-05T03:52:06Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/24bbc369-4035-4afa-bfeb-294eb1177212.jsonl"
}
```

**Problem:**
TODO

**Expected Summary:**
TODO

**Root Cause (suspected):**
TODO

**Fix Approach:**
TODO

---

## Example 9: Raw Markup Echo as Summary

**Date Added:** 2025-12-04
**Category:** attribution error (echo/passthrough)
**Transcript:** `a2d7ae22-e6f8-4f4e-a2ba-ceb271776215.jsonl`

**Entry:**
```json
{
  "detail": "<bash-input>gs</bash-input>",
  "entry_id": "d614b86e-eaad-48f8-9bd3-e9708145b318",
  "summary": "<bash-input>gs</bash-input>",
  "timestamp": "2025-12-05T03:52:41Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/a2d7ae22-e6f8-4f4e-a2ba-ceb271776215.jsonl"
}
```

**Problem:**
TODO

**Expected Summary:**
TODO

**Root Cause (suspected):**
TODO

**Fix Approach:**
TODO

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
