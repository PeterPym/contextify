# Proper Test Procedure for P0 Discovery Fix

## Complete Test Sequence

### Step 1: Start Log Monitoring (CRITICAL - Do This First!)

```bash
# Start monitoring in background for 120 seconds
bash scripts/logging/monitor-transcript-queues.sh 120 &
```

### Step 2: Reset and Launch (Choose ONE)

**For DMG build:**
```bash
bash scripts/xc.sh dr
```

**For App Store build:**
```bash
bash scripts/xc.sh ar
```

### Step 3: Interact with App

- Welcome modal appears
- **App Store only:** Grant permissions when prompted
- Wait for discovery to complete
- Note total time

### Step 4: Find and Analyze Log

```bash
# Find the latest log
LOG=$(ls -t /private/tmp/transcript-queue-monitor-*.log | head -1)
echo "Log file: $LOG"

# Check key metrics
grep -E "DISCOVERY-START|DISCOVERY-COMPLETE|SWITCHER-MONITOR.*Received|Fallback timeout|Ingestion started" "$LOG"
```

## Expected Results

**DMG Build:**
- Discovery starts immediately
- Total time: ~1.6s
- Notification received within ms
- No fallback timeout

**App Store Build:**
- Permissions shown first
- After granting: discovery starts
- "Ingestion started - beginning 30s fallback timer"
- Total time: ~1.8s (from permission grant)
- Notification received within ms
- No fallback timeout warning

## Share Log File Path

When reporting results, share the actual log file path so I can analyze it properly.
