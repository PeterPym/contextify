---
todo_id: P1-CONVO-SEARCH
title: Contextify Conversation Search Specification
type: spec
date: 2025-11-24
status: reference
description: Unified UX and phased backend plan for the incoming project-scoped Quick Search and cross-project Deep Search experiences.
---
Here’s a unified spec that dovetails both docs into one coherent design.

I’ll start with a **short executive summary that explicitly picks a single, recommended UX flow and phase plan**, then give the full brief with all the detail preserved (and call out option/variant places where the earlier specs diverged).

---

# Executive Summary

## 1. Mental Model (Single Recommended Flow)

**Core idea:**

* The **HUD search field** is a fast, **project-scoped Quick Search** (“this project”).
* The **Deep Search window** is a dedicated **Search Center** for **cross-project and advanced search** (“all projects / filtered projects”).

This gives you the Reddit “this sub / all Reddit” and Apple Music “My Library / All Music” feel, but expressed as:

* **Quick Search (HUD, Enter)** → search within the **current project only**.
* **Deep Search (Search Center, ⌘Enter)** → search **across all projects**, with project filters and more powerful exploration.

### Recommended behavior

* **Enter** in HUD search field:

  * Switches HUD into **Quick Search** mode.
  * Runs search **only in the selected project**.
  * Shows results + a context preview inline, replacing the timeline content.

* **⌘Enter** in HUD search field:

  * Opens the **Deep Search window** (“Search Center”).
  * Uses the same query but **scope = All Projects** by default.
  * Allows filtering down to specific projects or sets of projects.

* **“Open in Deep Search” from Quick Search**:

  * Opens Deep Search with the same query.
  * Presents broader, cross-project results and more advanced tools.

This replaces the earlier “scope toggle inside a single panel” with a clearer **two-surface model**:

* HUD = fast, project-focused.
* Search Center = global, archival, and advanced.

### Option (alternative, not recommended for v1)

* **Option B:** Keep an explicit **Current Project / All Projects** scope toggle in the HUD Quick Search pane and let the HUD itself switch between project-scoped and all-projects search.
* **Trade-offs:** More complexity in the HUD and more potential for confusion around “what am I searching right now?”. Recommended to **defer** or restrict the full “All Projects” experience to Deep Search.

---

## 2. Phased Architecture (Good / Better / Best)

Across both surfaces, we keep the same three-phase backend story:

### Phase 1 – **GOOD** (FTS + Context Excerpts)

* **Indexing:** SQLite FTS5 index on **user + assistant messages** only.
* **Quick Search (HUD):**

  * Project-scoped lexical search.
  * List of hits + **±N message context** preview.
  * “Copy excerpt”, “Copy for AI”, “Open in timeline”.
* **Deep Search (Search Center):**

  * Same underlying hit model.
  * Cross-project scope + project filters.
  * Pagination, context preview, and “Open in HUD”.

No embeddings, no segmenting, no cards. Simple, robust, shippable.

---

### Phase 2 – **BETTER** (Embeddings + Hybrid Ranking + Summaries)

* **Indexing:**

  * Add per-entry embeddings table (`transcript_entry_embeddings`).
  * Background worker to embed new user/assistant messages.
* **Search behavior:**

  * Hybrid ranking: BM25 lexical + cosine similarity via embeddings.
  * Query embedding computed per search.
* **UX enhancements:**

  * Same UI layouts as Phase 1.
  * **Results are more forgiving and recall improves**, especially for “gist-y” queries.
  * Add **“Summarize this excerpt”** in both Quick Search and Deep Search context previews:

    * Short summary + key bullets.
    * “Copy summary” / “Copy summary + excerpt”.

No new visual surface; just better results and a summarization button.

---

### Phase 3 – **BEST** (Segments & Conversation Cards / Hierarchical RAG)

* **Indexing:**

  * Introduce **segments / episodes** (`transcript_segments` + membership table).
  * Each segment has:

    * Time span.
    * Short summary.
    * Segment-level embedding.
* **Retrieval pipeline:**

  * Step 1: Segment-level retrieval (by embedding, scoped to project(s)).
  * Step 2: Within selected segments, message-level retrieval via FTS + embeddings.
* **UX:**

  * **Deep Search** becomes **card-based**:

    * Each top segment is a **Conversation Card**:

      * Title, time range, project, summary, key quotes.
      * Actions: “Open full segment in HUD”, “Copy card as AI context”, “Copy summary”, “Copy full excerpt”.
    * Optionally a project summary table above results in Deep Search (matches per project).
  * **Quick Search** stays simple:

    * Still shows message-level hits + context preview.
    * “Deep Search…” takes you into the card-based experience.

This gives you a local, hierarchical RAG system that still feels deterministic and transparent.

**Option:** In a future iteration, Quick Search could also surface a *small* “Top Card” for your current project; recommended to keep v1 Quick Search message-oriented and put cards primarily in Deep Search.

---

## 3. Conflicts & How They’re Resolved

1. **Where does “Current Project vs All Projects” live?**

   * Earlier spec: direct scope toggle in a unified search panel.
   * UX spec: Quick Search is current-project-only; Deep Search does cross-project work.
   * **Decision:** Use **two surfaces** (HUD vs Search Center) as the main expression of scope.

     * Quick Search: project only.
     * Deep Search: All Projects + project filters.
   * **Option B (recorded but not recommended):** Add a scope toggle in the HUD Quick Search panel.

2. **Project summary table in All Projects search**

   * Earlier spec: a table summarizing matches per project above results.
   * Deep Search spec: global result list, project shown per row.
   * **Decision:** Treat the project summary table as a **Phase 3+ enhancement** in Deep Search:

     * Recommended: add it once segments/cards exist, since cards are naturally grouped by project.
   * Phase 1/2 Deep Search can launch with a simple list and filter controls.

3. **Segments / Cards vs plain excerpts**

   * Earlier spec: “Conversation Cards” as Phase 3.
   * UX spec: message + excerpt view.
   * **Decision:** **Phase 1–2** = message hits + excerpt only; **Phase 3** = cards layered on top, primarily in Deep Search.

---

From here on, the rest of the doc is the **full unified brief**, with the two original specs merged and aligned to these decisions.

---

# Contextify Search – Unified UX & Multi-Phase Design Spec (v1)

## 0. Scope

This document defines:

* The **UX and front-end behavior** of Contextify search:

  * **Quick Search**: inline HUD search (Enter).
  * **Deep Search / Search Center**: dedicated global search window (⌘Enter).
* The **multi-phase backend model** that supports these experiences:

  * Phase 1: FTS-only search + excerpts.
  * Phase 2: Hybrid FTS + embeddings + summarization.
  * Phase 3: Segments / Conversation Cards (hierarchical RAG).

Backend implementation details (exact SQL, GRDB structures, embedding model choice) are defined in a separate SearchService / Indexer spec. This doc describes contracts and expectations from the UX down.

---

## 1. Overall Goal & Context

### 1.1 Product Goal

Add a generalized search feature that lets you:

1. Search **actual user and AI assistant messages**, not tools/system noise.
2. Default to **current project** in the HUD, with an easy path to broaden to **all projects**.
3. For any hit:

   * Pull **surrounding context** (before/after messages) so you can see the local conversation.
   * Optionally get a **summary** of that context.
   * Easily **hand that context into your current AI conversation** as:

     * Exact text (excerpt).
     * Compact summary.
     * A structured “conversation card”.

### 1.2 Underlying Data Model

* **Transcript files**: append-only logs of user/assistant/tool/system messages.

* **SQLite + GRDB** abstraction over transcripts, with core table like:

  ```text
  TranscriptEntry:
    id
    project_id
    role        // user, assistant, tool, system
    content
    created_at  // timestamp
    seq         // monotonic order within project/file
    ...
  ```

* Clear notion of **current project** in the HUD.

---

## 2. Design Principles (Why Contextify ≠ Claude Code)

Contextify’s search constraints differ from tools like Claude Code:

1. **Data mutability**

   * Claude Code: live code, branches, unsaved buffers → embeddings go stale, need reindexing all the time.
   * Contextify: transcripts are **append-only**; you mostly need to embed **new entries**, not re-embed old ones.

2. **Infra & scale**

   * Claude Code: multi-tenant, remote services, vector stores as large distributed systems.
   * Contextify: single-user, local macOS app. The “vector index” is **just another SQLite table**.

3. **Security**

   * Claude Code: vector store is an additional sensitive datastore.
   * Contextify: if someone has your DB, they already have your raw transcripts; embeddings don’t add meaningful new risk.

4. **Use case**

   * Claude Code: search is used to **mutate live code**, so stale or wrong retrieval is a big deal.
   * Contextify: search is for **recall, reflection, and context building**. Imperfect recall is annoying, not catastrophic.

5. **Agentic search vs structured DB**

   * Claude Code: tools like ripgrep/LSP over file trees.
   * Contextify: data is already structured in tables; a deterministic search layer (SQL, FTS, embeddings) is simpler, more controllable. Agentic behavior can sit **on top** later.

**Conclusion:** The arguments *against* embeddings in Claude Code don’t really apply here. A hybrid approach with:

* **Deterministic SQL / FTS**, plus
* **Optional embeddings + segment summaries**

is a good fit.

---

## 3. Surfaces & Modes

### 3.1 Surfaces

1. **Main HUD Window**

   * Overlay shown while the user works in IDE/terminal.
   * Contains:

     * **Toolbar** (top): project info, global controls, search field (top-right).
     * **Sidebar** (left): list of projects, current selection.
     * **Center content area**: either timeline or Quick Search SERPs.

2. **Deep Search Window (Search Center)**

   * Separate NSWindow dedicated to search and “history archaeology”.
   * Used for:

     * Cross-project search.
     * Advanced operators.
     * Pagination and longer explorations.
     * (Phase 3+) Conversation Cards and project summary table.

### 3.2 HUD Modes

The HUD has two primary modes:

```swift
enum HudMode {
    case timeline(projectId: ProjectID)
    case quickSearch(projectId: ProjectID, query: String)
}
```

`HudViewState` holds:

```swift
@Observable
final class HudViewState {
    var mode: HudMode
    var searchQuery: String   // contents of HUD search field
}
```

Transitions between modes are driven by the HUD search behavior (see below).

---

## 4. HUD Search Field (Top-Right)

### 4.1 Placement & Visuals

* Located in the **HUD toolbar**, upper right.
* Always visible in both `Timeline` and `QuickSearch` modes.
* Standard Cocoa search field:

  * Placeholder: `Search messages…`
  * Clear (“X”) button when non-empty.

### 4.2 Behavior (Unified)

**Typing**

* Updates `HudViewState.searchQuery`.
* Does **not** change HUD mode until Enter / ⌘Enter.

**Enter (⏎) → Quick Search (Current Project)**

* If `searchQuery` is non-empty:

  * Requires a selected project in sidebar.
  * Switches HUD mode to:

    * `quickSearch(projectId: currentProjectId, query: searchQuery)`.
  * Runs **project-scoped** search using Phase-appropriate backend (FTS ± embeddings).
* If `searchQuery` is empty:

  * No-op.

**Command–Enter (⌘⏎) → Deep Search (All Projects)**

* If `searchQuery` is non-empty:

  * Opens **Deep Search window**.
  * Initializes Deep Search with:

    * `query = searchQuery`
    * **Scope = All Projects** (default).
* If `searchQuery` is empty:

  * Opens Deep Search with empty query field focused.

**Clear (“X”)**

* Clears `searchQuery`.
* If HUD is in `QuickSearch` mode:

  * Exits Quick Search → `timeline(projectId: currentProjectId)`.

---

## 5. Phase 1 – GOOD: FTS-Only Search + Context Excerpts

### 5.1 Data & Schema

Add an FTS5 table for indexable messages:

```sql
CREATE VIRTUAL TABLE transcript_entries_fts USING fts5(
  content,
  project_id UNINDEXED,
  role UNINDEXED,
  entry_id UNINDEXED,
  created_at UNINDEXED,
  tokenize = 'unicode61 remove_diacritics 2'
);
```

Keep it in sync with `transcript_entries` via triggers:

* **INSERT**:

  * Insert into FTS for rows where `role IN ('user', 'assistant')`.
* **UPDATE**:

  * Update FTS row for that `entry_id`.
* **DELETE**:

  * Delete corresponding FTS row.

### 5.2 Search Request Model

```swift
enum SearchScope {
    case project(ProjectID)   // used for Quick Search
    case allProjects          // used for Deep Search default
    case projects([ProjectID])// used for Deep Search with filters
}

struct SearchRequest {
    var query: String
    var scope: SearchScope
    var limit: Int            // e.g., 50 for Quick Search
    var offset: Int           // paging in Deep Search
}
```

### 5.3 FTS Query (Conceptual)

**Project-scoped (Quick Search):**

```sql
SELECT
  e.id,
  e.project_id,
  e.role,
  e.content,
  e.created_at,
  bm25(transcript_entries_fts) AS rank
FROM transcript_entries_fts f
JOIN transcript_entries e ON e.id = f.entry_id
WHERE transcript_entries_fts MATCH :query
  AND e.role IN ('user', 'assistant')
  AND e.project_id = :projectId
ORDER BY rank
LIMIT :limit;
```

**All projects (Deep Search):**

Same, but keep project filter out and honor page `offset`.

### 5.4 Surrounding Context (Excerpt)

Given a hit with known `project_id` and `seq`:

```sql
SELECT *
FROM transcript_entries
WHERE project_id = :projectId
  AND seq BETWEEN :hitSeq - :before AND :hitSeq + :after
ORDER BY seq;
```

* Default window: ~10 messages before / up to 19 after.
* Hard cap (~30 messages or ~8–10k chars) to keep it manageable.
* Truncation markers added in UI if there are older/newer messages beyond window.

---

## 6. Quick Search UX (HUD, Enter)

### 6.1 Activation & Scope

* Trigger: **Enter** in HUD search field with non-empty query.
* Scope: **current project only**.
* State:

  * `HudMode` → `quickSearch(projectId: currentProjectId, query: searchQuery)`.

Switching projects in sidebar while in Quick Search:

* Exits Quick Search → `timeline(projectId: newProjectId)`.
* Leaves `searchQuery` in HUD field for reuse.

### 6.2 Layout in Quick Search Mode

Center content is replaced with:

1. **Search Mode Bar** (top of center area, under toolbar)

   Example:

   > Search results for “unread counts”
   > Project: **Contextify** · 37 matches · **Exit Search** · Deep Search… ⌘⏎

   Elements:

   * Label: `Search results for "<query>"`.
   * Project label.
   * “N matches” (approximate ok).
   * **Exit Search** button.
   * **Deep Search… ⌘⏎** link → opens Deep Search (All Projects) with same query.

2. **Main Split View**

   **Left pane: Result list**

   * Up to **50** hits.

   * Each row shows:

     * Role icon (user/assistant).
     * Text snippet with highlighted terms.
     * Subline: `Nov 11, 2025 · 2:43 PM` and optional conversation label.

   * Sorted by **relevance** (Phase 1: BM25).

   **Right pane: Context preview**

   * Chat-style preview of excerpt around selected hit:

     * ±10 before, up to 19 after, truncated if needed.
   * Hit message visually emphasized:

     * Slight background tint / left border.
     * Search term highlighting.
   * Header with actions:

     > Conversation excerpt
     > `<start time> – <end time>`
     > [Open in Timeline] · [Copy Excerpt] · [Copy for AI]

### 6.3 Actions

* **Selection:**

  * First result auto-selected after search.
  * Keyboard: Up/Down navigates rows.
  * Mouse: click row to select.

* **Open in Timeline:**

  * Sets HUD mode to `timeline(projectId: currentProjectId)`.
  * Scrolls timeline to entry.
  * Brief highlight flash.

* **Copy Excerpt:**

  * Copies visible excerpt (including truncation markers) with metadata:

    ```text
    CONTEXTIFY EXCERPT
    Project: <project name>
    Time range: <excerpt start> – <excerpt end>
    Shown messages: i–j of N (if known)

    … earlier messages omitted …
    [User, 14:21]: ...
    [Assistant, 14:23]: ...
    … later messages omitted …
    ```

* **Copy for AI:**

  * Copies structured, AI-friendly block, e.g.:

    ```text
    CONTEXTIFY CONTEXT EXCERPT
    Project: <project name>
    Time range: <excerpt start> – <excerpt end>

    [User, 14:21]: ...
    [Assistant, 14:23]: ...
    ...
    ```

* **Deep Search… ⌘⏎:**

  * Opens Deep Search window with same query.
  * Default scope: **All Projects**.
  * Recommended: restore HUD to Timeline mode (or keep Quick Search visible but it’s fine either way; simplest is to exit Quick Search).

### 6.4 Limits & No Results

* Limit: 50 results.

* If more than 50 exist:

  * Footer in list:

    > Showing top 50 matches in this project. [Open more in Deep Search… ⌘⏎]

* No results:

  > No matches in project **<project name>** for “<query>”.
  > [Deep Search all projects… ⌘⏎]

  * Exit Search remains available.

### 6.5 Dismissing Quick Search

Any of the following exits Quick Search → Timeline:

* **Exit Search** button.
* **Esc** while focus is in result list or preview.
* Clicking “X” in HUD search field (clears query).

---

## 7. Deep Search UX (Search Center, ⌘Enter)

### 7.1 Activation

* From HUD:

  * ⌘Enter with non-empty query → Deep Search with `query = searchQuery`, `scope = All Projects`.
  * ⌘Enter empty → Deep Search with empty query.
* From Quick Search:

  * “Deep Search… ⌘⏎” links → same query, scope = All Projects.

HUD state is unchanged when Deep Search opens (other than optional Quick Search exit).

### 7.2 Window Behavior

* Independent NSWindow.
* Resizable, position remembered.
* Comes to front on activation.
* Close (⌘W) doesn’t affect HUD.

### 7.3 Layout (Messages view, Phase 1)

Deep Search initially ships with a single **Messages** view:

1. **Top search bar**

   * Search field:

     * Same syntax as Quick Search (keywords, phrases).
     * Enter runs search in this window only.

   * Scope controls:

     * **Primary scope** default: `All Projects`.
     * Project filter:

       * Dropdown or multi-select listing projects.
       * Default: “All projects”.
       * User may restrict to one or several.

   * Sort:

     * v1: **Relevance** only.
     * Future: add Newest / Oldest.

2. **Main split view**

   **Left pane: Global result list**

   * Paginated; 50 results per page.

   * Row content similar to Quick Search, plus project name:

     * Role icon.
     * Snippet with highlighted terms.
     * Subline: `Project: <name> · Nov 11, 2025 · 2:43 PM`.

   * Pagination header:

     > `1–50 of 237` `<Prev` `Next>`

   **Right pane: Context preview**

   * Same as Quick Search preview:

     * Excerpt window around hit.
     * Truncation markers.
   * Header actions:

     > Conversation excerpt
     > `<start time> – <end time>`
     > [Open in HUD] · [Copy Excerpt] · [Copy for AI]

### 7.4 Actions

* **Selection:**

  * First result auto-selected when results exist.
  * Up/Down arrow navigation.

* **Page navigation:**

  * `Prev` / `Next` buttons (mouse v1; keyboard later).

* **Open in HUD:**

  * Brings HUD to front.
  * Sets HUD to `timeline(projectId: hit.projectId)`.
  * Selects that project in sidebar.
  * Scrolls timeline to hit, highlights.

* **Copy Excerpt / Copy for AI:**

  * Same semantics as Quick Search.

### 7.5 Option: Project Summary Table (Phase 3+)

* For `scope = All Projects`, Deep Search may include an optional **summary table above results**:

  | Project              | Matches | Last Activity |
  | -------------------- | ------- | ------------- |
  | Contextify           | 42      | Today         |
  | Macrodata POC        | 6       | Yesterday     |
  | Personal Experiments | 3       | Last week     |

* Clicking a row:

  * Applies a project filter while preserving query.
  * Scrolls result list to that project’s section.

* Recommended to add in **Phase 3** when segments/cards are implemented, so table counts can be based on segment counts or message hits.

---

## 8. Phase 2 – BETTER: Embeddings + Hybrid Ranking + Summaries

### 8.1 Schema: Entry-Level Embeddings

Add:

```sql
CREATE TABLE transcript_entry_embeddings (
  entry_id   TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  role       TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  embedding  BLOB NOT NULL
);
```

### 8.2 Embedding Worker

* On new `TranscriptEntry` with `role ∈ {user, assistant}`:

  * Queue entry for embedding (in DB or in-memory job queue).
* Worker:

  * Fetch queued entries.
  * Clean/normalize content (strip noisy markup, tool scaffolding).
  * Call Apple text-embedding model.
  * Store `Float32` array as BLOB in `transcript_entry_embeddings`.
* Backlog embedding:

  * Throttle to keep UX responsive.
  * Index state reflected in status bar.

### 8.3 Search Algorithm (Hybrid)

For a query:

1. Compute **query embedding**.

2. Retrieve candidates:

   * Option A (recommended for v2):

     * Use FTS to get top N lexical hits within scope.
     * Compute semantic similarity for their embeddings.
     * Combine into a final score.
   * Option B (future):

     * Vector search over all entries within scope, optionally fused with FTS.

3. Fusion:

   * Normalize `lexScore` and `semScore` to [0,1].
   * Compute `final = 0.4 * lexScore + 0.6 * semScore` (tunable per config).
   * Sort by `final`.

**UX impact:** both Quick Search and Deep Search keep their layouts; results are simply smarter.

### 8.4 “Summarize Excerpt” (New Action)

In both Quick Search and Deep Search context preview:

* Add **“Summarize excerpt for AI”**.

Behavior:

* Pass the excerpt (±N messages) to an on-device LLM with a fixed summarization prompt.

* Show inline:

  * Short paragraph summary.
  * 3–5 bullet “Key points”.

* Actions:

  * **Copy summary**
  * **Copy summary + excerpt**

This is additive; existing “Copy Excerpt” / “Copy for AI” still exist.

---

## 9. Phase 3 – BEST: Segments & Conversation Cards

### 9.1 Segment Model

Define **segments / episodes** as contiguous stretches of conversation:

* Partition transcripts by:

  * Transcript file boundaries, and/or
  * Time gaps > X minutes (e.g., 30 minutes between entries).

Schema:

```sql
CREATE TABLE transcript_segments (
  segment_id        TEXT PRIMARY KEY,
  project_id        TEXT NOT NULL,
  start_created_at  INTEGER NOT NULL,
  end_created_at    INTEGER NOT NULL,
  summary           TEXT NOT NULL,
  embedding         BLOB NOT NULL
);

CREATE TABLE transcript_segment_membership (
  segment_id TEXT NOT NULL,
  entry_id   TEXT NOT NULL,
  seq        INTEGER NOT NULL,
  PRIMARY KEY (segment_id, entry_id)
);
```

For each segment:

* Concatenate content (bounded).
* Use LLM to generate:

  * `summary` (short).
* Use embedding model to generate:

  * Segment embedding.

Segments built by:

* Background indexing passes over historical data.
* Incremental updates:

  * Append new entries to current tail segment until time gap threshold, then start new segment.

### 9.2 Hierarchical Retrieval

When searching (especially in Deep Search):

1. **Segment-level retrieval:**

   * Compute query embedding.
   * Find nearest segments within given scope (All Projects / filtered).
2. **Within each segment:**

   * Use FTS + entry embeddings to identify best lines.
   * Extract ±N messages to preserve flow.
3. Build **Conversation Card**:

   ```jsonc
   {
     "segmentId": "seg_123",
     "projectId": "contextify",
     "title": "Unread count P1 fix",
     "dateRange": "2025-11-04 14:03 – 15:12",
     "segmentSummary": "You debugged a P1 bug where unread counts stayed stale when switching projects...",
     "keyMessages": [
       { "role": "user", "excerpt": "I'm seeing unread counts not updating when..." },
       { "role": "assistant", "excerpt": "The issue is split update responsibility..." }
     ],
     "canonicalUri": "contextify://project/contextify/segment/seg_123"
   }
   ```

### 9.3 Deep Search UX (Cards)

In Phase 3, **Deep Search** evolves:

* Primary result list becomes a set of **Conversation Cards**, grouped by project.

Each card includes:

* Title / inferred topic.
* Project name, date range.
* Summary.
* Key messages (short excerpts).
* Actions:

  * **Open full segment in HUD**:

    * Switch HUD to segment’s project.
    * Scroll timeline to segment’s start.
  * **Copy card as AI context**:

    * Structured text block with:

      * Project.
      * Time range.
      * Summary.
      * Key quotes.
      * Canonical URI.
  * **Copy summary only**.
  * **Copy full excerpt** (full segment excerpt).

**Project summary table** fits naturally here as a **Phase 3+** header for All Projects search.

### 9.4 Quick Search UX in Phase 3

Recommended:

* **Quick Search** remains message-centric:

  * Same result list + excerpt preview as Phase 2.
* Under the hood:

  * Message hits in Quick Search may come from the same segment-aware index.
* “Deep Search… ⌘⏎”:

  * Takes you to the card-centric view for the same query.

**Option:** Later, Quick Search could show a single “Top Card” for current project above message hits; not required in Phase 3.

---

## 10. Search Semantics

Applies to both Quick Search and Deep Search (with extra operators gradually added to Deep Search).

### 10.1 Query Language

**Quick Search (HUD)**

* **Supported:**

  * Keyword search:

    * Space = AND (`foo bar` → messages containing both).
  * Phrase search:

    * Quotes for exact phrase: `"unread counts"`.
* **Not guaranteed in Quick Search v1:**

  * Named operators (e.g., `project:`, `before:`, `after:`).
* If user types a clearly operator-heavy query:

  * Quick Search may still run a best-effort search.
  * Mode bar shows hint:

    > This query uses advanced filters that may not be fully supported in Quick Search.
    > For complete results, use Deep Search. [Open Deep Search… ⌘⏎]

**Deep Search**

* Intended to support **Gmail-style** syntax over time:

  * Keywords + phrases.
  * `after:YYYY/MM/DD`, `before:YYYY/MM/DD`.
  * Possibly `project:<name>` or similar.
* Exact syntax defined in SearchService spec.
* UI: small “Search operators” help in the Deep Search window only.

### 10.2 Case, Diacritics, Stemming

* Case: search is **case-insensitive**.
* Diacritics: treat accent-insensitive where supported (`é` ≈ `e`).
* Stemming:

  * v1: **no stemming**.
  * `summary`, `summaries`, `summarization` treated separately.

### 10.3 Roles & Content Types

* Indexed initially:

  * **user** and **assistant** messages.
* Not indexed in v1:

  * Tool messages, system messages, metadata.
* Future options:

  * Add tool/system search as filters or separate tabs in Deep Search.

### 10.4 Code-like Tokens & Partial Matches

* FTS may match tokens like `UNREAD_COUNT_UPDATED`.
* Ranking should prefer **exact word/phrase matches** over noisier partial matches when possible.
* UI doesn’t need special handling; it’s a backend concern.

### 10.5 Sorting

* v1:

  * Quick Search: **Relevance** only.
  * Deep Search: **Relevance** only; toggles to add Newest / Oldest later.

---

## 11. Indexing & Data Availability UX

### 11.1 Indexing Status

* Status bar (already used for ingestion) also reflects search indexing:

  > Indexing messages… 83%

* While visible:

  * Tooltip / small `(i)` explains that search results may be incomplete.

### 11.2 Incomplete Index Behavior

* Search remains usable even while indexing.
* Results might be incomplete; no special blocking screen.
* Rely on status bar messaging.

### 11.3 Error Handling

**Quick Search errors**

* If project-scoped search fails:

  > **Search temporarily unavailable**
  > An error occurred while searching this project.
  >
  > [Retry] [Open Deep Search]

* Status bar shows:

  > Search error — tap for details

**Deep Search errors**

* If search or index is broken:

  > **Search failed**
  > We couldn’t run this search because the search index is missing or corrupted.
  >
  > [Retry] [Rebuild Search Index…]

* “Rebuild Search Index…”:

  * Kicks off full reindex.
  * Shows global banner:

    > Rebuilding search index… results may be incomplete. 23%

All errors are logged to existing diagnostics.

---

## 12. Keyboard, Focus, Accessibility

### 12.1 Keyboard & Focus

**HUD → Quick Search**

* After Enter:

  * If results: select first row, focus result list.
  * Esc: exit Quick Search → Timeline, focus timeline list.

**Quick Search navigation**

* Up/Down: move selection.
* Esc: exit Quick Search.

**Deep Search**

* Enter in search bar: run search.
* Up/Down: navigate result list.
* Mouse for pagination in v1; keyboard shortcuts later.

### 12.2 Accessibility & Theming

* All major actions available via keyboard.
* Screen readers:

  * Result rows expose:

    * Role, project (Deep Search), timestamp, snippet.
  * Mode bar announces:

    * “Search results for ‘<query>’, project <name>, N matches.”
* Hit highlighting:

  * Use color + structural cue (border, marker text) for color-blind friendliness.
* Dark/light theme:

  * Make sure contrasts are acceptable in both.

---

## 13. Persistence & History (v1)

* HUD Quick Search:

  * `searchQuery` is **not** persisted across app restart in v1.
  * No search history dropdown.
* Deep Search:

  * No persisted search history / saved search yet.
  * Explicit v2+ feature; doesn’t affect current design.

---

## 14. Rollout Summary

**Phase 1 – GOOD**

* FTS index + triggers on `TranscriptEntry` for user/assistant.
* HUD Quick Search (current project only, Enter).
* Deep Search window (All Projects, ⌘Enter).
* Context excerpts, copy actions, open-in-timeline/HUD.
* Basic indexing status + error handling.

**Phase 2 – BETTER**

* Per-entry embeddings + background worker.
* Hybrid lexical/semantic ranking.
* “Summarize excerpt” action in both surfaces.

**Phase 3 – BEST**

* Segment tables + memberships.
* Segment embeddings + summaries.
* Deep Search Conversation Cards (with “copy card as AI context”).
* Optional project summary table for All Projects view.
* Quick Search remains message-oriented; Deep Search becomes the card-heavy archival view.

Each phase is self-contained and can be shipped independently. You can pause at any phase without invalidating the UX contracts above.

---

## Appendix: Market Research - HN Feedback on Chat Search (Nov 2025)

From the Onyx (YC W24) Launch HN discussion (https://news.ycombinator.com/item?id=46045987), users highlighted specific pain points around search and chat history discovery. These validate Contextify's search direction and suggest areas to explore.

### Key Pain Points

**1. "Sidebar = graveyard" (visarga)**
> "That sidebar of past chats is where they go to be lost forever. Nobody came up with a UI that has decent search experience."

**Contextify answer:** Project-centric organization + timeline view prevents the "endless sidebar" problem. Search adds discoverability.

**2. Feature wishlist (aargh_aargh)**
Suggested improvements for conversation management:
- Categorization by topic/date
- Topic clustering
- Ranked search options
- Conversation tree views
- Integration with external tools (email, issue trackers)
- Knowledge bank for saving learned information

**Contextify answer:**
| Request | Status |
|---------|--------|
| Categorization by date | ✅ Already have (timeline) |
| Categorization by topic | ✅ LLM summaries provide light categorization |
| Topic clustering | 🔮 Phase 3 segments could enable this |
| Ranked search | ✅ Phase 1 BM25, Phase 2 hybrid ranking |
| Conversation tree views | ❓ Not planned, but timeline is linear |
| External tool integration | 🔮 MCP server could enable this |
| Knowledge bank | ✅ The database IS the knowledge bank |

**3. Source mapping (rao-v)**
> Users cannot easily track what's been processed or map results back to source materials.

**Contextify answer:** Every entry links to source transcript file. Transcript Inventory view shows all indexed files.

### Areas to Explore (Future Phases)

Based on this feedback, consider for Phase 3+:

1. **Topic clustering / tagging**
   - Auto-generate topic tags from segment summaries
   - Filter/browse by topic across projects
   - "What have I worked on related to X?"

2. **Knowledge bank / pinning**
   - Let users "star" or "pin" important excerpts
   - Build a curated subset of key learnings
   - Export as reference doc

3. **Conversation tree visualization**
   - Visual representation of conversation flow
   - See branching points where you tried different approaches
   - May be overkill for CLI transcripts (linear by nature)

4. **External tool integration via MCP**
   - Let other tools query Contextify's history
   - "What did we decide about authentication?" from any MCP client
   - GitHub issue linking ("find conversations mentioning issue #123")

### Positioning Insight

The consistent theme: **chat UIs treat history as an afterthought**. Users generate valuable context, then it disappears into an unsearchable sidebar.

Contextify's value prop: **We're the search/discovery layer that chat UIs neglect.** Your conversations are an asset, not a liability.
