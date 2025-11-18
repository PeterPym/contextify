# P0 #P1-DISCOVERY Manual Test Instructions

## CRITICAL: Proper Testing Requires Clean State

**DO NOT** test without resetting database and permissions first!

## Test 1: DMG Build (Unsandboxed)

```bash
# 1. Kill any running instance
killall Contextify

# 2. Reset database and permissions
bash scripts/xc.sh dr

# 3. App will launch automatically
# 4. Welcome modal should appear
# 5. Wait for discovery to complete
# 6. Note the time from modal appearance to completion

# 7. Find the latest log
ls -lhtr /private/tmp/transcript-queue-monitor-*.log | tail -1

# 8. Analyze the log
LOG_FILE=$(ls -t /private/tmp/transcript-queue-monitor-*.log | head -1)
grep -E "DISCOVERY-START|DISCOVERY-COMPLETE|SWITCHER-MONITOR|Fallback timeout" "$LOG_FILE"
```

**Expected Results (DMG):**
- Total time: <2 seconds
- No "Fallback timeout triggered" warning
- "✅ Received .projectsDiscoveryComplete notification"
- "[INIT-SKIP-DISCOVERY] Projects already ingested"

## Test 2: App Store Build (Sandboxed)

```bash
# 1. Kill any running instance
killall Contextify

# 2. Reset database and permissions
bash scripts/xc.sh ar

# 3. App will launch automatically
# 4. Permissions step will appear FIRST
# 5. Grant access to both Claude and Codex
# 6. Discovery will start AFTER permissions granted
# 7. Wait for discovery to complete
# 8. Note the time from permissions grant to completion

# 9. Find the latest log
ls -lhtr /private/tmp/transcript-queue-monitor-*.log | tail -1

# 10. Analyze the log
LOG_FILE=$(ls -t /private/tmp/transcript-queue-monitor-*.log | head -1)
grep -E "PERMISSIONS|Granted access|DISCOVERY-START|DISCOVERY-COMPLETE|SWITCHER-MONITOR|Fallback timeout|Ingestion started" "$LOG_FILE"
```

**Expected Results (App Store):**
- Permissions step appears first
- After granting permissions, discovery starts
- Total time: <2 seconds (from permission grant to complete)
- "Ingestion started - beginning 30s fallback timer"
- No "Fallback timeout triggered" warning (or if it appears, check monitor already started)
- "✅ Received .projectsDiscoveryComplete notification"

## What to Look For

### Success Indicators ✅
- Total time <2 seconds
- Notification received with <10ms gap
- Monitor skips duplicate discovery
- All 19 watchers ready in <1s
- No fallback timeout warning (or monitor already started if it appears)

### Failure Indicators ❌
- Total time >10 seconds
- "Fallback timeout triggered" AND monitor NOT already started
- Duplicate discovery runs
- UI appears frozen

## Common Mistakes

❌ **Testing without reset** - Database already has projects, test is invalid
❌ **Using wrong reset command** - `dr` for DMG, `ar` for App Store
❌ **Not waiting for app to fully launch** - Check logs 30-60s after reset
❌ **Looking at old logs** - Always check timestamp on log file

## Validation Commands

After each test, run:

```bash
# Get the latest log
LOG_FILE=$(ls -t /private/tmp/transcript-queue-monitor-*.log | head -1)

# Check log timestamp matches test time
ls -lh "$LOG_FILE"

# Run automated validation (if it works with new log format)
bash scripts/logging/validate-discovery-fix.sh "$LOG_FILE"

# Manual check - key timing points
echo "=== Discovery Timing ==="
grep "DISCOVERY-START" "$LOG_FILE" | tail -1
grep "DISCOVERY-COMPLETE" "$LOG_FILE" | tail -1
grep "SWITCHER-MONITOR.*Received" "$LOG_FILE" | tail -1
grep "Fallback timeout" "$LOG_FILE" | tail -1

# Should see:
# - DISCOVERY-START
# - DISCOVERY-COMPLETE (1-2s later)
# - Received notification (within ms of DISCOVERY-COMPLETE)
# - NO fallback timeout (or monitor already started)
```

## Reporting Results

When reporting test results, include:

1. Build type (DMG or App Store)
2. Log file name and timestamp
3. Total time (from discovery start to complete)
4. Whether fallback timeout triggered
5. Whether notification was received
6. Full relevant log excerpt

**Example:**
```
Test: App Store build
Log: transcript-queue-monitor-20251118-080727.log
Total time: 1.8s
Fallback timeout: NO
Notification received: YES (2ms gap)
Monitor skip optimization: YES
Result: PASS ✅
```
