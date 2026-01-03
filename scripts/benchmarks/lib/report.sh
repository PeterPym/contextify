#!/bin/bash
# Report generation utilities

# Generate markdown report from metrics JSON
# Usage: generate_report "/path/to/metrics.json" "/path/to/report.md"
generate_report() {
    local metrics_file=$1
    local report_file=$2

    python3 << 'PYTHON_SCRIPT' "$metrics_file" "$report_file"
import json
import sys
from datetime import datetime

metrics_file = sys.argv[1]
report_file = sys.argv[2]

with open(metrics_file) as f:
    data = json.load(f)

m = data.get('metrics', {})

def fmt_ms(ms):
    if ms is None:
        return "N/A"
    if ms < 1000:
        return f"{ms}ms"
    return f"{ms/1000:.2f}s"

def fmt_rate(value, unit=""):
    if value is None:
        return "N/A"
    return f"{value:,.0f}{unit}"

report = f"""# Benchmark Results

**Run ID:** {data.get('run_id', 'unknown')}
**Timestamp:** {data.get('timestamp', 'unknown')}
**Machine:** {data.get('machine', 'unknown')}
**OS Version:** {data.get('os_version', 'unknown')}
**Git:** {data.get('git_branch', 'unknown')} @ {data.get('git_commit', 'unknown')}

---

## Corpus Statistics

| Metric | Value |
|--------|-------|
| Claude Projects | {m.get('corpus', {}).get('claude_projects', 'N/A')} |
| Claude Transcripts | {m.get('corpus', {}).get('claude_transcripts', 'N/A')} |
| Claude Lines | {fmt_rate(m.get('corpus', {}).get('claude_lines'))} |
| Codex Sessions | {m.get('corpus', {}).get('codex_sessions', 'N/A')} |
| Codex Lines | {fmt_rate(m.get('corpus', {}).get('codex_lines'))} |
| **Total Lines** | {fmt_rate(m.get('corpus', {}).get('total_lines'))} |

---

## Startup Performance

| Metric | Value | Target |
|--------|-------|--------|
| Cold Start to UI Ready | {fmt_ms(m.get('startup_cold_ms'))} | <200ms |
| Database Initialization | {fmt_ms(m.get('db_init_ms'))} | - |
| Lightweight Discovery | {fmt_ms(m.get('discovery_ms'))} | - |

---

## Ingest Performance

| Metric | Value |
|--------|-------|
| Total Ingest Time | {fmt_ms(m.get('ingest_total_ms'))} |
| Lines Ingested | {fmt_rate(m.get('ingest_lines'))} |
| Ingest Rate | {fmt_rate(m.get('ingest_lines_per_sec'))} lines/sec |
| Entries Created | {fmt_rate(m.get('ingest_entries'))} |
| Peak Memory | {m.get('peak_memory_mb', 'N/A')} MB |

---

## Project Switching

| Metric | Value | Target |
|--------|-------|--------|
| Switch Time (cold) | {fmt_ms(m.get('switch_cold_ms'))} | <1s |
| Switch Time (warm) | {fmt_ms(m.get('switch_warm_ms'))} | <200ms |
| UI Update Latency | {fmt_ms(m.get('ui_update_ms'))} | <350ms |

---

## Query Performance

| Query Type | Latency | Target |
|------------|---------|--------|
| Timeline Load (50 entries) | {fmt_ms(m.get('query_timeline_ms'))} | <100ms |
| Search Query | {fmt_ms(m.get('query_search_ms'))} | <200ms |
| Session List | {fmt_ms(m.get('query_sessions_ms'))} | <50ms |

---

## Log Files

- Full log: `{m.get('log_file', 'N/A')}`
- Log size: {m.get('log_size_mb', 'N/A')} MB

---

## Notes

{m.get('notes', 'No notes recorded.')}
"""

with open(report_file, 'w') as f:
    f.write(report)

print(f"Report saved to: {report_file}")
PYTHON_SCRIPT
}

# Append summary to results history file
# Usage: append_to_history "/path/to/metrics.json" "/path/to/history.md"
append_to_history() {
    local metrics_file=$1
    local history_file=$2

    python3 << 'PYTHON_SCRIPT' "$metrics_file" "$history_file"
import json
import sys
import os

metrics_file = sys.argv[1]
history_file = sys.argv[2]

with open(metrics_file) as f:
    data = json.load(f)

m = data.get('metrics', {})

# Create header if file doesn't exist
if not os.path.exists(history_file):
    header = """# Benchmark Results History

| Date | Commit | Startup | Ingest Rate | Peak Memory | Switch Time | Notes |
|------|--------|---------|-------------|-------------|-------------|-------|
"""
    with open(history_file, 'w') as f:
        f.write(header)

# Append row
row = f"| {data.get('timestamp', 'N/A')[:10]} | {data.get('git_commit', 'N/A')} | {m.get('startup_cold_ms', 'N/A')}ms | {m.get('ingest_lines_per_sec', 'N/A')}/s | {m.get('peak_memory_mb', 'N/A')}MB | {m.get('switch_cold_ms', 'N/A')}ms | {m.get('run_notes', '-')} |\n"

with open(history_file, 'a') as f:
    f.write(row)

print(f"Added row to history: {history_file}")
PYTHON_SCRIPT
}
