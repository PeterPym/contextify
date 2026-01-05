# Performance Documentation

Documentation for Contextify performance optimization and benchmarking.

## Documents

| Document | Purpose |
|----------|---------|
| [benchmark-guide.md](benchmark-guide.md) | How to run benchmarks and interpret results |
| [benchmark-history.md](benchmark-history.md) | Historical results, optimization notes, lessons learned |
| [optimization-plan.md](optimization-plan.md) | Optimization roadmap and priorities |
| [baseline-2026-01.md](baseline-2026-01.md) | January 2026 baseline measurements |
| [ingest-optimization-analysis.md](ingest-optimization-analysis.md) | Deep dive on ingest pipeline optimization |

## Scripts

Performance scripts in [`scripts/performance/`](../../../scripts/performance/):

```bash
# Run full benchmark suite
./scripts/performance/run-perf-suite.sh

# Profile with Instruments or sample command
./scripts/performance/profile.sh -t 60
./scripts/performance/profile.sh -s -t 10  # sample command (text output)

# Compare runs
./scripts/performance/compare.sh
```

See [`scripts/performance/README.md`](../../../scripts/performance/README.md) for full usage.

## Related

- [PERFORMANCE-PROFILING-guide.md](../../notes/todo-support/PERFORMANCE-PROFILING-guide.md) - xctrace, os_signpost, XCTest patterns

## Current Status

**Optimization phase complete.** Ingest rate of 1623 lines/sec exceeds the 900-1200 target.

See [benchmark-history.md](benchmark-history.md) for the full optimization journey.
