# Quick Reference: Debugging with Claude Code

## When You Hit an Issue

### 1. Capture Recent Logs (Fastest)
If you just reproduced an issue:

```bash
./scripts/logging/capture-recent-logs.sh 5 /tmp/contextify-issue.log
```

Then tell me:
```
have a look at /tmp/contextify-issue.log
```

### 2. Build and Auto-Capture (Best for Testing Fixes)
After I make a fix:

```bash
# Delete old database for clean slate
rm -f ~/Library/Application\ Support/Contextify/transcripts.db*

# Build and capture logs for 30 seconds
./scripts/logging/build-and-capture-logs.sh 30
```

The log file path will be printed at the end. Share it with me:
```
have a look at build/logs/runtime/contextify-20251011-193045.log
```

### 3. Stream Live (For Watching Behavior)
If you want to watch logs in real-time while testing:

```bash
./scripts/logging/stream-logs.sh /tmp/contextify-live.log
```

Press Ctrl+C when done, then share the file.

## What I Can Do With Logs

Once you share a log file, I can:

✅ Read it directly using the `Read` tool
✅ Search for specific patterns with `Grep`
✅ Filter by error level, category, or emoji markers
✅ Correlate timestamps with database state
✅ Identify root causes without manual copy/paste

## Example Session

```bash
# You make a change or hit an issue
# Capture the last 5 minutes
./scripts/logging/capture-recent-logs.sh 5

# Tell me about it
"I'm seeing X issue, have a look at /tmp/contextify-recent.log"

# I analyze it and make a fix
# You test the fix with auto-capture
./scripts/logging/build-and-capture-logs.sh 30

# Share the new logs
"have a look at build/logs/runtime/contextify-20251011-193045.log"
```

## Log File Naming Convention

For clarity, name your logs descriptively when sharing:

```bash
./scripts/logging/capture-recent-logs.sh 5 /tmp/fk-constraint-error.log
./scripts/logging/capture-recent-logs.sh 5 /tmp/no-summaries-showing.log
./scripts/logging/capture-recent-logs.sh 5 /tmp/after-fix-test.log
```

## Filtering Before Sharing (Optional)

If logs are huge, you can pre-filter to just errors:

```bash
./scripts/logging/capture-recent-logs.sh 10 /tmp/full-log.log
grep -i error /tmp/full-log.log > /tmp/errors-only.log
```

Then share `/tmp/errors-only.log`.

## Database State Inspection

I can also check database state directly:

```bash
sqlite3 ~/Library/Application\ Support/Contextify/transcripts.db "
  SELECT COUNT(*) FROM transcript_entries;
  SELECT COUNT(*) FROM timeline_cache;
  SELECT COUNT(*) FROM projects;
"
```

Share this info along with logs for full context.
