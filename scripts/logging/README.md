# Log Monitoring Scripts

**Instructions for AI assistants** debugging issues by monitoring tagged log output in real-time.

## Debugging Workflow

This is the process for diagnosing issues through logging:

### 1. Use the Template to Monitor (Tier 1: Transient)

Start debugging by monitoring existing logs with the parameterized template:

```bash
# Monitor specific tags
./scripts/logging/monitor-template.sh FEATURE-START FEATURE-DONE

# Monitor all logs from configured subsystem
./scripts/logging/monitor-template.sh
```

**No file creation required.** The template accepts tags as arguments and runs immediately.

**Configure if needed:** Edit the CONFIGURATION section at the top of `monitor-template.sh`:
```bash
SUBSYSTEM="dev.contextify.timeline"     # Which subsystem to monitor
CATEGORIES="ConversationMonitor Hoover" # Which categories (space-separated)
LEVEL="debug"                           # debug | info | error
```

### 2. Add Tagged Logs to Source Code

If monitoring reveals missing instrumentation, add tagged logs:

```swift
import OSLog

// Choose subsystem based on feature area:
// - "dev.contextify.timeline" for timeline/summarization features
// - "dev.contextify.metadata" for transcript metadata processing
// - "dev.contextify" for general app logging
private let log = Logger(subsystem: "dev.contextify.timeline", category: "YourFeature")

// Add logs with [TAG] prefixes
log.info("[FEATURE-START] Starting operation: \(context, privacy: .public)")
log.debug("[FEATURE-STEP] Processing \(count, privacy: .public) items")
log.info("[FEATURE-DONE] Completed in \(elapsed, privacy: .public)s")
```

**Tag naming:** `[FEATURE-EVENT]` where:
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

```swift
// WRONG - value redacted as <private>
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

### 3. Iterate: Monitor → Add Logs → Rebuild → Monitor

Rebuild the app after adding logs, then run the template again:

```bash
bash scripts/xc.sh build
./scripts/logging/monitor-template.sh YOUR-NEW-TAG
# Test the feature, observe logs, refine
```

### 4. Save Custom Monitors (Tier 2/3)

**Tier 2 - Temporary (/tmp/):** For multi-day debugging, save template-based script to `/tmp/`:

```bash
cp scripts/logging/monitor-template.sh /tmp/monitor-my-debug.sh
# Edit /tmp/monitor-my-debug.sh CONFIGURATION section
chmod +x /tmp/monitor-my-debug.sh
/tmp/monitor-my-debug.sh
```

Scripts in `/tmp/` are session-local, not committed, and auto-cleaned by the OS.

**Tier 3 - Permanent (scripts/logging/):** Only for frequently-used, important monitors:

```bash
cp scripts/logging/monitor-template.sh scripts/logging/monitor-important-feature.sh
# Edit CONFIGURATION section and customize color-coding
chmod +x scripts/logging/monitor-important-feature.sh
git add scripts/logging/monitor-important-feature.sh
```

**Keep scripts/logging/ uncluttered.** Most debugging should use Tier 1 (template) or Tier 2 (/tmp/).

## Critical Gotchas

### Logger Subsystem/Category Must Match Script

**The predicate in your monitor script MUST exactly match the Logger in your code.**

Example:
```bash
# monitor-template.sh CONFIGURATION:
SUBSYSTEM="dev.contextify.timeline"
CATEGORIES="ConversationMonitor CacheMissGenerator"
```

Must match code:
```swift
// ConversationMonitor.swift:
private let log = Logger(subsystem: "dev.contextify.timeline", category: "ConversationMonitor")

// TimelineCacheMissGenerator.swift:
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

## Analyzing Captured Logs

After capturing logs, use `analyze-gaps.sh` to find performance bottlenecks by identifying multi-second gaps between consecutive log entries.

### Usage

```bash
# Find all gaps >= 1 second (default)
./scripts/logging/analyze-gaps.sh /tmp/monitor-*.log

# Find critical gaps >= 5 seconds
./scripts/logging/analyze-gaps.sh /tmp/monitor-*.log 5000

# Fine-grained analysis >= 500ms
./scripts/logging/analyze-gaps.sh /tmp/monitor-*.log 500
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
