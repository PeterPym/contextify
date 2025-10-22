# RAG Implementation Roadmap
**Feature Branch:** `feature/rag-implementation`
**Started:** 2025-10-21

## Overview

Implementing a Retrieval-Augmented Generation (RAG) system for Contextify's conversation history using Apple's on-device AI stack. See `implementation-guide.md` for full details.

## Phase 1: Embedding Generation (Current)
**Duration:** Weeks 1-2
**Goal:** Generate and store embeddings for all conversation entries

### Week 1: Foundation
- [ ] EmbeddingService actor with NLContextualEmbedding
- [ ] Database migration for embedding storage
- [ ] EmbeddingRepository CRUD operations
- [ ] Serialization/deserialization helpers
- [ ] Basic integration tests

**Behavioral Checkpoints:**
- Can generate 512-dim vectors for text
- Can save/retrieve embeddings from database
- App builds and runs without errors

### Week 2: Batch Processing
- [ ] EmbeddingOrchestrator for batch generation
- [ ] Progress tracking with callbacks
- [ ] Simple UI for triggering batch jobs
- [ ] Performance baseline (entries/sec)
- [ ] Resumability (skip already-embedded)

**Behavioral Checkpoints:**
- Can embed 1000+ entries without crashing
- Progress updates in real-time
- Idempotent (can re-run safely)

## Phase 2: Vector Storage & Basic Search (Future)
**Duration:** Week 3
**Goal:** Implement cosine similarity search

- Cosine similarity function (with Accelerate optimization)
- Top-k retrieval
- Basic search UI
- Performance profiling

**Behavioral Checkpoints:**
- Can search 1k entries in <100ms
- Results ranked by relevance
- Search UI is responsive

## Phase 3: Hybrid Search (Future)
**Duration:** Weeks 4-5
**Goal:** Combine semantic + metadata filtering

- Keyword boosting (BM25-style)
- Metadata filters (project, session, date, role)
- Reciprocal Rank Fusion
- Advanced search UI

**Behavioral Checkpoints:**
- Hybrid search outperforms semantic-only
- Filters work correctly
- Results are more relevant

## Phase 4: Context Assembly + Insights (Future)
**Duration:** Weeks 6-7
**Goal:** Generate insights from retrieved chunks

- Context assembly pipeline
- FoundationLLM integration
- Query templates (how-to, show-me, status)
- Export to transcript feature

**Behavioral Checkpoints:**
- LLM generates useful summaries
- Context fits within 4096 token limit
- Export works with Claude Code/Codex

## Phase 5: Advanced Retrieval (Future)
**Duration:** Weeks 8-10
**Goal:** Optimize retrieval quality

- Two-stage retrieval (retrieve 100, re-rank to 10)
- Query expansion
- Cross-project pattern detection
- Temporal weighting

**Behavioral Checkpoints:**
- Precision@10 ≥80%
- Advanced features provide measurable improvement

## Phase 6: Evaluation Framework (Future)
**Duration:** Week 11
**Goal:** Measure and monitor quality

- Test query set with ground truth
- Automated metrics (Precision@k, MRR, NDCG)
- A/B testing framework
- Quality dashboard

**Behavioral Checkpoints:**
- Can compare retrieval strategies quantitatively
- Metrics track quality over time

## Success Criteria

By end of Phase 1:
- ✅ All conversation entries have embeddings
- ✅ Database schema supports vector storage
- ✅ Foundation for semantic search is ready
- ✅ No regressions in existing functionality

## Development Principles

1. **Build incrementally:** Each phase builds on previous work
2. **Test continuously:** Validate behavior at each checkpoint
3. **Fail fast:** Fix issues before moving to next phase
4. **Document learnings:** Update notes as we discover things
5. **No attribution:** Keep commits human-focused (per project guidelines)

## File Locations

- **Implementation guide:** `build/notes/research/rag/implementation-guide.md`
- **Testing plan:** `build/notes/research/rag/phase1-testing-plan.md`
- **This roadmap:** `build/notes/research/rag/implementation-roadmap.md`
- **Source code (future):**
  - `app/Sources/ContextifyCore/Embeddings/EmbeddingService.swift`
  - `app/Sources/ContextifyCore/Embeddings/EmbeddingRepository.swift`
  - `app/Sources/ContextifyCore/Embeddings/EmbeddingOrchestrator.swift`

## Notes

- Using NLContextualEmbedding (macOS 14+) for embeddings
- Using FoundationModels (macOS 26+) for LLM in later phases
- SQLite with GRDB for storage (no external vector DB needed yet)
- Target: <10k entries initially (brute-force search is sufficient)
