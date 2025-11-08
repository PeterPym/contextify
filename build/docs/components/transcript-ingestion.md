# Transcript Ingestion Pipeline - Technical Reference

**Status:** Production Investigation (2025-10-28)
**Purpose:** Complete flow diagram and root cause analysis for timeline update issues

---

## Executive Summary

Contextify's transcript ingestion pipeline has **three independent systems** for detecting and ingesting new conversation content:

1. **ProjectActivityMonitor** - FSEvents-based global monitoring (real-time)
2. **TranscriptWatcher** - Per-file DispatchSource monitoring (real-time)
3. **Discovery Polling** - Periodic transcript discovery (5-minute intervals)

**Current Issue:** New messages written to transcript files are not appearing in the timeline UI.

**Root Cause:** Event system mismatch - ProjectActivityMonitor emits events via AsyncStream, but ConversationMonitor listens to NotificationCenter. TranscriptWatcher (which uses NotificationCenter) is not being reliably started for active transcripts.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                  Claude Code / Codex CLI                        │
│                  Writes to JSONL files                          │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ├── ~/.claude/projects/[project]/[session].jsonl
                       └── ~/.codex/sessions/[project]/[session].jsonl
                       │
            ┌──────────┴───────────┐
            │ File System Events   │
            └──────────┬───────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
┌──────────────┐ ┌────────────┐ ┌──────────────┐
│ FSEvents     │ │ Dispatch   │ │  Discovery   │
│ (global)     │ │ Source     │ │  Polling     │
│              │ │ (per-file) │ │  (5 min)     │
└──────┬───────┘ └─────┬──────┘ └──────┬───────┘
       │               │               │
       │ Project       │ Transcript    │
       │ Activity      │ Watcher       │
       │ Monitor       │               │
       │               │               │
       │               │               │
       ▼               ▼               ▼
┌──────────────────────────────────────────┐
│       TranscriptOrchestrator             │
│    ┌──────────────────────┐             │
│    │   HooverEngine       │             │
│    │   (streaming JSONL)  │             │
│    └──────────┬───────────┘             │
│               │                          │
│               ▼                          │
│    ┌──────────────────────┐             │
│    │   DatabaseManager    │             │
│    │   (SQLite + GRDB)    │             │
│    └──────────┬───────────┘             │
└───────────────┼──────────────────────────┘
                │
                ▼
┌──────────────────────────────────────────┐
│        SQL Database (WAL mode)           │
│  - projects                              │
│  - transcripts                           │
│  - transcript_entries                    │
│  - timeline_cache                        │
└──────────────┬───────────────────────────┘
               │
               │ (Notifications & Events)
               │
    ┌──────────┼───────────────┐
    │          │               │
    ▼          ▼               ▼
┌────────┐ ┌─────────────┐ ┌──────────┐
│ Status │ │Conversation │ │ Project  │
│ Bar    │ │  Monitor    │ │ Switcher │
│        │ │             │ │          │
└────────┘ └──────┬──────┘ └──────────┘
                  │
                  ▼
┌──────────────────────────────────────────┐
│      ConversationTimelineView (UI)       │
└──────────────────────────────────────────┘
```

---

## Complete Ingestion Flow (Step-by-Step)

### Step 1: File Write
**When:** User sends message → Claude Code responds
**Action:** Claude Code writes new JSON line to transcript file
**Location:** `~/.claude/projects/[mangled-path]/[session-uuid].jsonl`
**Format:** One JSON object per line (JSONL)

**Example:**
```
~/.claude/projects/-Users-rob-code-projects-contextify/d308931c-4c4b-4ad0-843c-846b14151247.jsonl
```

**Verification:**
```bash
wc -l ~/.claude/projects/[path]/[session].jsonl
tail -5 ~/.claude/projects/[path]/[session].jsonl
```

---

### Step 2: File System Detection

#### Option A: FSEvents (ProjectActivityMonitor)
**File:** `app/Sources/ContextifyCore/ProjectActivityMonitor.swift`
**Trigger:** FSEvents detects change in `.claude/projects` or `.codex/sessions`
**Latency:** ~500ms
**Conditional:** Requires `ConsentManager.shared.isMultiProjectModeEnabled = true` (defaults to true)

**Flow:**
1. FSEventsMonitor detects change (line 252-337)
2. Maps path → project ID (line 298-307)
3. Calls `orchestrator.discoverTranscript(..., startWatching: true)` (line 319-326)
4. **After hoover completes**, emits `ProjectEvent.transcriptUpdated` (line 328)
5. Event flows via AsyncStream to StatusBarViewModel and ProjectSwitcherState

**Key Code:**
```swift
// ProjectActivityMonitor.swift:328
await self.emitEvent(ProjectEvent(projectId: projectId, kind: .transcriptUpdated))
```

**Listeners:**
- StatusBarViewModel (line 208) - shows "Updated: contextify"
- ProjectSwitcherState (line 116) - updates unread counts
- **NOT ConversationMonitor** (uses NotificationCenter, not AsyncStream)

#### Option B: DispatchSource (TranscriptWatcher)
**File:** `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`
**Trigger:** DispatchSource file watcher detects `.write` or `.extend` events
**Latency:** ~150ms (debounced)
**Conditional:** Must be explicitly started via `orchestrator.startWatchingTranscript()`

**Flow:**
1. DispatchSource fires event (line 74-89)
2. Debounce timer (150ms) (line 122-126)
3. Process file change on background queue (line 130-166)
4. Run hoover engine (line 146)
5. **Post NotificationCenter notification** (line 154-159)

**Key Code:**
```swift
// TranscriptWatcher.swift:154-159
NotificationCenter.default.post(
  name: NSNotification.Name("TranscriptUpdated"),
  object: transcriptId,
  userInfo: ["projectId": transcript.projectId]
)
```

**Listeners:**
- ConversationMonitor (line 304) - triggers timeline refresh

#### Option C: Discovery Polling
**File:** `Contextify/Contextify/ConversationMonitor.swift:902-1034`
**Trigger:** Timer-based loop every 5 minutes
**Latency:** Up to 5 minutes

**Flow:**
1. Timer fires (line 215)
2. Scan `.claude/projects/[project]` directory (line 929-946)
3. Call `orchestrator.upsertTranscripts()` (line 959)
4. Start watchers for all transcripts (line 992-997)
5. Load feed from SQL (line 1032)

---

### Step 3: Hoover Ingestion

**File:** `app/Sources/ContextifyCore/Database/HooverEngine.swift:180-387`
**Purpose:** Stream JSONL file, parse entries, insert to database

**Algorithm:**
1. Load transcript checkpoint from DB (`last_processed_line`, `last_processed_entry_id`)
2. Seek to resume point in file (line 238-254)
3. Read in 64KB chunks (line 257-321)
4. Parse each line via `TranscriptLineParser` (line 274-290)
5. Batch insert 1000 entries at a time (line 305-319)
6. Update checkpoint after each batch (line 533-553)
7. Compute window SHA256 for cache keys (line 405-412)
8. Handle FK constraints gracefully (line 416-425)

**Checkpoint Format (transcripts table):**
```sql
last_processed_line: INT       -- Line number resume point
last_processed_entry_id: TEXT  -- UUID of last entry (for window tracking)
line_count: INT                -- Total lines in file
parser_version: INT            -- Parser compatibility version
status: TEXT                   -- 'active' | 'unavailable' | 'error'
```

**Error Handling:**
- Parse errors logged to `parse_errors` table (line 503-520)
- FK constraint violations skipped (line 416-425)
- Bad UTF-8 lines logged (line 267-269, 361)
- Processing continues after errors (isolation)

**Performance:**
- Memory: O(batch_size) ~1MB for 1000 entries
- Throughput: ~5000 lines/second (measured on M3, 50K test set)

---

### Step 4: Database Write

**Tables Updated:**
1. `transcript_entries` - canonical conversation data
2. `transcripts` - checkpoint update
3. `parse_errors` - any failed lines
4. `file_snapshots`, `tracked_files`, `transcript_summaries`, `system_events`, `assistant_usage` (v7 metadata)

**Schema:**
```sql
CREATE TABLE transcript_entries (
  id TEXT PRIMARY KEY,
  transcript_id TEXT NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
  project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  session_id TEXT,
  kind TEXT NOT NULL,  -- 'user' | 'assistant' | 'system'
  timestamp INTEGER NOT NULL,
  content TEXT NOT NULL,
  content_sha256 TEXT NOT NULL,
  display_in_timeline INTEGER NOT NULL DEFAULT 1,
  prev1_id TEXT REFERENCES transcript_entries(id) ON DELETE SET NULL,
  prev2_id TEXT REFERENCES transcript_entries(id) ON DELETE SET NULL,
  window_sha256 TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

**Indexes:**
```sql
-- Covering index for fast feed loading
CREATE INDEX idx_entries_feed_cover ON transcript_entries(
  project_id,
  timestamp,
  created_at,
  id,
  content_sha256,
  window_sha256,
  kind,
  session_id
) WHERE display_in_timeline = 1;
```

**Query Performance:**
- Feed load (50 entries): ~3ms (p95)
- Batch insert (1000 entries): ~35ms (p95)

---

### Step 5: Event Emission

#### ProjectActivityMonitor Events
**File:** `app/Sources/ContextifyCore/ProjectActivityMonitor.swift:168-171`
**Emission Point:** After hoover completes (line 328)
**Transport:** AsyncStream
**Event Type:** `ProjectEvent.transcriptUpdated`

**Flow:**
```swift
// ProjectActivityMonitor.swift:328
await self.emitEvent(ProjectEvent(projectId: projectId, kind: .transcriptUpdated))
```

**Observers:**
```swift
// StatusBarViewModel.swift:208
for await event in await monitor.observeProjectEvents() {
  await self.handleHooverEvent(event)
}

// ProjectSwitcherState.swift:116
for await event in await monitor.observeProjectEvents() {
  await self.handle(event)
}
```

#### TranscriptWatcher Notifications
**File:** `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift:154-159`
**Emission Point:** After hoover completes (in processFileChange)
**Transport:** NotificationCenter
**Notification Name:** `"TranscriptUpdated"`

**Flow:**
```swift
// TranscriptWatcher.swift:154-159
NotificationCenter.default.post(
  name: NSNotification.Name("TranscriptUpdated"),
  object: transcriptId,
  userInfo: ["projectId": transcript.projectId]
)
```

**Observers:**
```swift
// ConversationMonitor.swift:304
for await note in center.notifications(named: "TranscriptUpdated") {
  // Debounce and refresh timeline
}
```

---

### Step 6: State Update (ConversationMonitor)

**File:** `Contextify/Contextify/ConversationMonitor.swift`
**Role:** UI-facing singleton for timeline state

**Update Flow:**
1. Receive notification (line 304-337)
2. Branch on projectId match (line 316-331)
3. Cancel existing debounce task (line 319)
4. Wait 150ms (debounce) (line 321)
5. Call `processIncrementalUpdate()` (line 327)
6. Query new entries from SQL (line 255-260)
7. Deduplicate with seenEntryIDs (line 274)
8. Append to TimelineState (line 279)
9. Sort chronologically (line 284)
10. Queue cache misses for LLM (line 290)

**Keyset Cursor (Incremental Updates):**
```swift
// ConversationMonitor.swift:236-271
private var lastSeenCursor: (timestamp: Int, createdAt: Int, id: String)?

// Query entries after cursor (efficient pagination)
let newEntries = try? orchestrator.getEntriesAfter(
  cursor: lastSeenCursor,
  limit: 100
)
```

**Cache Invalidation:**
```swift
// TimelineState.swift:31-44
func replace(with entries: [TimelineEntry]) {
  self.entries = entries
  revision &+= 1  // SwiftUI invalidation trigger
  rebuildCacheIndex()
}
```

---

### Step 7: UI Rendering

**File:** `Contextify/Contextify/ConversationTimelineView.swift`
**Pattern:** @Observable + SwiftUI diffing

**Flow:**
1. ConversationMonitor.state.revision increments
2. SwiftUI detects change via @Observable
3. `visibleEntries` recomputes (cached by revision)
4. List re-renders with new entries
5. TimelineEntryRow views created for new items

**Performance:**
- Observable overhead: <1ms
- visibleEntries (cached): <1ms
- visibleEntries (miss): ~2ms (filter 1000 entries)
- List diffing: Handled by SwiftUI (lazy rendering)

---

## Component Reference

### Key Files

| Component | File | Lines | Role |
|-----------|------|-------|------|
| **ProjectActivityMonitor** | `app/Sources/ContextifyCore/ProjectActivityMonitor.swift` | 1-339 | FSEvents global monitoring |
| **TranscriptWatcher** | `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift` | 1-168 | Per-file DispatchSource monitoring |
| **HooverEngine** | `app/Sources/ContextifyCore/Database/HooverEngine.swift` | 1-579 | Streaming JSONL parser & DB ingestor |
| **ConversationMonitor** | `Contextify/Contextify/ConversationMonitor.swift` | 1-1060 | Timeline state & event orchestration |
| **TimelineState** | `Contextify/Contextify/ConversationMonitor.swift` | 8-72 | Single source of truth for entries |
| **StatusBarViewModel** | `Contextify/Contextify/StatusBarViewModel.swift` | 1-257 | Hoover status UI (observes AsyncStream) |
| **ProjectSwitcherState** | `Contextify/Contextify/ProjectSwitcherState.swift` | 1-400 | Project list & unread counts |

### Notification & Event Summary

| System | Type | Name/Event | Emitter | Listeners |
|--------|------|------------|---------|-----------|
| ProjectActivityMonitor | AsyncStream | `ProjectEvent.transcriptUpdated` | ProjectActivityMonitor:328 | StatusBarViewModel:208, ProjectSwitcherState:116 |
| TranscriptWatcher | NotificationCenter | `"TranscriptUpdated"` | TranscriptWatcher:154 | ConversationMonitor:304 |
| ConversationMonitor | NotificationCenter | `".timelineCacheUpdated"` | TimelineCacheMissGenerator | ConversationMonitor:432 |
| HUDViewModel | NotificationCenter | `".projectRootDidChange"` | HUDViewModel | ConversationMonitor:238 |

---

## Root Cause Analysis (2025-10-28)

### Issue Summary
New messages written to transcript files are not appearing in the timeline. Database shows 690 lines processed, but file has 709 lines (19 missing).

### Investigation Findings

#### 1. Database State
```sql
-- Transcript checkpoint
SELECT last_processed_line, line_count FROM transcripts
WHERE id = '95865248-1770-427D-97F7-737BAB2DC61F';
-- Result: 690 | 690

-- Actual file
wc -l ~/.claude/projects/-Users-rob-code-projects-contextify/d308931c-4c4b-4ad0-843c-846b14151247.jsonl
-- Result: 709 lines

-- Database entries
SELECT COUNT(*) FROM transcript_entries
WHERE transcript_id = '95865248-1770-427D-97F7-737BAB2DC61F';
-- Result: 146 entries
```

**Conclusion:** 19 lines (691-709) not ingested, including test message at line 704.

#### 2. Event System Mismatch

**The Critical Bug:**

ConversationMonitor listens to **NotificationCenter** for `"TranscriptUpdated"`:
```swift
// ConversationMonitor.swift:304
for await note in center.notifications(named: NSNotification.Name("TranscriptUpdated")) {
  // Handle update
}
```

ProjectActivityMonitor emits events via **AsyncStream**:
```swift
// ProjectActivityMonitor.swift:328
await self.emitEvent(ProjectEvent(projectId: projectId, kind: .transcriptUpdated))
```

**These two systems are NOT connected!**

StatusBarViewModel observes ProjectActivityMonitor events (AsyncStream), so it would see hoover activity.
ConversationMonitor observes TranscriptWatcher notifications (NotificationCenter), so it only updates if TranscriptWatcher runs.

#### 3. TranscriptWatcher Lifecycle

TranscriptWatcher is started via:
```swift
// ConversationMonitor.swift:996
try orchestrator.startWatchingTranscript(transcriptId: tr.transcriptId, fileURL: tr.fileURL)
```

This is called from `discoverNewTranscripts()` which runs:
1. At startup (once)
2. Every 5 minutes (polling)

**Issue:** Between discovery runs, if a watcher dies or is never started, file changes are not detected.

#### 4. ProjectActivityMonitor FSEvents

FSEvents monitoring is started if:
```swift
// ProjectSwitcherState.swift:101-108
if ConsentManager.shared.isMultiProjectModeEnabled {
  try await monitor.startGlobalMonitoring()
}
```

Consent defaults to `true` (auto opt-in), so FSEvents **should** be running.

But ProjectActivityMonitor events flow to StatusBarViewModel and ProjectSwitcherState, **not ConversationMonitor**.

### Root Cause

**Primary Issue:** Event system architecture mismatch
- ProjectActivityMonitor uses AsyncStream
- TranscriptWatcher uses NotificationCenter
- ConversationMonitor only listens to NotificationCenter
- If TranscriptWatcher is not running for a transcript, ConversationMonitor never receives updates

**Secondary Issue:** TranscriptWatcher reliability
- Started during discovery (every 5 minutes)
- No guarantee watchers persist between discovery runs
- If watcher crashes or is never started, timeline doesn't update until next discovery

**Tertiary Issue:** No fallback mechanism
- If both watchers fail, only option is manual refresh or 5-minute poll
- No health check or recovery for failed watchers

---

## Debugging Checklist

### Stage 1: File Write
- [ ] Verify transcript file exists: `ls ~/.claude/projects/[path]/[session].jsonl`
- [ ] Count lines: `wc -l [file]`
- [ ] Check last entries: `tail -5 [file] | jq -r '.timestamp'`
- [ ] Verify file permissions: `ls -la [file]`

### Stage 2: File System Detection
- [ ] Check FSEvents monitoring: `log stream --predicate 'subsystem == "dev.contextify" AND category == "ProjectActivity"' --level info`
- [ ] Check TranscriptWatcher: `log stream --predicate 'subsystem == "dev.contextify" AND category == "TranscriptWatcher"' --level info`
- [ ] Verify consent: `defaults read dev.contextify dev.contextify.multiProjectMode.enabled`
- [ ] Check app is running: `ps aux | grep Contextify | grep -v grep`

### Stage 3: Hoover Ingestion
- [ ] Check hoover logs: `log stream --predicate 'subsystem == "dev.contextify" AND category == "HooverEngine"' --level info`
- [ ] Verify checkpoint: `sqlite3 [db] "SELECT last_processed_line, line_count FROM transcripts WHERE id = '[id]';"`
- [ ] Check for parse errors: `sqlite3 [db] "SELECT * FROM parse_errors WHERE transcript_id = '[id]' ORDER BY created_at DESC LIMIT 10;"`

### Stage 4: Database Write
- [ ] Count entries: `sqlite3 [db] "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id = '[id]';"`
- [ ] Check latest entry: `sqlite3 [db] "SELECT timestamp, kind, content FROM transcript_entries WHERE transcript_id = '[id]' ORDER BY timestamp DESC LIMIT 1;"`
- [ ] Verify FK constraints: `sqlite3 [db] "PRAGMA foreign_key_check;"`

### Stage 5: Event Emission
- [ ] Check ProjectActivityMonitor events: `log stream --predicate 'category == "ProjectActivity"' --level info | grep "emitted"`
- [ ] Check NotificationCenter posts: `log stream --predicate 'category == "TranscriptWatcher"' --level info | grep "TranscriptUpdated"`

### Stage 6: State Update
- [ ] Check ConversationMonitor logs: `log stream --predicate 'category == "Timeline"' --level info`
- [ ] Verify debounce task: Look for "Debounce complete - calling processIncrementalUpdate"
- [ ] Check incremental update: Look for "processIncrementalUpdate" logs

### Stage 7: UI Rendering
- [ ] Check SwiftUI invalidation (no direct logs - use Instruments)
- [ ] Verify timeline entries: Count rows in ConversationTimelineView
- [ ] Check for UI errors: Look for SwiftUI warnings in console

---

## Common Failure Scenarios

### Scenario 1: Watchers Not Started
**Symptoms:**
- New messages not appearing for hours
- Status bar shows no hoover activity
- Last update timestamp frozen

**Diagnosis:**
```bash
# Check if TranscriptWatcher is posting notifications
log stream --predicate 'subsystem == "dev.contextify" AND category == "TranscriptWatcher"' --level info

# Should see:
# "Started watching transcript: [id]"
# "Processing file change for transcript: [id]"
# "Streamed new content for transcript: [id]"
```

**Root Cause:** Discovery loop hasn't run yet, or watchers crashed

**Fix:** Trigger manual discovery or wait up to 5 minutes

### Scenario 2: Event System Mismatch
**Symptoms:**
- Status bar shows "Updated: contextify" (hoover ran)
- Timeline doesn't update (ConversationMonitor didn't receive event)
- Database has new entries but UI is stale

**Diagnosis:**
```bash
# Check if hoover ran (ProjectActivityMonitor)
log stream --predicate 'category == "ProjectActivity"' --level info | grep "transcriptUpdated"

# Check if ConversationMonitor received notification
log stream --predicate 'category == "Timeline"' --level info | grep "TranscriptUpdated"
```

**Root Cause:** ProjectActivityMonitor emits AsyncStream events, ConversationMonitor listens to NotificationCenter

**Fix:** Bridge the two systems - make ProjectActivityMonitor also post to NotificationCenter, OR make ConversationMonitor subscribe to ProjectActivityMonitor's AsyncStream

### Scenario 3: Checkpoint Stuck
**Symptoms:**
- File has more lines than `last_processed_line`
- Hoover runs but doesn't advance checkpoint
- Same entries re-processed repeatedly

**Diagnosis:**
```bash
# Compare file lines vs checkpoint
wc -l [transcript file]
sqlite3 [db] "SELECT last_processed_line, line_count FROM transcripts WHERE file_path = '[path]';"
```

**Root Cause:** Hoover crash mid-batch, or parse errors blocking progress

**Fix:** Re-ingest transcript: `./scripts/db_manager.sh reingest [transcript-id]`

### Scenario 4: FK Constraint Violations
**Symptoms:**
- Hoover logs show "Entry insert failed"
- Missing entries in database
- Parse errors table has FK violation errors

**Diagnosis:**
```bash
# Check for FK errors
log stream --predicate 'category == "HooverEngine"' --level error | grep "Entry insert failed"
```

**Root Cause:** Out-of-order entries (child references parent that doesn't exist yet)

**Fix:** HooverEngine handles this (sets parent_id to NULL), but may indicate data corruption

---

## Recommended Fixes

### Fix #1: Bridge Event Systems (HIGH PRIORITY)
**Problem:** ProjectActivityMonitor and ConversationMonitor use different event mechanisms

**Solution A: Make ProjectActivityMonitor post to NotificationCenter**
```swift
// ProjectActivityMonitor.swift:328
private func emitEvent(_ event: ProjectEvent) {
  eventStream.continuation.yield(event)

  // NEW: Also post to NotificationCenter for ConversationMonitor
  DispatchQueue.main.async {
    NotificationCenter.default.post(
      name: NSNotification.Name("TranscriptUpdated"),
      object: nil,  // or event.projectId
      userInfo: ["projectId": event.projectId]
    )
  }
}
```

**Solution B: Make ConversationMonitor subscribe to ProjectActivityMonitor**
```swift
// ConversationMonitor.swift:startMonitoring()
// Subscribe to ProjectActivityMonitor events
if let monitor = await ProjectSwitcherState.shared.activityMonitor {
  Task {
    for await event in await monitor.observeProjectEvents() {
      guard case .transcriptUpdated = event.kind else { continue }
      await MainActor.run {
        // Trigger refresh (same as NotificationCenter path)
        self.debounceTask?.cancel()
        self.debounceTask = Task {
          try? await Task.sleep(nanoseconds: 150_000_000)
          await self.processIncrementalUpdate()
        }
      }
    }
  }
}
```

### Fix #2: Ensure TranscriptWatcher Starts at App Launch
**Problem:** TranscriptWatcher only started during discovery (every 5 minutes)

**Solution:**
```swift
// ConversationMonitor.swift:startMonitoring()
// After loading initial feed, start watchers for all known transcripts
Task { [weak self] in
  guard let self else { return }
  let projectId = self.currentProjectId!
  let transcripts = try? self.orchestrator.getTranscripts(forProject: projectId)

  for transcript in transcripts ?? [] {
    let fileURL = URL(fileURLWithPath: transcript.filePath)
    try? self.orchestrator.startWatchingTranscript(
      transcriptId: transcript.id,
      fileURL: fileURL
    )
  }

  log.info("Started watchers for \(transcripts?.count ?? 0) transcripts at app launch")
}
```

### Fix #3: Add Watcher Health Checks
**Problem:** No visibility into watcher failures

**Solution:**
```swift
// TranscriptWatcher.swift
public func getWatchedTranscripts() -> [String] {
  return Array(watchers.keys)
}

// ConversationMonitor.swift
func verifyWatchersHealthy() async {
  let expected = try? orchestrator.getTranscripts(forProject: currentProjectId!)
  let watching = orchestrator.watcher?.getWatchedTranscripts() ?? []

  let missing = expected?.filter { !watching.contains($0.id) } ?? []

  if !missing.isEmpty {
    log.warning("⚠️ Missing watchers for \(missing.count) transcripts - restarting")
    for transcript in missing {
      try? orchestrator.startWatchingTranscript(
        transcriptId: transcript.id,
        fileURL: URL(fileURLWithPath: transcript.filePath)
      )
    }
  }
}
```

### Fix #4: Reduce Discovery Polling Interval (SHORT-TERM WORKAROUND)
**Problem:** 5 minutes is too long for real-time updates

**Solution:**
```swift
// ConversationMonitor.swift:384
try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)  // 30 seconds instead of 5 minutes
```

**Trade-off:** More CPU usage, but better UX until proper fix deployed

---

## Testing Protocol

### Unit Tests
- [ ] HooverEngine: Resume from checkpoint with correct window state
- [ ] TranscriptWatcher: Debounce rapid file changes
- [ ] ProjectActivityMonitor: FSEvents path parsing for both providers
- [ ] ConversationMonitor: Incremental updates with keyset cursor

### Integration Tests
- [ ] End-to-end: Write to JSONL → appears in timeline (< 1 second)
- [ ] Multi-project: Updates to background project increment unread badge
- [ ] Session switch: Timeline reloads with correct project entries
- [ ] Watcher crash recovery: Restart watcher after failure

### Manual Testing
1. Start app with existing transcript
2. Send test message via Claude Code: "TEST-[timestamp]"
3. Verify appears in timeline within 2 seconds
4. Check status bar shows "Updated: [project]"
5. Switch to different project and back
6. Verify test message still visible

---

## Performance Targets

| Operation | Target (p95) | Current (measured) | Notes |
|-----------|--------------|-------------------|-------|
| File write → UI | < 2s | Unknown (broken) | Real-time responsiveness |
| Hoover 1000 lines | < 100ms | ~35ms | Batch ingestion |
| Feed load (50 entries) | < 10ms | ~3ms | Timeline initial load |
| Incremental update (100 entries) | < 20ms | ~10ms | Background refresh |
| Cache miss generation (1 entry) | < 500ms | ~200ms | LLM on-device |

---

## Related Documentation

- **SQL Backend:** `build/docs/architecture/sql-backend.md`
- **Conversation Monitor State:** `build/docs/architecture/conversation-monitor-state.md`
- **LLM Processing:** `build/docs/architecture/llm-processing.md`
- **Transcript Format:** `build/docs/archive/completed-work/technical-briefing-local-history-claude-code-codex.md`
- **Logging Guidelines:** `build/docs/guides/logging-best-practices.md`

---

## Appendix A: Log Messages by Stage

### Stage 1: File Write
No Contextify logs (external to app)

### Stage 2: File System Detection
```
ProjectActivity: FSEvents: path=/Users/rob/.claude/projects/.../session.jsonl
ProjectActivity: projectId=... sessionId=...
TranscriptWatcher: Started watching transcript: [id]
TranscriptWatcher: Processing file change for transcript: [id]
```

### Stage 3: Hoover Ingestion
```
HooverEngine: Hoovered transcript [id]: 709 lines in 125ms (5672/s)
HooverEngine: Staged usage for entry [id] (entry not yet present)
```

### Stage 4: Database Write
No specific logs (implicit in hoover completion)

### Stage 5: Event Emission
```
ProjectActivity: emitted transcriptUpdated project=[id]
TranscriptWatcher: Streamed new content for transcript: [id]
```

### Stage 6: State Update
```
Timeline: 📬 TranscriptUpdated notification: projectId=[id]
Timeline: 📬 Matches current project - scheduling debounced refresh
Timeline: 📬 Debounce complete - calling processIncrementalUpdate
```

### Stage 7: UI Rendering
No specific logs (SwiftUI internal)

---

**Document Version:** 1.0
**Last Updated:** 2025-10-28
**Author:** Investigation based on code audit + diagnostics
**Status:** Draft - pending implementation of fixes
