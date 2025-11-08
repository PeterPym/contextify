# Debugging Toolkit for Contextify

**For LLMs:** This is a dispatch table. Match the problem symptom to a debugging pattern, then use the recommended template. Bias toward **automated approaches** that generate reports without human interpretation.

**For Humans:** Choose a pattern based on symptoms, run the script, observe or receive a report.

---

## Quick Dispatch Table

| Problem Symptom | Pattern | Script | Mode | Exit Code |
|----------------|---------|--------|------|-----------|
| Feature not appearing in UI | Pipeline Completeness | `monitor-pipeline-check.sh` | Automated | 0=pass, 1=fail |
| Need to verify bug fix works | Automated Test | `monitor-automated-test.sh` | Automated | 0=pass, 1=fail |
| App slow/laggy, timing issues | Gap Analysis | `monitor-interactive.sh` + `analyze-gaps.sh` | Semi-auto | - |
| Exploring unknown issue | Interactive Monitoring | `monitor-interactive.sh` | Interactive | - |
| Re-analyze captured logs | Pipeline Analysis | `analyze-pipeline.sh` | Post-hoc | 0=pass, 1=fail |

**Default choice for LLMs:** Start with **Pipeline Completeness** or **Automated Test** (self-validating, reports findings).

---

## Debugging Patterns

### Pattern 1: Pipeline Completeness Check

**When to use:**
- Feature implemented but not appearing in UI
- User action triggers file change, but no visible result
- Unclear which pipeline stage is broken

**How it works:**
Captures logs for 30 seconds, verifies all pipeline stages show activity (File System → Discovery → Hoover → Database → Timeline → UI). Reports which stage is broken.

**Usage:**
```bash
./scripts/logging/monitor-pipeline-check.sh

# Or customize duration
DURATION=60 ./scripts/logging/monitor-pipeline-check.sh
```

**Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  STAGE-BY-STAGE ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ File System Events:            42 events
✅ Transcript Discovery:           12 events
✅ Hoover Engine:                  24 events
❌ Database Updates:                0 events  PIPELINE BROKEN HERE
❌ Timeline Updates:                0 events  PIPELINE BROKEN HERE
❌ UI Rendering:                    0 events  PIPELINE BROKEN HERE

🔍 FOCUS INVESTIGATION HERE:
   Last working stage:  Hoover Engine
   First broken stage:  Database Updates
```

**Exit code:** 0 if complete, 1 if broken stages found

**When it fails:**
- Indicates WHERE in the pipeline data is lost
- Focus investigation on the connection between last working and first broken stage
- Check for errors: `grep -i error /tmp/pipeline-check-*.log`

**Next steps:**
- If pipeline complete but still issues → Use Gap Analysis (timing problem)
- If specific stage broken → Use Interactive Monitoring to observe that stage

---

### Pattern 2: Automated Test Harness

**When to use:**
- Verifying a bug fix works correctly
- Regression testing (ensure bug doesn't come back)
- CI/CD validation
- Need pass/fail result without human interpretation

**How it works:**
Captures logs and validates against **expected patterns**. You define what "success" looks like (e.g., "HOOVER-START count should match HOOVER-DONE count"). Reports pass/fail.

**Usage:**
```bash
# Basic usage (default 30s)
./scripts/logging/monitor-automated-test.sh

# Customize test
TEST_NAME="hoover-fix-validation" \
DURATION=45 \
RESTART_APP=true \
./scripts/logging/monitor-automated-test.sh
```

**Customization:**
Edit the script's `EXPECTATIONS` array:
```bash
EXPECTATIONS=(
    "WATCHER-EVENT:1-100:optional"      # Expect 1-100 occurrences
    "HOOVER-START:1-100:optional"
    "HOOVER-DONE:HOOVER-START:match"    # Must equal HOOVER-START count
    "TIMELINE-APPEND:0-1000:optional"
)
```

**Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RESULTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Passed:  4
Failed:  1
Warnings: 0

💥 OVERALL: FAIL

Failures:
❌ HOOVER-DONE: 15 (expected 18 to match HOOVER-START)
```

**Exit code:** 0 if all pass, 1 if any failures

**When it fails:**
- Indicates WHAT behavior is unexpected
- Use the report to identify which expectations failed
- Review raw tag counts to understand what actually happened

**Next steps:**
- If test passes → Bug fix verified ✅
- If test fails → Investigate specific failed expectations

---

### Pattern 3: Gap Analysis

**When to use:**
- App feels slow or laggy
- Operations take too long
- Need to identify performance bottlenecks
- Timeline updates are delayed

**How it works:**
Captures logs with `monitor-interactive.sh`, then analyzes with `analyze-gaps.sh` to find multi-second delays between consecutive log entries.

**Usage:**
```bash
# Step 1: Capture logs (run for 30-60s, reproduce the slow behavior)
./scripts/logging/monitor-interactive.sh TIMELINE- HOOVER- VIEWPORT-

# Step 2: Analyze gaps (finds delays >= 1000ms by default)
./scripts/logging/analyze-gaps.sh /tmp/monitor-*.log

# Or find critical gaps only (>= 5 seconds)
./scripts/logging/analyze-gaps.sh /tmp/monitor-*.log 5000
```

**Output:**
```
🔴 CRITICAL GAP: 12450ms
Before (line 847): [TIMELINE-APPEND] Added 15 entries to timeline
After (line 891):  [VIEWPORT-UPDATE] Viewport refreshed

Gap indicates: Timeline processing completed but took 12s to update viewport
Likely cause: Main thread blocking, UI state update delay
```

**When it finds gaps:**
- Gaps reveal **uninstrumented code** between logged operations
- Common patterns:
  - Between DONE and AWAIT → Thread scheduling delay
  - Between DB update and Timeline append → Notification not received
  - Between Timeline append and UI update → SwiftUI state propagation delay

**Next steps:**
- Add more instrumentation around the gap
- Check for blocking operations on main thread
- Verify async/await flow is correct

---

### Pattern 4: Interactive Monitoring

**When to use:**
- Initial exploration of unknown issues
- Need to observe system behavior in real-time
- Want to see raw log stream with color coding
- Creating custom analysis after observation

**How it works:**
Streams logs in real-time with color-coded output. Human observes patterns, timing, and sequences. Logs auto-saved for later analysis.

**Usage:**
```bash
# Monitor specific tags
./scripts/logging/monitor-interactive.sh HOOVER- TIMELINE-

# Monitor all logs from timeline subsystem
./scripts/logging/monitor-interactive.sh

# Customize in script first (edit CONFIGURATION section):
# - SUBSYSTEM: which subsystem to monitor
# - CATEGORIES: which categories (space-separated)
# - LEVEL: debug | info | error
```

**Output:**
Real-time color-coded stream:
```
🚀 14:06:37.455 [TIMELINE-INIT] Initializing timeline monitor
▶️  14:06:37.607 [HOOVER-START] Starting hoover for transcript: d063bff6...
✅ 14:06:37.624 [HOOVER-DONE] Hoovered 1 new lines (total: 149)
```

**Logs saved to:** `/tmp/monitor-YYYYMMDD-HHMMSS.log`

**Human workflow:**
1. Run monitor script
2. Reproduce the issue
3. Observe patterns/timing/sequences
4. Press Ctrl+C
5. Analyze saved log with other tools (`analyze-gaps.sh`, `analyze-pipeline.sh`)

**LLM workflow:**
1. Generate a custom monitor script in `/tmp/`
2. Tell human: "Please run `/tmp/debug-issue-xyz.sh` while reproducing the issue"
3. After human provides log location, analyze with `analyze-pipeline.sh` or `analyze-gaps.sh`

---

### Pattern 5: Pipeline Analysis (Post-Hoc)

**When to use:**
- Already have captured logs
- Want to re-analyze old logs
- Offline analysis (CI/CD, batch processing)
- Multiple log files to compare

**How it works:**
Analyzes existing log files to identify broken pipeline stages. Same analysis as `monitor-pipeline-check.sh` but doesn't capture logs.

**Usage:**
```bash
# Analyze specific log
./scripts/logging/analyze-pipeline.sh /tmp/pipeline-check-20251108-140637.log

# Analyze most recent
./scripts/logging/analyze-pipeline.sh /tmp/contextify-monitor-*.log

# Batch analysis
for log in /tmp/monitor-2025110*.log; do
    echo "=== Analyzing $log ==="
    ./scripts/logging/analyze-pipeline.sh "$log"
done
```

**Output:**
Same as Pipeline Completeness Check (stage-by-stage analysis, broken stage identification).

**Exit code:** 0 if complete, 1 if broken stages found

---

## Tool Reference

### Monitoring Scripts (Capture Logs)

**monitor-interactive.sh** - Real-time observation
- **Input:** Tags to monitor (optional)
- **Output:** Color-coded stream + saved log file
- **Use:** Exploring, observing, initial investigation

**monitor-automated-test.sh** - Self-validating test
- **Input:** Expectations (edit script)
- **Output:** Pass/fail report
- **Use:** Verifying fixes, regression testing

**monitor-pipeline-check.sh** - Pipeline verification
- **Input:** None (monitors all pipeline stages)
- **Output:** Stage completeness report
- **Use:** Finding broken pipeline stages

### Analysis Scripts (Analyze Logs)

**analyze-gaps.sh** - Find timing delays
- **Input:** Log file path
- **Output:** List of multi-second gaps with context
- **Use:** Performance investigation

**analyze-pipeline.sh** - Find broken stages
- **Input:** Log file path
- **Output:** Stage completeness analysis
- **Use:** Post-hoc pipeline analysis

---

## Critical Gotchas

### 1. Subsystem/Category Must Match

**The predicate in your monitor script MUST exactly match the Logger in your code.**

Example:
```bash
# monitor script:
SUBSYSTEM="dev.contextify.timeline"
CATEGORIES="ConversationMonitor CacheMissGenerator"
```

Must match code:
```swift
private let log = Logger(subsystem: "dev.contextify.timeline", category: "ConversationMonitor")
```

**If they don't match, you'll see NO logs** - this is the #1 debugging issue.

### 2. Every Log Line Must Have Tags

```swift
// WRONG - detail lines filtered out
log.info("[SUMM-QUEUE] Queueing \(count) entries:")
log.info("  - Entry 1...")  // ❌ Filtered by grep

// RIGHT - every line has tag
log.info("[SUMM-QUEUE] Queueing \(count) entries:")
log.info("  [SUMM-QUEUE] Entry 1...")  // ✅ Captured
```

### 3. Privacy Annotations Required

```swift
// WRONG - value redacted as <private>
log.info("[PERF] Completed in \(elapsed)ms")

// RIGHT - value visible
log.info("[PERF] Completed in \(elapsed, privacy: .public)ms")
```

Without `.public`, macOS redacts values and you can't analyze metrics.

### 4. Buffering Issues

```bash
# WRONG - no output until buffer full
log stream | grep "\[TAG\]" | tee file

# RIGHT - real-time output
log stream | grep --line-buffered "\[TAG\]" | tee file
```

Always use `grep --line-buffered` for real-time monitoring.

### 5. Log Levels

```bash
# Script must capture same or lower level than code
# Code: log.debug()
# Script: --level debug ✅
# Script: --level info ❌ (won't see debug logs)
```

---

## Adding Instrumentation

When monitoring reveals missing logs, add structured logging to your code:

### 1. Choose Subsystem

```swift
// Timeline/summarization features:
"dev.contextify.timeline"

// Transcript metadata processing:
"dev.contextify.metadata"

// General app logging:
"dev.contextify"
```

### 2. Add Tagged Logs

```swift
import OSLog

private let log = Logger(subsystem: "dev.contextify.timeline", category: "YourFeature")

// Tag format: [FEATURE-EVENT]
log.info("[FEATURE-START] Starting operation: \(context, privacy: .public)")
log.debug("[FEATURE-STEP] Processing \(count, privacy: .public) items")
log.info("[FEATURE-DONE] Completed in \(elapsed, privacy: .public)s")
```

### 3. Tag Naming Convention

- `FEATURE` = your feature area (e.g., SUMM, BATCH, COORD)
- `EVENT` = specific event (e.g., START, DONE, ERROR)
- Examples: `[HOOVER-START]`, `[TIMELINE-APPEND]`, `[SUMM-QUEUE]`

### 4. Rebuild and Test

```bash
bash scripts/xc.sh build
./scripts/logging/monitor-interactive.sh YOUR-NEW-TAG
# Test feature, observe logs, refine
```

---

## LLM Workflow Recommendations

### When Debugging a Bug

1. **Identify symptom pattern from conversation:**
   - User says: "Messages not appearing" → Pipeline Completeness
   - User says: "App is slow" → Gap Analysis
   - User says: "Does this fix work?" → Automated Test

2. **Try automated approach first:**
   ```bash
   # Generate and run self-validating script
   ./scripts/logging/monitor-pipeline-check.sh
   # or
   ./scripts/logging/monitor-automated-test.sh
   ```

3. **If automated fails to find issue, create interactive monitor:**
   ```bash
   # Create custom monitor in /tmp/
   cat > /tmp/debug-issue-xyz.sh << 'EOF'
   #!/bin/bash
   # [Configured monitor-interactive.sh for specific subsystem]
   EOF
   chmod +x /tmp/debug-issue-xyz.sh
   ```
   Then tell user: "I've created `/tmp/debug-issue-xyz.sh` - please run it while reproducing the issue, then share the log location"

4. **Analyze results:**
   - Pipeline check → identifies broken stage → focus investigation there
   - Automated test → identifies failed expectation → investigate why behavior differs
   - Interactive monitor + analyze-gaps.sh → identifies timing bottleneck

### When Adding a Feature

1. **Add instrumentation first** (before implementation):
   ```swift
   log.info("[NEWFEATURE-START] ...")
   log.info("[NEWFEATURE-DONE] ...")
   ```

2. **Create test expectations**:
   Edit `monitor-automated-test.sh` expectations for the new feature

3. **Test with pipeline check**:
   ```bash
   ./scripts/logging/monitor-pipeline-check.sh
   ```
   Verify new feature integrated into pipeline

---

## Directory Structure

```
scripts/logging/
├── README.md (this file)
│
├── Core Templates:
├── monitor-interactive.sh          Real-time observation
├── monitor-automated-test.sh       Self-validating test harness
├── monitor-pipeline-check.sh       Pipeline stage verification
│
├── Analysis Tools:
├── analyze-gaps.sh                 Find timing delays
├── analyze-pipeline.sh             Post-hoc stage analysis
│
└── examples/
    ├── README.md
    ├── monitor-cache-generation.sh       (reference: LLM/cache monitoring)
    ├── monitor-summarization-flow.sh     (reference: summarization pipeline)
    └── monitor-ui-performance.sh         (reference: UI rendering)
```

**When to use examples:** Only as templates for creating permanent feature-specific monitors. For most debugging, use the core templates.

---

## Related Documentation

- **Logging best practices:** `build/docs/guides/logging-best-practices.md`
- **Log capture guide:** `scripts/LOG-CAPTURE-README.md`
- **Debugging case study:** `build/notes/research/debugging-setup-2025-11-08.md`

---

## Quick Start Examples

**Problem:** "New messages not appearing in timeline"
```bash
./scripts/logging/monitor-pipeline-check.sh
# → Automated report identifies broken stage
```

**Problem:** "Need to verify hoover bug fix"
```bash
# Edit expectations in monitor-automated-test.sh, then:
./scripts/logging/monitor-automated-test.sh
# → Pass/fail report
```

**Problem:** "App feels laggy"
```bash
./scripts/logging/monitor-interactive.sh TIMELINE- UI-
# (reproduce lag, press Ctrl+C)
./scripts/logging/analyze-gaps.sh /tmp/monitor-*.log 1000
# → List of multi-second delays
```

**Problem:** "Exploring unknown issue"
```bash
./scripts/logging/monitor-interactive.sh
# (reproduce issue, observe patterns, press Ctrl+C)
./scripts/logging/analyze-pipeline.sh /tmp/monitor-*.log
# → Stage-by-stage analysis
```

---

**For LLMs:** Default to `monitor-pipeline-check.sh` (pipeline completeness) or `monitor-automated-test.sh` (self-validating). Both generate reports without human interpretation. Fall back to `monitor-interactive.sh` only when automated approaches don't identify the issue.
