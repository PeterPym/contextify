# Debugging Workflows Guide

**Status:** Active (2025-11-17)
**Related:** `scripts/logging/README.md`, `build/docs/guides/log-analysis-*.md`
**Purpose:** Decision trees and workflows for diagnosing common issues in Contextify

---

## Key Components and Log Prefixes

**Components:** AppStateOrchestrator state transitions, LightweightDiscoveryService, JIT ingestion
**Log prefixes:** `[ORCH-*]` for orchestrator, `[DISC-LIGHT]` for lightweight discovery, `[INGEST-JIT]` for JIT ingestion

---

## Executive Summary

This document provides **decision trees and workflows** for debugging Contextify issues. Use this when:
- Something isn't working and you don't know where to start
- Choosing between multiple debugging tools
- Investigating user-reported issues
- Performing systematic troubleshooting

**Core Philosophy:** Prefer **automated, self-validating tools** over manual log inspection.

---

## Quick Decision Tree

```
What type of issue are you investigating?
│
├─ 🐛 Feature Not Appearing (UI/Data Missing)
│   └─→ Workflow 1: Pipeline Completeness Check
│
├─ 🐌 Performance/Lag (App Slow, Timeline Delays)
│   └─→ Workflow 2: Performance Investigation
│
├─ 🔄 State Sync Issues (Stale UI, Incorrect Data)
│   └─→ Workflow 3: State Management Debugging
│
├─ 💾 Database Issues (Corruption, Missing Data)
│   └─→ Workflow 4: Database Integrity Check
│
├─ 🔐 Sandbox/Permissions Issues (Access Denied)
│   └─→ Workflow 5: Sandbox Debugging
│
├─ 🧪 Verifying Bug Fix Works
│   └─→ Workflow 6: Automated Test Harness
│
└─ ❓ Unknown Issue (Exploratory)
    └─→ Workflow 7: Interactive Monitoring
```

---

## Workflow 1: Pipeline Completeness Check

### When to Use

**Symptoms:**
- New timeline entry created but doesn't appear in UI
- Project discovered but not showing in project switcher
- Transcript file exists but entries missing from database

**Goal:** Verify all pipeline stages completed successfully (file watch → database write → UI update).

### Automated Approach (Recommended)

**Script:** `monitor-pipeline-check.sh`

```bash
# Run automated pipeline check
./scripts/logging/monitor-pipeline-check.sh

# Exit codes:
# 0 = All pipeline stages detected (PASS)
# 1 = Missing stage activity (FAIL)
```

**Output Example:**

```
=== Pipeline Completeness Check ===
✅ Stage 1: File System Events     (3 events detected)
✅ Stage 2: Database Updates        (2 writes detected)
✅ Stage 3: Timeline Hydration      (1 hydration detected)
✅ Stage 4: UI Optimization         (1 update detected)

RESULT: PASS (All stages active)
```

**If FAIL:**

Script reports which stage failed:

```
❌ Stage 3: Timeline Hydration      (0 hydrations detected)
RESULT: FAIL (Missing: Timeline Hydration)
```

**Next Steps:**

| Missing Stage | Investigation Path |
|---------------|-------------------|
| File System Events | Check `TranscriptWatcher` logs, verify file permissions |
| Database Updates | Check `HooverEngine` logs, verify SQL errors |
| Timeline Hydration | Check `ConversationMonitor` logs, verify project switch |
| UI Optimization | Check main thread blocking, verify SwiftUI updates |

### Manual Approach (Deep Dive)

**Step 1: Capture Full Pipeline Logs**

```bash
# Capture 30 seconds of all subsystems
./scripts/logging/monitor-transcript-queues.sh
```

**Step 2: Analyze Captured Logs**

```bash
# Run pipeline analysis on captured log
./scripts/logging/analyze-pipeline.sh /tmp/transcript-queue-monitor-*.log

# Output shows stage-by-stage activity:
# - [FSEVENTS-*] tags for file watching
# - [DB-UPDATE] tags for database writes
# - [TIMELINE-HYDRATE-*] tags for UI updates
```

**Step 3: Follow the Data**

Use tags to trace data flow:

```bash
# Find file event → database write correlation
grep "\[FSEVENTS-CHANGE\]" /tmp/transcript-queue-monitor-*.log
grep "\[HOOVER-UPDATE-ROWS\]" /tmp/transcript-queue-monitor-*.log

# Check timeline hydration
grep "\[TIMELINE-HYDRATE-" /tmp/transcript-queue-monitor-*.log
```

---

## Workflow 2: Performance Investigation

### When to Use

**Symptoms:**
- App feels sluggish or unresponsive
- Timeline takes >1s to load
- Project switch is slow
- UI freezes or stutters

**Goal:** Identify performance bottlenecks (database queries, main thread blocking, excessive logging).

### Step 1: Capture Logs with Timing Data

```bash
# Capture 45 seconds with performance tags
DURATION=45 ./scripts/logging/monitor-transcript-queues.sh
```

**Key Tags to Look For:**
- `[UIOPT-*]` - UI optimization milestones with durations
- `[TIMELINE-HYDRATE-*]` - Timeline loading times
- `[HOOVER-*]` - Database ingestion times
- `[COORD-*]` - Startup coordinator milestones

### Step 2: Run Gap Analysis

```bash
# Find gaps >1000ms (1 second)
./scripts/logging/analyze-gaps.sh /tmp/transcript-queue-monitor-*.log 1000

# Output shows time gaps between consecutive log lines
```

**Example Output:**

```
Gap Analysis Report
Threshold: 1000ms

Found 3 gaps exceeding threshold:
  12:34:56.123 → 12:34:57.456  (1333ms)  Between: [HOOVER-START] → [HOOVER-DONE]
  12:35:10.000 → 12:35:12.500  (2500ms)  Between: [COORD-DB-START] → [COORD-DB-DONE]
  12:35:20.100 → 12:35:21.200  (1100ms)  Between: [TIMELINE-HYDRATE-START] → [TIMELINE-HYDRATE-DONE]

Top Bottlenecks:
1. Database operations (2500ms)
2. Hoover ingestion (1333ms)
3. Timeline hydration (1100ms)
```

### Step 3: Profile with Instruments (If Needed)

**When:** Gap analysis shows >5s bottleneck, need to drill into code.

```bash
# Open Instruments
open /Applications/Xcode.app/Contents/Applications/Instruments.app

# Record Time Profiler trace
# File → New Trace → Time Profiler
# Record → Reproduce slow operation → Stop

# Filter to "Contextify" in Call Tree
# Sort by Self Time (descending)
# Identify hot functions
```

### Step 4: Check Database Query Performance

Check database query performance via logging (see `scripts/logging/README.md`).

**Slow Query Thresholds:**
- `getRecentFeed` (50 entries): <50ms expected
- `getCachedTimeline` (single entry): <5ms expected
- `hooverTranscript` (1000 rows): <200ms expected

**If queries are slow:**
1. Check database size: `ls -lh ~/Library/Application\ Support/Contextify/contextify.db`
2. Run VACUUM: `sqlite3 contextify.db "VACUUM"`
3. Check index coverage: `EXPLAIN QUERY PLAN SELECT ...`

---

## Workflow 3: State Management Debugging

### When to Use

**Symptoms:**
- UI shows stale data after project switch
- Timeline doesn't update after new entry
- Project switcher shows wrong active project
- Settings changes don't take effect

**Goal:** Verify state synchronization across components (StartupCoordinator → ConversationMonitor → UI).

### Step 1: Verify StartupCoordinator Published Context

```bash
# Filter for coordinator updates
log stream --predicate 'subsystem BEGINSWITH "dev.contextify" AND category == "StartupCoordinator"' \
  --level debug \
  | grep "COORD-PUBLISH"
```

**Expected Output:**

```
[COORD-PUBLISH-START] Publishing context
[COORD-PUBLISH-NOTIF] Notification posted
[COORD-PUBLISH-DONE] publishContext() complete in 5ms
```

**If Missing:**
- Check if `switchProject()` was called
- Verify `publishContext()` deduplication didn't suppress update
- Check `lastSignature` matches expected project

### Step 2: Verify ConversationMonitor Received Update

```bash
# Filter for monitor updates
log stream --predicate 'subsystem == "dev.contextify.timeline" AND category == "ConversationMonitor"' \
  --level debug \
  | grep "handleContextUpdate"
```

**Expected Output:**

```
📬 Received context: <project-id>
🔄 Stopping monitoring for old project
🚀 Starting monitoring for new project
```

**If Missing:**
- Check if ConversationMonitor subscribed to coordinator updates
- Verify subscription task is still running (not cancelled)

### Step 3: Verify UI Refresh

```bash
# Filter for SwiftUI state updates
log stream --predicate 'subsystem BEGINSWITH "dev.contextify"' \
  --level debug \
  | grep -E "TIMELINE-HYDRATE|refreshCache"
```

**Expected Output:**

```
[TIMELINE-HYDRATE-START] Loading feed for project <id>
[TIMELINE-HYDRATE-DONE] Loaded 50 entries in 45ms
```

### Step 4: Check Notification Center Delivery

**If state updates aren't propagating:**

```bash
# Monitor all Contextify notifications
log stream --predicate 'subsystem == "com.apple.Foundation"' --level debug \
  | grep "dev.contextify"
```

**Common Notifications:**
- `.activeProjectContextDidChange` - Coordinator publishes new context
- `.projectsIngestionComplete` - Discovery finished
- `.timelineCacheUpdated` - Cache entry generated

---

## Workflow 4: Database Integrity Check

### When to Use

**Symptoms:**
- App crashes on launch
- Database errors in logs
- Missing projects/transcripts that should exist
- Timeline shows duplicate entries

**Goal:** Verify database file integrity and schema correctness.

### Step 1: Run SQLite Integrity Check

```bash
# Get database path
DB_PATH=$(defaults read dev.contextify "dev.contextify.database_location" 2>/dev/null)/contextify.db
if [ -z "$DB_PATH" ]; then
  DB_PATH="$HOME/Library/Application Support/Contextify/contextify.db"
fi

# Run integrity check
sqlite3 "$DB_PATH" "PRAGMA quick_check"

# Expected: ok
# If not: Database is corrupted
```

**If Corrupted:**

```bash
# Try full check (slower but more thorough)
sqlite3 "$DB_PATH" "PRAGMA integrity_check"

# Attempt recovery
sqlite3 "$DB_PATH" ".recover" | sqlite3 recovered.db

# Verify recovered database
sqlite3 recovered.db "PRAGMA quick_check"

# If OK, replace original:
mv "$DB_PATH" "$DB_PATH.corrupted-backup"
mv recovered.db "$DB_PATH"
```

### Step 2: Verify Schema Version

```bash
# Check schema version
sqlite3 "$DB_PATH" "PRAGMA user_version"

# Expected: 26 (current schema version as of 2025-11-17)
```

**If Version Mismatch:**

| Version | Action |
|---------|--------|
| 0 | Empty database - normal for first launch |
| <26 | Old schema - app should auto-migrate on next launch |
| >26 | Newer database from future app version - **DO NOT USE** |

### Step 3: Check Table Existence

```bash
# List all tables
sqlite3 "$DB_PATH" ".tables"

# Expected tables:
# - projects
# - transcripts
# - transcript_entries
# - timeline_cache
# - transcript_metadata
# - database_access_metadata
# - grdb_migrations
```

**If Tables Missing:**

Database schema incomplete - likely corruption or interrupted migration.

**Recovery:**

```bash
# Restore from backup (see database-migration-runbook.md)
# OR reset database (DESTRUCTIVE - loses all data):
rm "$DB_PATH"*
# App will create fresh database on next launch
```

### Step 4: Verify Row Counts

```bash
# Check data exists
sqlite3 "$DB_PATH" "SELECT
  (SELECT COUNT(*) FROM projects) AS projects,
  (SELECT COUNT(*) FROM transcripts) AS transcripts,
  (SELECT COUNT(*) FROM transcript_entries) AS entries,
  (SELECT COUNT(*) FROM timeline_cache) AS cache_entries"

# Example output:
# projects|transcripts|entries|cache_entries
# 5|12|1234|987
```

**If Counts Are Zero:**

- App launched but no transcripts discovered yet (normal for first launch)
- OR discovery failed (check ProjectDiscoveryService logs)
- OR database reset/cleared

---

## Workflow 5: Sandbox Debugging

### When to Use

**Symptoms:**
- App Store build can't access `~/.claude/projects`
- "No authorization" errors in logs
- Projects discovered in DMG build but not App Store build
- Security-scoped bookmark resolution failures

**Goal:** Verify folder authorization and bookmark resolution for sandboxed builds.

### Step 1: Check Build Type

```bash
# Check if running sandboxed build
log stream --predicate 'subsystem BEGINSWITH "dev.contextify"' --level debug \
  | grep -i sandbox

# Look for: "[STARTUP-SANDBOX]" tags or "isSandboxed = true"
```

### Step 2: Verify Folder Authorization

```bash
# Check TCC database for folder permissions (App Store builds)
BUNDLE_ID="PeterPym.Contextify.Debug"  # Or PeterPym.Contextify for release

sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, allowed FROM access WHERE client LIKE '%$BUNDLE_ID%';"

# Expected:
# kTCCServiceSystemPolicyAllFiles|PeterPym.Contextify.Debug|1
```

**If `allowed = 0` or No Rows:**

User hasn't granted folder access. App should show welcome modal.

### Step 3: Verify Bookmark Persistence

```bash
# Check UserDefaults for bookmarks
defaults read dev.contextify

# Look for:
# - dev.contextify.claude.bookmark (Base64 data)
# - dev.contextify.codex.bookmark (Base64 data)
```

**If Bookmarks Missing:**

User needs to re-grant access via Settings or welcome modal.

### Step 4: Check Bookmark Resolution

```bash
# Monitor bookmark resolution attempts
log stream --predicate 'subsystem BEGINSWITH "dev.contextify"' --level debug \
  | grep -E "bookmark|security.scope"

# Look for:
# - "Failed to resolve bookmark" → Bookmark stale or invalid
# - "Access denied" → Bookmark exists but startAccessingSecurityScopedResource() failed
```

**Common Failures:**

| Error | Cause | Fix |
|-------|-------|-----|
| "Bookmark stale" | Folder moved/renamed | Re-grant access |
| "Access denied" | TCC permission revoked | Reset TCC, re-grant |
| "Bookmark not found" | Never granted access | Show welcome modal |

---

## Workflow 6: Automated Test Harness

### When to Use

**Symptoms:**
- You fixed a bug and want to verify it works
- Need automated regression test for critical path
- Want to test with clean database state

**Goal:** Run automated test with pass/fail exit code (no human interpretation needed).

### Standard Test

```bash
# Run automated pipeline test
./scripts/logging/monitor-automated-test.sh

# Exit codes:
# 0 = Test passed (all stages detected)
# 1 = Test failed (missing stage or timeout)
```

### Clean Database Test

**Scenario:** Bug only reproduces with empty database.

**Custom Script:**

```bash
#!/bin/bash
set -euo pipefail

# 1. Backup current database
cp ~/Library/Application\ Support/Contextify/contextify.db /tmp/contextify-backup.db

# 2. Remove database (force clean state)
rm ~/Library/Application\ Support/Contextify/contextify.db*

# 3. Launch app
open -a Contextify

# 4. Wait for startup
sleep 5

# 5. Capture logs and check for expected behavior
./scripts/logging/monitor-pipeline-check.sh

# Exit code determines test result

# 6. Cleanup: Restore original database
killall Contextify
cp /tmp/contextify-backup.db ~/Library/Application\ Support/Contextify/contextify.db
```

### Regression Test for Specific Bug

**Example: Verify timeline loads after project switch**

```bash
#!/bin/bash
set -euo pipefail

# 1. Switch to project A
osascript -e 'tell application "System Events" to keystroke "p" using {command down, shift down}'
# ... select project A ...

# 2. Capture logs
./scripts/logging/monitor-transcript-queues.sh &
PID=$!
sleep 10

# 3. Switch to project B
# ... select project B ...

sleep 10
kill $PID

# 4. Analyze for timeline hydration
grep -q "\[TIMELINE-HYDRATE-DONE\]" /tmp/transcript-queue-monitor-*.log

if [ $? -eq 0 ]; then
  echo "✅ Timeline loaded after switch (PASS)"
  exit 0
else
  echo "❌ Timeline did not load (FAIL)"
  exit 1
fi
```

---

## Workflow 7: Interactive Monitoring (Exploratory)

### When to Use

**Symptoms:**
- Issue is vague or intermittent
- Don't know which component is involved
- Need to observe system behavior in real-time

**Goal:** Capture live logs to understand system state and data flow.

### Step 1: Start Interactive Monitor

```bash
# Monitor all Contextify subsystems in real-time
./scripts/logging/monitor-interactive.sh

# Logs stream to console with color coding
# Press Ctrl+C to stop
```

### Step 2: Reproduce Issue

While monitor is running:
1. Perform action that triggers issue
2. Observe log output for errors/warnings
3. Note timestamp of issue

### Step 3: Analyze Patterns

Look for:
- **Errors:** Red lines with `error:` or `❌`
- **Warnings:** Yellow lines with `warning:` or `⚠️`
- **Missing activity:** Expected logs not appearing
- **Timing issues:** Large gaps between related events

### Step 4: Narrow Focus

If specific component is suspect:

```bash
# Filter to single subsystem
log stream --predicate 'subsystem == "dev.contextify.timeline"' --level debug

# Or single category
log stream --predicate 'category == "ConversationMonitor"' --level debug
```

### Step 5: Capture for Post-Hoc Analysis

```bash
# Save logs to file for later analysis
./scripts/logging/monitor-transcript-queues.sh

# Then run analysis tools:
./scripts/logging/analyze-pipeline.sh /tmp/transcript-queue-monitor-*.log
./scripts/logging/analyze-tags.sh /tmp/transcript-queue-monitor-*.log
./scripts/logging/analyze-gaps.sh /tmp/transcript-queue-monitor-*.log 1000
```

---

## Tool Selection Matrix

| Goal | Automated Tool | Manual Tool | Time Investment |
|------|---------------|-------------|-----------------|
| Verify bug fix | `monitor-automated-test.sh` | N/A | 30 sec |
| Check pipeline stages | `monitor-pipeline-check.sh` | `analyze-pipeline.sh <log>` | 30 sec / 2 min |
| Find performance bottleneck | `analyze-gaps.sh <log>` | Instruments | 5 min / 30 min |
| Explore unknown issue | `monitor-interactive.sh` | Log grep/filtering | 10 min |
| Verify database health | `sqlite3 PRAGMA quick_check` | `.recover` | 10 sec / 10 min |
| Check sandbox permissions | TCC query | System Settings UI | 1 min / 5 min |

**General Rule:** Start with automated tools (exit code 0/1), escalate to manual tools if needed.

---

## Common Issues Quick Reference

| Symptom | Most Likely Cause | First Tool to Use |
|---------|------------------|------------------|
| Timeline empty after project switch | ConversationMonitor didn't receive context update | `monitor-pipeline-check.sh` |
| New entry not appearing | TranscriptWatcher didn't detect file change | `monitor-pipeline-check.sh` |
| App slow/laggy | Main thread blocking or slow database query | `analyze-gaps.sh` |
| "No authorization" error (sandbox) | TCC permission missing | TCC query + welcome modal |
| Projects missing from switcher | Discovery failed or security scope issue | Check discovery logs |
| Database corruption | Interrupted write or multi-machine conflict | `PRAGMA integrity_check` |

---

## Related Documentation

- **Logging Toolkit:** `scripts/logging/README.md` (comprehensive automation tools)
- **Log Analysis:** `build/docs/guides/log-analysis-methodology.md`
- **Quick Reference:** `build/docs/guides/log-analysis-quick-reference.md`
- **Best Practices:** `build/docs/guides/logging-best-practices.md`
- **Database Operations:** `build/docs/operations/database-migration-runbook.md`
- **Sandbox Debugging:** `build/docs/architecture/sandbox-appstore-architecture.md`

---

## Changelog

**2025-11-17:**
- Initial debugging workflows guide created
- Decision tree for issue classification
- 7 comprehensive workflows (pipeline, performance, state, database, sandbox, testing, exploratory)
- Tool selection matrix for quick reference
- Integration with existing logging toolkit
- Diagnostic API reference
- Common issues quick reference table
