# Ingest Optimization Analysis

> Originally created 2026-01-03. Updated with implementation results.

## Baseline Metrics

| Metric | Value |
|--------|-------|
| Startup (cold) | 43ms |
| Total ingest time | 1,516s (~25 min) |
| Corpus size | 360,891 lines |
| Ingest rate | **237 lines/sec** |
| Peak memory | 864.2MB |
| Final DB size | 385MB |
| Entries created | 172,657 |

## Profiling Analysis

### Hotspot: HooverEngine.commitBatch (90% of time)

From `sample` output:
```
257 Thread: GRDB.DatabasePool.writer
  └── 256 TranscriptOrchestrator.ingestTranscript
       └── 256 HooverEngine.hooverTranscript
            └── 238 HooverEngine.commitBatch
                 └── 238 DatabaseWriter.write
                      └── 237 Database.inTransaction
                           └── 133 Database.execute (UPDATE/DELETE)
                           └── 104 model.insert
                                └── 128 sqlite3_step
                                     └── 118 sqlite3VdbeExec
                                          └── 114 sqlite3BtreeNext
                                               └── 112 moveToChild
                                                    └── 110 getAndInitPage
                                                         └── 90 getPageNormal
                                                              └── 89 readDbPage
                                                                   └── 89 unixRead
```

**Root cause:** SQLite is spending most time doing disk I/O for B-tree page reads.

## Identified Bottlenecks

### 1. Per-Entry Parent Validation (HooverEngine.swift:1137)

```swift
// For EACH entry:
let parentExists = try Bool.fetchOne(db, sql: """
  SELECT EXISTS(SELECT 1 FROM transcript_entries WHERE id = ?)
""", arguments: [parentId]) ?? false
```

**Impact:** O(n) queries for batch of n entries
**Fix:** Collect parent IDs, do single batch validation query

### 2. Index Write Amplification

**54 indexes on database** - each insert triggers multiple index updates:
- `transcript_entries` has 12+ indexes
- `tool_invocations` has 8+ indexes

**Impact:** Write amplification factor ~15-20x
**Fix Phase 2:** Consider dropping some indexes during bulk ingest, or marking them as partial

### 3. Sequential Individual Inserts

Each entry is inserted individually via `model.insert(db)` rather than batch multi-row INSERT.

**Impact:** More transaction log writes, more syscalls
**Fix:** Use GRDB's batch insert if available, or construct multi-row INSERT

### 4. Update Storm for Tool Results (HooverEngine.swift:1206-1248)

Each `toolResultData` item does:
- 1 UPDATE for result linkage
- 1 UPDATE for sidechain linkage (conditional)
- Additional UPDATE for sidechain entries

**Impact:** Many UPDATE queries per batch
**Fix:** Batch UPDATE queries or defer to end of ingest

## Optimization Priority List

### P1: Batch Parent Validation - DONE (commit 972adb39)
- **File:** `HooverEngine.swift:1136-1147`
- **Effort:** 30 min
- **Expected gain:** 5-10% on ingest time (reduce query count)
- **Actual result:** +8% with batch=1000, +3% with batch=2000
- **Implementation:**
  - Changed O(n) per-entry queries to single batch query
  - P0.1 fix: Add inserted entries to existingParentIds for same-batch parent links
  - P0.2 fix: Chunk parent ID queries into groups of 500 to avoid SQLite 999 parameter limit
  - P1.1 fix: Clamp CONTEXTIFY_BATCH_LINES to max 10000

### P2: Increase Batch Size (Experiment) - DONE
- **Current:** 1000 lines/batch (default)
- **Test:** 2000 batch size tested
- **Result:** No improvement - slightly slower (244 vs 256 lines/sec)
- **Conclusion:** P0.2 chunking overhead offsets gains from fewer commits. Stick with 1000.

### P3: WAL Checkpoint After Bulk Ingest - TODO
- **File:** `DatabaseManager.swift`
- **Effort:** 15 min
- **Expected gain:** Reduce WAL file size, improve subsequent queries

### P4: Defer Tool Result Updates - TODO
- **Effort:** 2-3 hours
- **Expected gain:** 10-15% on ingest time

## Memory Profile

| Time | Memory |
|------|--------|
| 0-40s | 300MB → 864MB (peak) |
| 50s | Drops to 348MB |
| 100s-500s | Oscillates 170-400MB |
| 600s+ | Settles at 130-200MB |

Peak memory during initial project discovery and first batch processing.

## Current Performance

| Version | Ingest Rate | vs Baseline |
|---------|-------------|-------------|
| Baseline (v1.0.7) | 237 lines/sec | - |
| With P1/P2 fixes | 244 lines/sec | +3% |

## Recommendations

1. ~~**Start with P1 (batch parent validation)**~~ - DONE, +3% improvement
2. ~~**Experiment with batch size**~~ - DONE, no benefit from larger batches
3. **Add WAL checkpoint** - prevents WAL bloat during long ingest sessions
4. **Consider deferred tool result updates** - potential 10-15% gain
5. **Consider deferred index updates** for full-corpus scenarios (more invasive)

## Next Steps

1. ~~Implement P1 batch parent validation~~ - DONE
2. ~~Run benchmark to measure improvement~~ - DONE
3. Implement P3 (WAL checkpoint) - low effort, prevents WAL bloat
4. Evaluate P4 (defer tool result updates) - higher effort, bigger potential gain
