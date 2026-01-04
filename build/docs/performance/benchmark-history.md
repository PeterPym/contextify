# Benchmark Results History

| Date | Commit | Startup | Ingest Rate | Peak Memory | Switch Time | Notes |
|------|--------|---------|-------------|-------------|-------------|-------|
| 2026-01-03 | c667d59f | 43ms | 237 lines/sec | 864MB | - | Baseline v1.0.7 with CLI flags |
| 2026-01-03 | e253f9f1 | 53ms | 256 lines/sec | 897MB | - | P1: batch parent validation (+8%) |
| 2026-01-03 | 972adb39 | 44ms | 244 lines/sec | 847MB | - | P0/P1/P2 fixes, batch=2000 (+3% vs baseline) |

## Notes

- **2026-01-03 972adb39**: Added P0.1 (same-batch parent links), P0.2 (chunk queries for SQLite limit), P1.1 (clamp batch size). Batch size 2000 tested but showed no improvement over 1000 - the P0.2 chunking overhead offsets gains from fewer commits. Recommended batch size remains 1000.
