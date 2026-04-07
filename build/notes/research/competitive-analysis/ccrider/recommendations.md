---
session_id: 16b4e9f8-7d2d-4841-a59d-51ddb15bf9ca
date: 2026-04-06
project: contextify
branch: main
status: ready-for-review
---

# Actionable Recommendations from ccrider Competitive Analysis

## Prioritized Against Existing Contextify Roadmap

### R1: Ship Contextify MCP Server (NEW - P1)

**What:** Add `contextify serve-mcp` command exposing search, recent conversations, and conversation detail as MCP tools. Claude Code users configure it in their MCP settings for native in-session history search.

**Priority justification:** ccrider's MCP server is their strongest differentiator and directly competes with Total Recall's niche. Contextify's richer data (summaries, project identity, cloud-synced history) would make it a strictly better MCP backend. First-mover advantage in MCP "AI memory" is significant.

**Roadmap interaction:** No existing MCP task in the roadmap. This is net-new. Could be packaged with ct-850 (v1.4.0 release) or as standalone.

**Effort:** M (2-3 days). TranscriptOrchestrator already has all the queries. MCP server is a thin protocol wrapper.

**Key patterns to borrow from ccrider:**
- Token budget cap (9000 tokens to stay under Claude Code's 10k warning)
- coerceStringNumbers() for LLM parameter type coercion
- Sync-before-query option for CLI mode

---

### R2: Evaluate Dual FTS5 Tokenizers via Benchmark (ENHANCEMENT to existing search work - P2)

**What:** Add a second FTS5 virtual table with unicode61 tokenizer (no stemming) alongside the existing porter-stemmed table. Search queries hit both tables, results are merged and deduplicated.

**Priority justification:** Contextify already uses porter stemming (ct-726, ct-763, ct-780 all dealt with FTS5 stemming). ccrider's dual approach preserves code identifiers (camelCase, snake_case, dotted paths) that porter mangles. This could improve Total Recall benchmark scores.

**Roadmap interaction:**
- Directly extends ct-801 (Add file-path gold queries to benchmark)
- Builds on ct-724 (AutoResearch ratchet) infrastructure
- Use existing benchmark suite to validate: if Recall@k improves >2%, ship it

**Effort:** S (1 day). Migration + search query modification + benchmark run.

**Decision gate:** Must show measurable improvement on Total Recall benchmark. If no improvement, don't add complexity.

---

### R3: Add Anchor Phrase / Session Tagging to Total Recall (NEW - P2)

**What:** Add `contextify anchor` command that generates a memorable diceware phrase. User mentions it in their AI session, it gets indexed, and future Total Recall searches can find the session by phrase. Solves context compaction recovery.

**Priority justification:** Context compaction is a real problem for Total Recall users. When Claude Code compresses context, conversation-specific details get lost. An anchor phrase survives compaction because it's a unique string. ccrider calls this generate_session_anchor.

**Roadmap interaction:**
- Enhances Total Recall (ct-293 family)
- Could be part of ct-126 (Create /contextify-search-improvement skill)
- Independent of other work

**Effort:** S (0.5 day). Diceware generation (standard library), CLI command, search verification.

---

### R4: Natural Language Date Filtering in Search (ENHANCEMENT - P3)

**What:** Support "yesterday", "last week", "3 days ago" in CLI search queries alongside existing `--days` flag.

**Priority justification:** Nice UX polish. ccrider uses the `olebedev/when` Go library for this. Swift equivalents exist. Low effort, but not blocking any user workflow.

**Roadmap interaction:**
- Could be bundled with ct-59 (#SEARCH-FOLLOWON) or ct-154 (--format markdown)
- Independent of other work

**Effort:** S (0.5 day). Date parsing in query preprocessing.

---

### R5: Monitor ccrider + Consider Complementary Positioning (ONGOING)

**What:** Watch ccrider's GitHub for their Phase 3 (real-time watching), any cloud features, and community growth metrics (stars, forks, issues). Consider whether to position ccrider as complementary ("ccrider for terminal search, Contextify for visual monitoring and cloud") rather than competitive.

**Priority justification:** ccrider is growing (29 releases in 5 months, Show HN post, external contributors). Understanding their trajectory helps Contextify's roadmap prioritization.

**Roadmap interaction:**
- Feeds into ct-102 (Audit and update all public surfaces)
- Informs ct-104 (Social media campaign)

**Effort:** Negligible. Periodic GitHub check.

---

## Summary Table

| # | Recommendation | Priority | Effort | Existing Task | New Task Needed? |
|---|---------------|----------|--------|---------------|-----------------|
| R1 | MCP Server | P1 | M | None | YES |
| R2 | Dual FTS5 Tokenizers | P2 | S | ct-801 (related) | YES (or extend ct-801) |
| R3 | Anchor Phrase | P2 | S | ct-126 (related) | YES |
| R4 | NLP Date Filters | P3 | S | ct-59 (related) | NO (bundle) |
| R5 | Monitor ccrider | Ongoing | Negligible | ct-102 (related) | NO |

**Net new Bloon issues needed:** 2-3 (MCP server, anchor phrase, possibly dual FTS5)
