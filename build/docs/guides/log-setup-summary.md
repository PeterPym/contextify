# Log Capture Setup for Claude Code Integration

## What We Set Up

Created automated log capture infrastructure so Claude Code can directly read and analyze Contextify runtime logs without manual copy/paste.

## Files Created

1. **`scripts/logging/stream-logs.sh`** - Real-time log streaming to file
2. **`scripts/logging/capture-recent-logs.sh`** - Capture last N minutes retroactively
3. **`scripts/logging/build-and-capture-logs.sh`** - Build and auto-capture for 30 seconds
4. **`build/docs/guides/log-capture.md`** - Detailed documentation
5. **`build/docs/guides/log-quick-reference.md`** - Quick debugging workflow guide
6. **`build/docs/guides/log-setup-summary.md`** - This file

## Makefile Targets Added

```makefile
make logs       # Capture last 5 minutes → /tmp/contextify-recent.log
make logs-live  # Stream live → /tmp/contextify-live.log
make debug      # Build + capture 30s → build/logs/runtime/contextify-*.log
make clean-db   # Delete database for fresh testing
```

## Updated Documentation

- **`CLAUDE.md`** - Added log capture section to main project docs
- **`Makefile`** - Added convenience targets

## How It Works

### macOS Unified Logging
All logs use macOS's native `log` command which captures:
- All `OSLog` messages from Contextify
- Timestamps and log levels (debug, info, warning, error)
- Subsystem and category metadata
- Process name filtering

### Storage Locations
- Quick captures: `/tmp/contextify-*.log` (temporary)
- Automated captures: `build/logs/runtime/` (git-ignored, persistent)

### Integration with Claude Code

**Before this setup:**
```
You: "I'm seeing X error"
Claude: "Can you share the console logs?"
You: [manually copy/paste from Console.app]
Claude: [analyzes text]
```

**After this setup:**
```bash
# You hit an issue
make logs

# In chat
You: "have a look at /tmp/contextify-recent.log"
Claude: [directly reads file with Read tool, analyzes with Grep]
```

## Example Workflow

### Scenario: Database FK Constraint Error

```bash
# 1. Reproduce the issue
# 2. Capture logs
make logs

# 3. Share with Claude
"I'm getting FK constraint errors, have a look at /tmp/contextify-recent.log"

# Claude can now:
# - Read the log directly
# - Search for specific error patterns
# - Correlate timestamps
# - Identify root cause
# - Suggest fixes

# 4. Test the fix
make clean-db && make debug

# 5. Share results
"have a look at build/logs/runtime/contextify-20251011-193045.log"
```

## Benefits

1. **No manual copy/paste** - Claude reads files directly
2. **Full context** - Captures all log levels and categories
3. **Timestamped** - Easy to correlate events
4. **Searchable** - Claude can grep for patterns
5. **Reproducible** - Scripts can be re-run anytime
6. **Git-friendly** - Logs are git-ignored but locally persistent

## Log Categories to Filter

```bash
# By subsystem
grep 'dev.contextify' /tmp/contextify-recent.log

# By category
grep 'HooverEngine' /tmp/contextify-recent.log
grep 'TranscriptOrchestrator' /tmp/contextify-recent.log
grep 'ConversationMonitor' /tmp/contextify-recent.log
grep 'CacheMissGenerator' /tmp/contextify-recent.log

# By level
grep -i error /tmp/contextify-recent.log
grep -i warning /tmp/contextify-recent.log

# By emoji markers (diagnostic logs)
grep '📁' /tmp/contextify-recent.log  # Project setup
grep '🚀' /tmp/contextify-recent.log  # Background tasks
grep '✅' /tmp/contextify-recent.log  # Validations passed
grep '❌' /tmp/contextify-recent.log  # Errors
```

## Tips for Effective Debugging

1. **Name your logs descriptively** when sharing:
   ```bash
   ./scripts/logging/capture-recent-logs.sh 5 /tmp/fk-constraint-issue.log
   ```

2. **Clean database** before testing fixes for fresh state:
   ```bash
   make clean-db && make debug
   ```

3. **Filter before sharing** if logs are huge:
   ```bash
   make logs
   grep -A 10 -B 5 '❌' /tmp/contextify-recent.log > /tmp/errors-with-context.log
   ```

4. **Include database state** for full context:
   ```bash
   sqlite3 ~/Library/Application\ Support/Contextify/transcripts.db \
     "SELECT COUNT(*) FROM transcript_entries;"
   ```

## Next Steps

- Scripts are ready to use immediately
- Documentation is in `build/docs/guides/log-quick-reference.md`
- Makefile targets work out of the box
- Log directory `build/logs/runtime/` will be created automatically

## Testing

Try it now:
```bash
make logs
cat /tmp/contextify-recent.log
```

You should see recent Contextify logs (if the app was running in the last 5 minutes).
