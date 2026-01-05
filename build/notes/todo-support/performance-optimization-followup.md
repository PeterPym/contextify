# Performance Optimization Follow-up

**Created:** 2026-01-05
**Related TODO:** #PERF-AUDIT-FOLLOWUP
**Prior work:** P1.1 PRAGMA tuning, P6 preloaded entry IDs, P7 observation-free bulk ingest

---

## Summary

Performance optimization phases P1-P7 completed with significant gains:
- **Baseline (v1.0.7):** 237 lines/sec
- **Final (P7 merged):** ~925 entries/sec (CLI), ~500 entries/sec (real app)
- **Total improvement:** ~4x over baseline

However, a significant gap exists between CLI-mode performance and real-app performance that warrants investigation.

---

## Performance Gap Analysis

| Mode | Rate | Notes |
|------|------|-------|
| CLI with flags (`--database-path /tmp/test.db --no-summaries --quiet`) | ~925 entries/sec | Headless, minimal overhead |
| Real app (cleanrun) | ~480 entries/sec | Full UI, observers, lifecycle |
| **Gap** | **48%** | Real app is ~half CLI speed |

**Potential causes to investigate:**
1. UI thread contention during ingest
2. GRDB ValueObservation overhead on the main pool (separate from bulk ingest)
3. Memory pressure from UI components
4. SwiftUI view updates triggered by database changes
5. Background task scheduling differences

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
