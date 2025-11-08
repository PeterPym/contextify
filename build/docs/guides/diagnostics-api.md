# Diagnostics API Usage Guide

**Purpose:** External access to timeline diagnostics without human intervention

## Overview

The Diagnostics API provides two access methods:

1. **Periodic State Export** - App writes state every 10s to `/tmp/contextify-state.json`
2. **On-Demand Requests** - Create trigger file, app responds with fresh snapshot

## Quick Start

### From Command Line (Human)

```bash
# Quick check (cached state, instant)
./scripts/read_timeline_state.sh --state | jq '.hooverState'

# Fresh snapshot (waits for app, ~100ms)
./scripts/read_timeline_state.sh --request | jq '.issues'

# Human-readable report
./scripts/read_timeline_state.sh --report
```

### From Claude Code (Automated)

```bash
# Read cached state (fast, non-blocking)
cat /tmp/contextify-state.json | jq '.hooverState'

# Request fresh diagnostics
echo "request" > /tmp/contextify-diag-request
sleep 0.5
cat /tmp/contextify-diag-response.json

# Read human-readable report
cat /tmp/contextify-diag-report.txt
```

## API Files

| File | Purpose | Update Frequency | Blocking |
|------|---------|------------------|----------|
| `/tmp/contextify-state.json` | Periodic state export | Every 10s | No (read cached) |
| `/tmp/contextify-diag-request` | Trigger for fresh snapshot | On-demand | Yes (wait for response) |
| `/tmp/contextify-diag-response.json` | Fresh snapshot (JSON) | On request | Yes |
| `/tmp/contextify-diag-report.txt` | Fresh snapshot (human) | On request | Yes |

## Use Cases

### 1. Quick Health Check

**Scenario:** Check if timeline is stalled

```bash
# Read cached state (fast)
STALLED=$(cat /tmp/contextify-state.json | jq -r '.hooverState.isStalled')
if [ "$STALLED" = "true" ]; then
  echo "⚠️ Timeline is stalled!"
  cat /tmp/contextify-state.json | jq '.hooverState'
fi
```

### 2. Debug Missing Messages

**Scenario:** User reports message not appearing in timeline

```bash
# Request fresh diagnostics
./scripts/read_timeline_state.sh --report

# Check specific issues
./scripts/read_timeline_state.sh --request | jq '.issues[] | select(.severity == "critical")'
```

### 3. Monitor During Development

**Scenario:** Watch for issues while developing

```bash
# Continuous monitoring
while true; do
  ISSUES=$(cat /tmp/contextify-state.json 2>/dev/null | jq -r '.issues | length')
  echo "$(date +%H:%M:%S) - Issues: $ISSUES"
  sleep 5
done
```

### 4. Automated Testing

**Scenario:** CI/test verification

```bash
# In test script
./scripts/read_timeline_state.sh --request > /tmp/test-state.json

CRITICAL=$(jq -r '.issues[] | select(.severity == "critical") | .message' /tmp/test-state.json)
if [ -n "$CRITICAL" ]; then
  echo "❌ Critical issues found:"
  echo "$CRITICAL"
  exit 1
fi
```

## JSON Structure

```json
{
  "timestamp": "2025-11-04T18:30:00Z",
  "projectState": {
    "projectId": "project-uuid",
    "projectPath": "/Users/rob/code/projects/contextify",
    "isMonitoring": true,
    "orchestratorExists": true
  },
  "hooverState": {
    "transcriptId": "transcript-uuid",
    "lastProcessedLine": 715,
    "fileSizeBytes": 2739766,
    "lastUpdated": "2025-11-04T17:14:27Z",
    "bytesUnprocessed": 0,
    "linesUnprocessed": 0,
    "isStalled": false,
    "stallDurationSeconds": null
  },
  "watcherState": {
    "transcriptId": "transcript-uuid",
    "isWatching": true,
    "fileExists": true,
    "lastModified": "2025-11-04T18:29:45Z",
    "debounceValue": 0.15
  },
  "timelineState": {
    "entryCount": 150,
    "visibleEntryCount": 25,
    "lastUpdate": "2025-11-04T18:29:50Z",
    "isProcessing": false,
    "lastError": null,
    "cursorExists": true
  },
  "fileState": {
    "path": "~/.claude/projects/.../session.jsonl",
    "exists": true,
    "sizeBytes": 2739766,
    "lineCount": 715,
    "lastModified": "2025-11-04T18:29:45Z",
    "lastContentTimestamp": "2025-11-04T18:29:43Z"
  },
  "issues": [
    {
      "severity": "high",
      "category": "databaseLag",
      "message": "Database is 5 lines behind file",
      "recommendation": "Check if watcher is running and hoover engine is healthy"
    }
  ]
}
```

## Common jq Queries

```bash
# Check if monitoring is active
jq -r '.projectState.isMonitoring' /tmp/contextify-state.json

# Get hoover lag
jq -r '.hooverState.linesUnprocessed' /tmp/contextify-state.json

# List all critical issues
jq -r '.issues[] | select(.severity == "critical") | .message' /tmp/contextify-state.json

# Get last timeline update time
jq -r '.timelineState.lastUpdate' /tmp/contextify-state.json

# Check watcher status
jq -r '.watcherState.isWatching' /tmp/contextify-state.json

# Get timeline entry count
jq -r '.timelineState.entryCount' /tmp/contextify-state.json

# Full issue details
jq '.issues' /tmp/contextify-state.json
```

## Performance

| Operation | Latency | I/O | Notes |
|-----------|---------|-----|-------|
| Read cached state | <1ms | 1 read | Instant, uses cached data |
| Request fresh snapshot | ~50-100ms | 1 write + 1 read | Waits for app response |
| Periodic export | N/A | 1 write every 10s | Background, no impact |

## Troubleshooting

### No state file exists

**Symptom:** `/tmp/contextify-state.json` not found

**Causes:**
1. App not running
2. Monitoring not started
3. Diagnostics API not initialized

**Check:**
```bash
pgrep -x Contextify  # Is app running?
ps aux | grep Contextify  # Check process details
```

### State file is stale

**Symptom:** State file hasn't been updated in >15 seconds

**Causes:**
1. App frozen/crashed
2. Diagnostics exporter stopped
3. File system issue

**Check:**
```bash
# Check file age
stat -f %Sm -t "%Y-%m-%d %H:%M:%S" /tmp/contextify-state.json

# Request fresh snapshot (will timeout if app dead)
./scripts/read_timeline_state.sh --request
```

### Request times out

**Symptom:** `--request` mode waits 5s then fails

**Causes:**
1. App not processing requests
2. Diagnostics capture failed
3. File permissions issue

**Check:**
```bash
# Check app logs
log show --predicate 'subsystem == "dev.contextify" AND category == "DiagnosticsExporter"' --last 1m

# Verify trigger file was created
ls -la /tmp/contextify-diag-*
```

## Integration Examples

### Shell Function for Claude Code

Add to your shell profile:

```bash
ctx_diag() {
  local MODE="${1:---state}"
  /Users/rob/code/projects/contextify/scripts/read_timeline_state.sh "$MODE"
}

ctx_issues() {
  ctx_diag --request | jq '.issues'
}

ctx_hoover() {
  ctx_diag --state | jq '.hooverState'
}
```

Usage:
```bash
ctx_diag --report
ctx_issues
ctx_hoover
```

### Python Script

```python
import json
import subprocess
import time

def get_timeline_state(fresh=False):
    """Get timeline diagnostics state"""
    if fresh:
        # Request fresh snapshot
        subprocess.run(['touch', '/tmp/contextify-diag-request'])
        time.sleep(0.5)

        with open('/tmp/contextify-diag-response.json') as f:
            return json.load(f)
    else:
        # Read cached state
        with open('/tmp/contextify-state.json') as f:
            return json.load(f)

def check_critical_issues():
    """Check for critical issues"""
    state = get_timeline_state(fresh=True)
    critical = [i for i in state['issues'] if i['severity'] == 'critical']

    if critical:
        print(f"⚠️ {len(critical)} critical issues found:")
        for issue in critical:
            print(f"  - {issue['message']}")
        return True

    return False

if __name__ == '__main__':
    check_critical_issues()
```

## Security Considerations

- Files written to `/tmp` are world-readable
- Do NOT include sensitive data in diagnostics
- Paths are included (acceptable for local dev)
- User content is NOT included (only metadata)

## Related

- **Internal API:** `ConversationMonitor.captureDiagnostics()`
- **Service:** `TimelineDiagnosticsService`
- **Exporter:** `DiagnosticsExporter`
- **Framework Documentation:** `build/docs/guides/timeline-diagnostics.md`

---

**Last Updated:** 2025-11-04
**Status:** Implemented and integrated
