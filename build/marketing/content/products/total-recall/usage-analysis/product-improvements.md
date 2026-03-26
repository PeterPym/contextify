---
session_id: 7167f5f7-2eb0-47d9-92b7-3cd37532bdf5
date: 2026-03-26
project: contextify
branch: ct-390-v3-polish
status: ready-for-review
---

# Total Recall: Product Improvements

Prioritized list of improvements derived from friction analysis across 38 invocations in 5 analysis batches (2026-03-01 to 2026-03-25).

## Priority 1: Fix Before Next Release

### 1.1 FTS5 Hyphen Tokenization

**Problem:** FTS5 splits hyphenated terms on hyphens. Searching for "cli-ai-setup" produces tokens [cli, ai, setup], and "ai" is interpreted as a column reference, causing "no such column: ai" errors. Similarly, "review-loop" fails as a search term.

**Observed in:** Batch 2 (tr-003a), Batch 5 (batch5-004), and implied workarounds throughout.

**Impact:** Blocks the most natural query patterns for project names, tool names, and hyphenated identifiers that are ubiquitous in software development.

**Current workarounds:**
- Quote as phrase: `"review loop"` (drops the hyphen)
- Switch to `contextify activity --project-id <UUID>` (bypasses FTS entirely)
- Use `contextify projects --json` to find UUID first, then query by ID

**Recommended fix:** Configure FTS5 tokenizer to treat hyphens as part of tokens (not as separators). Consider `unicode61` tokenizer with `separators` option excluding hyphen, or add a `remove_diacritics` + custom tokenizer. Alternatively, preprocess queries to quote hyphenated terms automatically.

**Effort estimate:** Small. Tokenizer configuration change + migration to rebuild FTS index.

---

### 1.2 Suppress "Multiple Contextify Installs Detected" Warning

**Problem:** Warning appears in every Total Recall invocation. It is correct (multiple worktree builds exist) but not actionable during a search and adds visual noise to every result.

**Observed in:** Every invocation in Batch 1 (6/6). Likely present in all batches but not always noted.

**Impact:** Low severity but high annoyance. Clutters output on every search, training users to ignore warnings entirely.

**Recommended fix:** Either:
- Move to `--verbose` / `--diagnostics` flag output only
- Show once per session, not per command
- Suppress entirely when running in skill/agent context (detect non-interactive usage)

**Effort estimate:** Trivial. Conditional on invocation context or suppress-after-first-show logic.

---

### 1.3 --project Flag CWD Default Bug

**Problem:** `contextify activity --project [name]` defaults to the current working directory's project instead of looking up the project by name. Users must use `--project-id` with an explicit UUID from `contextify projects --json` output.

**Observed in:** Batch 2 (tr-003a).

**Impact:** Moderate. Forces a two-step lookup (list projects, copy UUID, re-run with UUID) when a one-step name lookup should work.

**Recommended fix:** When `--project` value is provided and does not match the cwd project, perform a name-based lookup in the database before falling back to cwd.

**Effort estimate:** Small. Argument parsing change in CLI.

---

## Priority 2: Improve Query Quality

### 2.1 Embed Query Construction Guidance in Skill

**Problem:** AI agents construct poor queries too often. Common anti-patterns observed:
- Using narrow date windows (--days 30) for exploratory "lost work" searches
- Giving up after 1-2 failed searches without trying synonyms, wider windows, or relaxed AND clauses
- Using multi-word phrases that are too specific for FTS5 matching
- Not retrying with broader terms when initial queries return 0 results

**Observed in:** Batch 3 (3 of 6 invocations rated "poor" query construction). Batch 2 (narrow windows in tr-003a). Batch 3 batch3-6 (single overly specific search, immediate pivot to git).

**Impact:** Moderate-high. Poor query construction is the primary cause of false-negative search outcomes. The tool has the data; the queries are not finding it.

**Recommended fix:** Add query strategy guidance to the Total Recall skill definition:
- Default to `--days 365` for exploratory searches; narrow only when user specifies recency
- If first query returns 0 results, automatically retry with: (a) wider date window, (b) fewer AND constraints, (c) synonym expansion
- Warn against multi-word phrase searches that may not match FTS5 tokenization
- Provide example query patterns for common use cases (decision recall, implementation reference, incident forensics)

**Effort estimate:** Medium. Skill definition text update + optional query preprocessor.

---

### 2.2 Self-Referential Hit Filtering

**Problem:** The current session's own entries appear in search results, creating false positive noise. When the AI mentions "Paperbark Maple" in conversation, then searches for it, the top hit is the current session's own entry.

**Observed in:** Batch 1 (inv-004). The AI recognized and worked around it, but the noise is unnecessary.

**Impact:** Low-medium. Savvy AI agents recognize self-hits, but it wastes a result slot and can confuse less capable models.

**Recommended fix:** Add `--exclude-session <session-id>` flag to `contextify search`. The skill can automatically pass the current session ID to exclude self-referential results.

**Effort estimate:** Small. WHERE clause addition in the search query.

---

### 2.3 Default Date Window Configuration

**Problem:** No standard default for `--days` parameter. AI agents arbitrarily choose 7, 30, 60, 90, 180, or 365. For "lost work" or "what did we decide" queries, narrow windows miss results that exist in older sessions.

**Observed in:** Batch 3 (batch3-4 used --days 30/60 for exploratory searches, returned 0 results; --days 365 was never tried). Batch 2 (various narrow windows).

**Impact:** Medium. The mismatch between query window and actual history window is a common cause of false negatives.

**Recommended fix:**
- Skill guidance should recommend --days 365 as default for all non-time-specific queries
- Consider a `--recent` flag (7-14 days) as a convenience alias for time-boxed searches
- Consider auto-widening: if a search returns 0 results with a narrow window, automatically retry with a wider window before reporting "no results"

**Effort estimate:** Small (guidance update) to medium (auto-widening logic).

---

## Priority 3: New Capabilities

### 3.1 Cross-Project Search Improvements

**Problem:** Searching across projects is unreliable. The `--project .` flag with worktree expansion helps but does not cover unrelated projects. Cross-project contamination occurs (batch3-3: "gcal" search returned GheeCalendar results). Project ID resolution across worktrees was unreliable (batch5-003).

**Observed in:** Batch 2 (tr-003a), Batch 3 (batch3-3), Batch 5 (batch5-003).

**Impact:** Medium. Cross-project search is an occasional but high-value use case, especially for users with many projects.

**Recommended fix:**
- Improve project name resolution to handle worktree variants
- Add `--all-projects` flag for explicit cross-project search
- Add project name to result snippets so users can see which project each hit came from
- Consider project filtering in result display (group by project)

**Effort estimate:** Medium.

---

### 3.2 Machine / Device Provenance

**Problem:** No hostname or device_id field in the CLI data model. Cross-machine attribution is not possible. When a user syncs transcripts from multiple machines, there is no way to determine which machine produced a given entry.

**Observed in:** Batch 2 (tr-003a), where the AI honestly stated "I can't tell which machine produced any entry."

**Impact:** Medium for multi-machine users. This is a growing use case as cloud sync rolls out.

**Recommended fix:** Add `device_id` or `hostname` field to the transcript entry schema. Populate from the local machine's hostname at ingestion time. Expose in search results and context display.

**Effort estimate:** Medium. Schema migration + ingestion pipeline change.

---

### 3.3 Agent-Optimized Search Mode

**Problem:** Agent-delegated searches consume 60-226K tokens per invocation. The raw `contextify search` output includes full JSON payloads that are verbose for agent consumption.

**Observed in:** Batch 4 (B4-003: 80K tokens, B4-004: 90K tokens, B4-012: 226K tokens).

**Impact:** Medium. Token costs compound across frequent agent-delegated searches. Some searches could be answered with compact summaries instead of full JSON.

**Recommended fix:**
- Add `--compact` or `--agent` output mode that returns only entry ID, score, timestamp, project, and snippet (no full JSON envelope)
- Consider a `--top N` flag that returns only the highest-scoring N results
- Provide a one-shot "search + context" command that combines the two most common sequential operations

**Effort estimate:** Medium.

---

### 3.4 Batch Task Verification

**Problem:** B4-015 showed a pattern of "check all open P1 tasks against conversation history." This required spawning two parallel agents and running dozens of individual searches. There is no built-in batch verification mode.

**Observed in:** Batch 4 (B4-015), Batch 5 (batch5-003).

**Impact:** Low-medium. This is an emerging power-user pattern, not yet common.

**Recommended fix:** Consider a `contextify verify-tasks` command that takes a list of task IDs and searches for evidence of completion for each. Could also integrate with bloon to automatically pull open task lists.

**Effort estimate:** Large. New command + integration with task management.

---

## Priority 4: Quality of Life

### 4.1 Better Error Messages for FTS5 Failures

**Problem:** When FTS5 tokenization causes errors, the error message is cryptic: "no such column: ai". Users and AI agents cannot easily diagnose the root cause.

**Recommended fix:** Catch FTS5 column-reference errors and return a helpful message: "Search term 'X' was split on hyphens by the search engine. Try quoting it: '\"X\"' or removing hyphens."

**Effort estimate:** Trivial.

---

### 4.2 Session-Start TR Orientation

**Problem:** Two invocations in Batch 5 (batch5-001, batch5-005) were at the very start of a session (lines 7-8), used as a session orientation tool. This is a valuable pattern but requires explicit user invocation.

**Recommended fix:** Consider an optional "session start summary" mode where TR automatically provides a brief status of recent work in the current project when a new session begins. Could be opt-in via a config flag.

**Effort estimate:** Medium.

---

### 4.3 Result Deduplication

**Problem:** When the same topic is discussed across multiple sessions, search results can include many entries that all say roughly the same thing. The AI must manually identify and deduplicate these.

**Recommended fix:** Add a `--deduplicate` or `--unique-sessions` flag that returns at most one result per session, selecting the highest-scoring entry from each.

**Effort estimate:** Small-medium. GROUP BY in query + max score selection.

---

## Summary Table

| # | Improvement | Priority | Effort | Batches Affected |
|---|-------------|----------|--------|------------------|
| 1.1 | FTS5 hyphen tokenization | P1 | Small | 2, 5 |
| 1.2 | Suppress multi-install warning | P1 | Trivial | 1 (all batches likely) |
| 1.3 | --project flag CWD default | P1 | Small | 2 |
| 2.1 | Query construction guidance | P2 | Medium | 2, 3 |
| 2.2 | Self-referential hit filtering | P2 | Small | 1 |
| 2.3 | Default date window config | P2 | Small-Medium | 2, 3 |
| 3.1 | Cross-project search | P3 | Medium | 2, 3, 5 |
| 3.2 | Machine/device provenance | P3 | Medium | 2 |
| 3.3 | Agent-optimized search mode | P3 | Medium | 4 |
| 3.4 | Batch task verification | P3 | Large | 4, 5 |
| 4.1 | Better FTS5 error messages | P4 | Trivial | 2 |
| 4.2 | Session-start orientation | P4 | Medium | 5 |
| 4.3 | Result deduplication | P4 | Small-Medium | All |
