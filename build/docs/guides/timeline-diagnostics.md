# Timeline Diagnostics Framework

**Created:** 2025-11-04
**Purpose:** Automated diagnosis and recovery for timeline update failures
**Status:** Implemented and integrated

## Overview

The Timeline Diagnostics Framework provides comprehensive, automated debugging capabilities for the timeline ingestion pipeline without requiring human intervention. It captures complete system state, identifies issues, and automatically attempts recovery.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   ConversationMonitor                        │
│                                                              │
│  ┌────────────────────┐      ┌──────────────────────────┐  │
│  │ Health Monitoring  │──┬──▶│  TimelineDiagnostics     │  │
│  │ (30s interval)     │  │   │  Service                 │  │
│  └────────────────────┘  │   └──────────────────────────┘  │
│                          │                                  │
│  ┌────────────────────┐  │   ┌──────────────────────────┐  │
│  │ Fallback Polling   │──┤   │  Auto-Recovery           │  │
│  │ (10s interval)     │  │   │  - Watcher resurrection  │  │
│  └────────────────────┘  │   │  - Manual hoover trigger │  │
│                          │   └──────────────────────────┘  │
│  ┌────────────────────┐  │                                  │
│  │ Public Diagnostic  │──┘                                  │
│  │ API                │                                     │
│  └────────────────────┘                                     │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. TimelineDiagnosticsService

**Location:** `app/Sources/ContextifyCore/Diagnostics/TimelineDiagnostics.swift`

**Purpose:** Captures complete system state for debugging

**Key Capabilities:**
- Project state (ID, path, monitoring status)
- Hoover state (processed lines, file size, lag)
- Watcher state (active, file exists, last modified)
- Timeline UI state (entry counts, last update, errors)
- File state (actual size, line count, last timestamp)
- Issue detection with severity levels (Critical, High, Medium, Info)

**Usage:**
```swift
// In ConversationMonitor or any component with access to orchestrator
let snapshot = await ConversationMonitor.shared.captureDiagnostics()
print(snapshot?.report() ?? "No diagnostics available")
```

### 2. Health Monitoring Loop

**Runs:** Every 30 seconds
**Location:** `ConversationMonitor.runHealthMonitoring()`

**Behavior:**
1. Captures diagnostic snapshot
2. Logs heartbeat (debug level)
3. Detects critical issues
4. Triggers auto-recovery for:
   - Stalled watchers
   - Stalled hoover (no update in 60s+ with pending content)

**Logging:**
```
🏥 Health monitoring started
🏥 Health check: 2 issues
🏥 Critical issue detected: Hoover stalled for 127s with 33 unprocessed lines
🔧 Attempting manual hoover for stalled transcript: 85ac4e3e-a697...
```

### 3. Fallback Polling

**Runs:** Every 10 seconds
**Location:** `ConversationMonitor.runFallbackPolling()`

**Purpose:** Safety net when FSEvents fails

**Behavior:**
1. Gets all transcripts for current project
2. Checks file modification time vs last DB update
3. If file modified recently but DB not updated in 60s, manually triggers hoover

**Use Case:**
- FSEvents not firing (rare macOS issue)
- File system monitoring paused/crashed
- High-load scenarios where events get dropped

### 4. Auto-Recovery Mechanisms

#### Watcher Resurrection
```swift
private func attemptWatcherRecovery(projectId:orchestrator:)
```
- Checks all transcripts for missing watchers
- Restarts watchers via `startWatchingTranscript()`
- Idempotent (skips if already watching)

#### Hoover Recovery
```swift
private func attemptHooverRecovery(projectId:orchestrator:)
```
- Finds transcripts with unprocessed content
- Manually triggers `orchestrator.manualHoover()`
- Bypasses watcher to force ingestion

### 5. Public Diagnostic API

```swift
@MainActor
public func captureDiagnostics() async -> TimelineDiagnosticsSnapshot?
```

**Returns:** Complete diagnostic snapshot with:
- All system state
- List of detected issues with severity
- Recommendations for each issue
- Human-readable report

**Example Output:**
```
=== TIMELINE DIAGNOSTICS SNAPSHOT ===
Timestamp: 2025-11-04 17:20:00

PROJECT STATE:
  ID: contextify-project-123
  Path: /Users/rob/code/projects/contextify
  Monitoring: ✅
  Orchestrator: ✅

HOOVER STATE:
  Transcript: 85ac4e3e-a697...
  Last Processed Line: 682
  File Size: 2739766 bytes
  Unprocessed: 8600 bytes (33 lines)
  Last Updated: 2025-11-04 17:14:15
  Stalled: ❌ YES
  Stall Duration: 127s

WATCHER STATE:
  Transcript: 85ac4e3e-a697...
  Watching: ❌
  File Exists: ✅
  Last Modified: 2025-11-04 17:14:27
  Debounce: 0.15s

FILE STATE:
  Path: ~/.claude/projects/.../85ac4e3e-a697...jsonl
  Exists: ✅
  Size: 2739766 bytes (715 lines)
  Last Modified: 2025-11-04 17:14:27
  Last Content Timestamp: 2025-11-04T17:14:27.922Z

TIMELINE UI STATE:
  Entries: 129 (visible: 25)
  Last Update: 2025-11-04 17:14:15
  Processing: ✅
  Cursor: ✅

ISSUES DETECTED:
  1. 🔴 [CRITICAL] hooverStall
     Hoover stalled for 127s with 33 unprocessed lines
     → Check watcher status and trigger manual hoover if needed

  2. 🔴 [CRITICAL] watcherMissing
     Watcher not running for transcript 85ac4e3e-a697...
     → Call startWatchingTranscript() to resume monitoring

  3. 🟠 [HIGH] databaseLag
     Database is 33 lines behind file
     → Check if watcher is running and hoover engine is healthy

=== END DIAGNOSTICS ===
```

## Issue Categories

| Category | Severity | Meaning | Auto-Recovery |
|----------|----------|---------|---------------|
| `hooverStall` | Critical | No DB update in 60s+ with pending content | ✅ Manual hoover |
| `watcherMissing` | Critical | Watcher not running for active transcript | ✅ Restart watcher |
| `fileSystemIssue` | High | Transcript file missing or inaccessible | ❌ Manual fix needed |
| `databaseLag` | High | 10+ lines unprocessed | ⚠️ If watcher missing |
| `uiState` | High | Timeline UI stale (120s+ old) | ❌ Informational |
| `initialization` | Critical | Orchestrator or project not initialized | ❌ Restart needed |

## Usage Scenarios

### Scenario 1: Timeline Not Updating

**Symptoms:** Recent messages not appearing in timeline

**Automated Response:**
1. Health monitoring detects stall after 60s
2. Captures diagnostic snapshot
3. Identifies critical issues (hoover stall, watcher missing)
4. Auto-recovery attempts:
   - Restart watcher → `startWatchingTranscript()`
   - Force hoover → `manualHoover()`
5. If successful, timeline updates within 10s

**Manual Intervention:** None required (auto-recovery handles it)

### Scenario 2: FSEvents Not Firing

**Symptoms:** File changes not triggering hoover

**Automated Response:**
1. Fallback polling checks every 10s
2. Detects file modified recently but DB stale
3. Manually triggers hoover
4. Timeline updates despite FSEvents failure

**Manual Intervention:** None required

### Scenario 3: On-Demand Diagnosis

**Use Case:** User reports timeline issues, developer needs full state

**Steps:**
```swift
// From any component with access to ConversationMonitor
let snapshot = await ConversationMonitor.shared.captureDiagnostics()

// Print full report
if let snapshot {
    print(snapshot.report())

    // Or access structured data
    for issue in snapshot.issues {
        print("[\(issue.severity)] \(issue.category): \(issue.message)")
        if let rec = issue.recommendation {
            print("  → \(rec)")
        }
    }
}
```

**Output:** Complete state dump for debugging

### Scenario 4: CI/Testing

**Use Case:** Automated tests or CI pipeline

**Integration:**
```swift
// In test setup/teardown
let snapshot = await ConversationMonitor.shared.captureDiagnostics()
XCTAssertEqual(snapshot?.issues.filter { $0.severity == .critical }.count, 0,
               "Critical issues detected: \(snapshot?.report() ?? "unknown")")
```

## Configuration

### Health Monitoring Interval
**Current:** 30 seconds
**Tuning:** Increase for less overhead, decrease for faster recovery

Location: `ConversationMonitor.runHealthMonitoring()`
```swift
try await Task.sleep(for: .seconds(30))  // Adjust here
```

### Fallback Polling Interval
**Current:** 10 seconds
**Tuning:** Increase to reduce I/O, decrease for faster fallback

Location: `ConversationMonitor.runFallbackPolling()`
```swift
try await Task.sleep(for: .seconds(10))  // Adjust here
```

### Stall Threshold
**Current:** 60 seconds
**Meaning:** No DB update in 60s with pending content = stalled

Location: `TimelineDiagnosticsService.captureSnapshot()`
```swift
let isStalled = stallDuration > 60  // Adjust here
```

## Logging

All diagnostic components use OSLog with consistent categories:

| Component | Subsystem | Category | Level |
|-----------|-----------|----------|-------|
| Health monitoring | `dev.contextify` | `Timeline` | Debug (heartbeat), Warning (issues) |
| Auto-recovery | `dev.contextify` | `Timeline` | Info (recovery attempts) |
| Diagnostics service | `dev.contextify` | `TimelineDiagnostics` | Info |
| Fallback polling | `dev.contextify` | `Timeline` | Debug |

**View logs:**
```bash
# Real-time
log stream --predicate 'subsystem == "dev.contextify"' --level debug

# Last 5 minutes
log show --predicate 'subsystem == "dev.contextify" AND category == "Timeline"' --last 5m
```

## Performance Impact

### Health Monitoring
- **Frequency:** 30s
- **Cost per check:** ~10ms (single SQL query + file stat)
- **CPU impact:** Negligible (<0.1%)
- **I/O impact:** Minimal (1 file stat per check)

### Fallback Polling
- **Frequency:** 10s
- **Cost per check:** ~5ms per transcript
- **Typical load:** 1-3 transcripts = 5-15ms
- **CPU impact:** Negligible (<0.2%)

### Auto-Recovery
- **Frequency:** On-demand (triggered by health checks)
- **Cost:** Same as normal hoover + watcher startup
- **Typical:** 50-200ms one-time cost

**Total overhead:** <1% CPU, <20ms every 10s

## Debugging Tips

### Silent Health Monitoring

**Problem:** Health checks running but not visible

**Solution:** Enable debug logging
```bash
# Xcode console filter
TYPE Debug

# Or view in Console.app
Predicate: subsystem == "dev.contextify" AND category == "Timeline"
```

### False Stall Detection

**Problem:** Health check reports stall but file is up to date

**Likely Cause:** Clock skew between file mtime and system time

**Check:**
```bash
# Compare file mtime vs current time
stat -f "%Sm %z" -t "%Y-%m-%d %H:%M:%S" ~/.claude/projects/.../[session].jsonl
date
```

### Recovery Not Working

**Problem:** Auto-recovery runs but timeline still stale

**Check:**
1. Verify orchestrator exists: `snapshot.projectState.orchestratorExists == true`
2. Check file permissions: `ls -la [transcript-file]`
3. Look for hoover errors in logs: `log show --predicate 'category == "HooverEngine"'`

## Future Enhancements

### Planned (Not Yet Implemented)

1. **Log Analysis Tool**
   - Scan macOS unified log for errors
   - Correlate timeline issues with system events
   - Extract relevant error messages

2. **UI Staleness Indicator**
   - Visual badge showing "Last updated: Xm ago"
   - Warning icon if stale > 5 minutes
   - Click to trigger manual refresh

3. **Diagnostic History**
   - Store last N snapshots in memory
   - Track issue frequency over time
   - Identify recurring problems

4. **Remote Diagnostics**
   - Export snapshot as JSON
   - Share with support/developers
   - Privacy-preserving (redacts paths)

## Related Documentation

- **Hoover Engine:** `app/Sources/ContextifyCore/Database/HooverEngine.swift`
- **Transcript Watcher:** `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`
- **Conversation Monitor:** `Contextify/Contextify/ConversationMonitor.swift`
- **Ingestion Pipeline:** `build/docs/components/transcript-ingestion.md`
- **Data Flow:** `build/docs/architecture/data-flow.md`

## API Reference

### TimelineDiagnosticsService

```swift
public actor TimelineDiagnosticsService {
    public init(db: DatabasePool)

    public func captureSnapshot(
        projectId: String?,
        orchestrator: TranscriptOrchestrator?,
        monitorState: MonitorStateSnapshot?
    ) async -> TimelineDiagnosticsSnapshot
}
```

### TimelineDiagnosticsSnapshot

```swift
public struct TimelineDiagnosticsSnapshot: Codable, Sendable {
    public let timestamp: Date
    public let projectState: ProjectState?
    public let hooverState: HooverState
    public let watcherState: WatcherState
    public let timelineState: TimelineUIState?
    public let fileState: FileState?
    public let issues: [DiagnosticIssue]

    public func report() -> String  // Human-readable report
}
```

### ConversationMonitor Additions

```swift
extension ConversationMonitor {
    @MainActor
    public func captureDiagnostics() async -> TimelineDiagnosticsSnapshot?

    // Auto-started during monitoring
    private func runHealthMonitoring(projectId:orchestrator:) async
    private func runFallbackPolling(projectId:orchestrator:) async

    // Recovery methods (called by health monitoring)
    private func attemptWatcherRecovery(projectId:orchestrator:) async
    private func attemptHooverRecovery(projectId:orchestrator:) async
}
```

### TranscriptOrchestrator Additions

```swift
extension TranscriptOrchestrator {
    public func isWatchingTranscript(transcriptId: String) -> Bool

    @discardableResult
    public func manualHoover(transcriptId: String, fileURL: URL) throws -> HooverResult
}
```

## Troubleshooting

### Health Monitoring Not Starting

**Symptom:** No "🏥 Health monitoring started" log

**Possible Causes:**
1. `startMonitoring()` never called
2. Background tasks cancelled early
3. Project not initialized

**Check:**
```swift
print("isMonitoring: \(ConversationMonitor.shared.isMonitoring)")
print("projectId: \(ConversationMonitor.shared.currentProjectId ?? "nil")")
```

### Diagnostics Return Nil

**Symptom:** `captureDiagnostics()` returns `nil`

**Cause:** Diagnostics service not initialized

**Fix:** Ensure `startMonitoring()` completed successfully

### Auto-Recovery Fails

**Symptom:** Recovery attempted but issues persist

**Possible Causes:**
1. File permissions issue
2. Database locked
3. Transcript file corrupted

**Check Logs:**
```bash
log show --predicate 'subsystem == "dev.contextify"' --last 5m | grep "error\|failed\|Error"
```

---

**Last Updated:** 2025-11-04
**Maintained By:** Contextify Core Team
