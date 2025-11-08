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
log.info("[FEATURE-START] Starting operation: \(context, privacy: .public)", privacy: .public)
log.info("[FEATURE-STEP] Processing \(count) items", privacy: .public)
log.info("[FEATURE-DONE] Completed in \(elapsed)s", privacy: .public)
```

**Tag naming convention:** `[FEATURE-EVENT]` where:
- `FEATURE` = your feature area (e.g., SUMM, BATCH, COORD)
- `EVENT` = specific event (e.g., START, DONE, ERROR)

**IMPORTANT - Privacy:** Always use `privacy: .public` for logs with interpolated values (timing, counts, names).
Without `.public`, macOS redacts values as `<private>`, breaking performance analysis.

**Examples:**
```swift
// WRONG - timing will show as <private>ms
log.info("[PERF] Completed in \(elapsed)ms")

// RIGHT - timing visible in logs
log.info("[PERF] Completed in \(elapsed)ms", privacy: .public)

// RIGHT - project name visible
log.info("[PERF] Switched to \(name, privacy: .public)", privacy: .public)

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

- **Logging best practices:** `build/docs/guides/logging-best-practices.md`
- **Log capture:** `scripts/LOG-CAPTURE-README.md`
