---
session_id: ceb6eaf1-17dd-45f6-bd81-ed25b748e96c
date: 2026-03-26
project: contextify
branch: ct-671-total-recall-analysis
status: ready-for-review
---

# Total Recall: CLI and Skill Improvements

Comprehensive analysis of Total Recall friction points and improvement proposals, derived from 38 real invocations across 5 analysis batches, 29 sessions, covering the period 2026-03-01 to 2026-03-25.

This document supersedes `product-improvements.md` (13 items) with an expanded analysis (25 proposals).

## 1. Executive Summary

### Methodology

Every Total Recall invocation during the analysis period was captured in raw batch files (tr-analysis-batch-1 through tr-analysis-batch-5), each recording the query text, CLI arguments, outcome, workarounds, user satisfaction, category classification, and friction points. References in this document use batch:id format (e.g., 3:batch3-4 means batch 3, invocation batch3-4).

### Scope

- **38 invocations** across **29 sessions** in **5 analysis batches**
- Invocations by category: decision-archaeology (10), negative-proof (9), implementation-reference (7), debugging (7), session-opener (4), cross-session-continuity (3), other (4)
- 9 invocations delegated to researcher subagents; 5 invocations where the AI bypassed the skill entirely

### Key Findings

**Success rates:** 24 successes (63.2%), 4 partial successes (10.5%), 5 failures (13.2%), 5 not-applicable/preempted (13.2%). Excluding not-applicable cases, the effective success rate is 72.7%.

**Agent delegation is the most reliable pattern.** All 9 agent-delegated invocations succeeded (100%), compared to approximately 65% for direct skill invocations. The agent's ability to run multiple searches with iterative refinement accounts for the difference.

**Context drilldown is nearly always needed.** 29 of 33 invocations that produced results required a follow-up `contextify context` call. Snippets alone were sufficient in only 4 cases, indicating the default snippet length (10 tokens) is too short.

**Negative proof is the second most common use case.** 9 of 38 invocations (24%) sought to confirm the absence of a topic in conversation history. There is no dedicated support for this pattern, and each requires 2-4 searches to establish confidence.

**FTS5 hyphen tokenization is a recurring hard failure.** Hyphenated identifiers (cli-ai-setup, review-loop, ct-361) are ubiquitous in software development. FTS5 splits them on hyphens, causing hard errors ("no such column: ai") or zero results. This failure mode appeared in batches 2, 3, and 5 despite SKILL.md documentation.

**The "Multiple Contextify installs detected" warning appears in every invocation** across all 5 batches, making it the most consistent UX friction point in the dataset.

---

## 2. Friction Taxonomy

Every friction point observed during the 38 invocations, categorized by type. Each entry lists the specific invocations where the friction was observed, the severity, and the current workaround if any.

### 2.1 Query Construction Failures

**Description:** Cases where the AI built suboptimal queries: too narrow a `--days` window, gave up too early, used overly specific phrases for FTS5, or failed to try synonyms and morphological variants.

**Severity:** High | **Frequency:** 7 of 38 invocations

| Invocation | Description |
|------------|-------------|
| 3:batch3-4 | `--days 30` and `--days 60` used for exploratory "lost work" search; never widened to 365; zero results; AI concluded "not found" without retrying |
| 3:batch3-6 | Single search with exact multi-word phrase "review-loop refactor multi-session browser pool chatgpt"; zero results; no retry; immediate pivot to git log |
| 3:batch3-3 | Two searches with similar phrasing for gcal CLI shell file; both returned cross-project noise; no attempt to filter or reframe; gave up quickly |
| 2:tr-006 | Searching for "cc-" prefix as a short token; FTS5 matched entry IDs, abbreviations, filenames; 80 results, all noise; no narrowing strategy |
| 1:inv-001 | Required 4 rounds due to technical false positives (regex flag -qE matching "QE", CI scripts matching "QA"); multiple refinement rounds needed |
| 4:B4-013 | 30-day window for checking when a task was "last touched"; window may have been too narrow for older work |
| 5:tr-batch5-003 | 14-day window used for cross-worktree audit of "recent work"; could miss work from 15-30 days ago that is still recent in project terms |

**Sub-patterns identified:**

- **Narrow days window (4 instances):** AI defaults to 7-30 day windows for exploratory searches about "lost work" that may be weeks or months old. Observed in batch3-4, batch3-6, B4-013, tr-batch5-003.
- **Early abandonment (3 instances):** AI gives up after 1-2 failed attempts without trying synonym expansion, prefix matching, or days widening. Observed in batch3-3, batch3-4, batch3-6.
- **Phrase too specific (2 instances):** Multi-word phrases with specific technical terms are too specific for FTS5 to match. Observed in batch3-6, tr-006.

**Current workaround:** Agent delegation provides better query construction; direct skill invocations with small `--days` windows are most failure-prone.

---

### 2.2 FTS5 Tokenization Issues

**Description:** FTS5 treats hyphens, underscores, and most punctuation as token separators. Hyphenated identifiers (review-loop, cli-ai-setup, ct-361) are split into separate tokens, leading to column-not-found errors or unexpected match behavior.

**Severity:** High | **Frequency:** 4 of 38 invocations

| Invocation | Description | Error Type |
|------------|-------------|------------|
| 2:tr-003a | "cli-ai-setup" tokenized as [cli, ai, setup]; "ai" interpreted as column name; produced hard error: "no such column: ai" | Hard error |
| 5:tr-batch5-004 | "review-loop" returned zero results; had to reformulate as `"review loop"` (quoted phrase without hyphen) after 4 search variations | Zero results |
| 3:batch3-2 | "auto-compact" and "claude-patch" required careful quoting; SKILL.md documents this but AI still struggled | Zero results |
| 2:tr-006 | "cc-" as a search prefix is tokenized, making it match "cc" as an isolated token in entry IDs, filenames, and abbreviations indiscriminately | Excess noise |

**Error taxonomy:**

- **Hard error:** FTS5 interprets a split token as a column reference, causing the query to fail entirely. Example: "no such column: ai" from "cli-ai-setup".
- **Zero results:** The hyphenated term is split and the individual tokens do not match as expected. Example: "review-loop" returns 0 results because the database stores "review-loop" as two separate tokens.
- **Excess noise:** A short token fragment from the split matches far too many unrelated entries. Example: "cc-" matches 80 results including entry IDs, abbreviations, and filenames.

**Current workaround:** SKILL.md documents hyphen tokenization and recommends `CT AND 97` or `"CT 97"` forms. Despite this documentation, AIs still hit the issue in practice.

---

### 2.3 Output Quality Issues

**Description:** Cases where results were returned but lacked sufficient context, were too brief, or required extensive follow-up to be useful.

**Severity:** Medium | **Frequency:** 6 of 38 invocations

| Invocation | Description |
|------------|-------------|
| 2:tr-002 | Results referenced the creative project only "in passing," providing administrative context but not the actual project work or repo location |
| 2:tr-003a | Found 2 recent sessions but machine provenance was indeterminate, with no hostname/device_id in the data model. AI reported "I can't tell which machine produced any entry" |
| 3:batch3-2 | TR returned supporting context but the actual task ID required fallback to bloon CLI. TR output was "necessary but not sufficient" |
| 1:inv-001 | False positive interpretation required: -qE regex flag matching "QE," CI scripts matching "QA". AI needed multiple rounds to correctly discard false positives |
| 4:B4-012 | Agent ran async and completed after the design spec was already drafted. TR results validated decisions post-facto rather than informing them |
| 5:tr-batch5-003 | Coverage varied by worktree; project ID resolution was unreliable for some worktrees. Partial results required git/bloon fallback |

**Missing data fields that contributed to output quality issues:**

- Hostname/device_id for machine provenance attribution
- Worktree name in result metadata for cross-worktree searches
- Confidence score explaining why a result was ranked at a given position

**Current workaround:** Context drilldown (`contextify context`) used after nearly every search. Snippets alone were sufficient in only 4 of 33 successful invocations.

---

### 2.4 Skill Guidance Gaps

**Description:** Cases where the SKILL.md guidance failed to prevent observed failure modes or did not address specific scenarios the AI encountered.

**Severity:** Medium | **Frequency:** 5 of 38 invocations

| Invocation | Gap |
|------------|-----|
| 3:batch3-4 | Skill did not prevent AI from using narrow `--days` windows for exploratory searches about "lost work." AI needed to widen from 30 to 365 but did not |
| 3:batch3-5 | AI substituted quick inline search for the user-requested agent-delegated thorough search. Skill does not require agent delegation for complex searches |
| 3:batch3-6 | Skill guidance about phrase decomposition was not followed. Single overly-specific phrase used with no fallback |
| 2:tr-001 | Queue injection pattern caused TR to run in parallel with filesystem search. No guidance about when TR is redundant or superseded |
| 1:inv-005 | Query was framed as a question ("When was...? Which session created it?") rather than keywords. Skill worked correctly here but could be more explicit about keyword-first framing |

**Specific gaps identified:**

- **No days escalation rule:** Skill does not specify: if 0 results on `--days 30`, try 90; if still 0, try 365.
- **No agent delegation trigger:** Skill does not specify when to delegate vs run inline. "For complex multi-query searches" is vague.
- **No systematic hyphen pre-check:** Skill documents FTS5 behavior but does not give a systematic pre-search check for hyphens in query terms.
- **No guidance on parallel search supersession:** No guidance for when filesystem or other searches succeed before TR completes.

**Current workaround:** Agent delegation produces better results (9 of 9 agent-delegated invocations succeeded); direct skill invocations have a higher failure rate.

---

### 2.5 Fallback Behaviors

**Description:** What the AI did when Total Recall failed or was insufficient. Fallback behaviors indicate what TR should ideally be doing.

**Severity:** Medium | **Frequency:** 6 of 38 invocations

| Invocation | Fallback Used | Effectiveness |
|------------|---------------|---------------|
| 3:batch3-6 | `git log` used after TR returned 0 results for review-loop refactor. Git log showed 12+ relevant commits | High for recent commit history |
| 3:batch3-3 | Direct system lookup (`which gcal && ls -la`) used after TR returned only cross-project noise | High for locating installed tools |
| 3:batch3-2 | `bloon CLI` used to find the actual task ID after TR returned supporting context but not the specific answer | High for task metadata |
| 4:B4-002 | `bloon show ct-10` and `git log` used instead of TR entirely. User had explicitly requested TR | Medium (correct answer, wrong tool) |
| 2:tr-001 | Filesystem traversal completed the task before TR results arrived. TR became redundant | High (faster tool won) |
| 3:batch3-4 | After TR returned 0 results, AI pivoted to explaining why the patcher had failed from current context, bypassing the original search intent | Low (missed prior session information) |

**Key insight:** Fallback tools (git log, filesystem, bloon) serve different purposes than TR. TR provides conversation history; these tools provide code/task metadata. The fallbacks indicate TR failing when it should have succeeded, not competition between tools.

---

### 2.6 False Positives

**Description:** Cases where TR returned results that appeared relevant but were actually unrelated, requiring the AI to spend time discarding noise.

**Severity:** Medium | **Frequency:** 4 of 38 invocations

| Invocation | False Positive Type | Description |
|------------|---------------------|-------------|
| 1:inv-001 | Technical content overlap | Regex flag `-qE` in shell scripts matched "QE"; project QA testing activity matched "QA". Required 4 searches to confirm negative |
| 1:inv-004 | Self-reference | Current session's own mention of "Paperbark Maple" ranked as top result. AI's prior statement outscored older relevant entries |
| 3:batch3-3 | Cross-project token collision | "gcal" matched GheeCalendar project results. Short token search for a specific tool name returned results from a different project |
| 2:tr-006 | Technical content overlap + short token | "cc-" matched entry IDs starting with "cc," Claude Code abbreviation, filenames with "cc" prefix. 80 results, all noise for the specific event being sought |

**False positive types:**

- **Technical content overlap:** Technical artifacts (regex flags, filenames, abbreviations) share tokens with the conceptual search terms. Examples: `-qE` matching "QE," `cc` prefix matching Claude Code.
- **Self-reference:** Current session entries where the AI itself mentioned the search term in prior turns outrank older, more relevant historical entries. Example: "Paperbark Maple" mentioned by AI in current session ranked #1.
- **Cross-project token collision:** Short or common tokens match results from unrelated projects. Examples: "gcal" matching GheeCalendar, "cc" matching Claude Code abbreviation.

**Current workaround:** The `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID` mechanism exists in SKILL.md for self-reference detection, but the AI does not consistently use it.

---

### 2.7 UX Friction

**Description:** Usability issues that create noise or confusion without blocking functionality.

**Severity:** Low (noise items) to High (silent wrong results) | **Frequency:** 6 of 38 invocations

**Note:** The multi-install warning is low severity but high frequency. The silent wrong-scope resolution (2:tr-003a) is high severity, a correctness bug that now drives F-03 to P0. Cost opacity is low-medium unless agent economics are explicitly productized.

| Invocation | Issue | Impact |
|------------|-------|--------|
| All batches | "Multiple Contextify installs detected" warning appeared in every invocation across all sessions in all 5 batches | Low severity, high frequency noise; trains users/AIs to ignore warnings |
| 2:tr-006 | Sibling tool call error on `contextify context` fetch. Error message was opaque: "Sibling tool call errored" with no actionable detail | Investigation dead-ended |
| 2:tr-003a | `--project` flag defaulted to cwd project instead of looking up by project name. Error was silent; returned wrong project results | **High severity**: silent wrong results (correctness bug) |
| 3:batch3-5 | AI delegation bypassed Skill layer when user explicitly requested it. User had to call this out to get proper agent-delegated search | User trust erosion |
| 4:B4-003 | 80,896 token subagent for a 1.5.0 release plan search. Token cost of agent delegation was not visible to user | Cost opacity |
| 4:B4-004 | 90,049 token subagent for pricing history search across 8 queries. High cost for an ultimately negative proof | Cost opacity |

---

### 2.8 Missing Capabilities

**Description:** Things users wanted that TR could not provide, based on observed failure modes and user frustration signals.

**Severity:** High | **Frequency:** 6 of 38 invocations

| Invocation | Missing Capability | Current Impact |
|------------|-------------------|----------------|
| 2:tr-003a | Machine provenance: no hostname or device_id field in data model. Request to "verify cross-machine cloud sync" is fundamentally impossible | Cross-machine attribution impossible |
| 5:tr-batch5-003 | Cross-worktree status audit: no dedicated mode for holistic summary of all worktrees. Required 10+ commands plus git/bloon fallbacks | 10+ commands for a single question |
| 3:batch3-4, 3:batch3-5 | Lost session recovery: no mechanism to find sessions indexed under different terminology or project IDs | Genuine negatives indistinguishable from bad queries |
| 2:tr-003b | Indexing window transparency: no way to know if content is "not indexed yet" vs "does not exist" | False negative confidence |
| 4:B4-002 | Conversation history about a decision: user wanted TR to confirm what was reverted and why, but AI used bloon + git instead | Right tool skipped |
| 2:tr-006 | Incident forensics for a specific creation event: TR can find general discussions but cannot pinpoint a specific AI action within a session | Insufficient granularity |

---

## 3. Feature Proposals

25 proposals organized by priority, each derived from observed friction points. The proposals span three implementation areas: CLI changes (ct-675), SKILL.md behavior changes (ct-676), and new capabilities (ct-677).

### Summary Table

| ID | Title | Priority | Effort | Area |
|----|-------|----------|--------|------|
| F-01 | Suppress "Multiple Contextify installs detected" warning | P0 | XS | CLI |
| F-02 | FTS5 hyphen pre-processing in CLI | P0 | S | CLI |
| F-03 | --project flag name-based lookup | P0 | S | CLI |
| F-07 | Unified zero-result protocol in SKILL.md (merges F-07/F-11/F-13) | P0 | XS | Skill |
| F-08 | Pre-search hyphen detection checklist | P0 | XS | Skill |
| F-04 | Raise --snippet-tokens default to 50 | P1 | XS | CLI |
| F-05 | Better FTS5 error messages | P1 | XS | CLI |
| F-09 | Negative proof guidance (simplified) | P1 | S | Skill |
| F-10 | Skill invocation vs agent delegation (separated) | P1 | XS | Skill |
| F-14 | Query broadening strategy (synonyms, prefix) | P1 | XS | Skill |
| F-15 | --snippet-tokens default guidance | P1 | XS | Skill |
| F-06 | --exclude-session flag for self-hit filtering | P2 | S | CLI |
| F-12 | Self-referential hit awareness | P2 | XS | Skill |
| F-16 | Indexing window transparency in status | P2 | S | New Capability |
| F-17 | Search scope summary in output | P2 | S | New Capability |
| F-18 | Session-opener digest mode | P2 | M | New Capability |
| F-19 | Negative proof formatting mode | P2 | M | New Capability |
| F-20 | Auto-widening search (0-result retry) | P2 | M | New Capability |
| F-21 | Cross-project search improvements | P3 | M | New Capability |
| F-22 | Machine/device provenance | P3 | M-L | New Capability |
| F-23 | Agent-optimized compact output mode | P3 | M | New Capability |
| F-24 | Result deduplication (--unique-sessions) | P3 | S | New Capability |
| F-25 | Batch task verification | P4 | L | New Capability |

---

### P0: Critical / Fix Immediately

#### F-01: Suppress "Multiple Contextify installs detected" Warning

- **Priority:** P0 | **Effort:** XS (~10 lines changed)
- **Evidence:** All 5 batches, every single invocation. The most consistent UX friction point across the entire 38-invocation dataset.
- **Impact:** Eliminates constant visual noise from every TR invocation. Prevents training users and AIs to ignore warnings. Improves perceived tool reliability.
- **Approach:** In `Contextify/ContextifyQueryShim/main.swift:174-177`, bring the shim's warning behavior into parity with the CLI's existing deprecation warning model: (1) only emit when stderr is a TTY (matching the CLI's `isStderrTTY()` pattern), (2) suppress when `CONTEXTIFY_NO_DEPRECATIONS=1` is set. This is more robust than relying on SKILL.md to export an env var, since it catches all callers including direct CLI usage and non-skill invocations.

#### F-02: FTS5 Hyphen Pre-processing in CLI

- **Priority:** P0 | **Effort:** S (~50 lines)
- **Evidence:** 2:tr-003a (hard error from "cli-ai-setup"), 5:tr-batch5-004 (4 search variations for "review-loop"), 3:batch3-2 ("auto-compact" required careful quoting), 2:tr-006 ("cc-" prefix noise).
- **Impact:** Eliminates the most common hard failure mode. Hyphenated identifiers are ubiquitous in software development (project names, branch names, task IDs like ct-361).
- **Approach:** In `Sources/ContextifyQueryCLI/main.swift`, add a query pre-processing step before the FTS5 query reaches the database. Rewrite rules: (1) bare unquoted hyphenated alnum tokens like `cli-ai-setup` become `"cli ai setup"` (quoted phrase, hyphens removed), (2) task ID patterns like `ct-361` become `ct AND 361` (better precision than phrase quoting), (3) trailing-hyphen fragments like `cc-` are ambiguous and should NOT be auto-rewritten; instead emit a targeted hint to stderr suggesting the user quote or expand the term, (4) preserve already-quoted terms, wildcard suffixes, and FTS5 operators exactly as written. This is complementary to the SKILL.md guidance (F-08) but catches cases where the AI forgets.

#### F-03: --project Flag Name-based Lookup

- **Priority:** P0 | **Effort:** S (~30 lines)
- **Evidence:** 2:tr-003a (`--project` defaulted to cwd instead of looking up by name; required UUID workaround via `contextify projects --json`). Silent wrong-scope results are a correctness problem, more damaging than guidance-only fixes.
- **Impact:** Eliminates silent wrong results. A two-step lookup (list projects, copy UUID, re-run) is a poor fallback for a correctness bug.
- **Approach:** When `--project <value>` is provided and value is not ".": (1) try exact/normalized name match against project `displayName` (case-insensitive, trimmed); (2) if the argument is an existing filesystem path, resolve it as a path; (3) if neither matches, error loudly with fuzzy suggestions from `contextify projects` (but never auto-select a fuzzy match silently, as that would replace one silent wrong-scope failure with another); (4) if multiple exact matches exist (unlikely but possible with worktrees), error listing all candidates. The key constraint: fuzzy matching is for suggestions only, never for silent auto-selection.

#### F-07: Unified Zero-Result Protocol in SKILL.md (merges F-07/F-11/F-13)

- **Priority:** P0 | **Effort:** XS (~30 lines of SKILL.md text)
- **Evidence:** 3:batch3-4 (`--days 30/60`, never widened to 365, 0 results), 3:batch3-6 (single attempt at `--days 120`, immediate pivot to git log), 4:B4-013 (`--days 30` could have missed older work), 5:tr-batch5-003 (`--days 14` for cross-worktree audit).
- **Impact:** Would have prevented 3-4 failures in the dataset. The mismatch between query window and actual history window is the primary cause of false negatives.
- **Note:** This proposal consolidates the previously separate F-07 (days escalation), F-11 (default days per query type), and F-13 (mandatory retry before failure) into a single coherent decision tree. The skill should have one zero-result protocol, not three overlapping rules.
- **Approach:** Replace the current soft guidance with a single mandatory decision tree: (1) classify intent (lookup, exploratory, negative-proof, debugging), (2) choose starting `--days` from a table (lookup: 90, exploratory: 365, negative-proof: 365, debugging: 30), (3) run search, (4) if 0 results, follow zero-result protocol: widen days (30->90->365), try prefix matching, try without `--project` (for exploratory/negative-proof only, not for clearly repo-scoped debugging), (5) only declare "not found" after completing the protocol. Skipping these steps is a skill violation.

#### F-08: Pre-search Hyphen Detection Checklist

- **Priority:** P0 | **Effort:** XS (~15 lines of SKILL.md text)
- **Evidence:** 2:tr-003a, 5:tr-batch5-004, 3:batch3-2, 3:batch3-6.
- **Impact:** Prevents the AI from hitting FTS5 hyphen errors in the first place. The SKILL.md already documents FTS5 behavior but does not give a systematic pre-search check.
- **Approach:** Add a Step 1.5 ("Check for special characters") to the SKILL.md query construction section: scan each search term for hyphens (remove and quote), underscores (remove and quote), task IDs like ct-NNN (use `CT AND NNN`), and dots (quote). Note any reformulation in the response.

---

### P1: High Priority

#### F-04: Raise --snippet-tokens Default to 50

- **Priority:** P1 | **Effort:** XS (single line change)
- **Evidence:** Context drilldown was used in 29 of 33 successful invocations. The 10-token default generates snippets too short to evaluate relevance. Only 4 invocations got sufficient information from snippets alone. Most manual overrides used 50 tokens (11 times), suggesting 50 is the natural working default.
- **Impact:** Reduces follow-up `contextify context` calls by an estimated 50-70%.
- **Approach:** In `Sources/ContextifyQueryCLI/main.swift:521`, change `options.snippetTokens ?? 10` to `options.snippetTokens ?? 50`.

#### F-05: Better FTS5 Error Messages

- **Priority:** P1 | **Effort:** XS (~20 lines)
- **Evidence:** 2:tr-003a ("no such column: ai" from "cli-ai-setup"). The error message is cryptic and gives no hint about the root cause.
- **Impact:** When the CLI pre-processor (F-02) misses a case, the error message guides the AI to fix it immediately rather than floundering.
- **Approach:** Catch GRDB/SQLite FTS5 errors containing "no such column" and wrap with a helpful message: `Search error: FTS5 interpreted 'ai' as a column name (from hyphenated term 'cli-ai-setup'). Try quoting: "cli ai setup" or use: cli AND ai AND setup`.

#### F-09: Negative Proof Guidance (Simplified)

- **Priority:** P1 | **Effort:** S (~25 lines skill text)
- **Evidence:** 9 of 38 invocations (24%) were negative proof: 1:inv-001, 2:tr-003b, 3:batch3-4, 4:B4-004, 4:B4-013, 4:B4-014, 4:B4-015, 5:tr-batch5-004, and others. Each required 2-4 searches to confirm absence.
- **Impact:** Standardizes the most common non-lookup use case. Reduces false negatives from premature abandonment.
- **Approach:** Add a "Negative proof" section to SKILL.md with lightweight guidance: (1) classify as negative-proof intent, (2) use `--days 365` and broad scope by default, (3) run 2-3 materially different query variations (original terms, synonym expansion, prefix matching), (4) only declare absence after at least one broad retry, (5) explicitly state the scope searched and any caveats (e.g., "searched 365 days across all projects; earlier history not indexed"). Formal confidence levels and structured metadata (like `--assert-absent`) are reserved for a future CLI mode (F-19), not skill guidance.

#### F-10: Skill Invocation vs Agent Delegation (Separated)

- **Priority:** P1 | **Effort:** XS (~15 lines)
- **Evidence:** 3:batch3-5 (AI substituted inline search for user-requested agent delegation), 4:B4-002 (AI bypassed skill entirely), 3:batch3-4 (failed inline search that should have been delegated). Agent delegation had 100% success rate (9/9) vs approximately 65% for direct invocations.
- **Impact:** Clarifies two separate decisions that the current skill conflates.
- **Approach:** The skill must distinguish two independent decisions: (a) **Use the Contextify CLI**: mandatory whenever the user invokes `/total-recall`. Never bypass to bloon, git log, or filesystem tools when the user explicitly requests TR. (b) **Delegate to researcher agent vs search inline**: delegate when the query is exploratory with vague terms, when cross-project search is needed, when first inline search returned 0 results and systematic widening is needed, or when negative proof requires multiple query variations. Search inline for simple lookups, specific entry IDs, or narrow time-bounded questions. These are orthogonal: a simple lookup should use the CLI inline; a complex search should use the CLI via agent delegation. Neither should bypass the CLI entirely.

#### F-14: Query Broadening Strategy

- **Priority:** P1 | **Effort:** XS (~20 lines)
- **Evidence:** 3:batch3-6 (multi-word phrase "review-loop refactor multi-session browser pool chatgpt" too specific for FTS5), 2:tr-006 ("cc-" too short/common), 1:inv-001 ("QE" matched regex flags).
- **Impact:** Prevents overly specific or overly broad queries from failing.
- **Approach:** Add a Step 3.5 ("Query complexity check") to SKILL.md: if query has 4+ AND-joined terms, split to the 2 most distinctive terms; if any term is 3 characters or fewer, combine with a qualifying term via AND; if searching for an acronym (QA, QE, CI, CD), also search for the expanded form.

#### F-15: --snippet-tokens Default Guidance in SKILL.md

- **Priority:** P1 | **Effort:** XS (~5 lines)
- **Evidence:** 29/33 successful invocations needed context drilldown. Most invocations that explicitly set `--snippet-tokens` used 50 (11 uses), 60 (4), or 80 (3).
- **Impact:** Aligns skill guidance with the new CLI default (F-04).
- **Approach:** Update SKILL.md to reflect the new 50-token default. Add guidance: use 80-100 for complex searches where more context helps, use 10-20 only for high-volume counting/triage.

---

### P2: Medium Priority

#### F-16: Indexing Window Transparency in Status

- **Priority:** P2 | **Effort:** S (~40 lines, possibly optimistic for per-project earliest/latest dates plus zero-result warnings)
- **Evidence:** 2:tr-003b (content predated indexing window; AI correctly reported this but had no way to know programmatically), 3:batch3-4 (0 results could have been "too old" or "never discussed").
- **Impact:** Enables the AI to distinguish "not discussed" from "predates indexed history." Useful for negative-proof confidence but not critical unless negative-proof confidence is a flagship product promise.
- **Approach:** Add `earliestEntryDate` and `latestEntryDate` to `contextify status --json` output. Add per-project dates to `contextify projects --json`. When search returns 0 results, check if the `--days` window predates the project's earliest entry and emit a warning.

#### F-06: --exclude-session Flag for Self-hit Filtering

- **Priority:** P2 | **Effort:** S (~20 lines CLI + ~5 lines skill)
- **Evidence:** 1:inv-004 (current session's "Paperbark Maple" mention ranked #1, burying the older relevant result).
- **Impact:** Eliminates self-referential false positives. Low frequency but easy to prevent.
- **Approach:** Add `--exclude-transcript <id>` flag to search command. In SKILL.md, instruct: pass `--exclude-transcript $CONTEXTIFY_CLAUDE_TRANSCRIPT_ID` to exclude current session results. Implementation: `AND e.transcriptId != ?` WHERE clause.

#### F-12: Self-referential Hit Awareness in SKILL.md

- **Priority:** P2 | **Effort:** XS (~10 lines)
- **Evidence:** 1:inv-004 (Paperbark Maple self-hit).
- **Impact:** Even without F-06, guidance helps the AI recognize and skip self-hits.
- **Approach:** Add guidance: check each result's transcriptId against `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID`; results from the current transcript are self-references; skip self-references when selecting anchors for context drilldown; report "Skipped N self-referential hits from current session."

#### F-17: Search Scope Summary in Output

- **Priority:** P2 | **Effort:** S (~30 lines)
- **Evidence:** 2:tr-003a (machine provenance unknown), 5:tr-batch5-003 (coverage varied by worktree), 3:batch3-4 (unclear if results represented full corpus or just one project).
- **Impact:** Adds transparency to search results so the AI and user can assess completeness.
- **Approach:** Add a `scope` object to search response metadata with fields: `projectsSearched`, `totalProjectsInDB`, `totalEntriesInDB`, `entriesInScope`, `daysWindow`, `earliestEntryInScope`. No SKILL.md changes needed; the AI can read and report it naturally.

#### F-18: Session-opener Digest Mode

- **Priority:** P2 | **Effort:** M (~150 lines)
- **Evidence:** 4:B4-001 (cloud service session opener, success), 5:tr-batch5-001 (lost work recovery, success), 5:tr-batch5-003 (cross-worktree audit, 10+ commands, partial), 5:tr-batch5-005 (navigation UX work recovery, success). All 4 session-opener invocations succeeded. 100% success rate, high user satisfaction. This is the most commercially compelling use case.
- **Impact:** Reduces a 10+ command workflow to a single command.
- **Approach:** New subcommand: `contextify digest --days 7 --project . --json`. Returns structured summary of recent activity: project name, worktree, last activity timestamp, transcript count, top topics (extracted from LLM-generated summaries already available), and optionally open tasks. Optional bloon integration for task context.

#### F-19: Negative Proof Formatting Mode

- **Priority:** P2 | **Effort:** M (~80 lines CLI + ~30 lines skill)
- **Evidence:** 9 of 38 invocations (24%) were negative proof. Each required 2-4 searches with no structured way to report the negative finding.
- **Impact:** Standardizes the most common non-lookup outcome with structured confidence reporting.
- **Approach:** Add `--assert-absent` flag to search. When used and 0 results found, return a structured negative proof response including: original query, confidence level, number of searches run, days searched, projects searched, entries scanned, earliest entry date, and conclusion. When results are found, behave identically to normal search.

#### F-20: Auto-widening Search (0-result Retry)

- **Priority:** P2 | **Effort:** M (~80 lines)
- **Evidence:** 3:batch3-4 (0 results at `--days 30/60`, never widened), 3:batch3-6 (0 results at `--days 120`, never retried), 4:B4-013 (30-day window could have missed older work).
- **Impact:** Catches the "narrow window, gave up" pattern at the CLI level, complementing the SKILL.md guidance (F-07).
- **Approach:** When search returns 0 results and `--days` was specified: retry with `--days` doubled (up to 365); if still 0, retry without project scope. Report widening in metadata (`autoWidened: true`, `originalDays`, `effectiveDays`, `wideningSteps`). Add `--no-auto-widen` flag to disable.

---

### P3: Nice to Have

#### F-21: Cross-project Search Improvements

- **Priority:** P3 | **Effort:** M (~100 lines)
- **Evidence:** 3:batch3-3 (gcal matched GheeCalendar), 5:tr-batch5-003 (project ID resolution unreliable across worktrees), 2:tr-003a (cross-project scope needed).
- **Impact:** Improves accuracy for users with many projects.
- **Approach:** Add `--all-projects` flag for explicit cross-project search. Add project name to result snippets (already present as `projectName`). Group results by project in output when multiple projects matched. Improve project name resolution for worktree variants.

#### F-22: Machine/Device Provenance

- **Priority:** P3 | **Effort:** M-L (schema migration + ingest-path population + null/backfill behavior for existing entries + output/filter integration across search, context, and entry commands)
- **Evidence:** 2:tr-003a (AI reported "I can't tell which machine produced any entry").
- **Impact:** Enables cross-machine attribution for multi-device users. Growing use case with cloud sync.
- **Approach:** Add `deviceId` column (populated from hostname at ingestion time) to entry table via schema migration v34. Expose in search, context, and entry output. Wire up the existing `--device` filter flag in CLI Options (already defined at line 164 but not fully connected). Handle null/backfill for existing entries that predate the migration (either backfill from hostname or leave null with explicit "unknown device" in output).

#### F-23: Agent-optimized Compact Output Mode

- **Priority:** P3 | **Effort:** M (~60 lines)
- **Evidence:** 4:B4-003 (80K tokens in subagent), 4:B4-004 (90K tokens), 4:B4-012 (226K output file).
- **Impact:** Reduces token cost for agent-delegated searches by an estimated 50-70%.
- **Approach:** Add `--compact` flag to search output. Returns only: entryId, score, timestamp, projectName, snippet (no full JSON envelope, no array nesting). Consider TSV format for absolute minimum token overhead. Consider `--top N` shorthand for `--limit N --compact`.

#### F-24: Result Deduplication

- **Priority:** P3 | **Effort:** S (~40 lines)
- **Evidence:** Implicit across exploratory searches where the same topic recurred in many sessions (4:B4-012, 3:batch3-2). AI must manually identify and skip duplicates.
- **Impact:** Reduces noise in exploratory searches.
- **Approach:** Add `--unique-sessions` flag that returns at most one result per transcript (highest-scoring entry per transcriptId). Implementation: `GROUP BY transcriptId` with `MAX(rank)` selection in the FTS5 query.

---

### P4: Future / Exploratory

#### F-25: Batch Task Verification

- **Priority:** P4 | **Effort:** L (~300 lines)
- **Evidence:** 4:B4-015 (two parallel agents triaging 20+ P1 tasks), 5:tr-batch5-003 (cross-worktree audit). This is an emerging power-user pattern, not yet common.
- **Impact:** Enables multi-task evidence searches without spawning multiple agents.
- **Approach:** New subcommand: `contextify verify-tasks --task-ids ct-361,ct-254,ct-547 --json`. For each task ID, search and report: found/not-found, latest mention date, snippet. Optional bloon integration for task metadata.

---

## 4. CLI Flag/Option Changes

Specific CLI changes proposed across the 25 feature proposals. All changes are backward compatible (additive flags or default changes).

### 4.1 --days Default and Auto-widening Behavior

**Current:** No default. AI chooses arbitrarily (7, 14, 30, 60, 90, 180, 365). SKILL.md examples show `--days 30`. Omitting `--days` means "all time."

**Proposed changes:**
1. **No CLI-level default change.** Omitting `--days` continues to mean "all time," which is correct.
2. **SKILL.md guidance (F-11):** Default `--days` per query type table (see Section 5).
3. **Auto-widening (F-20):** CLI retries with wider windows on 0 results. When search returns 0 and `--days` was specified, retry with doubled window (up to 365), then without project scope. Add `--no-auto-widen` to disable.
4. **Escalation rule (F-07):** SKILL.md mandates widening before declaring failure.

**Motivating invocations:** 3:batch3-4, 3:batch3-6, 4:B4-013, 5:tr-batch5-003

### 4.2 FTS5 Hyphen Handling (Pre-processing)

**Current:** Hyphens in query terms cause FTS5 to split tokens. "cli-ai-setup" becomes [cli, ai, setup], and "ai" is interpreted as a column reference.

**Proposed:**
1. **Pre-processing (F-02):** Detect bare hyphenated tokens matching `\b\w+-\w+(-\w+)*\b` and auto-quote with hyphens removed.
2. **Error wrapping (F-05):** Catch "no such column" FTS5 errors and return helpful reformulation suggestions.
3. **SKILL.md checklist (F-08):** Pre-search check for hyphens with reformulation examples.

No new flag required. This is automatic pre-processing. Queries without hyphens are unaffected. Already-quoted hyphenated terms are preserved.

**Motivating invocations:** 2:tr-003a, 5:tr-batch5-004, 3:batch3-2, 2:tr-006

### 4.3 Install Warning Suppression

**Current:** `Contextify/ContextifyQueryShim/main.swift:174-177` emits "Multiple Contextify installs detected" to stderr whenever `candidates.count > 1`. This fires on every invocation for users with multiple worktree builds.

**Proposed:** Three-tier suppression:
1. **Env var suppression:** Check `CONTEXTIFY_NO_INSTALL_WARNING=1` or extend `CONTEXTIFY_NO_DEPRECATIONS=1` to cover this warning.
2. **Non-interactive suppression:** Only emit when stderr is a TTY.
3. **SKILL.md update:** Set the suppression env var in all skill-invoked commands.

No new CLI flag. Env var controlled. Interactive users still see the warning.

**Motivating invocations:** All 38 invocations across all 5 batches.

### 4.4 --snippet-tokens Default

**Current:** Default 10 tokens (`main.swift:521`: `options.snippetTokens ?? 10`). Max 100.

**Proposed:** Default 50 tokens. Change line 521 to `options.snippetTokens ?? 50`. The JSON output structure is unchanged; scripts parsing fixed-length output may need adjustment, but longer snippets are strictly more informative.

**Motivating invocations:** 29/33 successful invocations required context drilldown. Most manual `--snippet-tokens` overrides used 50 (11 times).

### 4.5 --exclude-transcript Flag

**Current:** No way to exclude entries from a specific transcript.

**Proposed:** `--exclude-transcript <transcript-id>` excludes all entries from the specified transcript from search results.

**Syntax:** `contextify search "query" --exclude-transcript $CONTEXTIFY_CLAUDE_TRANSCRIPT_ID --json`

Additive flag. No change to existing behavior when omitted.

**Motivating invocations:** 1:inv-004 (self-referential hit)

### 4.6 --project Name Lookup Fix

**Current:** `--project <value>` is treated as a path when value is not ".". If the name does not match a filesystem path, it silently defaults to the cwd project.

**Proposed:** Try name-based lookup first (fuzzy match against project `displayName`). If exactly one match, use it. If zero matches, error with suggestions. If multiple matches, error listing all. Fall back to path lookup only after name lookup fails.

**Motivating invocations:** 2:tr-003a

### 4.7 New Flags Summary

| Flag | Proposal | Purpose |
|------|----------|---------|
| `--assert-absent` | F-19 | Structured negative proof response when 0 results found |
| `--exhaustive` | F-09 | Runs original query plus synonym expansion and prefix variants |
| `--compact` | F-23 | Minimal output: id, score, timestamp, projectName, snippet |
| `--unique-sessions` | F-24 | At most one result per transcript (highest-scoring entry) |
| `--no-auto-widen` | F-20 | Disables automatic search widening on 0 results |
| `--all-projects` | F-21 | Explicit cross-project search |
| `--exclude-transcript <id>` | F-06 | Excludes entries from a specific transcript |
| `--device <hostname>` | F-22 | Filters by device (already defined but not fully wired) |

---

## 5. Skill Behavior Changes

Changes to SKILL.md guidance that alter how the AI constructs and executes Total Recall queries. These are text changes to the skill definition, not code changes.

### 5.1 Retry/Widening Logic

**Current guidance (advisory, soft language):**
```
If search returns 0 results:
1. Widen --days (try 90, then 365)
2. If not clearly about current repo, retry without --project .
...
```

**Proposed guidance (mandatory, explicit):**
```
### Zero results protocol (MANDATORY)

If search returns 0 results, you MUST complete ALL steps before reporting "not found":

1. Widen time window: If --days < 365, re-run with --days 365
2. Drop project scope: Re-run without --project (search all projects)
3. Try prefix matching: Re-run with key terms as prefixes (deploy* instead of deploy)
4. Try synonym expansion: Add 2-3 synonyms (deploy OR release OR ship)

Only after completing steps 1-4 may you report "not found."
Report which steps you completed in your response.
```

**Expected impact:** Prevents 3-4 of the 5 failures observed in the dataset. Makes "not found" declarations trustworthy.

### 5.2 Query Broadening Strategy

**Proposed addition after Step 3:**

- **Too many terms:** If query has 4+ AND-joined terms, reduce to the 2 most distinctive terms. Example: "review-loop refactor multi-session browser pool chatgpt" is too specific; use "review loop" OR "browser pool" instead.
- **Too few characters:** If any search term is 3 characters or fewer, always pair with a qualifying term via AND. Example: "cc" alone matches 80 results; use "cc AND project AND create" instead.
- **Acronym awareness:** If searching for an acronym (QA, QE, CI, CD), also search for the expanded form: `"QA OR \"quality assurance\""`. Short acronyms have high false positive rates in code-heavy conversations.

### 5.3 Negative Proof Mode Guidance

**Proposed new section:**

When the user asks "did we ever...", "has this been discussed...", "is there any record of...":
1. Classify as negative proof intent and announce it.
2. Use maximum scope: `--days 365`, consider omitting `--project`.
3. Run at least 3 query variations: direct terms, synonym expansion, prefix matching.
4. Report structured findings: query, searches run, time window, projects searched, entries scanned, confidence level, conclusion.
5. Confidence levels: High (365 days, all projects, 3+ variations, 0 results), Medium (limited scope), Low (single search, narrow scope: do not report as negative proof).

### 5.4 Agent Delegation Criteria

**Current guidance:** "For complex multi-query searches, delegate to contextify-researcher agent." This is too vague.

**Proposed replacement:**

Delegate to researcher agent when:
- User explicitly invokes Total Recall ("/total-recall" or "use total recall")
- Negative proof requiring 3+ query variations
- Cross-project search across 3+ projects
- Exploratory search with vague terms
- First inline search returned 0 results and systematic widening is needed

Search inline when:
- Simple lookup with specific terms ("what is the server IP")
- Narrow time-bounded question ("what did we do yesterday")
- Count queries

Never bypass: if the user explicitly invokes Total Recall, the AI must use the contextify CLI. Do not substitute git log, bloon, or filesystem searches, even if they seem faster.

Token cost awareness: agent delegation costs 60-90K tokens per invocation. For simple lookups, prefer inline search. For complex searches, the higher token cost is justified by 100% success rate.

### 5.5 Self-referential Hit Awareness

**Current guidance (minimal):** "If CONTEXTIFY_CLAUDE_TRANSCRIPT_ID is set, down-rank hits from that transcript."

**Proposed expanded guidance:**

When searching for a term previously mentioned in the current conversation, the current session's entries may rank highest. Detection: check each result's transcriptId against `$CONTEXTIFY_CLAUDE_TRANSCRIPT_ID`. If they match, the result is a self-referential hit. Handling: skip self-referential hits when selecting anchors for context drilldown; use `--exclude-transcript` if available; report "Skipped N self-referential hits from current session"; if all top results are self-referential, paginate past them.

### 5.6 Default --days Per Query Type

Add a lookup table so the AI selects an appropriate `--days` value based on query intent rather than choosing arbitrarily:

| Intent | Default --days | Rationale |
|--------|---------------|-----------|
| Decision archaeology | 365 | Decisions may be months old |
| Negative proof | 365 | Must search full history |
| Session opener | 14 | Recent activity focus |
| Implementation reference | 90 | Recent work context |
| Debugging | 30 | Usually recent sessions |
| Cross-session continuity | 90 | May span multiple sessions |
| Counting | 365 | Need complete picture |

---

## 6. New Capability Proposals

Features that do not exist in the current CLI or skill and require new code or new subcommands.

### 6.1 Session-opener Mode (contextify digest)

**User story:** "As a developer starting a new session, I want to quickly see what was worked on recently across my projects so I can orient myself and pick up where I left off."

**Evidence:** 4 of 38 invocations (11%) were session openers: 4:B4-001 (cloud service session opener), 5:tr-batch5-001 (lost work recovery), 5:tr-batch5-003 (cross-worktree audit requiring 10+ commands), 5:tr-batch5-005 (navigation UX work recovery). All succeeded and directly unblocked substantial work, but required extensive manual search construction.

**Technical approach:** New subcommand `contextify digest [--days N] [--project .] [--json]`. Queries recent transcripts grouped by project and worktree. Extracts topic keywords from LLM-generated transcript summaries (already available). Returns structured summary including project name, worktree, last activity timestamp, transcript count, top topics, and optionally open tasks (via bloon integration).

**Priority:** P2 | **Effort:** M (~150 lines)

### 6.2 Search Scope Summary

**User story:** "As an AI assistant, I want to see how many projects, entries, and devices were searched so I can report search comprehensiveness to the user."

**Evidence:** 2:tr-003a (machine provenance unknown), 5:tr-batch5-003 (coverage varied by worktree), 3:batch3-4 (unclear if 0 results was "not in DB" or "bad query").

**Technical approach:** Add `scope` object to search response metadata: `projectsSearched`, `totalProjectsInDB`, `totalEntriesInDB`, `entriesInScope`, `daysWindow`, `earliestEntryInScope`. No new flags needed; always included in metadata. Extends `contextify status --json` with `earliestEntryDate` and `latestEntryDate` per project.

**Priority:** P2 | **Effort:** S (~30 lines)

### 6.3 Negative Proof Formatting

**User story:** "As a user asking 'did we ever discuss X,' I want a clear, structured answer about whether X was found or not, with confidence level and search methodology."

**Evidence:** 9 of 38 invocations (24%) were negative proof: 1:inv-001, 4:B4-004, 2:tr-003b, 4:B4-013, 4:B4-014, 5:tr-batch5-004, and others.

**Technical approach:** CLI `--assert-absent` flag (see Section 4.7). When used and 0 results found, returns structured response: query, confidence level, searches run, days searched, projects searched, entries scanned, earliest entry date, conclusion. Works with auto-widening (F-20) to automatically expand search scope before declaring absence.

**Priority:** P2 | **Effort:** M (~80 lines CLI + ~30 lines skill)

### 6.4 Auto-widening Search

**User story:** "As a user, when my search returns 0 results, I want the CLI to automatically try broader search parameters before telling me nothing was found."

**Evidence:** 3:batch3-4 (0 results at `--days 30/60`, never widened), 3:batch3-6 (0 results at `--days 120`, no retry), 4:B4-013 (30-day window could have missed older work).

**Technical approach:** When search returns 0 results and `--days` was specified: (1) if `--days` < 90, retry with 90; (2) if still 0, retry with 365; (3) if still 0, retry without project scope. Report widening in metadata. Add `--no-auto-widen` to disable. This is the CLI-level complement to SKILL.md escalation (F-07): the skill guides the AI to widen, and the CLI catches cases where the AI does not.

**Priority:** P2 | **Effort:** M (~80 lines)

### 6.5 Cross-project Improvements

**User story:** "As a user searching across my projects, I want accurate project name resolution and clear attribution of which project each result comes from."

**Evidence:** 3:batch3-3 ("gcal" matched GheeCalendar), 5:tr-batch5-003 (project ID resolution unreliable across worktrees), 2:tr-003a (cross-project scope needed).

**Technical approach:** (1) Add `--all-projects` flag for explicit cross-project search. (2) Group results by project in output when multiple projects matched. (3) Improve project name resolution for worktree variants so that searching for "contextify" correctly resolves across wb1-wb4.

**Priority:** P3 | **Effort:** M (~100 lines)

### 6.6 Device Provenance

**User story:** "As a multi-device user, I want to know which machine produced a given conversation entry so I can verify cross-device sync and attribute work correctly."

**Evidence:** 2:tr-003a ("I can't tell which machine produced any entry"). Growing use case with cloud sync rollout.

**Technical approach:** Add `deviceId` column (populated from hostname at ingestion time) to entry table via schema migration v34. Expose in search, context, and entry output. Wire up existing `--device` filter flag in CLI Options (already defined at line 164 but may not be fully connected).

**Priority:** P3 | **Effort:** M (~100 lines, schema migration)

### 6.7 Compact Output Mode

**User story:** "As an AI agent running multiple searches, I want compact output that minimizes token consumption while preserving key information."

**Evidence:** 4:B4-003 (80K tokens in subagent), 4:B4-004 (90K tokens), 4:B4-012 (226K output file). Token costs compound across frequent agent-delegated searches.

**Technical approach:** Add `--compact` flag to search. Returns minimal fields: id, score, timestamp, projectName, snippet. No envelope nesting. Consider TSV format for lowest token overhead. Consider `--top N` shorthand for `--limit N --compact`.

**Priority:** P3 | **Effort:** M (~60 lines)

### 6.8 Result Deduplication

**User story:** "As a user searching for a topic discussed across many sessions, I want to see the best result from each session rather than multiple entries from the same session saying similar things."

**Evidence:** Implicit across exploratory searches where the same topic recurred (4:B4-012, 3:batch3-2). AI must manually identify and skip duplicates.

**Technical approach:** Add `--unique-sessions` flag. Returns at most one result per transcript (highest-scoring entry per transcriptId). Implementation: `GROUP BY transcriptId` with `MAX(rank)` selection in the FTS5 query.

**Priority:** P3 | **Effort:** S (~40 lines)

### 6.9 Batch Verification

**User story:** "As a project manager, I want to check multiple task IDs against conversation history to find which ones have been discussed, completed, or left open."

**Evidence:** 4:B4-015 (two parallel agents triaging 20+ P1 tasks), 5:tr-batch5-003 (cross-worktree audit). This is an emerging power-user pattern, not yet common enough to justify the investment.

**Technical approach:** New subcommand: `contextify verify-tasks --task-ids ct-361,ct-254,ct-547 --json`. For each task ID, run a search and report: found/not-found, latest mention date, snippet. Optional bloon integration to auto-pull open task lists.

**Priority:** P4 | **Effort:** L (~300 lines)

---

## 7. Statistics Appendix

Summary statistics from the 38-invocation dataset.

### Cross-Document Reconciliation (Working)

The analysis package contains three documents that report slightly different figures. This table is a working reconciliation; some rows represent best-guess explanations rather than verified filtration rules.

**Inclusion criteria for the 38-invocation set:** Each invocation represents a distinct user-facing Total Recall request (user said "use /total-recall" or equivalent) that triggered at least one `contextify` CLI call. The 54 raw `Skill` tool_use events in the README include duplicates, sub-invocations within agent delegations, and retry attempts. The exact filtration from 54 to 38 was performed by the original analysis agents; the criteria are inferred from the batch files, not formally documented.

| Metric | This document | case-studies.md | README.md | Notes |
|--------|---------------|-----------------|-----------|-------|
| Total invocations | 38 | 38 | 54 skill invocations found, 38 analyzed | Best explanation: 54 raw events filtered to 38 distinct user-facing invocations. Exact filtration criteria not formally documented. |
| Sessions | 29 | 23 | 29 | 29 unique session files processed. Discrepancy with case-studies' 23 likely reflects counting methodology (some sessions had multiple invocations). |
| Success | 24 | 22 | n/a | Likely: this document counts "success" strictly; case-studies may classify some differently. |
| Partial success | 4 | 5 | n/a | Minor classification boundary difference. |
| Failure | 5 | 4 | n/a | This document counts one additional indeterminate case as failure. |
| Context drilldown | 29/33 (87.9%) | 28/38 (74%) | n/a | Different denominators: this doc uses result-bearing invocations (33); case-studies uses all invocations (38). |
| Batch 3 invocation count | 6 IDs (batch3-1 through batch3-6) | n/a | "5 invocations" | Raw file contains 6 entries. README counted 5 "actual skill tool_use" events; batch3-5 appears to be an agent continuation of batch3-4. |

**Note:** Category percentages exceed 100% because invocations are multi-labeled (an invocation can be both "decision archaeology" and "negative proof").

### Outcome Distribution

| Outcome | Count | Rate |
|---------|-------|------|
| Success | 24 | 63.2% |
| Partial success | 4 | 10.5% |
| Failure | 5 | 13.2% |
| Not applicable / preempted | 5 | 13.2% |

Effective success rate (excluding not-applicable): **72.7%**

### Category Distribution

| Category | Count | % of Total |
|----------|-------|------------|
| Decision archaeology | 10 | 26.3% |
| Negative proof | 9 | 23.7% |
| Implementation reference | 7 | 18.4% |
| Debugging | 7 | 18.4% |
| Session opener | 4 | 10.5% |
| Cross-session continuity | 3 | 7.9% |
| Other | 4 | 10.5% |

Note: Percentages exceed 100% because some invocations overlap categories.

### Common CLI Arguments

**--days values (across all invocations where explicitly set):**

| Value | Usage Count |
|-------|-------------|
| 365 | 12 |
| 90 | 7 |
| 30 | 7 |
| 180 | 6 |
| 7 | 4 |
| 60 | 4 |
| 14 | 3 |

**--limit values:**

| Value | Usage Count |
|-------|-------------|
| 10 | 14 |
| 15 | 12 |
| 20 | 10 |
| 5 | 2 |

**--snippet-tokens values (when explicitly set):**

| Value | Usage Count |
|-------|-------------|
| 50 | 11 |
| 60 | 4 |
| 80 | 3 |
| 30 | 3 |

### Agent Delegation

| Metric | Value |
|--------|-------|
| Agent-delegated invocations | 9 of 38 (23.7%) |
| Agent delegation success rate | 9 of 9 (100%) |
| Direct skill invocation success rate | ~65% |
| Skill bypassed (direct contextify used) | 3 of 38 (7.9%) |
| Skill bypassed (other tool used) | 2 of 38 (5.3%) |

### Context Drilldown Usage

| Metric | Value |
|--------|-------|
| Invocations with results | 33 |
| Context drilldown used | 29 of 33 (87.9%) |
| Snippet alone sufficient | 4 of 33 (12.1%) |

### Most Common Friction Points

| Friction Point | Count | Description |
|----------------|-------|-------------|
| Multiple Contextify installs warning | 6+ (all batches) | Warning appears on every invocation |
| Agent bypassed skill | 5 | User invoked TR but AI used other tools |
| FTS5 hyphen tokenization | 4 | Hyphens cause hard errors or zero results |
| Narrow days window not widened | 4 | AI uses narrow window and never widens |
| High token usage (agent delegation) | 3 | 60-90K+ tokens per subagent |
| Single attempt, no retry | 3 | AI gives up after 1-2 searches |
| Cross-project noise | 2 | Short tokens match unrelated projects |
| Project ID resolution unreliable | 2 | Cross-worktree project lookup fails |
| Content predates indexing window | 2 | Work is genuinely too old for the database |
| Self-reference false positive | 1 | Current session entry outranks older relevant results |

### Implementation Ordering

Recommended implementation sequence. Batches A and B can run in parallel. Batch C is a single coherent SKILL.md rewrite (not piecemeal).

**Batch A: Correctness and noise (P0 CLI)**
- F-01 (install warning suppression)
- F-02 (FTS5 hyphen pre-processing)
- F-03 (--project name lookup)
- F-05 (better FTS5 error messages)

**Batch B: Output-quality defaults (P1 CLI, parallel with A)**
- F-04 (--snippet-tokens default to 50)
- F-23 (compact output mode, optional quick win)

**Batch C: Unified SKILL.md rewrite (P0+P1 Skill, after A ships)**
- F-07 (unified zero-result protocol, merging F-07/F-11/F-13)
- F-08 (hyphen detection checklist)
- F-09 (negative proof guidance)
- F-10 (skill invocation vs agent delegation)
- F-14 (query broadening strategy)
- F-15 (snippet-tokens guidance update)

**Batch D: Scope and self-hit transparency (P2)**
- F-06 (--exclude-session flag)
- F-12 (self-hit awareness in skill)
- F-17 (search scope summary)

**Batch E: Selective product extensions (P2)**
- F-16 (indexing window transparency)
- F-18 (session-opener digest)
- F-19 (negative proof formatting)
- F-20 (auto-widening search)

**Later (P3-P4):**
- F-21 (cross-project search)
- F-22 (device provenance)
- F-24 (result deduplication)
- F-25 (batch verification)

Key dependency: F-04 before F-15 (align skill guidance with new CLI default). F-07 skill protocol complements F-20 CLI auto-widening (both are valuable, not redundant: F-07 improves model behavior, F-20 makes the CLI safer for all callers including imperfect skill usage).
