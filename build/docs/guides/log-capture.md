# Log Capture Scripts for Contextify

These scripts help capture and analyze Contextify runtime logs for debugging.

## Quick Start

### For Real-Time Debugging
Stream logs as the app runs (useful when watching behavior):

```bash
./scripts/stream-logs.sh
# or save to specific file:
./scripts/stream-logs.sh /tmp/my-debug-session.log
```

### For Post-Mortem Analysis
Capture the last N minutes of logs after reproducing an issue:

```bash
# Capture last 5 minutes (default)
./scripts/capture-recent-logs.sh

# Capture last 10 minutes
./scripts/capture-recent-logs.sh 10

# Save to specific file
./scripts/capture-recent-logs.sh 5 build/logs/runtime/issue-123.log
```

### For Automated Testing
Build and automatically capture logs for 30 seconds:

```bash
./scripts/build-and-capture-logs.sh

# Capture for different duration (in seconds)
./scripts/build-and-capture-logs.sh 60
```

## Log Locations

Automated logs are saved to:
- `build/logs/runtime/contextify-YYYYMMDD-HHMMSS.log`

This directory is git-ignored.

## Filtering Logs

### By Error Level
```bash
grep -i error build/logs/runtime/contextify-*.log
grep -i warning build/logs/runtime/contextify-*.log
```

### By Category/Subsystem
```bash
grep 'HooverEngine' build/logs/runtime/contextify-*.log
grep 'TranscriptOrchestrator' build/logs/runtime/contextify-*.log
grep 'ConversationMonitor' build/logs/runtime/contextify-*.log
grep 'CacheMissGenerator' build/logs/runtime/contextify-*.log
```

### By Emoji Markers (Diagnostic Logs)
```bash
grep '📁' build/logs/runtime/contextify-*.log  # Project ID
grep '🚀' build/logs/runtime/contextify-*.log  # Background tasks
grep '✅' build/logs/runtime/contextify-*.log  # Success markers
grep '❌' build/logs/runtime/contextify-*.log  # Error markers
grep '🔍' build/logs/runtime/contextify-*.log  # Discovery
grep '📊' build/logs/runtime/contextify-*.log  # Feed loading
```

## Sharing Logs with Claude Code

When debugging with Claude Code, you can:

1. **Use the automated script** to capture logs:
   ```bash
   ./scripts/build-and-capture-logs.sh 30
   ```

2. **Share the log file** location so Claude can read it directly:
   ```bash
   ls -t build/logs/runtime/*.log | head -1
   ```

3. **Filter for relevant sections** before sharing:
   ```bash
   # Extract just the error context
   grep -B 5 -A 10 '❌' build/logs/runtime/contextify-*.log > /tmp/error-context.log
   ```

## System Log Commands

### Manual Log Collection (without scripts)

```bash
# Show logs from last 5 minutes
log show --predicate 'process == "Contextify"' \
  --style compact \
  --start "$(date -v-5M '+%Y-%m-%d %H:%M:%S')"

# Stream live logs
log stream --predicate 'process == "Contextify"' --style compact

# Filter by log level
log show --predicate 'process == "Contextify" AND messageType == "Error"' \
  --style compact \
  --start "$(date -v-5M '+%Y-%m-%d %H:%M:%S')"
```

## Tips

1. **Clear logs before testing**: Close Contextify, wait a few seconds, then restart to get clean logs
2. **Timestamp correlation**: The scripts use compact style which includes timestamps
3. **Log verbosity**: Debug logs are hidden by default in Console.app - use `.debug` in code for verbose output
4. **Performance**: Live streaming has minimal overhead, capture is retroactive and fast

## Troubleshooting

### "No logs appearing"
- Verify Contextify is running: `pgrep Contextify`
- Check process name in Activity Monitor (should be "Contextify")
- Try broader predicate: `--predicate 'processImagePath CONTAINS "Contextify"'`

### "Too many logs"
- Add subsystem filter: `--predicate 'process == "Contextify" AND subsystem == "dev.contextify"'`
- Filter by category: `--predicate 'process == "Contextify" AND category == "HooverEngine"'`

### "Missing diagnostic emoji"
- Emoji markers are in the log message text, not metadata
- Use `grep` on the output, not predicate filtering
