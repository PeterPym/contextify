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

// Choose subsystem based on feature area:
// - "dev.contextify.timeline" for timeline/summarization features
// - "dev.contextify.metadata" for transcript metadata processing
// - "dev.contextify" for general app logging
private let log = Logger(subsystem: "dev.contextify.timeline", category: "YourFeature")

// In your code:
log.info("[FEATURE-START] Starting operation: \(context, privacy: .public)")
log.debug("[FEATURE-STEP] Processing \(count, privacy: .public) items")
log.info("[FEATURE-DONE] Completed in \(elapsed, privacy: .public)s")
```

**Tag naming convention:** `[FEATURE-EVENT]` where:
- `FEATURE` = your feature area (e.g., SUMM, BATCH, COORD)
- `EVENT` = specific event (e.g., START, DONE, ERROR)

**CRITICAL - Tag on Every Line:** The grep filter in monitoring scripts matches log lines by tag. If you have multi-line output, **every line must contain the tag** or it will be filtered out.

```swift
// WRONG - detail lines have no tag, won't be captured
log.info("[SUMM-QUEUE] Queueing \(count) entries:")
log.info("  - Entry 1...")  // ❌ Filtered out by grep
log.info("  - Entry 2...")  // ❌ Filtered out by grep

// RIGHT - every line has the tag
log.info("[SUMM-QUEUE] Queueing \(count) entries:")
log.info("  [SUMM-QUEUE] Entry 1...")  // ✅ Captured by grep
log.info("  [SUMM-QUEUE] Entry 2...")  // ✅ Captured by grep
```

**IMPORTANT - Privacy:** Always use `privacy: .public` for interpolated values (timing, counts, names).
Without `.public`, macOS redacts values as `<private>`, breaking performance analysis.

**Examples:**
```swift
// WRONG - timing will show as <private>ms
log.info("[PERF] Completed in \(elapsed)ms")

// RIGHT - timing visible in logs
log.info("[PERF] Completed in \(elapsed, privacy: .public)ms")

// WRONG - applying privacy to whole string literal
log.info("[PERF] Switched to \(name, privacy: .public)", privacy: .public)

// RIGHT - privacy on interpolated value only
log.info("[PERF] Switched to \(name, privacy: .public)")

// OK - no values to redact
log.info("[PERF] Operation started")
```

### 2. Create Monitor Script

Copy the example and modify for your tags:

```bash
cp scripts/logging/monitor-summarization-flow.sh scripts/logging/monitor-yourfeature.sh
chmod +x scripts/logging/monitor-yourfeature.sh
```

Edit the script:
1. Change `LOGFILE` prefix (line 10)
2. Update help text with your tags (lines 23-33)
3. **CRITICAL**: Update `log stream` predicate (line 43-44) to match your Logger's subsystem and category
4. Update grep pattern for your tags (line 47): `grep --line-buffered -E "PATTERN1|PATTERN2|..."`
5. Update color coding cases (lines 55-86)

### 3. Run and Debug

```bash
./scripts/logging/monitor-yourfeature.sh
# Trigger your feature in the app
# Watch color-coded output in real-time
```

## Critical Gotchas

### Logger Subsystem/Category Must Match Script Predicate

**The predicate in your script MUST exactly match the Logger in your code.**

Example - monitor-cache-generation.sh:
```bash
# Script predicate (line 43-44):
log stream \
  --predicate 'subsystem == "dev.contextify.timeline" AND (category == "CacheMissGenerator" OR category == "ConversationMonitor")'
```

Must match code:
```swift
// ConversationMonitor.swift line 145:
private let log = Logger(subsystem: "dev.contextify.timeline", category: "ConversationMonitor")

// TimelineCacheMissGenerator.swift line 31:
private let log = Logger(subsystem: "dev.contextify.timeline", category: "CacheMissGenerator")
```

**If subsystem or category doesn't match, you'll see NO logs** - this is the #1 debugging issue.

### macOS Log Stream Predicate Operators
Both `==` and `BEGINSWITH` work:
```bash
# Exact match (recommended):
--predicate 'subsystem == "dev.contextify.timeline"'

# Prefix match (captures multiple subsystems):
--predicate 'subsystem BEGINSWITH "dev.contextify"'
```

Use `==` when targeting a specific subsystem, `BEGINSWITH` when you want multiple.

### Buffering Issues
**WRONG:** `log stream | grep "\[TAG-" | tee file`
**RIGHT:** `log stream | grep --line-buffered "\[TAG-" | tee file`

Without `--line-buffered`, grep buffers output and you see nothing in real-time.

**WRONG:** `while read line; do`
**RIGHT:** `while IFS= read -r line; do`

Preserves whitespace and special characters in log lines.

### Log Levels
- `--level debug` captures `.debug()` and above (recommended for development)
- `--level info` captures `.info()` and above (less noise, might miss details)

**IMPORTANT:** The log level in the script must be <= the log level in code.
If your code uses `log.debug()` but script uses `--level info`, you won't see those logs.

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

## Analyzing Captured Logs

After capturing logs with a monitor script, use `analyze-gaps.sh` to find performance bottlenecks by identifying multi-second gaps between consecutive log entries.

### Usage

```bash
# Find all gaps >= 1 second (default)
./scripts/logging/analyze-gaps.sh /tmp/ui-performance-*.log

# Find critical gaps >= 5 seconds
./scripts/logging/analyze-gaps.sh /tmp/ui-performance-*.log 5000

# Fine-grained analysis >= 500ms
./scripts/logging/analyze-gaps.sh /tmp/ui-performance-*.log 500
```

### Output

Color-coded by severity:
- 🔴 **RED (CRITICAL)**: >= 10 seconds
- 🟡 **YELLOW (WARNING)**: >= 5 seconds
- 🟢 **GREEN (INFO)**: >= threshold

For each gap, shows:
- Gap duration in milliseconds
- Log entry **before** the gap
- Log entry **after** the gap
- Line numbers in the original log file
- Tag analysis (what operations were involved)

### Example

```
Gap #1: 8101ms (WARNING)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Before (line 718):
  [UIOPT-COORD-GIT-TASK-DONE] Task complete in 0ms

After (line 719):
  [UIOPT-COORD-GIT-TASK-AWAIT] Task.value returned

Analysis:
  Previous tag: [UIOPT-COORD-GIT-TASK-DONE]
  Next tag:     [UIOPT-COORD-GIT-TASK-AWAIT]
  Gap location: Between these operations
```

### Interpreting Gaps

Common gap patterns:
- **Between TASK-DONE and TASK-AWAIT**: Background task completed but took time to return to main thread
- **Between SPAWN and TASK-START**: Task.detached took too long to schedule
- **Between INPUT and TABS-UPDATE**: UI event handling delay

### Tips

- Start with **5000ms** to find critical issues only
- Use **1000ms** to see all multi-second delays
- Use **500ms** for fine-grained analysis
- Check **line numbers** to see full context in original log
- Gaps reveal **uninstrumented code** between logged operations

## Related

- **Logging preferences:** `build/notes/technical-reference/logging-preferences.md`
- **Log capture:** `scripts/LOG-CAPTURE-README.md`
