# Performance Benchmark Guide

## Overview

The benchmark suite measures Contextify performance across several dimensions:
- **Startup:** Cold start to UI ready
- **Ingest:** Full corpus processing rate and memory usage
- **Switching:** Project switch latency
- **Queries:** Database query performance

## Optimization Workflow

The standard workflow for performance optimization:

```bash
# 1. Establish baseline (once, before making changes)
./scripts/benchmarks/run-perf-suite.sh --full
./scripts/benchmarks/set-baseline.sh

# 2. Make your optimization changes
# ... edit code ...

# 3. Run benchmark again
./scripts/benchmarks/run-perf-suite.sh --full --notes "Description of change"

# 4. Compare to baseline
./scripts/benchmarks/compare.sh

# 5. If improvement confirmed, update baseline for next round
./scripts/benchmarks/set-baseline.sh
```

## Running Benchmarks

### Prerequisites

1. Build the DMG target:
   ```bash
   bash scripts/xc.sh build
   ```

2. Ensure you have transcript data in standard locations:
   - `~/.claude/projects/`
   - `~/.codex/sessions/`

### Quick Benchmark

Measures startup only (fast, ~1 minute):

```bash
./scripts/benchmarks/run-perf-suite.sh --quick
```

### Full Benchmark

Measures everything including full ingest (~20 minutes):

```bash
./scripts/benchmarks/run-perf-suite.sh --full
```

### With Instruments Profiling

Adds CPU/memory profiling (slower, more data):

```bash
./scripts/benchmarks/run-perf-suite.sh --full --instruments
```

### Adding Notes

Tag runs for comparison:

```bash
./scripts/benchmarks/run-perf-suite.sh --full --notes "After index optimization"
```

## Output Files

Each run produces:

| File | Description |
|------|-------------|
| `scripts/benchmarks/results/benchmark-YYYYMMDD-HHMMSS.json` | Raw metrics (JSON) |
| `scripts/benchmarks/results/benchmark-YYYYMMDD-HHMMSS.md` | Human-readable report |
| `/tmp/contextify-benchmark-YYYYMMDD-HHMMSS.log` | Full application logs |
| `build/docs/performance/benchmark-history.md` | Historical comparison |

## Interpreting Results

### Target Metrics

| Metric | Target | Notes |
|--------|--------|-------|
| Cold Startup | <200ms | Time to UI ready |
| Ingest Rate | >1000 lines/sec | Higher is better |
| Peak Memory | <500MB | During full ingest |
| Project Switch | <1s cold, <200ms warm | Time to timeline update |
| Timeline Query | <100ms | 50 entry load |

### Log Analysis

The full log file contains OSLog output with timing information. Key patterns:

```
# Startup timing
[ORCH-STARTUP] Beginning lightweight startup...
[ORCH-STARTUP] Startup complete in Xs. UI ready.

# Ingest progress
[HOOVER] Processing transcript: X lines
[HOOVER] Batch committed: X entries

# Query timing
[TIMELINE] loadFeedFromSQL completed in Xms
```

## Comparing Runs

### Using compare.sh

Compare latest run to baseline:

```bash
./scripts/benchmarks/compare.sh
```

Compare a specific run to baseline:

```bash
./scripts/benchmarks/compare.sh 20260102-143022
```

Compare two specific runs:

```bash
./scripts/benchmarks/compare.sh 20260101-100000 20260102-143022
```

### Setting the Baseline

Mark a run as the official baseline:

```bash
# Use most recent run
./scripts/benchmarks/set-baseline.sh

# Use specific run
./scripts/benchmarks/set-baseline.sh 20260102-143022
```

The baseline symlink is at `scripts/benchmarks/baseline.json`.

### Historical Trends

View the history file for trends over time:

```bash
cat build/docs/performance/benchmark-history.md
```

### Raw Comparison

For detailed diff of raw metrics:

```bash
diff scripts/benchmarks/results/benchmark-A.json scripts/benchmarks/results/benchmark-B.json
```

## Troubleshooting

### Benchmark Hangs

If the benchmark hangs during ingest:
1. Check Activity Monitor for Contextify CPU usage
2. If CPU is 0%, the app may have crashed
3. Check Console.app for crash logs

### Incomplete Results

If metrics show "N/A":
1. Check the log file for errors
2. Verify the app built correctly
3. Ensure transcript directories exist

### Database Not Deleted

The benchmark backs up and restores your database. If something goes wrong:
```bash
# Find backup
ls /tmp/contextify-db-backup-*.db

# Restore manually
cp /tmp/contextify-db-backup-XXXXX.db ~/Library/Application\ Support/Contextify/contextify.db
```
