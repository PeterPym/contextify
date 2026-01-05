# Performance Baseline - January 2026

**Status:** Pending first benchmark run
**Branch:** main-wb1
**Commit:** (to be filled after run)

## Context

This baseline establishes performance metrics after the P0 UI lag fixes:
- `2f447097 fix(watcher,timeline): prevent UI lag and stuck spinner`

The fixes addressed:
- TranscriptWatcher events blocking main thread
- ConversationMonitor phase state not resetting on stop

## Baseline Metrics

*Run `./scripts/performance/run-perf-suite.sh --full` to populate these values.*

### Corpus Size

| Metric | Value |
|--------|-------|
| Claude Projects | TBD |
| Claude Transcripts | TBD |
| Total Lines | TBD |

### Startup

| Metric | Value | Target |
|--------|-------|--------|
| Cold Start | TBD | <200ms |

### Ingest

| Metric | Value |
|--------|-------|
| Total Time | TBD |
| Rate | TBD lines/sec |
| Peak Memory | TBD MB |

### Project Switching

| Metric | Value | Target |
|--------|-------|--------|
| Cold Switch | TBD | <1s |
| Warm Switch | TBD | <200ms |

### Queries

| Metric | Value | Target |
|--------|-------|--------|
| Timeline Load | TBD | <100ms |
| Search | TBD | <200ms |

## Notes

- Baseline taken on production corpus (not synthetic data)
- Database wiped for clean measurement
- Full ingest expected to take ~16 minutes

## Next Steps

After establishing baseline:
1. Phase 2: Quick Wins (index audit, cache tuning)
2. Re-run benchmark to measure improvement
3. Update this document with comparison
