# Log Monitoring Scripts

Scripts for debugging Contextify by monitoring tagged log output in real-time.

## Quick Start

```bash
./scripts/logging/monitor-summarization-flow.sh
# Perform actions in the app (e.g., switch projects)
# Press Ctrl+C to stop
# Logs saved to /tmp/summarization-flow-YYYYMMDD-HHMMSS.log
```

## Creating a Custom Monitor

### 1. Add Tagged Logs to Source Code

Add structured log tags to trace your feature:

```swift
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "YourFeature")

// In your code:
log.info("[FEATURE-START] Starting operation: \(context)")
log.info("[FEATURE-STEP] Processing \(count) items")
log.info("[FEATURE-DONE] Completed in \(elapsed)s")
```

**Tag naming convention:** `[FEATURE-EVENT]` where:
- `FEATURE` = your feature area (e.g., SUMM, BATCH, COORD)
- `EVENT` = specific event (e.g., START, DONE, ERROR)

### 2. Create Monitor Script

Copy the example and modify for your tags:

```bash
cp scripts/logging/monitor-summarization-flow.sh scripts/logging/monitor-yourfeature.sh
chmod +x scripts/logging/monitor-yourfeature.sh
```

Edit the script:
1. Change `LOGFILE` prefix (line 6)
2. Update help text with your tags (lines 17-26)
3. Update grep pattern for your tags (line 44): `grep --line-buffered -E "\[FEATURE-"`
4. Update color coding cases (lines 53-61)

### 3. Run and Debug

```bash
./scripts/logging/monitor-yourfeature.sh
# Trigger your feature in the app
# Watch color-coded output in real-time
```

## Critical Gotchas

### macOS Log Stream Predicate
**WRONG:** `--predicate 'subsystem == "dev.contextify"'`
**RIGHT:** `--predicate 'subsystem BEGINSWITH "dev.contextify"'`

macOS requires `BEGINSWITH` operator for subsystem matching.

### Buffering Issues
**WRONG:** `log stream | grep "\[TAG-" | tee file`
**RIGHT:** `log stream | grep --line-buffered "\[TAG-" | tee file`

Without `--line-buffered`, grep buffers output and you see nothing in real-time.

**WRONG:** `while read line; do`
**RIGHT:** `while IFS= read -r line; do`

Preserves whitespace and special characters in log lines.

### Log Levels
Use `--level info` to capture `.info()` and above. Using `--level debug` works but includes noise.

### stdbuf Not Available
`stdbuf` doesn't exist on macOS - use `grep --line-buffered` instead.

## Example Output

```
[SUMM-TAP] User tapped project: contextify id=ABC123
[SUMM-SWITCH] ProjectSwitcherState initiating switch to: ABC123
[SUMM-COORD] Publishing ActiveProjectContext (id: XYZ789)
[SUMM-MONITOR] ConversationMonitor received context update
[SUMM-LOAD] Feed loaded: 50 entries from database
[SUMM-MISSES] Detected 50 cache misses
[SUMM-SKIP] ⚠️ Summarization disabled - skipping 50 entries
```

## Related

- **Logging preferences:** `build/notes/technical-reference/logging-preferences.md`
- **Log capture:** `scripts/LOG-CAPTURE-README.md`
