# RAG Phase 1 Testing Plan
**Feature Branch:** `feature/rag-implementation`
**Phase:** 1 - Embedding Generation (Weeks 1-2)
**Started:** 2025-10-21

## Testing Strategy

We'll validate each component with simple behavioral checks before moving to the next step. This ensures we catch issues early and have a working foundation.

## Week 1: NLContextualEmbedding Integration

### Checkpoint 1.1: EmbeddingService Basic Functionality
**Component:** `EmbeddingService` actor

**Tests:**
- [ ] Can instantiate EmbeddingService
- [ ] Can call `ensureModelAvailable()` without crashing
- [ ] Can generate embedding for simple text: "Hello world"
- [ ] Generated embedding is array of 512 floats
- [ ] All embedding values are between -1.0 and 1.0
- [ ] Same text produces same embedding (deterministic)
- [ ] Different texts produce different embeddings

**Manual Test:**
```swift
let service = EmbeddingService()
let vector = try await service.generateEmbedding(for: "Hello world")
print("Vector dimension: \(vector.count)")  // Should be 512
print("Sample values: \(vector.prefix(5))")
```

**Success Criteria:** Can generate embeddings without crashing; vectors have correct dimensions.

---

### Checkpoint 1.2: Database Migration
**Component:** `DatabaseMigration_v2_Embeddings`

**Tests:**
- [ ] Migration creates `embedding` BLOB column
- [ ] Migration creates `embedding_version` INTEGER column with default 1
- [ ] Migration creates `embedding_generated_at` INTEGER column
- [ ] Migration creates index `idx_entries_embedding_version`
- [ ] Existing data is preserved after migration
- [ ] Can insert/update rows with NULL embeddings
- [ ] Can insert/update rows with BLOB embeddings

**Manual Test:**
```bash
# After running migration
sqlite3 ~/Library/Application\ Support/Contextify/contextify.db
.schema transcript_entries
# Should show new columns

SELECT id, embedding, embedding_version
FROM transcript_entries
LIMIT 5;
# Should show NULL embeddings (not yet generated)
```

**Success Criteria:** Schema updated correctly; no data loss; app starts without errors.

---

### Checkpoint 1.3: Embedding Serialization
**Component:** Embedding helper functions

**Tests:**
- [ ] Can serialize [Float] to Data
- [ ] Can deserialize Data back to [Float]
- [ ] Round-trip preserves all values (serialize → deserialize = identity)
- [ ] Serialized size is 512 floats × 4 bytes = 2048 bytes
- [ ] Works with edge cases (all zeros, all ones, negative values)

**Manual Test:**
```swift
let original: [Float] = Array(repeating: 0.5, count: 512)
let data = serializeEmbedding(original)
let restored = deserializeEmbedding(data)

assert(data.count == 2048)
assert(original == restored)
print("✅ Serialization round-trip successful")
```

**Success Criteria:** Lossless round-trip; correct byte size.

---

### Checkpoint 1.4: EmbeddingRepository
**Component:** `EmbeddingRepository` implementation

**Tests:**
- [ ] Can save embedding for an entry ID
- [ ] Can retrieve saved embedding by entry ID
- [ ] Returns nil for entry without embedding
- [ ] `getEntriesWithoutEmbeddings()` returns only entries with NULL embedding
- [ ] `getAllEntriesWithEmbeddings()` returns entries with embeddings and skips NULLs
- [ ] Saving embedding updates `embedding_generated_at` timestamp
- [ ] Saving embedding updates `embedding_version` field

**Manual Test:**
```swift
let repo = EmbeddingRepositoryImpl(db: DatabaseManager.shared.pool)

// Get a real entry ID from the database
let entries = try await repo.getEntriesWithoutEmbeddings(version: 1)
guard let firstEntry = entries.first else {
  print("No entries in database - populate first")
  return
}

// Generate and save embedding
let testVector = Array(repeating: Float(0.123), count: 512)
try await repo.saveEmbedding(entryId: firstEntry.id, vector: testVector, version: 1)

// Retrieve and verify
if let retrieved = try await repo.getEmbedding(entryId: firstEntry.id) {
  print("✅ Retrieved embedding dimension: \(retrieved.count)")
  print("✅ First value matches: \(retrieved[0] == testVector[0])")
} else {
  print("❌ Failed to retrieve embedding")
}
```

**Success Criteria:** CRUD operations work; correct filtering by embedding presence.

---

### Checkpoint 1.5: Integration Test
**Component:** Full stack (Service → Repository → Database)

**Tests:**
- [ ] Can generate embedding via EmbeddingService
- [ ] Can save it via EmbeddingRepository
- [ ] Can retrieve it and verify it matches original
- [ ] App builds without errors
- [ ] App launches without crashing
- [ ] No console errors related to embeddings on startup

**Manual Test:**
```swift
// In a test view or button action
Task {
  let service = EmbeddingService()
  let repo = EmbeddingRepositoryImpl(db: DatabaseManager.shared.pool)

  // Get an entry
  let entries = try await repo.getEntriesWithoutEmbeddings(version: 1)
  guard let entry = entries.first else { return }

  // Generate embedding for its content
  let vector = try await service.generateEmbedding(for: entry.content)

  // Save to database
  try await repo.saveEmbedding(entryId: entry.id, vector: vector, version: 1)

  // Verify retrieval
  let retrieved = try await repo.getEmbedding(entryId: entry.id)
  print("✅ End-to-end test passed: \(retrieved?.count == 512)")
}
```

**Success Criteria:** Can generate, save, and retrieve embeddings for real conversation entries.

---

## Week 2: Batch Processing & Progress Tracking

### Checkpoint 2.1: Batch Processing Logic
**Component:** `EmbeddingOrchestrator`

**Tests:**
- [ ] Can process batch of 10 entries
- [ ] Progress callback fires for each batch
- [ ] All entries get embeddings after completion
- [ ] Process is resumable (skip already-embedded entries)
- [ ] Handles errors gracefully (e.g., one entry fails, others continue)

**Manual Test:**
```swift
let orchestrator = EmbeddingOrchestrator()

try await orchestrator.generateEmbeddingsForAllEntries(batchSize: 10) { current, total in
  print("Progress: \(current)/\(total)")
}

// Verify all entries now have embeddings
let remaining = try await repo.getEntriesWithoutEmbeddings(version: 1)
print("Entries without embeddings: \(remaining.count)")  // Should be 0
```

**Success Criteria:** Batch processing completes; all entries embedded; progress tracking works.

---

### Checkpoint 2.2: Progress UI
**Component:** `EmbeddingProgressView`

**Tests:**
- [ ] UI shows total entry count
- [ ] Progress bar updates during generation
- [ ] Button disables during processing
- [ ] Shows completion message when done
- [ ] Can run process multiple times (idempotent)

**Manual Test:**
1. Add temporary button to ContentView: "Test Embeddings"
2. Clicking shows EmbeddingProgressView sheet
3. Start generation and watch progress
4. Verify console shows embedding generation
5. After completion, re-run to verify it skips already-embedded entries

**Success Criteria:** UI is responsive; progress updates in real-time; no crashes.

---

### Checkpoint 2.3: Performance Baseline
**Component:** Embedding generation speed

**Tests:**
- [ ] Measure time to embed 100 entries
- [ ] Measure time to embed 1000 entries
- [ ] Verify memory usage is reasonable (<500MB for 10k entries)
- [ ] No memory leaks during batch processing

**Manual Test:**
```swift
let start = Date()
try await orchestrator.generateEmbeddingsForAllEntries(batchSize: 100)
let duration = Date().timeIntervalSince(start)
print("Embedded \(totalEntries) entries in \(duration) seconds")
print("Rate: \(Double(totalEntries) / duration) entries/sec")
```

**Expected Performance:**
- ~50-100 entries/sec on M1 Mac
- ~1000 entries in 10-20 seconds

**Success Criteria:** Performance meets baseline; no crashes with large batches.

---

## Phase 1 Completion Checklist

Before moving to Phase 2, verify:

- [ ] ✅ All Week 1 checkpoints pass
- [ ] ✅ All Week 2 checkpoints pass
- [ ] ✅ Database migration is backward compatible (can roll back if needed)
- [ ] ✅ App builds without warnings
- [ ] ✅ No new console errors on launch
- [ ] ✅ Embeddings persist across app restarts
- [ ] ✅ Can query database directly and see embeddings
- [ ] ✅ Documentation updated (inline comments + this test plan)
- [ ] ✅ Commit all changes with clear messages
- [ ] ✅ Push feature branch to remote

## Rollback Plan

If Phase 1 doesn't work:

1. **Database rollback:** Use `make db-restore` to restore pre-migration backup
2. **Code rollback:** `git checkout main` to return to stable state
3. **Preserve work:** Feature branch remains for future retry

## Next Phase Preview

Once Phase 1 is solid, Phase 2 will add:
- Cosine similarity search function
- Basic search UI (query input → results)
- Performance profiling for 1k/10k entries

---

**Notes:**
- Keep this document updated as we implement
- Mark checkpoints complete with date/time
- Add any unexpected issues or learnings
