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
The user asked "are you stuck?" (addressing Claude Code), but the summary says "if you were stuck" - confusing who "you" refers to. The summary should reflect that the USER asked if CLAUDE was stuck, not vice versa.

**Expected Summary:**
- "You asked if Claude Code was stuck."
- Or: "You checked if Claude Code was stalled."

**Root Cause (suspected):**
- The pronoun "you" in the original message refers to Claude Code (from the user's perspective)
- The LLM misinterpreted the subject/object relationship when transforming to third-person summary
- No special handling for user messages that address the assistant directly

**Fix Approach:**
1. Detect second-person questions addressed to the assistant ("are you...", "can you...", "do you...")
2. Transform "you" → "Claude Code" in such questions before summarizing
3. Post-process: ensure "you" in user summaries refers to the user, not the assistant

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
The summary is literally `<bash-input>gs</bash-input>` - the raw markup is echoed back without any transformation. The preprocessing should have converted this to something usable, or the LLM should have summarized the action.

**Expected Summary:**
- "You executed the command `gs`."
- Or: "You ran a shell command."

**Root Cause (suspected):**
- The `stripQuotedAndCode` function replaces `<bash-input>...</bash-input>` with `[system output]` but this might not have been applied
- Or the LLM received the raw markup and just echoed it back
- Very short command (`gs`) may have bypassed summarization logic

**Fix Approach:**
1. Ensure `stripQuotedAndCode` is always applied to user messages before summarization
2. Add fast path: if message is just a bash-input tag with short content, use template: "You executed the command `X`."
3. Post-process: detect XML-like tags in summaries and reject/regenerate

---

## Example 10: Suggestion Misattributed as Request

**Date Added:** 2025-12-05
**Category:** attribution error
**Transcript:** `1365595a-e23a-4a9e-ad03-dfad69afabe2.jsonl`

**Entry:**
```json
{
  "detail": "we should have docs on this",
  "entry_id": "queue-6945144986004572220-8685581187740856739",
  "summary": "You requested Claude Code to create documentation on this topic.",
  "timestamp": "2025-12-05T17:13:35Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/1365595a-e23a-4a9e-ad03-dfad69afabe2.jsonl"
}
```

**Problem:**
The user made a casual observation/suggestion ("we should have docs on this"), but the summary misinterprets this as a direct request to Claude Code. "We should have" is a general statement about documentation gaps, not "please create documentation."

**Expected Summary:**
- "You noted documentation should exist for this topic."
- Or: "You suggested adding documentation."

**Root Cause (suspected):**
- The phrase "should have docs" was interpreted as an imperative request rather than an observation
- LLM may be over-interpreting suggestions as actionable requests
- No distinction between "we should X" (suggestion/observation) vs "please do X" (request)

**Fix Approach:**
1. Adjust prompt to distinguish observations ("we should...", "it would be nice to...") from direct requests ("please...", "can you...", "do X")
2. For suggestion patterns, use verbs like "suggested", "noted", "observed" rather than "requested"

---

## Example 11: Pronoun Perspective Confusion

**Date Added:** 2025-12-07
**Category:** attribution error (pronoun/perspective)
**Transcript:** `50fe1b79-bde4-4675-9292-a71a4c6e6e0a.jsonl`

**Entry:**
```json
{
  "detail": "my video is 35 minutes :P",
  "entry_id": "d4343f62-afa1-4e19-a075-06f7f9c1c984",
  "summary": "You noted that my video is 35 minutes.",
  "timestamp": "2025-12-08T07:53:57Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/50fe1b79-bde4-4675-9292-a71a4c6e6e0a.jsonl"
}
```

**Problem:**
The summary says "You noted that my video..." - mixing second person ("You") with first person ("my"). The "my" should have been converted to "your" when summarizing from the user's perspective. As written, it sounds like Claude is claiming ownership of the video.

**Expected Summary:**
- "You mentioned your video is 35 minutes."
- Or: "You noted the demo video came out to 35 minutes."

**Root Cause (suspected):**
- LLM echoed the user's first-person pronoun without converting to second person
- The summarization prompt may not explicitly instruct perspective/pronoun transformation
- Short messages may trigger more literal echoing behavior

**Fix Approach:**
1. Add prompt instruction: "When summarizing user messages, convert first-person pronouns (my, I, me) to second-person (your, you)"
2. Post-processing: detect "You [verb] that my/I/me" patterns and flag as malformed
3. Consider this a subcategory of echo/passthrough - partial summarization but with pronoun leak

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

## Example 13: Request Misinterpreted as Observation

**Date Added:** 2025-12-08
**Category:** attribution error
**Transcript:** `12a75970-c8cf-4329-8fe0-41568627c506.jsonl`

**Entry:**
```json
{
  "detail": "great commit and push",
  "entry_id": "4b4a43f1-8a00-4806-9369-ad7fbac125e4",
  "summary": "You noted great commit and push.",
  "timestamp": "2025-12-08T20:00:38Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-personal-job-hunt-2025/12a75970-c8cf-4329-8fe0-41568627c506.jsonl"
}
```

**Problem:**
The message was "great. commit and push" - two separate ideas: (1) acknowledgment, (2) a request to commit and push. The summary misinterpreted this as an observation ("You noted") rather than recognizing the request/command portion.

**Expected Summary:**
- "You approved and asked Claude to commit and push."
- Or: "You requested a commit and push."

**Root Cause (suspected):**
- Punctuation/structure not parsed: "great. commit and push" has two clauses but was read as one phrase
- The imperative "commit and push" was not recognized as a command/request
- Inverse of Example 10: there a suggestion was misread as request, here a request was misread as observation

**Fix Approach:**
1. Recognize imperative verb patterns ("commit", "push", "run", "fix") as requests/commands
2. Parse multi-clause messages: period or comma often separates acknowledgment from request
3. "You noted" should be reserved for actual observations, not commands

---

## Example 14: Fragment Echo with Duplicate Attribution

**Date Added:** 2025-12-10
**Category:** attribution error (fragment echo)
**Transcript:** `f71cbb6a-1cd3-4df3-b1c8-aa62cb065c43.jsonl`

**Entry:**
```json
{
  "detail": "Good draft - authentic tone, valuable content structure. A few things to tighten up:\n\n**Title missing** - The draft recommended: \"Your Claude Code history auto-deletes after 30 days. I built something to fix that.\" - did you pick one?\n\n**Queue section header is misleading** - \"CC's Queue System changed in 2.0.50\" implies a regression, but the body just explains how it works. Based on your earlier investigation, the regression claim was inaccurate. I'd retitle to just:\n\n> **Claude Code's Queue System**\n\nor \n\n> **Understanding the Queue System**\n\n**Typos:**\n- \"stop_reasonmismatches\" → \"stop_reason mismatches\"\n- \"included it its thinking\" → \"included it in its thinking\"\n\n**Consider adding engagement questions** - The draft had these at the end to drive comments:\n\n> 1. Do you keep your Claude Code conversation history? Do you ever go back to it?\n> 2. Would you want Claude Code to be able to search its own past sessions?\n> 3. What other features would be useful?\n\n**Missing \"free\" callout** - Nowhere does it explicitly say the app is free. The draft had a \"**Pricing: Free.**\" section. Worth adding since that's a strong hook.\n\n**Optional - credibility** - You could mention FileKitty if you want (\"from the maker of FileKitty\" hit HN front page), but fine to skip if you'd rather let this stand on its own.\n\nOtherwise looks ready. Want me to produce a clean final version with these fixes?",
  "entry_id": "d5c4abf7-be15-4ae3-aad4-80a4ab049c45",
  "summary": "Claude Code Claude Code's Queue System",
  "timestamp": "2025-12-10T18:11:22Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/f71cbb6a-1cd3-4df3-b1c8-aa62cb065c43.jsonl"
}
```

**Problem:**
The summary is "Claude Code Claude Code's Queue System" - gibberish with "Claude Code" duplicated. The LLM extracted the markdown header suggestion `> **Claude Code's Queue System**` from the content, then prepended the standard "Claude Code" attribution, resulting in a nonsensical duplicate. The actual content is detailed feedback on an HN draft post.

**Expected Summary:**
- "Claude Code reviewed the HN draft, suggesting title changes, typo fixes, and engagement questions."
- Or: "Claude Code provided detailed feedback on the post draft including header, typos, and pricing callout."

**Root Cause (suspected):**
- Markdown blockquote headers (`> **Claude Code's Queue System**`) were extracted as if they were the message topic
- The attribution prefix "Claude Code" was added to text that already started with "Claude Code's"
- Long, structured feedback with multiple markdown elements confused the summarization into fragment extraction mode

**Fix Approach:**
1. Detect when extracted text already contains "Claude Code" and skip redundant attribution
2. Recognize blockquote patterns (`> **...`) as quoted suggestions, not the actual message topic
3. For detailed review/feedback messages, summarize the action ("reviewed", "provided feedback") rather than extracting fragments

---

## Example 15: Timeout on Markdown Table Echo

**Date Added:** 2025-12-16
**Category:** markdown table in summary output
**Transcript:** `9923fab6-535a-4930-95f4-ba917e7d135e.jsonl`

**Entry:**
```json
{
  "detail": "Done. \n\n| Alias | Path | Port |\n|-------|------|------|\n| `gdrive` | `~/code/consulting/openai/repos/gheeggle` | 3000 |\n| `gdrivewb` | `~/code/consulting/openai-workerbee/repos/gheeggle` | 4000 |\n\nRun `source ~/.zshrc` or open a new terminal to use `gdrivewb`.",
  "entry_id": "58b3e004-bcad-4900-ba1b-4292b204e8ee",
  "summary": "Done. \n\n| Alias | Path | Port |\n|-------|------|------|\n| `gdrive` | `~/code/consulting/openai/repos…",
  "timestamp": "2025-12-16T17:46:09Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-consulting-openai-workerbee/9923fab6-535a-4930-95f4-ba917e7d135e.jsonl"
}
```

**Error Message:**
> "2 conversation entries failed to generate summaries. Top error: Generation timed out. Summary generation took too long and was cancelled."

**Problem:**
The summary is a truncated echo of the detail, which contains a markdown table. Reported as a timeout, but the actual failure mode appears to be the LLM echoing table content rather than summarizing. The truncation with "…" suggests fallback behavior after the timeout.

**Expected Summary:**
- "Claude Code configured shell aliases for the gdrive and gdrivewb repositories with their respective ports."
- Or: "Claude Code set up two project aliases pointing to OpenAI repos on ports 3000 and 4000."

**Root Cause (suspected):**
- Markdown tables trigger echo/passthrough behavior (similar to Example 1)
- The timeout may be a secondary symptom - LLM may loop or stall when attempting to summarize tabular data
- Alternatively, the response exceeded token limits causing truncation
- User notes "not sure if gen length was what really happened" - timeout may be a red herring

**Fix Approach:**
1. Pre-process: detect markdown tables (`|---|`) and either strip or convert to prose before summarization
2. Investigate timeout thresholds - if tables trigger longer processing, may need special handling
3. Add post-processing to detect table markers in output and reject/regenerate
4. Consider whether tables should bypass LLM summarization entirely and use template: "Claude Code displayed [N]-row table of [topic]"

---

## Example 16: File Path Treated as Command

**Date Added:** 2025-12-24
**Category:** attribution error
**Transcript:** `68547b5c-474b-4257-a612-dd24a773f97f.jsonl`

**Entry:**
```json
{
  "detail" : "/private/tmp/v7-is-a-real-step-up.md  ultrathink",
  "entry_id" : "e89aea55-543a-4507-820f-47520301eb8f",
  "summary" : "You performed the following command: /private/tmp/v7-is-a-real-step-up.md ultrathink.",
  "timestamp" : "2025-12-24T23:17:42Z",
  "transcript_path" : "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify-worker-bee/68547b5c-474b-4257-a612-dd24a773f97f.jsonl"
}
```

**Problem:**
The summary says "You performed the following command" - interpreting the file path `/private/tmp/v7-is-a-real-step-up.md` as a slash command. The detail appears to be file path + mode metadata (ultrathink), not a user-issued command.

**Expected Summary:**
- "You referenced the file v7-is-a-real-step-up.md with ultrathink mode."
- Or contextual: "You pointed to a document about version 7 improvements."

**Root Cause (suspected):**
- Leading slash in file path (`/private/tmp/...`) was misinterpreted as a slash command prefix
- The summarization prompt may not distinguish between `/command` patterns and `/path/to/file` patterns
- "ultrathink" suffix may have reinforced the "command with argument" interpretation

**Fix Approach:**
1. Add heuristic: paths with multiple slashes and file extensions are file paths, not commands
2. Adjust prompt to recognize absolute paths (starting with `/`) as file references, not commands
3. Pattern match: if string matches `/[a-z]+/...` with slashes throughout, treat as path not command

---

## Example 17: Internal Monologue Literal Echo

**Date Added:** 2025-12-25
**Category:** attribution error (echo/passthrough)
**Transcript:** `fa5ca5f3-f3a4-4748-b363-5ed449e483cc.jsonl`

**Entry:**
```json
{
  "detail": "Build succeeds, tests pass. Let me stop messing around and actually do the wiring.\n\nLet me read the ViewportTrackingCoordinator to understand its API, then read the ConversationMonitor viewport methods that need to delegate to it:",
  "entry_id": "645f7de3-3c9a-4755-903d-c6b08e4e8660",
  "summary": "Build succeeds, tests pass. Let me stop messing around and actually do the wiring.\n\nLet me read the …",
  "timestamp": "2025-12-26T07:53:07Z",
  "transcript_path": "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/fa5ca5f3-f3a4-4748-b363-5ed449e483cc.jsonl"
}
```

**Problem:**
The summary is a truncated literal echo of Claude's internal monologue. No summarization occurred - just passthrough with truncation. The casual phrasing ("Let me stop messing around") and transitional statements shouldn't appear verbatim in a summary.

**Expected Summary:**
- "Claude Code confirmed build/tests pass and began wiring ViewportTrackingCoordinator."
- Or: "Claude Code verified build success and started reading viewport coordinator files."

**Root Cause (suspected):**
- Similar to Examples 2, 3, 6: passthrough behavior on Claude's own messages
- Conversational/informal language ("stop messing around") may bypass summarization logic
- Transitional phrases ("Let me read...") being echoed instead of summarized as actions

**Fix Approach:**
1. Detect transitional patterns ("Let me X...", "I'll read...") and summarize the action not the announcement
2. Strip conversational filler before summarization
3. For Claude messages that describe intent, summarize what Claude did/is doing, not the phrasing

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
