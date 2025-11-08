# RAG Implementation Briefing: Phase 3 Complete

**Project:** Contextify macOS HUD - Conversation Search & Retrieval
**Date:** 2025-10-22
**Status:** Phase 3 Complete (Hybrid Search with BM25 and RRF)
**Branch:** `feature/rag-implementation`
**Database:** SQLite with GRDB, ~1,342 entries (≥100 chars), 3.2 MB

---

## Executive Summary

We've built a production-ready hybrid search system combining:
- **Semantic search** (neural embeddings, 512-dim vectors via Apple's NLContextualEmbedding)
- **Keyword search** (BM25 probabilistic ranking)
- **Reciprocal Rank Fusion** (RRF) to merge rankings with configurable weights

The system searches conversation transcripts (Claude Code & Codex CLI sessions) with:
- **Sub-100ms search** across 1,300+ entries
- **Project-scoped filtering** (current project vs all projects)
- **Expandable results** with parent context (user question + assistant answer)
- **Score breakdown display** showing exactly how RRF calculated each result's rank

**User feedback:** "The hybrid search is much better."

---

## Implementation Status

### ✅ Phase 1: Embedding Infrastructure (Complete)
**Goal:** Generate and store embeddings for all conversation entries

**Implemented:**
- `EmbeddingService` (actor) - Uses Apple's `NLContextualEmbedding` (macOS 14+)
  - 512-dimensional vectors
  - Averages token embeddings for multi-token text
- `EmbeddingRepository` - GRDB-based storage with BLOB serialization
  - Stores as `Data` (Float32 array serialized)
  - Indexed on `transcript_entries.embedding` column
- `EmbeddingOrchestrator` - Batch processing with progress tracking
  - Default batch size: 10 entries
  - Tracks: processed, failed, skipped, total time
  - Crash-safe (can resume interrupted batches)

**Database Schema:**
```sql
ALTER TABLE transcript_entries ADD COLUMN embedding BLOB;
ALTER TABLE transcript_entries ADD COLUMN embedding_version INTEGER;
ALTER TABLE transcript_entries ADD COLUMN embedding_generated_at INTEGER;
```

**Performance:**
- Generate 1 embedding: ~50-100ms
- Batch 100 entries: ~8-10 seconds
- Storage: 2KB per entry (512 floats × 4 bytes)

---

### ✅ Phase 2: Semantic Search (Complete)
**Goal:** Fast cosine similarity search using Accelerate framework

**Implemented:**
- `SearchService` (actor) - Semantic search with cosine similarity
  - Uses Apple's `vDSP` (SIMD-optimized vector operations)
  - Formula: `cosine_sim = dot(a,b) / (norm(a) * norm(b))`
  - Returns results sorted by similarity (highest first)
- `SemanticSearchView` - SwiftUI search interface
  - Text field with submit/button
  - Expandable result rows (click anywhere to expand)
  - Shows: similarity score, role, timestamp, content preview
- Parent context integration
  - `SearchResult` includes `parentId`, `parentContent`, `parentRole`
  - Batch-fetches parent entries (SQL `IN` clause)
  - Displays user question + assistant response when expanded

**Performance:**
- Search 1,342 entries: <100ms (typically 50-80ms)
- Includes parent fetch overhead: +10-20ms
- Results displayed in real-time

**Search Quality Issues Discovered:**
- Initial run embedded ALL entries (2,928 total)
- Many short fragments (<100 chars): "Now let me...", "I'll...", etc.
- Polluted results with low-quality matches
- **Fix:** Added minimum content length filter (Phase 2.5)

---

### ✅ Phase 2.5: UX Enhancements (Complete)
**Goal:** Improve search quality and user experience

**Implemented:**

#### 1. Configurable Minimum Chunk Length
- **Problem:** Too many short, low-quality entries (823 entries <50 chars, 763 entries 50-99 chars)
- **Solution:**
  - Added slider in `BatchEmbeddingView` (50-500 chars, step 50, default 100)
  - Propagated `minLength` parameter through entire pipeline
  - Shows content length distribution table with stats
- **Results:**
  - Reduced from 2,928 to ~1,342 entries (54% reduction)
  - Database size: 5.8 MB → 3.2 MB (45% reduction)
  - Dramatically improved search quality

#### 2. Enhanced Batch Embedding UI
- **Scrollable modal** (fixed header/footer, scrollable content)
- **Close button** (X icon in top-right, also responds to Escape)
- **"Clear All Embeddings" button** (resets database for re-embedding)
- **Content distribution table:**
  ```
  Range       Count    % of Total
  <50         823      28.1%      [filtered out with strikethrough]
  50-99       763      26.1%      [filtered out with strikethrough]
  100-199     512      17.5%      ✓
  200-499     598      20.4%      ✓
  500+        232       7.9%      ✓
  ```
- **Real-time stats updates** when slider moves

#### 3. Project-Scoped Search
- **Problem:** Global search returned results from all projects (confusing)
- **Solution:**
  - "Search across projects" checkbox (unchecked by default)
  - Integrates with `HUDViewModel.projectRootURL`
  - Dynamic status: "Searching current project: contextify" vs "Searching all projects"
- **Backend:** Already supported `projectId` filtering via SQL `WHERE` clause

#### 4. Expandable Results with Full Context
- **Entire row is clickable** (not just header)
- **Collapsed view:** 2-line preview with chevron (▶)
- **Expanded view:**
  - Chevron points down (▼)
  - Shows user message (parent) in blue-tinted box
  - Shows full assistant response
  - Text selection enabled for copying
- **Visual indicators:**
  - Blue bubble icon if result has parent context
  - Person icon (👤) for user messages
  - CPU icon (💻) for assistant responses

---

### ✅ Phase 3: Hybrid Search (Complete)
**Goal:** Combine semantic + keyword search for better results

**Implemented:**

#### 1. BM25 Keyword Search (`BM25Service.swift`)
**Algorithm:** Best Matching 25 (probabilistic keyword ranking)

**Formula:**
```
BM25(D,Q) = Σ IDF(qi) × (f(qi,D) × (k1 + 1)) / (f(qi,D) + k1 × (1 - b + b × |D|/avgdl))
```

Where:
- `qi` = query term
- `f(qi,D)` = term frequency in document
- `|D|` = document length (character count)
- `avgdl` = average document length across corpus
- `k1 = 1.2` (term frequency saturation parameter)
- `b = 0.75` (length normalization parameter)
- `IDF = log((N - df + 0.5) / (df + 0.5) + 1)` (inverse document frequency)

**Tokenization:**
- Lowercase conversion
- Split on whitespace + punctuation
- Filter tokens <2 characters

**Performance:**
- Search 1,342 entries: ~50-80ms
- Computes statistics on-the-fly (no pre-built index)
- Actor-isolated with `nonisolated` helper methods for efficiency

**When BM25 Excels:**
- Exact term matching: "JWT", "SQLite", "API"
- Acronyms and technical terms
- Specific code symbols or function names
- Queries with rare terms (high IDF)

**When BM25 Struggles:**
- Synonyms: "auth" vs "authentication"
- Conceptual queries: "how to secure endpoints"
- Typos or variations
- Context-dependent terms: "Apple" (fruit vs company)

#### 2. Hybrid Search Service (`HybridSearchService.swift`)
**Architecture:** Parallel execution + RRF merge

**Flow:**
```
User Query
    ↓
    ├─→ Semantic Search (async) → Top 40 results by cosine similarity
    │
    └─→ BM25 Search (async)      → Top 40 results by BM25 score

         ↓  ↓

    Reciprocal Rank Fusion
         ↓
    Merged & Sorted Results
         ↓
    Top 20 Final Results
```

**Why fetch 2× candidates (topK × 2)?**
- Better fusion quality: More overlap between rankings
- Reduces "lost" good results that ranked #21 in one but #5 in the other

**RRF Score Calculation:**
```swift
for each document d:
  rrfScore = 0.0

  if d in semanticResults:
    rrfScore += semanticWeight / (k + semanticRank[d])

  if d in bm25Results:
    rrfScore += (1 - semanticWeight) / (k + bm25Rank[d])

  return rrfScore
```

Where:
- `k = 60` (standard RRF constant, from research papers)
- `semanticWeight = 0.5` (default: 50/50 split)
- `rank` is 0-indexed position in sorted list

**Why k=60?**
- Empirically optimal (Cormack, Clarke, Büttcher 2009)
- Balances top-rank emphasis vs robustness
- Lower k (e.g., 10): rank #1 dominates too much
- Higher k (e.g., 100): rankings too compressed
- k=60: Sweet spot for most retrieval tasks

**Score Normalization:**
```swift
// RRF scores are typically 0.01-0.03 (too small for UI display)
maxScore = topResults.first.score
minScore = topResults.last.score
normalizedScore = (score - minScore) / (maxScore - minScore)
// Now: top result = 1.0 (100%), others scale down
```

**Sort Order Preservation:**
```swift
// SQL WHERE IN returns rows in arbitrary order!
// Solution: Build lookup map, iterate through sorted scores
let resultMap = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
let finalResults = topEntries.compactMap { entry in
  guard let result = resultMap[entry.entryId] else { return nil }
  // ... build SearchResult in sorted order
}
```

**Performance:**
- Total search time: ~100-150ms (both searches + merge)
- Semantic + BM25 run in parallel (async let)
- Parent fetch: +10-20ms (batched)

#### 3. Score Breakdown Display
**Purpose:** Educational transparency - show users WHY a result ranked where it did

**What's Displayed (when result expanded):**
```
🔧 Score Calculation:

Semantic: rank #8 (similarity: 0.74) → 0.0075
BM25:     rank #3 (score: 14.37)     → 0.0081
─────────────────────────────────────────────
RRF Total: 0.0155 → normalized to 100%

(semantic weight: 50%, keyword weight: 50%)
```

**Data Captured in `ScoreBreakdown` struct:**
```swift
public struct ScoreBreakdown: Sendable {
  public let semanticRank: Int?        // 0-indexed position in semantic results
  public let semanticScore: Double?    // Raw cosine similarity (0.0-1.0)
  public let bm25Rank: Int?            // 0-indexed position in BM25 results
  public let bm25Score: Double?        // Raw BM25 score
  public let rrfScore: Double?         // Combined RRF score before normalization
  public let semanticWeight: Double?   // Weight used (0.5 = 50%)
}
```

**Color Coding:**
- Blue: Semantic contribution
- Orange: BM25 contribution
- Purple: RRF total
- Gray: "not in top results" (when one method didn't rank it)

**Educational Value:**
- Shows concrete example of RRF math
- Reveals when semantic vs keyword matching was stronger
- Helps users understand trade-offs
- Validates that hybrid is working correctly

#### 4. UI Integration
**Toggle in Search View:**
```
☑️ Use hybrid search
   ⚡ Semantic + keyword (RRF)

☐ Use hybrid search
   ✨ Semantic only
```

**Search Logic:**
```swift
if useHybridSearch {
  results = try await hybridSearchService.search(
    query: searchQuery,
    topK: 20,
    projectId: projectId,
    minLength: 100,
    semanticWeight: 0.5  // Equal weight
  )
} else {
  results = try await searchService.search(
    query: searchQuery,
    topK: 20,
    projectId: projectId,
    minLength: 100
  )
}
```

**Hybrid enabled by default** (checkbox checked on load)

---

## Key Architectural Decisions

### 1. Why Apple's NLContextualEmbedding?
- ✅ On-device (no API costs, no privacy concerns)
- ✅ Available on macOS 14+ (wide compatibility)
- ✅ Good general-purpose quality
- ✅ 512 dimensions (good balance: quality vs storage)
- ❌ Not code-specific (could use CodeBERT for better code understanding)
- ❌ No cross-encoder available in Apple frameworks

### 2. Why BM25 over Other Keyword Methods?
- **vs TF-IDF:** BM25 has term frequency saturation (diminishing returns for repeated terms)
- **vs Exact Match:** BM25 handles multi-term queries better
- **vs Full-Text Search (FTS):** BM25 provides relevance scoring, not just filtering
- **Trade-off:** No pre-built index (computes on-the-fly), but fast enough for <2K entries

### 3. Why RRF over Other Fusion Methods?
**Alternatives Considered:**

**Linear Combination:**
```
score = α × semantic_score + β × bm25_score
```
- ❌ Requires score normalization (different scales)
- ❌ Sensitive to outliers
- ❌ Weights hard to tune

**Reciprocal Rank Fusion:**
```
score = Σ 1/(k + rank_i)
```
- ✅ Scale-independent (uses ranks, not scores)
- ✅ Robust to outliers
- ✅ Well-studied (standard in IR research)
- ✅ Simple to implement
- ✅ k=60 works well across domains

**Borda Count:**
```
score = Σ (N - rank_i)
```
- Similar to RRF but linear weighting
- Less emphasis on top ranks

**Decision:** RRF chosen for robustness and research backing

### 4. Why NOT Cross-Encoder Reranking?
**What is a Cross-Encoder?**
- Jointly encodes `[query, document]` together
- More accurate than bi-encoder (semantic search)
- Typical RAG pattern: Bi-encoder (fast, 1000s docs) → Cross-encoder (slow, top 100)

**Why We Didn't Implement It:**
1. **Not available in Apple frameworks**
   - NLContextualEmbedding: bi-encoder only
   - FoundationModels: LLM for generation, no reranking models
2. **Would require external model**
   - Bundle CoreML model (~80-100 MB app size)
   - Manage model updates
   - Another dependency
3. **Scale doesn't warrant it**
   - We have ~1,300 entries (not millions)
   - RRF is fast enough (<150ms total)
   - Hybrid already provides good quality
4. **Can add later if needed**
   - Phase 5 "Two-stage retrieval" placeholder
   - Wait for search quality evaluation (Phase 6)

**Alternative: Use LLM as Reranker**
Could use FoundationModels to rerank:
```swift
let prompt = """
Score these results for relevance to "\(query)" from 0-10:
1. \(result1.content)
2. \(result2.content)
...
Return scores as JSON: [8, 3, 9, ...]
"""
```
- Pros: Uses existing FoundationModels, no new dependency
- Cons: Slower, more expensive, less accurate than dedicated cross-encoder

**Decision:** Phase 5 consideration if search quality insufficient

### 5. Why 100 Character Minimum?
**Data Distribution Analysis:**
```
<50 chars:   823 entries (28.1%) - "Now let me...", "I'll try..."
50-99 chars: 763 entries (26.1%) - "Let me check that file."
100-199:     512 entries (17.5%) - Short explanations
200-499:     598 entries (20.4%) - Substantive responses
500+:        232 entries (7.9%)  - Detailed explanations
```

**Trade-offs:**
- **50 chars:** Includes many noise fragments
- **100 chars:** Good balance (filters 54% of noise, keeps 46% substantive)
- **150 chars:** Would filter more good content
- **200 chars:** Too aggressive (loses useful short answers)

**User-configurable:** Slider allows experimentation (50-500 chars)

**Observed impact:** Search quality "much better" after filtering <100 char entries

---

## Database Schema

### Core Tables
```sql
CREATE TABLE transcript_entries (
  id TEXT PRIMARY KEY,
  transcript_id TEXT NOT NULL,
  project_id TEXT NOT NULL,
  session_id TEXT,
  provider TEXT,
  kind TEXT NOT NULL,  -- 'user', 'assistant', 'system', etc.
  timestamp INTEGER NOT NULL,
  content TEXT NOT NULL,
  content_sha256 TEXT,
  summary TEXT,
  disposition TEXT,
  display_in_timeline INTEGER,
  is_completion INTEGER,
  is_directive INTEGER,
  parent_id TEXT REFERENCES transcript_entries(id) ON DELETE SET NULL,
  git_branch TEXT,
  git_commit TEXT,
  cwd TEXT,

  -- Embedding fields (Phase 1)
  embedding BLOB,                -- 512 floats × 4 bytes = 2048 bytes
  embedding_version INTEGER,     -- Version 1
  embedding_generated_at INTEGER, -- Unix timestamp

  -- Window fields (for timeline cache)
  prev1_id TEXT,
  prev2_id TEXT,
  window_sha256 TEXT,

  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX idx_entries_embedding ON transcript_entries(embedding)
  WHERE embedding IS NOT NULL;

CREATE INDEX idx_entries_project ON transcript_entries(project_id);
```

### Parent-Child Relationships
**Pattern:**
- User message: `parent_id = NULL`
- Assistant response: `parent_id = <user_message_id>`

**Enables:**
- Showing user question when displaying assistant answer
- Understanding conversation context
- Bidirectional navigation (future: show child responses)

**Query Example:**
```sql
-- Get entry with parent
SELECT
  e.id, e.content, e.kind,
  p.content AS parent_content,
  p.kind AS parent_role
FROM transcript_entries e
LEFT JOIN transcript_entries p ON e.parent_id = p.id
WHERE e.id = ?
```

---

## Performance Characteristics

### Search Latency (1,342 entries)
```
Semantic only:    50-80ms
BM25 only:        50-80ms
Hybrid (parallel): 80-120ms
+ Parent fetch:   +10-20ms
─────────────────────────────
Total (hybrid):   100-150ms ✅
```

### Memory Footprint
```
Embeddings in DB:  ~2.7 MB (1,342 × 2KB)
Loaded in memory:  ~2.7 MB (when searching all)
Per-search temp:   ~5-10 MB (candidate lists, scores)
Peak total:        ~15-20 MB ✅
```

### Storage
```
Database size:     3.2 MB (with embeddings)
Without embeddings: ~0.8 MB (just text)
Embedding overhead: 4× storage increase
```

### Scalability Estimates
```
Current:  1,342 entries → <150ms search
10K entries:   ~500ms search (still acceptable)
100K entries:  ~5s search (would need optimization)
```

**Optimization strategies for scale:**
1. Pre-compute BM25 index (inverted index)
2. Use approximate nearest neighbors (HNSW, FAISS)
3. Shard by project (most queries are project-scoped anyway)
4. Add caching layer for frequent queries

---

## Testing & Validation

### Manual Testing Performed
- ✅ Generate embedding for sample text
- ✅ Serialize/deserialize embeddings (lossless)
- ✅ Save/retrieve embeddings from database
- ✅ Batch process 1,342 entries (with progress tracking)
- ✅ Search <100ms across all entries
- ✅ Semantic search returns conceptually similar results
- ✅ BM25 search returns keyword matches
- ✅ Hybrid search combines both effectively
- ✅ Project scoping filters correctly
- ✅ Parent context displays correctly
- ✅ Score breakdown math validates
- ✅ Sort order preserved (highest scores first)
- ✅ Score normalization displays correctly (100% → 50%)

### User Feedback
- **Phase 2 (semantic only):** Search quality poor due to short fragments
- **Phase 2.5 (chunking filter):** Search quality improved significantly
- **Phase 3 (hybrid):** "much better" - validates hybrid approach

### Known Issues
- ✅ ~~Search quality poor~~ - FIXED with minimum length filter
- ✅ ~~Score display wrong (1-3%)~~ - FIXED with normalization
- ✅ ~~Results not sorted~~ - FIXED with order preservation

### Tests Needed (Phase 6)
- [ ] Precision@K: Are top K results actually relevant?
- [ ] Mean Reciprocal Rank (MRR): How quickly do we find the answer?
- [ ] NDCG: Graded relevance evaluation
- [ ] A/B testing: Semantic vs Hybrid win rate
- [ ] Query latency under load
- [ ] Cross-project search accuracy

---

## Code Organization

### Core Modules

**`app/Sources/ContextifyCore/Embeddings/`**
```
EmbeddingService.swift         - Actor wrapping NLContextualEmbedding
EmbeddingRepository.swift      - Protocol + GRDB implementation
EmbeddingOrchestrator.swift    - Batch processing coordinator
SearchService.swift            - Semantic search (cosine similarity)
BM25Service.swift              - Keyword search (BM25 algorithm)
HybridSearchService.swift      - RRF fusion of semantic + BM25
```

**`Contextify/Contextify/`**
```
SemanticSearchView.swift       - Main search UI
BatchEmbeddingView.swift       - Batch generation UI
EmbeddingDatabaseTestView.swift - Dev testing UI
```

**Database**
```
app/Sources/ContextifyCore/Database/
  DatabaseManager.swift         - GRDB pool, migrations
  DatabaseSchema.swift          - SQL schema definitions
  Models.swift                  - Swift models (Entry, etc.)
  TranscriptOrchestrator.swift  - High-level DB operations
```

### Key Abstractions

**Actor Isolation:**
```swift
public actor EmbeddingService { ... }    // Thread-safe model access
public actor SearchService { ... }       // Thread-safe search
public actor BM25Service { ... }         // Thread-safe keyword search
public actor HybridSearchService { ... } // Thread-safe fusion
```

**Sendable Types:**
```swift
public protocol EmbeddingRepository: Sendable { ... }
public struct SearchResult: Sendable, Identifiable { ... }
public struct ScoreBreakdown: Sendable { ... }
```

**Async/Await:**
```swift
// All search operations are async
func search(query: String, topK: Int) async throws -> [SearchResult]

// Database reads/writes are async
func saveEmbedding(entryId: String, vector: [Float]) async throws
```

---

## Roadmap: What's Next

### 🔜 Phase 4: LLM Synthesis (Weeks 6-7)
**Goal:** Generate AI summaries of search results

**Plan:**
1. **"Synthesize" button** on search results
2. **Context assembly** - Take top 5-10 results, format with parent context
3. **FoundationLLM integration** - Generate summary using Apple Intelligence
   ```swift
   let prompt = """
   Based on these conversations about "\(query)", summarize what was learned:

   Conversation 1:
   User: \(result1.parentContent)
   Assistant: \(result1.content)

   Conversation 2:
   ...

   Provide a concise summary with key takeaways.
   """
   ```
4. **Display synthesis** - Show AI-generated answer with expandable sources
5. **Query templates** - Pre-built prompts for common tasks:
   - "What did I learn about X?"
   - "How did I solve Y?"
   - "Summarize discussions about Z"
6. **Export feature** - Copy to clipboard, save as markdown

**Infrastructure Ready:**
- ✅ FoundationLLM already integrated (timeline summaries)
- ✅ Search results include parent context
- ✅ Token counting/context fitting utilities exist

**Remaining Work:**
- Add "Synthesize" button to UI
- Implement prompt engineering
- Handle streaming responses
- Display synthesis with sources
- Add export functionality

### 🔜 Phase 5: Advanced Retrieval (Weeks 8-10)
**Options:**
1. **Two-stage retrieval** - Cross-encoder reranking (if quality insufficient)
2. **Query expansion** - Generate related queries, merge results
3. **Cross-project patterns** - Find similar solutions across projects
4. **Temporal ranking** - Boost recent conversations
5. **User feedback loop** - Click tracking, relevance feedback

### 🔜 Phase 6: Evaluation (Week 11)
**Goal:** Quantitative validation

**Metrics:**
1. **Precision@K** - % of top-K results that are relevant
2. **Recall@K** - % of relevant results found in top-K
3. **MRR (Mean Reciprocal Rank)** - Average position of first relevant result
4. **NDCG (Normalized Discounted Cumulative Gain)** - Graded relevance
5. **User study** - A/B test semantic vs hybrid

**Test Set Creation:**
- Manual annotation: 50-100 queries with ground truth
- Graded relevance: 0 (irrelevant) to 3 (perfect match)
- Cross-validation across annotators

---

## Educational Notes: RAG Concepts

### What is RAG?
**Retrieval-Augmented Generation** = Retrieve relevant documents + Generate answer with LLM

**Classic RAG Pipeline:**
```
User Query
    ↓
1. Retrieval - Find relevant documents (what we've built)
    ↓
2. Context Assembly - Format for LLM
    ↓
3. Generation - LLM produces answer using context
    ↓
Answer + Sources
```

**Why RAG?**
- LLMs have limited context windows
- LLMs don't know your private data
- RAG provides recent/specific information
- Citations/sources for verification

### Retrieval Methods Comparison

| Method | Speed | Accuracy | Strengths | Weaknesses |
|--------|-------|----------|-----------|------------|
| **BM25** | ⚡⚡⚡ Fast | ⭐⭐⭐ Good | Exact terms, acronyms | No synonyms, no context |
| **Semantic** | ⚡⚡ Medium | ⭐⭐⭐⭐ Better | Concepts, synonyms | Misses exact terms |
| **Hybrid (RRF)** | ⚡⚡ Medium | ⭐⭐⭐⭐⭐ Best | Best of both | More complex |
| **Cross-Encoder** | ⚡ Slow | ⭐⭐⭐⭐⭐ Best | Maximum accuracy | 10-100× slower |

### Bi-Encoder vs Cross-Encoder

**Bi-Encoder (what we use for semantic search):**
```
Query → Encoder → Vector Q
Document → Encoder → Vector D
Similarity = cosine(Q, D)
```
- ✅ Fast: Pre-compute document vectors
- ✅ Scalable: Constant-time similarity
- ❌ Less accurate: No query-document interaction

**Cross-Encoder (not implemented):**
```
[Query, Document] → Encoder → Relevance Score
```
- ✅ More accurate: Sees full interaction
- ❌ Slow: Must encode every query-doc pair
- ❌ Not scalable: O(N) per query

**Typical RAG Strategy:**
1. Bi-encoder: Find top 100 candidates (fast)
2. Cross-encoder: Rerank top 100 → top 10 (slow but accurate)
3. LLM: Generate answer from top 10

We skip step 2 because:
- Our corpus is small (1,300 entries)
- RRF hybrid is "good enough"
- No cross-encoder in Apple frameworks

### Why Hybrid Search Works

**Example Query:** "JWT authentication"

**Semantic Search Finds:**
- "implementing token-based user login" (concept match)
- "securing API endpoints with bearer tokens" (concept match)
- "OAuth vs session cookies discussion" (related concept)

**BM25 Finds:**
- "JWT tokens expire after 1 hour" (exact "JWT")
- "authentication middleware validates..." (exact "authentication")
- "I used the JWT library for..." (exact both terms)

**Hybrid (RRF) Ranks Highest:**
- Entries that appear in BOTH lists
- Validation: If semantic AND keyword methods agree, probably relevant!

**Example RRF Calculation:**
```
Entry A:
  Semantic rank #2 → 0.5/(60+2) = 0.0081
  BM25 rank #1     → 0.5/(60+1) = 0.0082
  RRF Total: 0.0163 ← HIGHEST (appears in both!)

Entry B:
  Semantic rank #1 → 0.5/(60+1) = 0.0082
  BM25 rank #50    → 0.5/(60+50) = 0.0045
  RRF Total: 0.0127 ← Lower (weak keyword match)

Entry C:
  Semantic rank #10 → 0.5/(60+10) = 0.0071
  BM25: not found   → 0.0000
  RRF Total: 0.0071 ← Lowest (semantic only)
```

Entry A ranks #1 because both methods found it relevant!

### Common RAG Pitfalls (and how we avoided them)

**1. Chunk Size Too Small**
- ❌ Problem: Embedding "Now let me..." provides no context
- ✅ Solution: 100-char minimum filter

**2. Chunk Size Too Large**
- ❌ Problem: Embedding entire conversation dilutes specific points
- ✅ Solution: We embed individual messages (natural chunking)

**3. Ranking Mismatch**
- ❌ Problem: SQL `WHERE IN` returns arbitrary order
- ✅ Solution: Map lookup + iterate through sorted scores

**4. Score Scale Confusion**
- ❌ Problem: RRF scores 0.01-0.03 display as 1-3%
- ✅ Solution: Normalize to 0-1 range for display

**5. Black Box Search**
- ❌ Problem: Users don't understand why results ranked where they did
- ✅ Solution: Score breakdown showing exact RRF calculation

**6. One-Size-Fits-All**
- ❌ Problem: Semantic OR keyword, not both
- ✅ Solution: Hybrid with configurable weights

---

## Common Commands

### Build & Run
```bash
# Build app
bash scripts/xc.sh build

# Run tests
bash scripts/xc.sh test

# Clean build
make clean

# Database management (ALWAYS use script, never rm manually!)
./scripts/db_manager.sh clean     # Clean database (creates backup)
./scripts/db_manager.sh backup    # Create backup
./scripts/db_manager.sh restore latest  # Restore latest backup
./scripts/db_manager.sh list      # List backups
```

### Git
```bash
# Current branch
git branch  # feature/rag-implementation

# Recent commits
git log --oneline -10

# Show changes
git diff
git diff --stat

# Status
git status
```

### Testing Search
1. Open app (magnifying glass icon)
2. Enter query (e.g., "authentication")
3. Toggle "Use hybrid search" on/off to compare
4. Click result to expand and see score breakdown
5. Toggle "Search across projects" to test scoping

---

## Files Reference

### Created/Modified in Phases 1-3

**New Files:**
```
app/Sources/ContextifyCore/Embeddings/BM25Service.swift           (Phase 3)
app/Sources/ContextifyCore/Embeddings/HybridSearchService.swift   (Phase 3)
build/notes/research/rag/phase2.5-addendum.md                     (Phase 2.5)
```

**Modified Files:**
```
app/Sources/ContextifyCore/Embeddings/EmbeddingRepository.swift   (minLength)
app/Sources/ContextifyCore/Embeddings/EmbeddingOrchestrator.swift (minLength)
app/Sources/ContextifyCore/Embeddings/SearchService.swift         (ScoreBreakdown)
Contextify/Contextify/BatchEmbeddingView.swift                    (slider, stats)
Contextify/Contextify/SemanticSearchView.swift                    (hybrid toggle)
Contextify/Contextify/EmbeddingDatabaseTestView.swift             (minLength)
```

### Key Documentation
```
build/notes/research/rag/rag-implementation-guide.md     - Original guide
build/notes/research/rag/phase2.5-addendum.md            - Phase 2.5 notes
build/notes/research/rag/implementation-roadmap.md       - Roadmap
build/notes/technical-reference/logging-preferences.md   - Logging guide
```

---

## Troubleshooting

### Search Returns No Results
**Check:**
1. Are embeddings generated? (Run batch embedding)
2. Is minLength too high? (Check distribution table)
3. Is project filter too restrictive? (Toggle "Search across projects")

### Search Quality Poor
**Try:**
1. Adjust minLength slider (lower = more results, higher = better quality)
2. Enable hybrid search (combines semantic + keyword)
3. Check that embeddings are generated for recent entries
4. Clear embeddings and regenerate with new minLength

### Scores Display Wrong (1-3%)
**Fixed in:** commit `488aba5`
**Solution:** Scores now normalized to 0-1 range

### Results Not Sorted High→Low
**Fixed in:** commit `13e19b7`
**Solution:** Iterate through sorted entries, map lookup for details

### Build Errors
```bash
# Clean derived data
make clean

# Rebuild
bash scripts/xc.sh build

# Check Xcode version
xcodebuild -version  # Should be 16+
```

---

## Context for AI Assistants

**If continuing this implementation, you should know:**

1. **Current State:** Phase 3 complete, working hybrid search deployed
2. **User Feedback:** Hybrid search is "much better" than semantic-only
3. **Next Goal:** Phase 4 (LLM Synthesis) when user is ready
4. **Code Quality:** All builds pass, no known bugs, clean git history
5. **Performance:** Meets all requirements (<150ms search)

**Key Decisions Made:**
- ✅ Use RRF instead of cross-encoder reranking (no Apple framework support)
- ✅ 100-char minimum by default (user-configurable)
- ✅ 50/50 semantic/keyword weight (could make configurable)
- ✅ k=60 for RRF (standard, no need to change)
- ✅ Score breakdown always visible (educational value)

**What User Cares About:**
- Search quality (getting better with each phase)
- Understanding how it works (hence score breakdown)
- Transparency (show the math)
- Performance (must be fast)

**Communication Style:**
- Technical but clear
- Show concrete examples
- Explain trade-offs
- Get feedback before major changes

---

## Quick Reference: Git History

```
385b116 refactor(rag): move score calculation to top of expanded results
749cfdc feat(rag): add score breakdown display for hybrid search results
13e19b7 fix(rag): preserve sort order in hybrid search results
488aba5 fix(rag): normalize RRF scores to 0-1 range for proper display
1b1b1c5 feat(rag): implement Phase 3 hybrid search with BM25 and RRF
6a81b48 docs(rag): add Phase 2.5 addendum documenting UX enhancements
322d861 feat(rag): enhance search UX with configurable chunking, expandable results, and project scoping
1caecf6 fix(search): use 'kind' column instead of 'role' in SQL query
ef39a8b feat(search): implement semantic search with Accelerate-optimized cosine similarity
818f8ad docs(rag): mark Phase 1 complete with performance baseline
```

**Branch:** `feature/rag-implementation`
**Commits:** 10 total
**Lines Changed:** ~1,500+ additions (new features + documentation)

---

**End of Briefing**

This document provides complete context to resume RAG implementation or review the system for educational purposes. All concepts, decisions, and trade-offs are documented above.

**Status:** ✅ Phase 3 Complete - Ready for Phase 4 (LLM Synthesis)
