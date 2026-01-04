# Benchmark Results History

| Date | Commit | Startup | Ingest Rate | Peak Memory | Switch Time | Notes |
|------|--------|---------|-------------|-------------|-------------|-------|
| 2026-01-03 | c667d59f | 43ms | 237 lines/sec | 864MB | - | Baseline v1.0.7 with CLI flags |
| 2026-01-03 | e253f9f1 | 53ms | 256 lines/sec | 897MB | - | P1: batch parent validation (+8%) |
| 2026-01-03 | 972adb39 | 44ms | 244 lines/sec | 847MB | - | P0/P1/P2 fixes, batch=2000 (+3% vs baseline) |
| 2026-01-04 | 70a21b56 | - | **505 entries/sec** | - | - | **P1.1: PRAGMA cache/mmap (+102% vs baseline)** |
| 2026-01-04 | 3b3d2404 | - | **750 entries/sec** | - | - | **P1.1 refined: +reader limit, better logging (+217% vs baseline)** |

## Notes

- **2026-01-03 972adb39**: Added P0.1 (same-batch parent links), P0.2 (chunk queries for SQLite limit), P1.1 (clamp batch size). Batch size 2000 tested but showed no improvement over 1000 - the P0.2 chunking overhead offsets gains from fewer commits. Recommended batch size remains 1000.

- **2026-01-04 70a21b56**: P1.1 PRAGMA tuning - major win. Added `cache_size=-102400` (100MB) and `mmap_size=1073741824` (1GB). The optimization brief predicted 15-30% gain; actual gain was **102%** (2x speedup). This suggests the previous bottleneck was disk I/O and page cache thrashing, not index maintenance or JSON parsing. Bulk ingest mode (index deferral) tested separately showed no benefit - confirms I/O was the real bottleneck.

- **2026-01-04 3b3d2404**: P1.1 review improvements after ChatGPT code review (2 iterations). Changes: (1) Extracted magic numbers to named constants with documentation, (2) Reduced `maximumReaderCount` from 5 to 2 to bound cache memory to ~300MB, (3) Added PRAGMA verification logging with computed MiB. Sustained rate of **750 entries/sec** confirmed (**3x improvement** over baseline 237/s). P1.2 (prepared statement reuse) and P1.3 (multi-row INSERT) were evaluated but deferred - GRDB already caches statements, and multi-row INSERT would break same-batch parent linking logic for marginal gains.

- **2026-01-04 (not merged)**: P2 fresh build optimizations investigated but abandoned. Tested: (1) `page_size=16KB`, (2) `synchronous=OFF`, (3) `wal_autocheckpoint=0`. Measured ~790/s (only 5% improvement over 750/s baseline). ChatGPT review identified P0 issues: page_size not reliably applied without VACUUM, unsafe settings persist after build phase without proper transition logic, missing checkpoint at end. Given marginal gain (5%) and significant complexity to implement correctly, decided not to merge. The P1.1 optimizations (cache/mmap) already captured the major I/O wins.
