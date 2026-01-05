# Performance Optimization Follow-up

**Created:** 2026-01-05
**Related TODO:** #PERF-AUDIT-FOLLOWUP
**Prior work:** P1.1 PRAGMA tuning, P6 preloaded entry IDs, P7 observation-free bulk ingest

---

## Summary

Performance optimization phases P1-P7 completed. Full benchmark results:

| Metric | Baseline (v1.0.7) | P7 (main) |
|--------|-------------------|-----------|
| Corpus | 363k lines | 363k lines |
| Entries created | ~65k | 174k |
| Total time | ~27 min | 11.1 min |
| Entry rate | ~40 entries/sec | 260 entries/sec |
| Line rate | 237 lines/sec | 544 lines/sec |

**Key finding:** Short burst tests (20s) show ~925 entries/sec, but sustained full-corpus ingest is 260 entries/sec. Performance degrades as database grows.

---

## Performance Gap Analysis

| Test Type | Rate | Duration | Notes |
|-----------|------|----------|-------|
| 20s burst (CLI flags) | ~925 entries/sec | 20s | Fresh DB, minimal entries |
| Full benchmark (CLI flags) | 260 entries/sec | 11.1 min | 174k entries, sustained |
| **Degradation** | **72%** | - | Performance drops 3.5x over time |

**Potential causes to investigate:**
1. Database size effects - INSERT slows as table grows
2. WAL checkpointing overhead - periodic checkpoints cause pauses
3. Memory pressure - peak 1GB, may trigger GC/compaction
4. FTS index maintenance - triggers fire on every INSERT
5. preloadedEntryIds set growth - O(n) memory and lookup cost

---

## Benchmark Testing Methodology

### What Works: Short Tests (20 seconds)

Quick 20-second tests are sufficient to identify gross performance differences:

```bash
# Clean test pattern
rm -f /tmp/test-perf.db*
./.derived-dmg/Build/Products/Debug/Contextify.app/Contents/MacOS/Contextify \
  --database-path /tmp/test-perf.db --no-summaries --quiet &
sleep 10
e1=$(sqlite3 /tmp/test-perf.db "SELECT COUNT(*) FROM transcript_entries")
sleep 10
e2=$(sqlite3 /tmp/test-perf.db "SELECT COUNT(*) FROM transcript_entries")
pkill -f Contextify
echo "10s: $e1 ($(($e1/10))/sec), 20s: $e2 ($(($e2/20))/sec)"
```

**Use for:** Quick A/B comparisons, cherry-pick testing, regression detection

### What Doesn't Work: Short Tests for Full-App Behavior

20-second CLI tests do NOT reflect real-app performance because:
- They bypass UI overhead
- They don't trigger ValueObservation
- They don't exercise the full app lifecycle

**Use full benchmarks or cleanrun for:** Validating production-representative performance

### Real-App Testing Pattern

```bash
# Via cleanrun (resets DB, TCC, state)
scripts/xc.sh dr  # Then measure from DB timestamps

# Check results
sqlite3 ~/Library/Application\ Support/Contextify/contextify.db "
SELECT
  datetime(MIN(created_at), 'unixepoch', 'localtime') as start,
  datetime(MAX(created_at), 'unixepoch', 'localtime') as end,
  (MAX(created_at) - MIN(created_at)) as duration_sec,
  COUNT(*) as entries,
  COUNT(*) / (MAX(created_at) - MIN(created_at)) as rate
FROM transcript_entries"
```

---

## Key Documents

### Performance Infrastructure
- `build/docs/performance/benchmark-guide.md` - How to run benchmarks
- `build/docs/performance/benchmark-history.md` - Historical results and notes
- `scripts/performance/README.md` - Script reference

### Architecture
- `build/docs/architecture/data-pipeline-architecture.md` - Ingest pipeline overview
- `build/docs/architecture/ingestion-workflow.md` - Detailed ingest flow
- `app/Sources/ContextifyCore/Database/BulkIngestManager.swift` - P7 implementation
- `app/Sources/ContextifyCore/Database/HooverEngine.swift` - Core ingest logic

### Profiling
- `build/profiles/` - Time Profiler samples
- `scripts/performance/profile.sh` - Profiling wrapper

---

## Abandoned Approaches

These were investigated and rejected (don't repeat):

| Approach | Why Abandoned |
|----------|---------------|
| P2 (page_size=16KB, sync=OFF) | Only 5% gain, unsafe settings, complex transition logic |
| P3.1 (temp table JOIN) | No improvement - overhead offsets benefit |
| P3.2 (WITHOUT ROWID) | High migration complexity for 5-10% expected gain |
| P5 (UNIQUE dedupe index) | Caused FK constraint failures |
| P7 hardening (thread safety queue) | 6% overhead for redundant safety (BulkIngestManager already serialized by HooverEngine) |

---

## Preserved Artifacts

- `backup/p7-hardening-aaea7c43` - Branch with hardening commits if ever needed
- `scripts/performance/results/*.json` - Benchmark result files
- Profile files referenced in benchmark-history.md

---

## Next Investigation Areas

### High Priority

1. **Headless macOS Ingest Engine**
   - The 48% CLI vs real-app gap suggests UI coupling is the bottleneck
   - Consider separating ingest into background process/XPC service
   - Benefits: faster ingest, UI remains responsive, architecture matches Linux
   - Implementation options:
     - XPC service (cleanest isolation)
     - Background daemon with IPC
     - In-process but fully decoupled from UI thread

2. **Linux Engine Validation**
   - Linux has no SwiftUI/AppKit - should perform at CLI speeds (~900+ entries/sec)
   - Verify P7 BulkIngestManager works on Linux
   - May become the reference implementation for "how fast ingest can be"

### Medium Priority

3. **Profile Real-App Overhead**
   - Where does the 48% overhead come from?
   - Candidates: ValueObservation, UI updates, memory pressure, task scheduling
   - Use Instruments Time Profiler on real app vs CLI

4. **Memory Optimization**
   - Current peak: ~1GB during ingest
   - May affect performance on memory-constrained machines

### Lower Priority

5. **Incremental Ingest Performance**
   - Current benchmarks measure cold-start full ingest
   - Re-ingest of existing transcripts should be faster (deduplication)

---

## Sustained Performance Interventions

The 72% degradation from burst (925/sec) to sustained (260/sec) suggests accumulating overhead. Possible interventions:

### High-Impact (likely culprits)

1. **Batch WAL Checkpointing**
   - Current: checkpoint after every batch or auto-triggered
   - Intervention: checkpoint every N batches or by size threshold
   - Why: checkpointing is expensive, less frequent = faster throughput

2. **preloadedEntryIds Set Growth**
   - Current: grows unbounded (174k entries in Set by end)
   - Intervention: use bloom filter or bounded LRU cache
   - Why: Set memory and lookup cost grow O(n)

3. **Defer FTS Indexing**
   - Current: FTS triggers fire on every INSERT
   - Intervention: disable triggers during bulk ingest, rebuild index at end
   - Why: FTS overhead compounds with volume (24% of write time per profiling)

### Medium-Impact

4. **Batch Size Tuning**
   - Test larger batches (2000, 5000) to reduce commit overhead
   - Trade-off: memory vs throughput
   - Earlier testing showed diminishing returns, but worth revisiting with P7

5. **Memory Pressure Mitigation**
   - Peak 1GB suggests possible GC pauses
   - Stream/release entries after commit rather than holding references

6. **Transaction Batching Across Transcripts**
   - Group multiple transcripts into single transaction
   - Reduces per-transcript transaction overhead

### Diagnostic Approach

Before implementing, run benchmark with fine-grained sampling to identify WHERE degradation occurs:

```bash
# Sample every 30s to see degradation curve
0-30s:    ???/sec (fresh DB, baseline burst)
30-60s:   ???/sec
...
600-660s: ???/sec (174k entries, final rate)
```

This reveals if degradation is:
- **Linear**: suggests O(n) overhead (preloadedEntryIds, index size)
- **Stepwise drops**: suggests periodic overhead (checkpointing, GC)
- **Exponential**: suggests compounding issue (memory fragmentation)
