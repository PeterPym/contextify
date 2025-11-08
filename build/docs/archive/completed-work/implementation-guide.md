# RAG Implementation Guide for Contextify
**Retrieval-Augmented Generation for Coding Conversation Knowledge Base**

**Version:** 1.0
**Date:** 2025-10-19
**Status:** Research & Planning Phase

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [Goals & Expected Outcomes](#goals--expected-outcomes)
4. [Apple AI Stack Architecture](#apple-ai-stack-architecture)
5. [RAG Fundamentals](#rag-fundamentals)
6. [Detailed Implementation Phases](#detailed-implementation-phases)
7. [Key Learning Objectives](#key-learning-objectives)
8. [Scope & Success Criteria](#scope--success-criteria)
9. [References & Resources](#references--resources)
10. [Glossary](#glossary)

---

## Executive Summary

This document outlines a comprehensive plan to implement a **Retrieval-Augmented Generation (RAG) system** for Contextify's coding conversation knowledge base using **Apple's on-device AI stack**. The system will enable semantic search across conversation history and LLM-powered insight generation, all while maintaining privacy through on-device processing.

### Why This Approach?

**Strong Foundation**: Contextify already has structured conversation data in SQL with rich metadata (project, session, timestamp, roles). This is 80% of what RAG needs.

**Apple-Only Constraint = Feature**: Using NLContextualEmbedding (macOS 14+) for embeddings and FoundationModels (macOS 26+) for LLM inference teaches real-world RAG constraints (4096 token limit) without external API dependencies.

**Practical Learning**: Building RAG for your own conversation history is highly motivating compared to abstract tutorials on external datasets.

### What You'll Build

- **Semantic Search**: Find relevant conversation chunks by meaning, not just keywords
- **Cross-Project Insights**: Discover patterns in how you solve problems across projects
- **Context Resumption**: Export relevant history as a new transcript to continue in Claude/Codex
- **Progress Tracking**: Surface work across multiple concurrent development threads

### Estimated Effort

**8-12 weeks** across 6 implementation phases, from basic embeddings to advanced retrieval optimization.

---

## Current State Analysis

### What Already Exists

#### 1. SQL Backend with Structured Data ✅
**Location**: `app/Sources/ContextifyCore/Database/`

- **DatabaseManager**: GRDB connection pool, WAL mode, migrations
- **TranscriptOrchestrator**: High-level API for projects, transcripts, entries
- **Repositories**: Type-safe CRUD operations (Project, Transcript, Entry, Metadata, Cache)
- **HooverEngine**: Streaming JSONL ingestion with checkpointing
- **TranscriptWatcher**: Real-time file monitoring

**Schema** (`DatabaseSchema.swift`):
```sql
-- Core entities
projects (id, name, root_path, created_at, updated_at)
transcripts (id, project_id, file_path, provider, session_id, ...)
transcript_entries (
  id, transcript_id, project_id,
  role, content, timestamp,  -- ← RAG candidates
  content_sha256, window_sha256,
  display_in_timeline
)

-- Metadata & caching
transcript_metadata (transcript_id, title, description, topics, ...)
timeline_cache (content_sha256, window_sha256, present_form, past_form, ...)
parse_errors (transcript_id, line_number, raw_line, error_message)
```

**Key Insight**: `transcript_entries` contains all conversational content (user messages, assistant responses, tool calls) with rich metadata. This is the primary RAG corpus.

#### 2. Basic Keyword Search ⚠️
**Location**: `app/Sources/ContextifyCore/Database/Repositories.swift:279-287`

```swift
public func search(content: String, projectId: String? = nil) throws -> [TranscriptEntry] {
  try db.read { db in
    var query = TranscriptEntry.filter(Column("content").like("%\(content)%"))
    if let projectId = projectId {
      query = query.filter(Column("project_id") == projectId)
    }
    return try query.order(Column("timestamp").desc).fetchAll(db)
  }
}
```

**Limitations**:
- SQL `LIKE` pattern matching only (no semantic understanding)
- No ranking by relevance (just timestamp desc)
- Substring matches are brittle ("fix bug" won't match "bugfix")
- Not exposed in UI (searchable() in TranscriptInventoryView only filters local metadata)

#### 3. LLM Integration ✅
**Location**: `Contextify/Contextify/FoundationLLM.swift`

- **FoundationModels** integration (macOS 26+)
- Timeline summary generation (present/past forms)
- 4096 token context window
- Stateful/stateless session management
- Structured output via `@Generable` schemas

**Key Insight**: Already has LLM plumbing for synthesis tasks. RAG will extend this to work with retrieved chunks.

#### 4. Metadata Generation ✅
**Location**: `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`

- LLM-powered transcript titles, descriptions, topics
- Confidence scoring, hallucination detection
- SQL persistence via `TranscriptMetadataRecord`

### What's Missing (RAG Gap Analysis)

| Component             | Status    | Gap                                               |
| --------------------- | --------- | ------------------------------------------------- |
| **Embeddings**        | ❌ Missing | No vector representations of conversation content |
| **Vector Storage**    | ❌ Missing | No schema for embedding columns or indexing       |
| **Semantic Search**   | ❌ Missing | No similarity-based retrieval                     |
| **Hybrid Search**     | ❌ Missing | Can't combine semantic + metadata filters         |
| **Retrieval Ranking** | ❌ Missing | No relevance scoring or re-ranking                |
| **Context Assembly**  | ❌ Missing | No prompt construction from retrieved chunks      |
| **Evaluation**        | ❌ Missing | No metrics for retrieval quality                  |

---

## Goals & Expected Outcomes

### Primary Goals

1. **Master RAG Fundamentals**: Deep understanding of embeddings, retrieval, ranking, and context assembly through hands-on implementation

2. **Build Production-Ready Search**: Semantic search over conversation history with <1s latency for <10k entries

3. **Generate Actionable Insights**: Use FoundationLLM to synthesize patterns from retrieved chunks within 4096 token budget

4. **Enable Knowledge Continuity**: Export relevant context as resumable transcripts for Claude Code/Codex CLI

### Expected Outcomes

#### Phase 1 Deliverables (Weeks 1-2)
- ✅ NLContextualEmbedding integration with asset management
- ✅ Batch embedding generation for all existing entries
- ✅ DB schema extended with embedding storage
- ✅ Progress tracking + resumability for long-running jobs

#### Phase 2 Deliverables (Week 3)
- ✅ Cosine similarity search (top-k retrieval)
- ✅ Basic search UI (query → results with similarity scores)
- ✅ Performance baseline (<100ms for 1k entries)

#### Phase 3 Deliverables (Weeks 4-5)
- ✅ Hybrid search (semantic + SQL filters)
- ✅ Keyword boosting (BM25-inspired)
- ✅ Reciprocal Rank Fusion for result merging
- ✅ Advanced UI filters (project, session, date range, role)

#### Phase 4 Deliverables (Weeks 6-7)
- ✅ Context assembly pipeline (chunks → formatted prompt)
- ✅ FoundationLLM integration for insight synthesis
- ✅ Query type templates:
  - "How did I handle X?" → approach summary
  - "Show me all Y" → cross-project patterns
  - "Status of Z?" → progress tracking
- ✅ Export feature (relevant context → new transcript file)

#### Phase 5 Deliverables (Weeks 8-10)
- ✅ Two-stage retrieval (retrieve 100, re-rank to 10)
- ✅ Query expansion (single query → multiple semantic searches)
- ✅ Cross-project pattern detection
- ✅ Temporal weighting (recent vs historical relevance)

#### Phase 6 Deliverables (Week 11)
- ✅ Test query set (20-50 curated queries with ground truth)
- ✅ Automated metric calculation (Precision@k, MRR, NDCG)
- ✅ A/B testing framework for retrieval strategies
- ✅ Quality monitoring dashboard

### Success Criteria

| Metric               | Target                   | Rationale                                             |
| -------------------- | ------------------------ | ----------------------------------------------------- |
| **Precision@10**     | ≥80%                     | Most queries return highly relevant results in top 10 |
| **Search Latency**   | <1s for <10k entries     | Interactive user experience                           |
| **Context Quality**  | ≥70% user satisfaction   | Generated insights are useful and grounded            |
| **Token Efficiency** | ≤3500 tokens/query       | Leave headroom for LLM output within 4096 limit       |
| **Coverage**         | 100% of entries embedded | All conversation history searchable                   |

---

## Apple AI Stack Architecture

### Component Overview

Contextify's RAG system uses **Apple's on-device AI frameworks** for privacy-preserving, offline-capable search and synthesis.

```
┌─────────────────────────────────────────────────────────────┐
│                   Contextify RAG Stack                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────┐      ┌─────────────────────┐     │
│  │ NLContextualEmbedding│      │  FoundationModels   │     │
│  │   (macOS 14+)        │      │    (macOS 26+)      │     │
│  ├─────────────────────┤      ├─────────────────────┤     │
│  │ • 512-dim vectors    │      │ • 4096 token limit  │     │
│  │ • BERT-based         │      │ • Structured output │     │
│  │ • Multilingual       │      │ • Session mgmt      │     │
│  │ • On-device          │      │ • On-device         │     │
│  └─────────────────────┘      └─────────────────────┘     │
│           ▲                              ▲                  │
│           │ Embeddings                   │ Synthesis        │
│           │                              │                  │
│  ┌────────┴────────────────────────────┴─────────┐        │
│  │         RAG Orchestration Layer               │        │
│  ├───────────────────────────────────────────────┤        │
│  │ • Query → Embeddings                          │        │
│  │ • Vector Similarity Search                    │        │
│  │ • Hybrid Filtering (semantic + SQL)           │        │
│  │ • Context Assembly (chunks → prompt)          │        │
│  │ • Insight Generation (LLM synthesis)          │        │
│  └───────────────────────────────────────────────┘        │
│                       ▲                                     │
│                       │ GRDB (WAL mode)                     │
│  ┌────────────────────┴───────────────────────────┐       │
│  │           SQL Database                         │       │
│  ├────────────────────────────────────────────────┤       │
│  │ • transcript_entries (content, metadata)       │       │
│  │ • entry_embeddings (vector BLOBs)              │       │
│  │ • similarity indices (optional HNSW)           │       │
│  └────────────────────────────────────────────────┘       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### NLContextualEmbedding (Retrieval)

**Framework**: `NaturalLanguage.framework`
**Availability**: macOS 14.0+ (Sonoma), iOS 17.0+
**Introduced**: WWDC 2023

#### Key Features

1. **Transformer-Based Sentence Embeddings**
   - Uses multilingual BERT architecture
   - Analyzes entire string to produce single 512-dimensional vector
   - Captures semantic meaning, not just keyword overlap

2. **On-Device Asset Management**
   ```swift
   // Request embedding model for language
   let embeddingModel = try await NLContextualEmbedding.contextualEmbedding(for: .english)
   
   // Check availability
   if embeddingModel.embeddingAvailable {
     let vector = try embeddingModel.vector(for: "How do I fix authentication bugs?")
     // vector: [Float] with 512 elements
   }
   ```

3. **Privacy Advantages**
   - No network round-trips
   - No data leaves device
   - Works offline
   - Zero inference costs

4. **Performance Characteristics**
   - Embedding generation: ~10-50ms per string (device-dependent)
   - Vector size: 512 × 4 bytes = 2KB per entry
   - Asset download: ~200MB one-time (per language)

#### Limitations

- **No fine-tuning**: Can't customize for domain-specific language (but coding conversations are general enough)
- **Fixed dimensionality**: 512 dims (vs. OpenAI's 1536 or 3072) - sufficient for on-device search
- **Language-specific models**: Must request appropriate language assets

### FoundationModels (Synthesis)

**Framework**: `FoundationModels.framework`
**Availability**: macOS 26.0+ (Tahoe)
**Introduced**: WWDC 2025

#### Key Features (Already Integrated)

1. **Structured Generation** (`@Generable` macro)
   - Type-safe JSON output
   - Schema validation
   - Field-level guidance via `@Guide`

2. **Session Management** (via `FoundationLLM.swift`)
   - Stateful conversations (up to 15 requests)
   - Stateless mode for fresh context
   - Circuit breakers for error recovery

3. **Context Window: 4096 tokens**
   - **This is a feature for RAG**: Forces disciplined retrieval
   - Typical breakdown:
     - System instructions: 300-500 tokens
     - Retrieved context: 2500-3000 tokens
     - User query: 50-200 tokens
     - LLM output: 150-500 tokens

#### Integration Points

**Existing** (`FoundationLLM.swift`):
```swift
// Timeline summaries (already working)
func summarizeTimeline(kind: TimelineEntryKind, text: String, ...) async throws -> TimelineSummaryResult

// Generic guided generation (new for RAG)
func generateGuided<T: Generable>(
  instructions: String,
  prompt: String,
  generating: T.Type,
  options: GenerationOptions
) async throws -> T
```

**New for RAG**:
```swift
// Insight synthesis from retrieved chunks
func synthesizeInsight(
  query: String,
  retrievedChunks: [TranscriptEntry],
  instructions: String
) async throws -> InsightResult {
  let context = assembleContext(chunks: retrievedChunks, tokenLimit: 3000)
  return try await generateGuided(
    instructions: instructions,
    prompt: "QUERY: \(query)\n\nCONTEXT:\n\(context)",
    generating: InsightResult.self,
    options: GenerationOptions(...)
  )
}
```

---

## RAG Fundamentals

This section covers core RAG concepts from first principles to state-of-the-art techniques. Understanding these will enable you to build, optimize, and debug your system.

### 1. Embeddings & Vector Representations

#### What Are Embeddings?

**Definition**: Embeddings are dense, continuous vector representations of discrete data (text, images, etc.) in a high-dimensional space where semantically similar items are closer together.

**Example**:
```
"fix authentication bug"    → [0.23, -0.45, 0.67, ..., 0.12]  (512 dims)
"debug login issue"         → [0.21, -0.43, 0.65, ..., 0.14]  (similar vector)
"install dependencies"      → [-0.54, 0.78, -0.32, ..., 0.91] (distant vector)
```

**Distance Metric**: Cosine similarity measures angle between vectors:
```
similarity = (A · B) / (||A|| × ||B||)
Range: [-1, 1] where 1 = identical, 0 = orthogonal, -1 = opposite
```

#### Why 512 Dimensions Is Sufficient

**Intuition**: Higher dimensions allow more nuanced distinctions, but with diminishing returns.

| Model                         | Dimensions | Use Case                            |
| ----------------------------- | ---------- | ----------------------------------- |
| Word2Vec                      | 100-300    | Word-level similarity               |
| BERT (base)                   | 768        | Sentence-level semantics            |
| **NLContextualEmbedding**     | **512**    | **General sentence similarity**     |
| OpenAI text-embedding-3-large | 3072       | Extreme precision for large corpora |

**For Contextify**: With <10k conversation entries, 512 dims provides sufficient discriminative power. The bottleneck is retrieval quality (chunking, query formulation), not dimensionality.

#### Dense vs. Sparse Embeddings

**Dense** (e.g., BERT, NLContextualEmbedding):
- Every dimension has non-zero value
- Captures semantic relationships learned from training data
- Better for "fuzzy" matching ("debugging" ≈ "troubleshooting")

**Sparse** (e.g., TF-IDF, BM25):
- Most dimensions are zero
- Represents presence/absence of specific terms
- Better for exact keyword matching ("import SwiftUI")

**Hybrid Approach** (Phase 3): Combine both for best results.

### 2. Chunking Strategies

#### The Chunking Problem

Conversation entries vary wildly in length:
- User message: "fix this" (2 tokens)
- Assistant response with code: 2000+ tokens
- Tool call output: 500-1000 tokens

**Challenge**: How do you create semantically coherent, searchable units?

#### Chunking Strategies

##### A. Entry-Level Chunking (Simple, Start Here)
**Definition**: One embedding per `transcript_entry` record.

**Pros**:
- Simple 1:1 mapping (entry.id → embedding)
- Preserves conversation context (user message + assistant response)
- Metadata already attached (project, session, timestamp, role)

**Cons**:
- Long entries (>1000 tokens) dilute semantic signal
- Irrelevant parts reduce retrieval precision

**Best for**: Initial implementation (Phase 1-2)

##### B. Message-Level Chunking (Medium Complexity)
**Definition**: Split multi-part entries into individual messages.

**Example**: Claude Code entry with tool calls:
```
Original Entry (2000 tokens):
  - Assistant message: "I'll fix the authentication bug..." (200 tokens)
  - Tool call: Bash "grep -r 'auth' src/" (50 tokens)
  - Tool result: [1500 tokens of output]
  - Assistant message: "Found the issue..." (250 tokens)

Chunked:
  - Chunk 1: "I'll fix the authentication bug..." (200 tokens)
  - Chunk 2: "Bash grep result: [truncated]" (300 tokens)
  - Chunk 3: "Found the issue..." (250 tokens)
```

**Pros**:
- Focused embeddings (one semantic unit per chunk)
- Better precision (tool output chunk won't pollute assistant analysis)

**Cons**:
- More complex (need to parse content blocks)
- Requires joining chunks during context assembly

**Best for**: Phase 5 optimization

##### C. Sliding Window Chunking (Advanced)
**Definition**: Overlapping chunks to preserve context boundaries.

**Example**:
```
Text: "The authentication system uses JWT tokens. Tokens expire after 1 hour. We should implement refresh logic."

Fixed chunks (no overlap):
  - Chunk 1: "The authentication system uses JWT tokens."
  - Chunk 2: "Tokens expire after 1 hour."
  - Chunk 3: "We should implement refresh logic."

Sliding window (50% overlap):
  - Chunk 1: "The authentication system uses JWT tokens. Tokens expire after 1 hour."
  - Chunk 2: "Tokens expire after 1 hour. We should implement refresh logic."
```

**Pros**:
- Context preserved at boundaries
- Reduces information loss from arbitrary splits

**Cons**:
- Storage overhead (2x embeddings for 50% overlap)
- Duplicate results in retrieval (need deduplication)

**Best for**: Phase 5+ if entry-level chunking shows boundary issues

##### D. Semantic Chunking (State-of-the-Art)
**Definition**: Split at natural semantic boundaries (paragraphs, topic shifts).

**Techniques**:
1. **Sentence Boundary Detection**: Use NLTokenizer to split at sentences
2. **Topic Modeling**: Detect when topic changes (e.g., LDA, sentence similarity)
3. **Hierarchical Chunking**: Parent chunks (full entry) + child chunks (paragraphs)

**Example**:
```
Entry: "First, I'll analyze the bug. <analysis>... Next, here's the fix: <code>..."

Semantic chunks:
  - Chunk 1 (analysis): "First, I'll analyze the bug. <analysis>..."
  - Chunk 2 (solution): "Next, here's the fix: <code>..."
```

**Pros**:
- Highest retrieval quality (chunks are semantically coherent)
- Natural language understanding

**Cons**:
- Complex implementation (requires NLP or LLM calls)
- Higher computational cost

**Best for**: Phase 5+ research (may not be needed for conversation data)

#### Recommended Approach for Contextify

**Phase 1-2**: Entry-level chunking
**Phase 3-4**: Add keyword extraction for hybrid search
**Phase 5**: Evaluate message-level chunking if precision is insufficient
**Phase 6**: Research semantic chunking only if measurable quality gains

### 3. Vector Storage & Indexing

#### Storage Options

##### Option A: SQL BLOB Column (Recommended for Phase 1-3)

**Schema**:
```sql
ALTER TABLE transcript_entries ADD COLUMN embedding BLOB;  -- 512 floats × 4 bytes = 2048 bytes
ALTER TABLE transcript_entries ADD COLUMN embedding_version INTEGER DEFAULT 1;
CREATE INDEX idx_entries_embedding_version ON transcript_entries(embedding_version);
```

**Pros**:
- Simple: Single source of truth (entries + embeddings in same table)
- GRDB integration: Works with existing repository pattern
- Transaction safety: Embeddings can't get out of sync

**Cons**:
- No native vector indexing in SQLite
- Full scan required for similarity search (acceptable for <10k entries)

**Implementation**:
```swift
// Serialize [Float] to Data
func serializeEmbedding(_ vector: [Float]) -> Data {
  vector.withUnsafeBufferPointer { Data(buffer: $0) }
}

// Deserialize Data to [Float]
func deserializeEmbedding(_ data: Data) -> [Float] {
  data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

// Store
try db.write { db in
  var entry = try TranscriptEntry.fetchOne(db, key: entryId)
  entry.embedding = serializeEmbedding(vector)
  entry.embeddingVersion = 1
  try entry.update(db)
}
```

##### Option B: Separate Vector Table (Future Optimization)

**Schema**:
```sql
CREATE TABLE entry_embeddings (
  entry_id TEXT PRIMARY KEY,
  vector BLOB NOT NULL,
  version INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (entry_id) REFERENCES transcript_entries(id) ON DELETE CASCADE
);
```

**Pros**:
- Faster queries (smaller table scan)
- Easier versioning (re-embed without touching main table)

**Cons**:
- Join overhead
- More complex query logic

**Best for**: Phase 5+ if performance profiling shows need

##### Option C: Dedicated Vector DB (HNSW Indexing)

**Options**:
- **ObjectBox Swift** (local HNSW index, iOS/macOS)
- **SQLite Vector Extension** (compile-time extension)
- **Faiss** (Facebook's vector search library, C++ bridge)

**When to Consider**:
- >50k entries
- Sub-100ms search latency required
- Willingness to add external dependencies

**For Contextify**: Likely **not needed** until >10k entries. Brute-force cosine similarity is fast enough.

#### Indexing Strategies

##### Brute-Force Search (Phase 1-3)
**Algorithm**:
```swift
func search(queryEmbedding: [Float], k: Int) -> [ScoredEntry] {
  let allEntries = try fetchAllEntriesWithEmbeddings()
  let scored = allEntries.map { entry in
    (entry: entry, score: cosineSimilarity(queryEmbedding, entry.embedding))
  }
  return scored.sorted { $0.score > $1.score }.prefix(k)
}
```

**Complexity**: O(N) where N = number of entries
**Performance**: ~1ms per 1000 entries on modern Macs (512-dim cosine)

##### HNSW (Hierarchical Navigable Small Worlds) - Advanced

**Concept**: Graph-based approximate nearest neighbor search.

**Trade-offs**:
- **Build time**: O(N log N) to construct graph
- **Query time**: O(log N) approximate search
- **Accuracy**: 90-99% recall@10 (configurable)

**When to Use**: >10k entries, need <100ms latency

### 4. Retrieval Techniques

#### Core Retrieval: Cosine Similarity Search

**Algorithm**:
```swift
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
  precondition(a.count == b.count)

  let dotProduct = zip(a, b).map(*).reduce(0, +)
  let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
  let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

  return dotProduct / (magnitudeA * magnitudeB)
}

func search(query: String, k: Int) async throws -> [ScoredEntry] {
  // 1. Generate query embedding
  let embedding = try await embeddingModel.vector(for: query)

  // 2. Fetch all entries with embeddings
  let entries = try await fetchEntriesWithEmbeddings()

  // 3. Score and rank
  let scored = entries.map { entry in
    ScoredEntry(
      entry: entry,
      score: cosineSimilarity(embedding, entry.embedding)
    )
  }

  // 4. Return top-k
  return scored.sorted { $0.score > $1.score }.prefix(k).map { $0 }
}
```

**Optimization**: Use Accelerate framework for SIMD vectorization:
```swift
import Accelerate

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
  var dotProduct: Float = 0
  var normA: Float = 0
  var normB: Float = 0

  vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
  vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
  vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))

  return dotProduct / (sqrt(normA) * sqrt(normB))
}
```

**Performance**: ~10-20x faster for 512-dim vectors

#### Hybrid Search (Semantic + Keyword + Metadata)

**Concept**: Combine multiple scoring signals for better results.

**Components**:
1. **Semantic Score**: Cosine similarity from embeddings
2. **Keyword Score**: BM25-style term frequency scoring
3. **Metadata Boost**: Recency, project relevance, role filters

**Implementation** (Phase 3):
```swift
struct HybridSearchQuery {
  let text: String                    // For semantic search
  let keywords: [String]              // For keyword boosting
  let projectId: String?              // Filter
  let sessionId: String?              // Filter
  let dateRange: ClosedRange<Date>?   // Filter
  let roles: [String]?                // Filter (user, assistant, system)

  let weights: SearchWeights = .default
}

struct SearchWeights {
  let semantic: Float = 0.7
  let keyword: Float = 0.2
  let recency: Float = 0.1

  static let `default` = SearchWeights()
}

func hybridSearch(query: HybridSearchQuery, k: Int) async throws -> [ScoredEntry] {
  // 1. Filter by metadata (SQL WHERE clauses)
  var sqlFilters: [String] = []
  if let projectId = query.projectId {
    sqlFilters.append("project_id = '\(projectId)'")
  }
  if let roles = query.roles {
    sqlFilters.append("role IN (\(roles.map { "'\($0)'" }.joined(separator: ",")))")
  }

  // 2. Fetch filtered candidates
  let candidates = try await fetchEntriesWithEmbeddings(where: sqlFilters)

  // 3. Semantic scoring
  let queryEmbedding = try await embeddingModel.vector(for: query.text)
  var scored = candidates.map { entry in
    ScoredEntry(
      entry: entry,
      score: cosineSimilarity(queryEmbedding, entry.embedding)
    )
  }

  // 4. Keyword boosting
  for keyword in query.keywords {
    for i in scored.indices {
      if scored[i].entry.content.localizedCaseInsensitiveContains(keyword) {
        scored[i].score += 0.1  // Boost by 0.1 per keyword match
      }
    }
  }

  // 5. Recency boosting
  let now = Date()
  for i in scored.indices {
    let age = now.timeIntervalSince(scored[i].entry.timestamp)
    let recencyScore = exp(-age / (30 * 24 * 3600))  // Decay over 30 days
    scored[i].score += recencyScore * query.weights.recency
  }

  // 6. Normalize and rank
  scored.sort { $0.score > $1.score }
  return Array(scored.prefix(k))
}
```

#### Reciprocal Rank Fusion (RRF)

**Problem**: How do you merge results from multiple ranking systems (semantic, keyword, metadata)?

**Solution**: Reciprocal Rank Fusion weights results by their position in each ranking.

**Algorithm**:
```swift
func reciprocalRankFusion(
  rankingsFromSources: [[ScoredEntry]],
  k: Int = 60  // RRF constant (typical: 60)
) -> [ScoredEntry] {
  var fusedScores: [String: Float] = [:]  // entry.id → RRF score

  for ranking in rankingsFromSources {
    for (rank, scoredEntry) in ranking.enumerated() {
      let rrfScore = 1.0 / Float(k + rank + 1)
      fusedScores[scoredEntry.entry.id, default: 0] += rrfScore
    }
  }

  // Sort by fused score
  return fusedScores
    .sorted { $0.value > $1.value }
    .compactMap { id, _ in rankings.first?.first { $0.entry.id == id } }
    .prefix(k)
    .map { $0 }
}
```

**Example**:
```
Semantic ranking: [A, B, C, D]
Keyword ranking:  [C, A, E, F]

RRF scores (k=60):
  A: 1/61 + 1/62 = 0.0328
  C: 1/63 + 1/61 = 0.0323
  B: 1/62 + 0    = 0.0161
  E: 0    + 1/63 = 0.0159

Final ranking: [A, C, B, E, D, F]
```

#### Query Expansion

**Problem**: User queries are often short and underspecified ("auth bug").

**Solution**: Expand query into multiple semantic variations.

**Techniques**:

1. **Synonym Expansion**:
```
"auth bug" → ["authentication bug", "login issue", "credential error"]
```

2. **LLM-Based Expansion** (Phase 5):
```swift
func expandQuery(_ query: String) async throws -> [String] {
  let prompt = """
    Generate 3 semantic variations of this search query:
    "\(query)"

    Variations should cover:
    1. Synonym substitution
    2. More specific phrasing
    3. Related concepts
    """

  let result = try await FoundationLLM.shared.rawWithInstructions(
    instructions: "You are a search query expander.",
    prompt: prompt,
    options: GenerationOptions(maximumResponseTokens: 100)
  )

  return result.split(separator: "\n").map(String.init)
}
```

3. **Search Multiple Embeddings**:
```swift
let expandedQueries = try await expandQuery(userQuery)
let allResults = try await expandedQueries.asyncMap { query in
  try await search(query: query, k: 20)
}
let fused = reciprocalRankFusion(rankingsFromSources: allResults)
```

#### Re-Ranking (Two-Stage Retrieval)

**Concept**: Fast approximate retrieval (stage 1) → expensive re-ranking (stage 2).

**Why**: Computing deep semantic similarity for all entries is slow. Instead:
1. **Stage 1**: Retrieve top 100 candidates via fast cosine similarity
2. **Stage 2**: Re-rank top 100 using expensive methods (cross-encoder, LLM scoring)

**Implementation** (Phase 5):
```swift
func twoStageRetrieval(query: String, k: Int) async throws -> [ScoredEntry] {
  // Stage 1: Fast retrieval (top 100)
  let candidates = try await search(query: query, k: 100)

  // Stage 2: Re-rank with LLM (expensive but accurate)
  let reranked = try await candidates.asyncMap { candidate in
    let relevanceScore = try await scoreRelevance(
      query: query,
      candidate: candidate.entry
    )
    return ScoredEntry(entry: candidate.entry, score: relevanceScore)
  }

  return reranked.sorted { $0.score > $1.score }.prefix(k).map { $0 }
}

func scoreRelevance(query: String, candidate: TranscriptEntry) async throws -> Float {
  let prompt = """
    Rate the relevance of this conversation entry to the query on a scale of 0.0 to 1.0.

    QUERY: \(query)

    ENTRY: \(candidate.content.prefix(500))

    Output only a number between 0.0 and 1.0.
    """

  let score = try await FoundationLLM.shared.rawWithInstructions(
    instructions: "You are a relevance scorer.",
    prompt: prompt,
    options: GenerationOptions(maximumResponseTokens: 5)
  )

  return Float(score.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
}
```

**Cost**: 100 LLM calls per query (batching recommended)

### 5. Context Assembly & Prompt Engineering

#### The 4096 Token Budget

**Breakdown** (typical):
```
System instructions:    300-500 tokens
Retrieved chunks:      2500-3000 tokens  ← Most important
User query:              50-200 tokens
LLM output budget:      150-500 tokens
─────────────────────────────────────
Total:                 3000-4200 tokens  (target: 3500)
```

**Key Constraint**: You can fit ~5-10 conversation entries (depending on length) in the context window.

#### Context Formatting Strategies

##### A. Simple Concatenation
```swift
func assembleContext(chunks: [TranscriptEntry], tokenLimit: Int = 3000) -> String {
  var context = ""
  var tokenCount = 0

  for chunk in chunks {
    let chunkText = formatChunk(chunk)
    let chunkTokens = estimateTokens(chunkText)

    if tokenCount + chunkTokens > tokenLimit {
      break  // Stop when budget exhausted
    }

    context += chunkText + "\n\n"
    tokenCount += chunkTokens
  }

  return context
}

func formatChunk(_ entry: TranscriptEntry) -> String {
  """
  [Project: \(entry.projectId) | Session: \(entry.transcriptId) | \(formatDate(entry.timestamp))]
  \(entry.role.uppercased()): \(entry.content)
  """
}
```

##### B. Hierarchical Summarization (Phase 5)
**Concept**: If top-k chunks exceed budget, summarize less relevant ones.

```
Top 3 chunks:    Full content (1500 tokens)
Chunks 4-10:     One-sentence summaries (300 tokens)
Chunks 11-20:    Omitted (user can request "see more")
```

##### C. Progressive Detail (Phase 5)
**Concept**: Show most relevant content first, truncate/summarize tail.

```
Chunk 1 (score 0.95):  Full content (400 tokens)
Chunk 2 (score 0.89):  Full content (350 tokens)
Chunk 3 (score 0.82):  First 200 tokens + "..." (200 tokens)
Chunk 4 (score 0.75):  One-sentence summary (50 tokens)
...
```

#### Prompt Templates for Common Queries

##### Template 1: "How did I solve X?"
```swift
let prompt = """
You are analyzing a developer's past conversation history to help them recall how they solved a specific problem.

USER QUERY:
\(userQuery)

RELEVANT CONVERSATION HISTORY:
\(assembledContext)

Provide a concise summary (≤500 tokens) that:
1. Identifies the approach taken
2. Lists key steps or techniques used
3. Notes any tools, libraries, or commands mentioned
4. Highlights lessons learned or gotchas

Format as a structured summary with clear sections.
"""
```

##### Template 2: "Show me all occurrences of Y"
```swift
let prompt = """
You are identifying patterns across a developer's conversation history.

USER QUERY:
Find all instances where I \(userQuery)

RELEVANT CONVERSATION HISTORY:
\(assembledContext)

List each occurrence with:
- Date and project
- Brief description of context
- Outcome or resolution

Format as a bulleted list ordered by recency.
"""
```

##### Template 3: "What's the status of Z?"
```swift
let prompt = """
You are tracking the progress of an ongoing development effort across multiple conversation sessions.

TOPIC:
\(userQuery)

CHRONOLOGICAL CONVERSATION HISTORY:
\(assembledContext)

Provide a status update with:
1. Current state (what's done, what's pending)
2. Timeline of progress (key milestones)
3. Next steps or open questions
4. Any blockers or risks mentioned

Format as a structured status report.
"""
```

#### Token Estimation

**Problem**: FoundationModels doesn't expose a tokenizer API.

**Heuristic** (approximate):
```swift
func estimateTokens(_ text: String) -> Int {
  // Rule of thumb: ~4 characters per token for English
  // Slightly conservative for code (more punctuation)
  return text.count / 3
}
```

**Better** (Phase 4+): Use NLTokenizer for word count:
```swift
import NaturalLanguage

func estimateTokens(_ text: String) -> Int {
  let tokenizer = NLTokenizer(unit: .word)
  tokenizer.string = text
  let tokens = tokenizer.tokens(for: text.startIndex..<text.endIndex)
  return tokens.count
}
```

**Caveat**: Still approximate (subword tokenization in LLMs differs).

### 6. Evaluation Metrics

#### Why Evaluation Matters

**Problem**: How do you know if your retrieval system is working well?

**Subjective**: "The results look good to me" (not reproducible)
**Objective**: Measure against ground truth labels

#### Key Metrics

##### Precision@k

**Definition**: Fraction of top-k results that are relevant.

```
Precision@10 = (# relevant docs in top 10) / 10
```

**Example**:
```
Query: "authentication bug fix"
Top 10 results: [R, R, N, R, N, N, R, R, N, R]  (R=relevant, N=not relevant)
Precision@10 = 6/10 = 0.6
```

**Interpretation**: High precision = few false positives

##### Recall@k

**Definition**: Fraction of all relevant docs that appear in top-k.

```
Recall@10 = (# relevant docs in top 10) / (total # relevant docs)
```

**Example**:
```
Query: "authentication bug fix"
Total relevant docs in corpus: 15
Relevant docs in top 10: 6
Recall@10 = 6/15 = 0.4
```

**Interpretation**: High recall = few false negatives

##### Mean Reciprocal Rank (MRR)

**Definition**: Average of reciprocal ranks of the first relevant result.

```
RR = 1 / rank_of_first_relevant_result
MRR = average(RR across all queries)
```

**Example**:
```
Query 1: First relevant at rank 2 → RR = 1/2 = 0.5
Query 2: First relevant at rank 1 → RR = 1/1 = 1.0
Query 3: First relevant at rank 5 → RR = 1/5 = 0.2
MRR = (0.5 + 1.0 + 0.2) / 3 = 0.57
```

**Interpretation**: How quickly do you surface a relevant result?

##### Normalized Discounted Cumulative Gain (NDCG)

**Definition**: Ranking quality metric that rewards placing highly relevant results at the top.

**Formula**:
```
DCG@k = Σ (relevance_i / log2(rank_i + 1))  for i in 1..k
NDCG@k = DCG@k / IDCG@k  (where IDCG = ideal DCG with perfect ranking)
```

**Example** (graded relevance: 0=not relevant, 1=somewhat, 2=highly):
```
Ranking: [2, 1, 0, 2, 1]
DCG@5 = 2/log2(2) + 1/log2(3) + 0/log2(4) + 2/log2(5) + 1/log2(6)
      = 2/1 + 1/1.58 + 0 + 2/2.32 + 1/2.58
      = 2 + 0.63 + 0 + 0.86 + 0.39 = 3.88

Ideal ranking: [2, 2, 1, 1, 0]
IDCG@5 = 2 + 2/1.58 + 1/2 + 1/2.32 + 0 = 4.29

NDCG@5 = 3.88 / 4.29 = 0.90
```

**Interpretation**: NDCG=1.0 means perfect ranking.

#### Creating a Test Query Set

**Phase 6 Deliverable**: 20-50 curated queries with ground truth labels.

**Process**:
1. **Mine Real Queries**: Review your own conversation history for common patterns
   - "How did I implement X?"
   - "When did I fix Y?"
   - "Show me all instances of Z"

2. **Manual Labeling**: For each query, identify relevant entries
   ```json
   {
     "query": "authentication bug fixes",
     "relevant_entry_ids": [
       "entry-uuid-1",  // highly relevant (2)
       "entry-uuid-2",  // somewhat relevant (1)
       "entry-uuid-3"   // highly relevant (2)
     ],
     "graded_relevance": {
       "entry-uuid-1": 2,
       "entry-uuid-2": 1,
       "entry-uuid-3": 2
     }
   }
   ```

3. **Automated Evaluation**: Run test queries, compute metrics
   ```swift
   func evaluateTestSet(queries: [TestQuery]) -> EvaluationResults {
     var precisionScores: [Float] = []
     var recallScores: [Float] = []
     var mrr: [Float] = []
     var ndcgScores: [Float] = []
   
     for query in queries {
       let results = try await search(query: query.text, k: 10)
   
       // Precision@10
       let relevant = results.filter { query.relevantIds.contains($0.entry.id) }
       precisionScores.append(Float(relevant.count) / 10.0)
   
       // Recall@10
       recallScores.append(Float(relevant.count) / Float(query.relevantIds.count))
   
       // MRR
       if let firstRelevant = results.firstIndex(where: { query.relevantIds.contains($0.entry.id) }) {
         mrr.append(1.0 / Float(firstRelevant + 1))
       } else {
         mrr.append(0)
       }
   
       // NDCG@10 (requires graded relevance)
       let dcg = computeDCG(results: results, groundTruth: query.gradedRelevance)
       let idcg = computeIDCG(groundTruth: query.gradedRelevance, k: 10)
       ndcgScores.append(dcg / idcg)
     }
   
     return EvaluationResults(
       avgPrecision: precisionScores.reduce(0, +) / Float(precisionScores.count),
       avgRecall: recallScores.reduce(0, +) / Float(recallScores.count),
       mrr: mrr.reduce(0, +) / Float(mrr.count),
       avgNDCG: ndcgScores.reduce(0, +) / Float(ndcgScores.count)
     )
   }
   ```

#### Iterative Improvement

**Baseline** (Phase 2): Entry-level embeddings, cosine similarity
**Hypothesis** (Phase 3): Hybrid search improves precision
**Test**: Run test set, compare metrics
**Result**: If Precision@10 improves from 0.65 to 0.82, hybrid search wins

**Example Iteration Log**:
```
Iteration 1 (entry-level, cosine):
  Precision@10: 0.65
  Recall@10:    0.48
  MRR:          0.72
  NDCG@10:      0.68

Iteration 2 (+ keyword boosting):
  Precision@10: 0.72  (+11%)
  Recall@10:    0.51  (+6%)
  MRR:          0.79  (+10%)
  NDCG@10:      0.74  (+9%)

Iteration 3 (+ query expansion):
  Precision@10: 0.82  (+14%)
  Recall@10:    0.63  (+24%)
  MRR:          0.85  (+8%)
  NDCG@10:      0.81  (+9%)
```

**Decision**: Query expansion yields biggest recall gains → keep in production.

---

## Detailed Implementation Phases

This section provides week-by-week implementation plans with concrete deliverables, code examples, and success criteria.

### Phase 1: Embedding Generation (Weeks 1-2)

**Goal**: Generate and store embeddings for all existing conversation entries.

#### Week 1: NLContextualEmbedding Integration

**Tasks**:

1. **Asset Management**
   ```swift
   import NaturalLanguage
   
   actor EmbeddingService {
     private var model: NLContextualEmbedding?
   
     func ensureModelAvailable() async throws {
       guard let embedding = try? NLContextualEmbedding.contextualEmbedding(for: .english) else {
         throw EmbeddingError.modelNotAvailable
       }
   
       if !embedding.embeddingAvailable {
         // Trigger asset download (requires user consent)
         throw EmbeddingError.assetsNotDownloaded
       }
   
       self.model = embedding
     }
   
     func generateEmbedding(for text: String) async throws -> [Float] {
       guard let model = model else {
         try await ensureModelAvailable()
         guard let m = model else { throw EmbeddingError.modelNotAvailable }
         return try m.vector(for: text)
       }
   
       return try model.vector(for: text)
     }
   }
   ```

2. **Database Schema Extension**
   ```swift
   // Add to DatabaseSchema.swift
   
   struct DatabaseMigration_v2_Embeddings: Migration {
     static let identifier = "v2_add_embeddings"
   
     func perform(_ db: Database) throws {
       try db.alter(table: "transcript_entries") { t in
         t.add(column: "embedding", .blob)
         t.add(column: "embedding_version", .integer).defaults(to: 1)
         t.add(column: "embedding_generated_at", .integer)
       }
   
       try db.create(index: "idx_entries_embedding_version", on: "transcript_entries", columns: ["embedding_version"])
     }
   }
   ```

3. **Embedding Repository**
   ```swift
   protocol EmbeddingRepository {
     func saveEmbedding(entryId: String, vector: [Float], version: Int) async throws
     func getEmbedding(entryId: String) async throws -> [Float]?
     func getEntriesWithoutEmbeddings(version: Int) async throws -> [TranscriptEntry]
     func getAllEntriesWithEmbeddings() async throws -> [(entry: TranscriptEntry, embedding: [Float])]
   }
   
   final class EmbeddingRepositoryImpl: EmbeddingRepository {
     private let db: DatabasePool
   
     func saveEmbedding(entryId: String, vector: [Float], version: Int) async throws {
       let data = serializeEmbedding(vector)
       let now = Int(Date().timeIntervalSince1970)
   
       try await db.write { db in
         try db.execute(sql: """
           UPDATE transcript_entries
           SET embedding = ?, embedding_version = ?, embedding_generated_at = ?
           WHERE id = ?
         """, arguments: [data, version, now, entryId])
       }
     }
   
     // ... other methods
   }
   ```

**Deliverables**:
- ✅ EmbeddingService actor with NLContextualEmbedding integration
- ✅ Database migration for embedding storage
- ✅ EmbeddingRepository with CRUD operations
- ✅ Unit tests for serialization/deserialization

#### Week 2: Batch Processing & Progress Tracking

**Tasks**:

1. **Batch Embedding Generation**
   ```swift
   actor EmbeddingOrchestrator {
     private let embeddingService: EmbeddingService
     private let entryRepo: EntryRepository
     private let embeddingRepo: EmbeddingRepository
   
     func generateEmbeddingsForAllEntries(
       batchSize: Int = 100,
       progress: @escaping (Int, Int) -> Void
     ) async throws {
       let entries = try await entryRepo.getEntriesWithoutEmbeddings(version: 1)
       let total = entries.count
   
       for (index, batch) in entries.chunked(into: batchSize).enumerated() {
         for entry in batch {
           let vector = try await embeddingService.generateEmbedding(for: entry.content)
           try await embeddingRepo.saveEmbedding(entryId: entry.id, vector: vector, version: 1)
         }
   
         progress(index * batchSize, total)
       }
     }
   }
   ```

2. **Progress UI**
   ```swift
   struct EmbeddingProgressView: View {
     @State private var progress: (current: Int, total: Int) = (0, 0)
     @State private var isRunning = false
   
     var body: some View {
       VStack {
         ProgressView(value: Double(progress.current), total: Double(progress.total)) {
           Text("Generating embeddings: \(progress.current) / \(progress.total)")
         }
   
         Button("Start Embedding Generation") {
           Task {
             isRunning = true
             try await EmbeddingOrchestrator.shared.generateEmbeddingsForAllEntries { current, total in
               progress = (current, total)
             }
             isRunning = false
           }
         }
         .disabled(isRunning)
       }
       .padding()
     }
   }
   ```

3. **Resumability** (handle interruptions)
   ```swift
   // Store progress checkpoint
   struct EmbeddingProgress: Codable {
     let lastProcessedEntryId: String
     let processedCount: Int
     let totalCount: Int
   }
   
   func generateEmbeddingsResumable() async throws {
     var progress = loadProgressFromDisk() ?? EmbeddingProgress(lastProcessedEntryId: "", processedCount: 0, totalCount: 0)
   
     let entries = try await entryRepo.getEntriesWithoutEmbeddings(version: 1, after: progress.lastProcessedEntryId)
   
     for entry in entries {
       let vector = try await embeddingService.generateEmbedding(for: entry.content)
       try await embeddingRepo.saveEmbedding(entryId: entry.id, vector: vector, version: 1)
   
       // Update checkpoint every 10 entries
       progress.processedCount += 1
       progress.lastProcessedEntryId = entry.id
       if progress.processedCount % 10 == 0 {
         saveProgressToDisk(progress)
       }
     }
   }
   ```

**Deliverables**:
- ✅ Batch processing with configurable batch size
- ✅ Progress UI with real-time updates
- ✅ Checkpoint/resume support for long-running jobs
- ✅ Performance profiling (embeddings/sec, estimated completion time)

**Success Criteria**:
- [ ] All existing entries have embeddings (version=1)
- [ ] Process completes in <10 min for 1000 entries
- [ ] Interruption + resume works without data loss

---

### Phase 2: Vector Storage & Basic Search (Week 3)

**Goal**: Implement cosine similarity search with simple query UI.

#### Tasks

1. **Cosine Similarity (Optimized)**
   ```swift
   import Accelerate
   
   func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
     precondition(a.count == b.count, "Vectors must have same dimensionality")
   
     var dotProduct: Float = 0
     var normA: Float = 0
     var normB: Float = 0
   
     vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
     vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
     vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
   
     return dotProduct / (sqrt(normA) * sqrt(normB))
   }
   ```

2. **Semantic Search Implementation**
   ```swift
   struct ScoredEntry {
     let entry: TranscriptEntry
     let score: Float
   }
   
   actor SemanticSearchEngine {
     private let embeddingService: EmbeddingService
     private let embeddingRepo: EmbeddingRepository
   
     func search(query: String, k: Int = 10, filters: SearchFilters? = nil) async throws -> [ScoredEntry] {
       // 1. Generate query embedding
       let queryEmbedding = try await embeddingService.generateEmbedding(for: query)
   
       // 2. Fetch candidates (with optional filters)
       let candidates = try await embeddingRepo.getAllEntriesWithEmbeddings(filters: filters)
   
       // 3. Score all candidates
       let scored = candidates.map { (entry, embedding) in
         ScoredEntry(
           entry: entry,
           score: cosineSimilarity(queryEmbedding, embedding)
         )
       }
   
       // 4. Return top-k
       return scored.sorted { $0.score > $1.score }.prefix(k).map { $0 }
     }
   }
   ```

3. **Search UI**
   ```swift
   struct SemanticSearchView: View {
     @State private var query: String = ""
     @State private var results: [ScoredEntry] = []
     @State private var isSearching = false
   
     var body: some View {
       VStack {
         // Search bar
         TextField("Search conversation history...", text: $query)
           .textFieldStyle(.roundedBorder)
           .onSubmit {
             performSearch()
           }
   
         // Results
         List(results, id: \.entry.id) { scoredEntry in
           VStack(alignment: .leading, spacing: 4) {
             HStack {
               Text(scoredEntry.entry.role.capitalized)
                 .font(.caption)
                 .foregroundStyle(.secondary)
   
               Spacer()
   
               Text("Score: \(String(format: "%.2f", scoredEntry.score))")
                 .font(.caption)
                 .foregroundStyle(.blue)
             }
   
             Text(scoredEntry.entry.content)
               .lineLimit(3)
               .font(.body)
           }
           .padding(.vertical, 4)
         }
       }
       .padding()
     }
   
     private func performSearch() {
       guard !query.isEmpty else { return }
   
       Task {
         isSearching = true
         defer { isSearching = false }
   
         results = try await SemanticSearchEngine.shared.search(query: query, k: 10)
       }
     }
   }
   ```

4. **Performance Benchmarking**
   ```swift
   func benchmarkSearch() async {
     let queries = ["authentication bug", "database migration", "UI layout"]
   
     for query in queries {
       let start = Date()
       let results = try await SemanticSearchEngine.shared.search(query: query, k: 10)
       let elapsed = Date().timeIntervalSince(start)
   
       print("Query: '\(query)' | Results: \(results.count) | Time: \(Int(elapsed * 1000))ms")
     }
   }
   ```

**Deliverables**:
- ✅ Optimized cosine similarity (Accelerate framework)
- ✅ SemanticSearchEngine with top-k retrieval
- ✅ Basic search UI with results display
- ✅ Performance benchmark suite

**Success Criteria**:
- [ ] Search returns results in <1s for <5k entries
- [ ] Top-3 results are relevant for test queries (manual validation)
- [ ] UI is responsive during search (async operations)

---

### Phase 3: Hybrid Search (Weeks 4-5)

**Goal**: Combine semantic search with metadata filters and keyword boosting.

#### Week 4: Metadata Filtering

**Tasks**:

1. **Search Filters**
   ```swift
   struct SearchFilters {
     var projectId: String?
     var sessionId: String?
     var dateRange: ClosedRange<Date>?
     var roles: [String]?  // ["user", "assistant", "system"]
     var minScore: Float = 0.0
   }
   
   func getAllEntriesWithEmbeddings(filters: SearchFilters? = nil) async throws -> [(TranscriptEntry, [Float])] {
     try await db.read { db in
       var sql = "SELECT * FROM transcript_entries WHERE embedding IS NOT NULL"
       var args: [DatabaseValueConvertible] = []
   
       if let filters = filters {
         if let projectId = filters.projectId {
           sql += " AND project_id = ?"
           args.append(projectId)
         }
         if let sessionId = filters.sessionId {
           sql += " AND transcript_id = ?"
           args.append(sessionId)
         }
         if let dateRange = filters.dateRange {
           sql += " AND timestamp BETWEEN ? AND ?"
           args.append(Int(dateRange.lowerBound.timeIntervalSince1970))
           args.append(Int(dateRange.upperBound.timeIntervalSince1970))
         }
         if let roles = filters.roles, !roles.isEmpty {
           sql += " AND role IN (\(roles.map { _ in "?" }.joined(separator: ",")))"
           args.append(contentsOf: roles)
         }
       }
   
       let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
       return rows.map { row in
         let entry = try! TranscriptEntry(row: row)
         let embedding = deserializeEmbedding(row["embedding"] as! Data)
         return (entry, embedding)
       }
     }
   }
   ```

2. **UI Filters**
   ```swift
   struct SearchFilterView: View {
     @Binding var filters: SearchFilters
   
     var body: some View {
       Form {
         Section("Project") {
           Picker("Select project", selection: $filters.projectId) {
             Text("All projects").tag(String?.none)
             ForEach(projects) { project in
               Text(project.name ?? "Unnamed").tag(String?.some(project.id))
             }
           }
         }
   
         Section("Role") {
           MultipleSelectionRow(title: "User", isSelected: filters.roles?.contains("user") ?? false) {
             toggleRole("user")
           }
           MultipleSelectionRow(title: "Assistant", isSelected: filters.roles?.contains("assistant") ?? false) {
             toggleRole("assistant")
           }
         }
   
         Section("Date Range") {
           DatePicker("From", selection: $startDate, displayedComponents: .date)
           DatePicker("To", selection: $endDate, displayedComponents: .date)
         }
       }
     }
   }
   ```

**Deliverables**:
- ✅ SearchFilters struct with SQL generation
- ✅ UI for interactive filter selection
- ✅ Integration with SemanticSearchEngine

#### Week 5: Keyword Boosting & RRF

**Tasks**:

1. **Keyword Extraction**
   ```swift
   func extractKeywords(from query: String) -> [String] {
     let tagger = NLTagger(tagSchemes: [.lexicalClass])
     tagger.string = query
   
     var keywords: [String] = []
     tagger.enumerateTags(in: query.startIndex..<query.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
       if tag == .noun || tag == .verb {
         keywords.append(String(query[range]))
       }
       return true
     }
   
     return keywords
   }
   ```

2. **Hybrid Scoring**
   ```swift
   func hybridSearch(query: String, k: Int, filters: SearchFilters?) async throws -> [ScoredEntry] {
     // 1. Semantic search
     let semanticResults = try await search(query: query, k: 100, filters: filters)
   
     // 2. Keyword boosting
     let keywords = extractKeywords(from: query)
     var boostedResults = semanticResults.map { scoredEntry in
       var score = scoredEntry.score
   
       // Boost by 0.1 for each keyword match
       for keyword in keywords {
         if scoredEntry.entry.content.localizedCaseInsensitiveContains(keyword) {
           score += 0.1
         }
       }
   
       return ScoredEntry(entry: scoredEntry.entry, score: score)
     }
   
     // 3. Re-sort and return top-k
     boostedResults.sort { $0.score > $1.score }
     return Array(boostedResults.prefix(k))
   }
   ```

3. **Reciprocal Rank Fusion**
   ```swift
   func rrfSearch(query: String, k: Int, filters: SearchFilters?) async throws -> [ScoredEntry] {
     // Get rankings from multiple sources
     let semanticRanking = try await search(query: query, k: 100, filters: filters)
     let keywordRanking = try await keywordSearch(query: query, k: 100, filters: filters)  // SQL LIKE
   
     // Fuse rankings
     return reciprocalRankFusion(
       rankingsFromSources: [semanticRanking, keywordRanking],
       k: 60
     ).prefix(k).map { $0 }
   }
   ```

**Deliverables**:
- ✅ Keyword extraction via NLTagger
- ✅ Hybrid scoring (semantic + keyword boost)
- ✅ RRF implementation for multi-source fusion
- ✅ A/B test: semantic vs hybrid vs RRF

**Success Criteria**:
- [ ] Hybrid search improves Precision@10 by ≥10% over baseline
- [ ] Filters reduce result set latency (fewer candidates to score)

---

### Phase 4: Context Assembly + Insight Generation (Weeks 6-7)

**Goal**: Use FoundationLLM to synthesize insights from retrieved chunks.

#### Week 6: Context Formatting

**Tasks**:

1. **Token Budget Manager**
   ```swift
   struct TokenBudget {
     let systemPrompt: Int = 400
     let userQuery: Int = 200
     let llmOutput: Int = 500
   
     var availableForContext: Int {
       4096 - systemPrompt - userQuery - llmOutput  // ~3000 tokens
     }
   }
   
   func assembleContext(chunks: [ScoredEntry], budget: TokenBudget) -> String {
     var context = ""
     var tokenCount = 0
   
     for chunk in chunks {
       let formatted = formatChunk(chunk)
       let tokens = estimateTokens(formatted)
   
       if tokenCount + tokens > budget.availableForContext {
         // Truncate or summarize remaining chunks
         context += "\n\n[... \(chunks.count - chunks.firstIndex(where: { $0.entry.id == chunk.entry.id })!) more results omitted ...]"
         break
       }
   
       context += formatted + "\n\n---\n\n"
       tokenCount += tokens
     }
   
     return context
   }
   
   func formatChunk(_ scoredEntry: ScoredEntry) -> String {
     let entry = scoredEntry.entry
     let date = Date(timeIntervalSince1970: TimeInterval(entry.timestamp))
     let formattedDate = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
   
     return """
     [Project: \(entry.projectId) | Session: \(entry.transcriptId.prefix(8)) | \(formattedDate) | Relevance: \(String(format: "%.2f", scoredEntry.score))]
     \(entry.role.uppercased()): \(entry.content)
     """
   }
   ```

2. **Prompt Templates**
   ```swift
   enum InsightType {
     case approach  // "How did I solve X?"
     case pattern   // "Show me all Y"
     case status    // "What's the status of Z?"
   }
   
   func buildPrompt(type: InsightType, query: String, context: String) -> String {
     let baseInstructions = "You are analyzing a developer's conversation history with an AI coding assistant."
   
     switch type {
     case .approach:
       return """
         \(baseInstructions)
   
         The developer wants to recall how they previously solved a problem.
   
         USER QUERY:
         \(query)
   
         RELEVANT CONVERSATION HISTORY:
         \(context)
   
         Provide a structured summary (≤400 tokens) with:
         1. **Approach**: High-level strategy taken
         2. **Key Steps**: Specific actions or techniques
         3. **Tools/Commands**: Any tools, libraries, or commands mentioned
         4. **Lessons Learned**: Gotchas or insights noted
   
         Be concise and actionable.
         """
   
     case .pattern:
       return """
         \(baseInstructions)
   
         The developer wants to find all instances of a pattern across their work.
   
         USER QUERY:
         \(query)
   
         RELEVANT CONVERSATION HISTORY:
         \(context)
   
         List each occurrence with:
         - Date and project
         - Brief context
         - Outcome or key detail
   
         Format as a bulleted list, ordered by recency.
         """
   
     case .status:
       return """
         \(baseInstructions)
   
         The developer wants a progress update on an ongoing topic.
   
         TOPIC:
         \(query)
   
         CHRONOLOGICAL CONVERSATION HISTORY:
         \(context)
   
         Provide a status report with:
         1. **Current State**: What's done, what's pending
         2. **Timeline**: Key milestones in chronological order
         3. **Next Steps**: Open questions or remaining work
         4. **Blockers**: Any issues mentioned
   
         Be factual and reference the conversation history.
         """
     }
   }
   ```

**Deliverables**:
- ✅ Token budget manager with overflow handling
- ✅ Chunk formatting with metadata
- ✅ Prompt templates for 3 insight types

#### Week 7: LLM Integration

**Tasks**:

1. **Insight Generation**
   ```swift
   @Generable(description: "Insight summary from conversation history")
   struct InsightResult {
     @Guide(description: "Concise summary (≤400 tokens)")
     var summary: String
   
     @Guide(description: "Confidence in the insight (0.0-1.0)", .range(0...1))
     var confidence: Float
   
     @Guide(description: "Whether more context is needed")
     var needsMoreContext: Bool
   }
   
   func generateInsight(
     query: String,
     type: InsightType,
     retrievedChunks: [ScoredEntry]
   ) async throws -> InsightResult {
     // 1. Assemble context
     let context = assembleContext(chunks: retrievedChunks, budget: TokenBudget())
   
     // 2. Build prompt
     let prompt = buildPrompt(type: type, query: query, context: context)
   
     // 3. Call LLM
     let instructions = "You synthesize insights from developer conversation history."
     let result = try await FoundationLLM.shared.generateGuided(
       instructions: instructions,
       prompt: prompt,
       generating: InsightResult.self,
       includeSchema: true,
       options: GenerationOptions(
         sampling: .greedy,
         temperature: 0.0,
         maximumResponseTokens: 500
       )
     )
   
     return result
   }
   ```

2. **Insight UI**
   ```swift
   struct InsightView: View {
     @State private var query: String = ""
     @State private var insightType: InsightType = .approach
     @State private var result: InsightResult?
     @State private var isGenerating = false
   
     var body: some View {
       VStack(alignment: .leading, spacing: 16) {
         // Query input
         TextField("Ask about your conversation history...", text: $query)
           .textFieldStyle(.roundedBorder)
   
         // Insight type picker
         Picker("Type", selection: $insightType) {
           Text("How did I solve...").tag(InsightType.approach)
           Text("Show me all...").tag(InsightType.pattern)
           Text("Status of...").tag(InsightType.status)
         }
         .pickerStyle(.segmented)
   
         // Generate button
         Button("Generate Insight") {
           performSearch()
         }
         .buttonStyle(.borderedProminent)
         .disabled(query.isEmpty || isGenerating)
   
         // Result
         if let result = result {
           VStack(alignment: .leading, spacing: 8) {
             HStack {
               Text("Insight")
                 .font(.headline)
   
               Spacer()
   
               Text("Confidence: \(String(format: "%.0f%%", result.confidence * 100))")
                 .font(.caption)
                 .foregroundStyle(.secondary)
             }
   
             Text(result.summary)
               .textSelection(.enabled)
   
             if result.needsMoreContext {
               Label("This insight may be incomplete. Try a more specific query.", systemImage: "exclamationmark.triangle")
                 .font(.caption)
                 .foregroundStyle(.orange)
             }
           }
           .padding()
           .background(Color.secondary.opacity(0.1))
           .clipShape(RoundedRectangle(cornerRadius: 8))
         }
       }
       .padding()
     }
   
     private func performSearch() {
       Task {
         isGenerating = true
         defer { isGenerating = false }
   
         // 1. Retrieve relevant chunks
         let chunks = try await SemanticSearchEngine.shared.search(query: query, k: 10)
   
         // 2. Generate insight
         result = try await generateInsight(query: query, type: insightType, retrievedChunks: chunks)
       }
     }
   }
   ```

3. **Export to Transcript**
   ```swift
   func exportAsTranscript(query: String, chunks: [ScoredEntry], insight: InsightResult) -> String {
     let header = """
       # Contextify RAG Export
       Query: \(query)
       Generated: \(Date())
       Confidence: \(String(format: "%.0f%%", insight.confidence * 100))
   
       ## Insight Summary
       \(insight.summary)
   
       ## Retrieved Context
       """
   
     let context = chunks.enumerated().map { index, chunk in
       """
       ### Result \(index + 1) (Relevance: \(String(format: "%.2f", chunk.score)))
       **Project**: \(chunk.entry.projectId)
       **Session**: \(chunk.entry.transcriptId)
       **Role**: \(chunk.entry.role)
       **Date**: \(Date(timeIntervalSince1970: TimeInterval(chunk.entry.timestamp)))
   
   ```
       \(chunk.entry.content)
       ```
       """
     }.joined(separator: "\n\n---\n\n")

     return header + "\n\n" + context
   }

   // Save to file
   func saveTranscript(content: String, filename: String) throws {
     let outputDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
     let fileURL = outputDir.appendingPathComponent("\(filename).md")
     try content.write(to: fileURL, atomically: true, encoding: .utf8)
   }
   ```

**Deliverables**:
- ✅ InsightResult schema with guided generation
- ✅ generateInsight() with FoundationLLM integration
- ✅ InsightView UI for query + result display
- ✅ Export feature (save as Markdown transcript)

**Success Criteria**:
- [ ] Insight generation completes in <5s for 10 chunks
- [ ] Generated insights are grounded in retrieved context (≥70% manual validation)
- [ ] Exported transcripts are resumable in Claude Code/Codex (manual test)

---

### Phase 5: Advanced Retrieval (Weeks 8-10)

**Goal**: Optimize retrieval quality with two-stage ranking, query expansion, and cross-project patterns.

#### Week 8: Two-Stage Retrieval

**Tasks**:

1. **Re-Ranking with LLM**
   ```swift
   func twoStageRetrieval(query: String, k: Int) async throws -> [ScoredEntry] {
     // Stage 1: Fast cosine similarity (top 100)
     let candidates = try await search(query: query, k: 100)
   
     // Stage 2: LLM-based re-ranking
     let reranked = try await withThrowingTaskGroup(of: (String, Float).self) { group in
       for candidate in candidates {
         group.addTask {
           let score = try await scoreRelevanceWithLLM(query: query, entry: candidate.entry)
           return (candidate.entry.id, score)
         }
       }
   
       var scores: [String: Float] = [:]
       for try await (id, score) in group {
         scores[id] = score
       }
   
       return candidates.map { candidate in
         ScoredEntry(entry: candidate.entry, score: scores[candidate.entry.id] ?? 0)
       }
     }
   
     return reranked.sorted { $0.score > $1.score }.prefix(k).map { $0 }
   }
   
   func scoreRelevanceWithLLM(query: String, entry: TranscriptEntry) async throws -> Float {
     let prompt = """
       Rate the relevance of this entry to the query on a scale from 0.0 (not relevant) to 1.0 (highly relevant).
   
       QUERY: \(query)
   
       ENTRY (\(entry.role)): \(entry.content.prefix(300))...
   
       Output only a single number between 0.0 and 1.0.
       """
   
     let result = try await FoundationLLM.shared.rawWithInstructions(
       instructions: "You are a relevance scorer.",
       prompt: prompt,
       options: GenerationOptions(maximumResponseTokens: 5)
     )
   
     return Float(result.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
   }
   ```

2. **Batched Re-Ranking** (optimize latency)
   ```swift
   func batchScoreRelevance(query: String, entries: [TranscriptEntry]) async throws -> [Float] {
     // Group into batches of 10 to avoid overwhelming LLM
     let batchSize = 10
     var scores: [Float] = []
   
     for batch in entries.chunked(into: batchSize) {
       let batchScores = try await batch.asyncMap { entry in
         try await scoreRelevanceWithLLM(query: query, entry: entry)
       }
       scores.append(contentsOf: batchScores)
     }
   
     return scores
   }
   ```

**Deliverables**:
- ✅ Two-stage retrieval with LLM re-ranking
- ✅ Batched scoring for latency optimization
- ✅ Comparison: single-stage vs two-stage precision

#### Week 9: Query Expansion

**Tasks**:

1. **LLM-Based Query Expansion**
   ```swift
   @Generable(description: "Expanded query variations")
   struct ExpandedQueries {
     @Guide(description: "Original query rephrased with synonyms")
     var synonymVariation: String
   
     @Guide(description: "More specific version of the query")
     var specificVariation: String
   
     @Guide(description: "Related concept or broader topic")
     var relatedConcept: String
   }
   
   func expandQuery(_ query: String) async throws -> [String] {
     let prompt = """
       Generate 3 variations of this search query to improve retrieval:
   
       ORIGINAL QUERY: \(query)
   
       Create variations that:
       1. Use synonyms (e.g., "bug" → "issue", "fix" → "resolve")
       2. Are more specific (e.g., "auth bug" → "authentication login failure")
       3. Cover related concepts (e.g., "database migration" → "schema changes")
       """
   
     let result = try await FoundationLLM.shared.generateGuided(
       instructions: "You expand search queries for better retrieval.",
       prompt: prompt,
       generating: ExpandedQueries.self,
       options: GenerationOptions(maximumResponseTokens: 100)
     )
   
     return [result.synonymVariation, result.specificVariation, result.relatedConcept]
   }
   ```

2. **Multi-Query Search with Fusion**
   ```swift
   func expandedSearch(query: String, k: Int) async throws -> [ScoredEntry] {
     // 1. Expand query
     let queries = [query] + (try await expandQuery(query))
   
     // 2. Search with each variation
     let allResults = try await queries.asyncMap { q in
       try await search(query: q, k: 50)
     }
   
     // 3. Fuse rankings
     return reciprocalRankFusion(rankingsFromSources: allResults, k: 60).prefix(k).map { $0 }
   }
   ```

**Deliverables**:
- ✅ LLM-based query expansion with structured output
- ✅ Multi-query search with RRF fusion
- ✅ Evaluation: expanded vs single-query recall

#### Week 10: Cross-Project Patterns

**Tasks**:

1. **Pattern Detection**
   ```swift
   func detectPatterns(topic: String, acrossProjects: Bool = true) async throws -> [PatternInstance] {
     // 1. Search for topic across all projects
     let filters = acrossProjects ? nil : SearchFilters(projectId: currentProjectId)
     let results = try await search(query: topic, k: 50, filters: filters)
   
     // 2. Group by project
     let grouped = Dictionary(grouping: results) { $0.entry.projectId }
   
     // 3. Summarize each project's occurrences
     var patterns: [PatternInstance] = []
     for (projectId, entries) in grouped {
       let summary = try await summarizePattern(topic: topic, entries: entries, projectId: projectId)
       patterns.append(summary)
     }
   
     return patterns.sorted { $0.occurrenceCount > $1.occurrenceCount }
   }
   
   struct PatternInstance {
     let projectId: String
     let projectName: String
     let occurrenceCount: Int
     let summary: String
     let firstSeen: Date
     let lastSeen: Date
   }
   
   func summarizePattern(topic: String, entries: [ScoredEntry], projectId: String) async throws -> PatternInstance {
     let context = assembleContext(chunks: entries, budget: TokenBudget())
     let prompt = """
       Summarize how the developer approached "\(topic)" in this project.
   
       CONTEXT:
       \(context)
   
       Provide a 1-2 sentence summary of the approach taken.
       """
   
     let summary = try await FoundationLLM.shared.rawWithInstructions(
       instructions: "You summarize developer patterns.",
       prompt: prompt,
       options: GenerationOptions(maximumResponseTokens: 100)
     )
   
     let timestamps = entries.map { Date(timeIntervalSince1970: TimeInterval($0.entry.timestamp)) }
   
     return PatternInstance(
       projectId: projectId,
       projectName: projectId,  // TODO: Lookup from DB
       occurrenceCount: entries.count,
       summary: summary,
       firstSeen: timestamps.min()!,
       lastSeen: timestamps.max()!
     )
   }
   ```

2. **Pattern View UI**
   ```swift
   struct CrossProjectPatternsView: View {
     @State private var topic: String = ""
     @State private var patterns: [PatternInstance] = []
   
     var body: some View {
       VStack {
         TextField("Topic (e.g., 'database migration')", text: $topic)
           .onSubmit {
             Task {
               patterns = try await detectPatterns(topic: topic)
             }
           }
   
         List(patterns, id: \.projectId) { pattern in
           VStack(alignment: .leading, spacing: 8) {
             HStack {
               Text(pattern.projectName)
                 .font(.headline)
   
               Spacer()
   
               Text("\(pattern.occurrenceCount) occurrences")
                 .font(.caption)
                 .foregroundStyle(.secondary)
             }
   
             Text(pattern.summary)
               .font(.body)
   
             HStack {
               Text("First: \(pattern.firstSeen, style: .date)")
               Text("•")
               Text("Last: \(pattern.lastSeen, style: .date)")
             }
             .font(.caption)
             .foregroundStyle(.secondary)
           }
         }
       }
       .padding()
     }
   }
   ```

**Deliverables**:
- ✅ Pattern detection across projects
- ✅ Per-project summarization
- ✅ Cross-project pattern UI

**Success Criteria**:
- [ ] Two-stage retrieval improves Precision@10 by ≥15%
- [ ] Query expansion improves Recall@10 by ≥20%
- [ ] Cross-project patterns surface non-obvious connections (manual validation)

---

### Phase 6: Evaluation Framework (Week 11)

**Goal**: Systematic evaluation of retrieval quality with metrics and A/B testing.

#### Tasks

1. **Test Query Set Creation**
   ```swift
   struct TestQuery: Codable {
     let query: String
     let relevantEntryIds: [String]
     let gradedRelevance: [String: Int]  // entry_id → relevance (0-2)
     let queryType: InsightType
   }
   
   // Example test set
   let testQueries: [TestQuery] = [
     TestQuery(
       query: "authentication bug fixes",
       relevantEntryIds: ["entry-uuid-1", "entry-uuid-2", "entry-uuid-3"],
       gradedRelevance: [
         "entry-uuid-1": 2,  // highly relevant
         "entry-uuid-2": 1,  // somewhat relevant
         "entry-uuid-3": 2
       ],
       queryType: .pattern
     ),
     // ... 19-49 more queries
   ]
   ```

2. **Metric Calculation**
   ```swift
   struct EvaluationResults {
     let avgPrecision: Float
     let avgRecall: Float
     let mrr: Float
     let avgNDCG: Float
     let perQueryResults: [QueryResult]
   }
   
   struct QueryResult {
     let query: String
     let precision: Float
     let recall: Float
     let rr: Float
     let ndcg: Float
   }
   
   func evaluateTestSet(queries: [TestQuery], searchFn: (String) async throws -> [ScoredEntry]) async throws -> EvaluationResults {
     var precisionScores: [Float] = []
     var recallScores: [Float] = []
     var rrScores: [Float] = []
     var ndcgScores: [Float] = []
     var perQueryResults: [QueryResult] = []
   
     for testQuery in queries {
       let results = try await searchFn(testQuery.query)
   
       // Precision@10
       let relevant = results.filter { testQuery.relevantEntryIds.contains($0.entry.id) }
       let precision = Float(relevant.count) / Float(min(results.count, 10))
       precisionScores.append(precision)
   
       // Recall@10
       let recall = Float(relevant.count) / Float(testQuery.relevantEntryIds.count)
       recallScores.append(recall)
   
       // MRR
       var rr: Float = 0
       if let firstRelevant = results.firstIndex(where: { testQuery.relevantEntryIds.contains($0.entry.id) }) {
         rr = 1.0 / Float(firstRelevant + 1)
       }
       rrScores.append(rr)
   
       // NDCG@10
       let dcg = computeDCG(results: results, groundTruth: testQuery.gradedRelevance, k: 10)
       let idcg = computeIDCG(groundTruth: testQuery.gradedRelevance, k: 10)
       let ndcg = idcg > 0 ? dcg / idcg : 0
       ndcgScores.append(ndcg)
   
       perQueryResults.append(QueryResult(
         query: testQuery.query,
         precision: precision,
         recall: recall,
         rr: rr,
         ndcg: ndcg
       ))
     }
   
     return EvaluationResults(
       avgPrecision: precisionScores.reduce(0, +) / Float(precisionScores.count),
       avgRecall: recallScores.reduce(0, +) / Float(recallScores.count),
       mrr: rrScores.reduce(0, +) / Float(rrScores.count),
       avgNDCG: ndcgScores.reduce(0, +) / Float(ndcgScores.count),
       perQueryResults: perQueryResults
     )
   }
   
   func computeDCG(results: [ScoredEntry], groundTruth: [String: Int], k: Int) -> Float {
     var dcg: Float = 0
     for (rank, result) in results.prefix(k).enumerated() {
       let relevance = Float(groundTruth[result.entry.id] ?? 0)
       dcg += relevance / log2(Float(rank + 2))  // rank+2 because rank is 0-indexed
     }
     return dcg
   }
   
   func computeIDCG(groundTruth: [String: Int], k: Int) -> Float {
     let sortedRelevances = groundTruth.values.sorted(by: >)
     var idcg: Float = 0
     for (rank, relevance) in sortedRelevances.prefix(k).enumerated() {
       idcg += Float(relevance) / log2(Float(rank + 2))
     }
     return idcg
   }
   ```

3. **A/B Testing Framework**
   ```swift
   enum SearchStrategy {
     case baseline              // Cosine similarity only
     case keywordBoosted        // + keyword boosting
     case hybrid                // + metadata filters
     case queryExpanded         // + query expansion
     case twoStage              // + LLM re-ranking
   }
   
   func compareStrategies(queries: [TestQuery]) async throws {
     let strategies: [SearchStrategy] = [.baseline, .keywordBoosted, .hybrid, .queryExpanded, .twoStage]
   
     print("Strategy Comparison on \(queries.count) test queries:\n")
     print("| Strategy | Precision@10 | Recall@10 | MRR | NDCG@10 |")
     print("|----------|--------------|-----------|-----|---------|")
   
     for strategy in strategies {
       let results = try await evaluateTestSet(queries: queries) { query in
         try await search(query: query, strategy: strategy)
       }
   
       print("| \(strategy) | \(String(format: "%.3f", results.avgPrecision)) | \(String(format: "%.3f", results.avgRecall)) | \(String(format: "%.3f", results.mrr)) | \(String(format: "%.3f", results.avgNDCG)) |")
     }
   }
   ```

4. **Evaluation Dashboard**
   ```swift
   struct EvaluationDashboardView: View {
     @State private var results: EvaluationResults?
   
     var body: some View {
       VStack {
         if let results = results {
           VStack(alignment: .leading, spacing: 16) {
             MetricCard(title: "Precision@10", value: results.avgPrecision, format: "%.1f%%")
             MetricCard(title: "Recall@10", value: results.avgRecall, format: "%.1f%%")
             MetricCard(title: "MRR", value: results.mrr, format: "%.3f")
             MetricCard(title: "NDCG@10", value: results.avgNDCG, format: "%.3f")
           }
   
           List(results.perQueryResults, id: \.query) { queryResult in
             VStack(alignment: .leading) {
               Text(queryResult.query)
                 .font(.headline)
   
               HStack {
                 Text("P: \(String(format: "%.2f", queryResult.precision))")
                 Text("R: \(String(format: "%.2f", queryResult.recall))")
                 Text("NDCG: \(String(format: "%.2f", queryResult.ndcg))")
               }
               .font(.caption)
               .foregroundStyle(.secondary)
             }
           }
         }
   
         Button("Run Evaluation") {
           Task {
             results = try await evaluateTestSet(queries: testQueries) { query in
               try await search(query: query, k: 10)
             }
           }
         }
         .buttonStyle(.borderedProminent)
       }
       .padding()
     }
   }
   
   struct MetricCard: View {
     let title: String
     let value: Float
     let format: String
   
     var body: some View {
       HStack {
         Text(title)
           .font(.headline)
   
         Spacer()
   
         Text(String(format: format, value * 100))
           .font(.title2)
           .fontWeight(.bold)
       }
       .padding()
       .background(Color.secondary.opacity(0.1))
       .clipShape(RoundedRectangle(cornerRadius: 8))
     }
   }
   ```

**Deliverables**:
- ✅ Test query set (20-50 queries with ground truth)
- ✅ Metric calculation (Precision, Recall, MRR, NDCG)
- ✅ A/B testing framework for strategy comparison
- ✅ Evaluation dashboard UI

**Success Criteria**:
- [ ] Final system achieves ≥80% Precision@10, ≥60% Recall@10
- [ ] Evaluation runs in <5 min for 50 queries
- [ ] Strategy comparison identifies best configuration

---

## Key Learning Objectives

By completing this implementation, you will have mastered:

### 1. Embeddings & Vector Representations
- ✅ How transformer-based embeddings capture semantic meaning
- ✅ When dimensionality matters (and when it doesn't)
- ✅ Trade-offs between dense and sparse representations
- ✅ Cosine similarity and its geometric intuition

### 2. Chunking Strategies
- ✅ Impact of chunk size on retrieval quality
- ✅ When to use entry-level vs message-level vs semantic chunking
- ✅ Overlap strategies for context preservation
- ✅ Trade-offs between storage and precision

### 3. Retrieval Techniques
- ✅ Exact k-NN vs approximate methods (HNSW)
- ✅ Hybrid search (semantic + keyword + metadata)
- ✅ Reciprocal Rank Fusion for multi-source ranking
- ✅ Query expansion for better recall
- ✅ Two-stage retrieval for precision

### 4. Context Assembly & Prompting
- ✅ Token budgeting under constrained windows (4096)
- ✅ Formatting retrieved chunks for LLM consumption
- ✅ Prompt engineering for different query types
- ✅ Balancing detail vs coverage in limited space

### 5. RAG Evaluation
- ✅ Precision, Recall, MRR, NDCG metrics
- ✅ Creating ground truth test sets
- ✅ A/B testing for retrieval strategies
- ✅ Iterative improvement via metrics

### 6. On-Device AI Patterns
- ✅ NLContextualEmbedding asset management
- ✅ FoundationModels session lifecycle
- ✅ Privacy-preserving RAG (no external APIs)
- ✅ Performance optimization for offline search

### 7. Production RAG Systems
- ✅ Batch processing and progress tracking
- ✅ Resumability for long-running jobs
- ✅ Error handling and fallbacks
- ✅ Monitoring and quality assurance

---

## Scope & Success Criteria

### What This IS

**Searchable Conversation History**:
- Query past conversations by semantic meaning
- Find relevant context across projects and sessions
- Surface patterns in problem-solving approaches

**LLM-Powered Insights**:
- Synthesize "how did I solve X?" summaries
- Generate progress reports for ongoing work
- Identify cross-project patterns

**Context Resumption**:
- Export relevant chunks as Markdown transcripts
- Continue conversations in Claude Code/Codex CLI
- Maintain context across tool boundaries

**RAG Education**:
- Hands-on learning from embeddings to evaluation
- Real-world constraints (4096 token window)
- Production-ready patterns (batch processing, error handling)

### What This IS NOT

**General-Purpose Document Retrieval**:
- This is not a replacement for web search or documentation lookup
- Scope: Coding conversations only

**Real-Time Collaborative Assistant**:
- Not building a chatbot or pair programmer
- Scope: Retrospective search and insight generation

**External API Integration**:
- No OpenAI, Anthropic, or cloud embedding services
- Scope: Apple on-device stack only

**Long-Form Document Generation**:
- 4096 token limit precludes extensive reports
- Scope: Concise insights (≤500 tokens)

### Success Criteria (Summary)

| Category              | Metric               | Target          | Rationale                                   |
| --------------------- | -------------------- | --------------- | ------------------------------------------- |
| **Retrieval Quality** | Precision@10         | ≥80%            | Most queries return highly relevant results |
|                       | Recall@10            | ≥60%            | System finds most relevant docs in corpus   |
|                       | NDCG@10              | ≥0.75           | Relevant results ranked highly              |
| **Performance**       | Search latency       | <1s             | Interactive user experience                 |
|                       | Embedding throughput | >50 entries/sec | Reasonable batch processing time            |
| **Insight Quality**   | User satisfaction    | ≥70%            | Generated insights are useful (manual eval) |
|                       | Grounding            | ≥85%            | Insights cite retrieved context accurately  |
| **Coverage**          | Embedded entries     | 100%            | All conversation history searchable         |
| **Efficiency**        | Token usage          | ≤3500/query     | Leaves headroom for LLM output              |

---

## References & Resources

### Apple Documentation

1. **NLContextualEmbedding**
   - [API Reference](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)
   - [WWDC 2023: Explore Natural Language multilingual models](https://developer.apple.com/videos/play/wwdc2023/10042/)

2. **FoundationModels**
   - [API Reference](https://developer.apple.com/documentation/FoundationModels)
   - [Apple Intelligence Foundation Language Models Tech Report 2025](https://machinelearning.apple.com/papers/apple_intelligence_foundation_language_models_tech_report_2025.pdf)

3. **Natural Language Framework**
   - [Overview](https://developer.apple.com/documentation/naturallanguage)
   - [NLTokenizer](https://developer.apple.com/documentation/naturallanguage/nltokenizer) (for token estimation)
   - [NLTagger](https://developer.apple.com/documentation/naturallanguage/nltagger) (for keyword extraction)

### RAG Research Papers

1. **Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks** (Lewis et al., 2020)
   - [arXiv:2005.11401](https://arxiv.org/abs/2005.11401)
   - Original RAG paper from Meta AI

2. **Chunk Twice, Embed Once** (2025)
   - [arXiv:2506.17277](https://arxiv.org/html/2506.17277v1)
   - Systematic study of segmentation strategies

3. **A Systematic Review of Key RAG Systems** (2025)
   - [arXiv:2507.18910](https://arxiv.org/html/2507.18910v1)
   - Progress, gaps, and future directions

### Open Source Swift Packages

1. **SimilaritySearchKit**
   - [GitHub](https://github.com/ZachNagengast/similarity-search-kit)
   - On-device semantic search with NLContextualEmbedding

2. **VecturaKit**
   - [GitHub](https://github.com/rryam/VecturaKit)
   - Swift vector database with hybrid search (BM25 + embeddings)

3. **ObjectBox Swift**
   - [HNSW Vector Index](https://objectbox.io/swift-ios-on-device-vector-database-aka-semantic-index/)
   - High-performance vector DB for iOS/macOS

### RAG Evaluation Resources

1. **RAG Evaluation Metrics Guide** (Medium)
   - [Link](https://medium.com/@autorag/tips-to-understand-rag-retrieval-metrics-71e9a2bd4b96)
   - Practical guide to Precision, Recall, MRR, NDCG

2. **Weaviate: Evaluation Metrics for Search**
   - [Link](https://weaviate.io/blog/retrieval-evaluation-metrics)
   - Deep dive on rank-aware metrics

3. **Pinecone: RAG Evaluation**
   - [Link](https://www.pinecone.io/learn/series/vector-databases-in-production-for-busy-engineers/rag-evaluation/)
   - Production best practices

### Contextify Codebase References

- **Database Layer**: `app/Sources/ContextifyCore/Database/`
  - `TranscriptOrchestrator.swift` - High-level DB API
  - `Repositories.swift` - Type-safe CRUD operations
  - `DatabaseSchema.swift` - Migrations and schema

- **LLM Integration**: `Contextify/Contextify/FoundationLLM.swift`
  - Timeline summarization
  - Structured generation via `@Generable`
  - Session management

- **UI Layer**: `Contextify/Contextify/`
  - `TranscriptInventoryView.swift` - Transcript browsing
  - `ConversationTimelineView.swift` - Timeline display

---

## Glossary

**BM25**: Best Matching 25, a probabilistic keyword-based ranking function (similar to TF-IDF but with better normalization).

**Chunk**: A segment of text used as a unit for embedding and retrieval (e.g., a conversation entry, paragraph, or sentence).

**Cosine Similarity**: Metric measuring the cosine of the angle between two vectors. Range [-1, 1], where 1 = identical direction.

**DCG (Discounted Cumulative Gain)**: Ranking metric that rewards placing relevant results at the top of the list.

**Dense Embedding**: Vector representation where most/all dimensions have non-zero values (e.g., BERT, NLContextualEmbedding).

**Embedding**: Dense vector representation of text in a continuous space where semantic similarity is captured by distance.

**HNSW (Hierarchical Navigable Small Worlds)**: Graph-based algorithm for approximate nearest neighbor search. Trade accuracy for speed.

**Hybrid Search**: Combining multiple retrieval methods (e.g., semantic + keyword + metadata filters).

**k-NN (k-Nearest Neighbors)**: Algorithm to find the k most similar items to a query (in embedding space, by cosine similarity).

**MRR (Mean Reciprocal Rank)**: Metric measuring how quickly the first relevant result appears. Average of 1/rank across queries.

**NDCG (Normalized Discounted Cumulative Gain)**: DCG normalized by the ideal ranking (IDCG). Range [0, 1] where 1 = perfect.

**NLContextualEmbedding**: Apple's API for generating sentence embeddings using a multilingual BERT model (512 dimensions).

**Precision@k**: Fraction of top-k results that are relevant. Measures false positive rate.

**RAG (Retrieval-Augmented Generation)**: Pattern where an LLM is augmented with retrieved context from an external knowledge base.

**Recall@k**: Fraction of all relevant items that appear in top-k results. Measures false negative rate.

**Re-Ranking**: Two-stage retrieval where fast approximate search retrieves candidates, then expensive method re-ranks them.

**RRF (Reciprocal Rank Fusion)**: Method to merge multiple rankings by summing reciprocal ranks (1/(k+rank)).

**Semantic Search**: Retrieval based on meaning rather than exact keyword matches (uses embeddings + cosine similarity).

**Sparse Embedding**: Vector where most dimensions are zero (e.g., TF-IDF, BM25).

**Token**: Subword unit used by LLMs for processing text. Rough estimate: 4 characters = 1 token.

**Vector Database**: Database optimized for storing and querying high-dimensional vectors (embeddings).

---

## Next Steps

**Immediate Actions**:
1. Review this document thoroughly
2. Set up development environment (Xcode 16+, macOS 14+ for NLContextualEmbedding)
3. Create feature branch: `feature/rag-implementation`
4. Begin Phase 1: NLContextualEmbedding integration

**Weekly Cadence**:
- **Monday**: Review phase goals, break into tasks
- **Wed**: Mid-phase checkpoint, adjust if needed
- **Fri**: Demo deliverables, update metrics

**Tracking Progress**:
- Use GitHub Issues for phase-level tracking
- Create sub-tasks in Contextify's existing TODO system
- Log evaluation metrics in `build/logs/rag-evaluation/`

**Questions / Feedback**:
- Document questions in `build/notes/research/rag/questions.md`
- Track learnings in `build/notes/research/rag/learnings.md`
- Update this guide as you discover edge cases

---

**End of Document**