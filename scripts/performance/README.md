# Performance Scripts

Tools for benchmarking and profiling Contextify performance.

## Quick Start

```bash
# Run full benchmark suite
./scripts/performance/run-perf-suite.sh

# Profile with Instruments (Time Profiler)
./scripts/performance/profile.sh -t 60

# Profile with sample command (simpler text output)
./scripts/performance/profile.sh -s -t 10
```

## Scripts

| Script | Purpose |
|--------|---------|
| `run-perf-suite.sh` | Full benchmark suite (startup, ingest, queries) |
| `profile.sh` | Wrapper for xctrace/sample profiling |
| `compare.sh` | Compare benchmark runs |
| `set-baseline.sh` | Set baseline for comparisons |

## Documentation

Detailed guides in `build/docs/performance/`:

- **[benchmark-guide.md](../../build/docs/performance/benchmark-guide.md)** - How to run and interpret benchmarks
- **[benchmark-history.md](../../build/docs/performance/benchmark-history.md)** - Historical results and optimization notes
- **[optimization-plan.md](../../build/docs/performance/optimization-plan.md)** - Optimization roadmap
- **[PERFORMANCE-PROFILING-guide.md](../../build/notes/todo-support/PERFORMANCE-PROFILING-guide.md)** - xctrace, os_signpost, XCTest profiling

## Output Locations

| Type | Location |
|------|----------|
| Benchmark results (JSON) | `scripts/performance/results/` |
| Instrument traces | `build/profiles/` |
| Sample output | `build/profiles/` |
| Benchmark logs | `/tmp/contextify-benchmark-*.log` |

## Workflow

```bash
# 1. Establish baseline
./scripts/performance/run-perf-suite.sh --full
./scripts/performance/set-baseline.sh

# 2. Make changes, then benchmark again
./scripts/performance/run-perf-suite.sh --full --notes "Description"

# 3. Compare
./scripts/performance/compare.sh

# 4. If improvement confirmed, update baseline
./scripts/performance/set-baseline.sh
```

## Profiling Options

```bash
# Instruments Time Profiler (default)
./scripts/performance/profile.sh -t 60

# Attach to running app
./scripts/performance/profile.sh -a -t 30

# Energy profiling
./scripts/performance/profile.sh -T "Energy Log" -t 120

# Memory/allocations
./scripts/performance/profile.sh -T "Allocations" -t 60

# Simple sample command (text output, easier to parse)
./scripts/performance/profile.sh -s -t 10
```
