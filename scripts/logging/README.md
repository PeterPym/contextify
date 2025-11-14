# Debugging Toolkit for Contextify

**For LLMs:** This is a dispatch table. Match the problem symptom to a debugging pattern, then use the recommended template. Bias toward **automated approaches** that generate reports without human interpretation.

**For Humans:** Choose a pattern based on symptoms, run the script, observe or receive a report.

---

## Quick Dispatch Table

| Problem Symptom | Pattern | Script | Mode | Exit Code |
|----------------|---------|--------|------|-----------|
| Feature not appearing in UI | Pipeline Completeness | `monitor-pipeline-check.sh` | Automated | 0=pass, 1=fail |
| Need to verify bug fix works | Automated Test | `monitor-automated-test.sh` | Automated | 0=pass, 1=fail |
| Verifying fix works with clean DB | Clean DB Test Harness | Custom script (see Pattern 6) | Automated | 0=pass, 1=fail |
| Capture logs for later analysis | Full Pipeline Capture | `monitor-transcript-queues.sh` | Capture-only | - |
| Unexpected tag volume or unknown instrumentation | Tag Exploration | `analyze-tags.sh` | Post-hoc | 0=pass, 1=error |
| Data flows through A but not B | Cross-Component Trace | Tag analysis (see Pattern 7) | Manual | - |
| App slow/laggy, timing issues | Gap Analysis | `monitor-interactive.sh` + `analyze-gaps.sh` | Semi-auto | - |
| Exploring unknown issue | Interactive Monitoring | `monitor-interactive.sh` | Interactive | - |
| Re-analyze captured logs | Pipeline Analysis | `analyze-pipeline.sh` | Post-hoc | 0=pass, 1=fail |

**Default choice for LLMs:** Start with **Pipeline Completeness** or **Automated Test** (self-validating, reports findings).

---

## ⚠️ CRITICAL: Before Using Any Tool

### Subsystem/Category Must Match Code

**The #1 reason debugging tools "don't work" is subsystem mismatch.**

Your log capture predicate MUST exactly match the Logger in your code:

```bash
# ❌ WRONG - Won't capture ConversationMonitor logs
log stream --predicate 'subsystem == "dev.contextify"'
```

```swift
// Code uses different subsystem:
private let log = Logger(subsystem: "dev.contextify.timeline", category: "ConversationMonitor")
```

```bash
# ✅ CORRECT - Captures ConversationMonitor logs
log stream --predicate 'subsystem == "dev.contextify.timeline"'

# ✅ BEST - Captures all Contextify logs regardless of subsystem
log stream --predicate 'subsystem BEGINSWITH "dev.contextify"'
```

**Quick check:** If your monitoring script shows zero logs, the subsystem doesn't match. Check the Logger declaration in the source file you're debugging.

**Common Contextify subsystems:**
- `dev.contextify` - General app logs (most components)
- `dev.contextify.timeline` - ConversationMonitor, TimelineCacheMissGenerator
- `dev.contextify.metadata` - TranscriptMetadataOrchestrator

**Pro tip:** Use `BEGINSWITH` to capture all subsystems in one predicate.

### Capture prerequisite: use monitor-transcript-queues.sh

Before running any analysis script, capture logs with `./scripts/logging/monitor-transcript-queues.sh`.
This restores the "monitor transcript queues" workflow in the diagnostics docset.
It records **all** `dev.contextify*` subsystems (Projects, Watchers, Hoover, Timeline, UI) into
`/tmp/transcript-queue-monitor-*.log`. Post-hoc tools such as `analyze-pipeline.sh` and
`analyze-gaps.sh` expect the log to contain the new instrumentation tags:

- `[FSEVENTS-*]` – watcher lifecycle + heartbeat
- `[DB-UPDATE]` / `[HOOVER-UPDATE-ROWS]` – confirmed database writes
- `[PREFLIGHT-CACHE-*]` – cache hits/misses (for corrupt transcript diagnosis)
- `[TIMELINE-HYDRATE-*]` – ConversationMonitor hydration timing

Example:

```bash
# Capture 45 seconds of complete pipeline logs (all subsystems)
DURATION=45 ./scripts/logging/monitor-transcript-queues.sh

# Then analyze or run gap reports
./scripts/logging/analyze-pipeline.sh /tmp/transcript-queue-monitor-*.log
./scripts/logging/analyze-gaps.sh /tmp/transcript-queue-monitor-*.log 1000
```

The monitor script is safe to run from LLM agents; it defaults to 30 s captures but respects
`DURATION` if you need longer windows when onboarding or reproducing a bug.

---

## Script cheat sheet

| Script | Purpose | Typical use |
|--------|---------|-------------|
| `monitor-transcript-queues.sh` | Capture **all** Contextify subsystems for a fixed window, save to `/tmp/transcript-queue-monitor-*` | Always run this first before `analyze-*` tools |
| `monitor-pipeline-check.sh` | Capture + immediately analyze pipeline stages (uses `[FSEVENTS-*]`, `[DB-UPDATE]`, `[TIMELINE-*]`, `[UIOPT-*]`) | Diagnose "feature not appearing" quickly |
| `analyze-pipeline.sh <log>` | Offline report using a previously captured log | Verify Stage 1–7 activity after test run |
| `analyze-gaps.sh <log> 1000` | Offline gap analysis over captured log | Investigate UI stalls/lurches |
| `analyze-tags.sh <log>` | Discover tag inventory, component breakdowns, START/DONE mismatches | Investigate suspicious tag counts or missing completions |
| `validate-priority-fix.sh <log>` | Check Git latency + CRITICAL gaps | Use after making priority / scheduler changes |

Run `monitor-transcript-queues.sh` whenever you need a ground-truth log; everything else can be
rerun against that file without re-capturing.

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

### Pattern 6: Clean DB Test Harness

**When to use:**
- Verifying a fix works with fresh database state
- Testing first-launch UX flows
- Reproducing bugs that only occur on clean install
- Validating end-to-end feature integration from scratch

**How it works:**
Creates a self-validating test script that: (1) cleans database, (2) launches app, (3) captures logs for N seconds, (4) validates expected log markers appear in correct sequence, (5) reports pass/fail for each feature.

**Key difference from Pattern 2:**
- Pattern 2: Validates expectations on running app
- Pattern 6: Full end-to-end test including DB reset and app launch

**Template:**
```bash
#!/bin/bash
set -euo pipefail

DURATION=45

echo "1. Clean database"
./scripts/db_manager.sh clean --force > /dev/null 2>&1
echo "✓ Done"

# Kill existing app
pkill -9 Contextify 2>/dev/null || true
sleep 1

# Start log capture
LOGFILE="/tmp/test-$(date +%Y%m%d-%H%M%S).log"
log stream --predicate 'subsystem == "dev.contextify"' --level debug > "$LOGFILE" 2>&1 &
LOG_PID=$!

sleep 1
echo "2. Launching app..."
open .derived/Build/Products/Debug/Contextify.app

echo "3. Capturing for ${DURATION}s..."
sleep ${DURATION}

# Stop logging
kill $LOG_PID 2>/dev/null || true

echo ""
echo "=== VALIDATION ==="

# Validate expected markers
PASS=0
FAIL=0

check() {
    local tag="$1"
    local desc="$2"

    if grep -q "$tag" "$LOGFILE" 2>/dev/null; then
        echo "✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "✗ $desc - MISSING TAG: $tag"
        FAIL=$((FAIL + 1))
    fi
}

# Define your feature validations
check "\[BACKEND-INIT\]" "Backend initialized"
check "\[FEATURE-WORKING\]" "Feature works correctly"
check "\[UI-RENDERED\]" "UI rendered expected state"

echo ""
echo "Passed: $PASS / Failed: $FAIL"

if [ $FAIL -eq 0 ]; then
    echo "✅ ALL CHECKS PASSED"
    exit 0
else
    echo "❌ SOME CHECKS FAILED"
    echo "Full log: $LOGFILE"
    exit 1
fi
```

**Real-world example:**
See `/tmp/final-comprehensive-test.sh` - validates 6 features for welcome modal UX:
- State changes (`[PSTATE-INGEST-START]`, `[PSTATE-PROGRESS]`)
- UI rendering (`[WMODAL-BARS]`, `[TIMELINE-LOADING]`)
- Data flow (`[SWITCHER-SORTED]` with contextify in order)

**Output:**
```
=== VALIDATION ===
✓ State: isIngesting set to true
✓ State: discoveryProgress updated
✗ UI: Welcome modal shows progress bars - MISSING TAG: [WMODAL-BARS]
✓ UI: Timeline shows loading indicator
✓ Switcher: Projects sorted
✓ Switcher: Contextify in tab order

Passed: 5 / Failed: 1

❌ SOME CHECKS FAILED
Full log: /tmp/test-20251110-125828.log
```

**When it fails:**
- Shows EXACTLY which features work vs fail
- Provides log file for detailed investigation
- Reproducible (same result every run)

**Next steps:**
- Focus on missing tags → add logging if needed
- Check timing: do tags appear in wrong order?
- Use `grep "MISSING-TAG\|RELATED-TAG" $LOGFILE` to understand context

**Benefits over manual testing:**
- No human interpretation required
- Runs in CI/CD
- Documents expected behavior as code
- Catches regressions immediately

---

### Pattern 7: Cross-Component Data Flow Tracing

**When to use:**
- Feature works in Component A but fails in Component B
- Data successfully enters pipeline but doesn't reach UI
- Need to identify WHERE in multi-component flow data is lost
- Debugging integration issues between modules

**How it works:**
Tag each stage of a data pipeline with unique markers, then trace the flow through logs to find where it breaks.

**Example problem:**
"Project discovery finds contextify first, but tab bar shows it last"

**Solution approach:**

**1. Identify the components:**
```
ProjectDiscoveryService → TranscriptOrchestrator → ProjectSwitcherState → UI
```

**2. Add tags at each stage:**
```swift
// ProjectDiscoveryService.swift
log.info("[DISCOVERY-ORDER] Top 3: contextify, ...")

// TranscriptOrchestrator.swift
log.info("[BACKEND-RESET-DONE] Reset display_order for 15 projects")

// ProjectSwitcherState.swift
log.info("[SWITCHER-SORTED] Tab order: contextify, ...")
```

**3. Trace the flow:**
```bash
grep "DISCOVERY\|BACKEND\|SWITCHER" /tmp/test.log
```

**4. Find the break:**
```
✓ [DISCOVERY-ORDER] Top 3: contextify first       ← Discovery works
✓ [BACKEND-RESET-DONE] Reset 15 projects          ← DB operation works
✗ [SWITCHER-SORTED] Tab order: webviewer first    ← Switcher uses different sort!
```

**Analysis:**
- Data flows correctly through Discovery → Database
- But Switcher sorts differently (SQL vs filesystem)
- **Root cause:** Two components using incompatible sorting methods

**Common patterns:**
```
✓ Stage A → ✗ Stage B   = Missing connection (event not fired, observer not registered)
✓ Stage A → ⏱️ Stage B   = Timing issue (Stage B runs before Stage A completes)
✓ Stage A → ⚠️ Stage B   = Transformation issue (Stage B receives wrong format)
```

**Tag naming for tracing:**
Use format `[COMPONENT-EVENT]` with consistent event names:
```
[DISCOVERY-START] → [DISCOVERY-DONE]
[HOOVER-START] → [HOOVER-DONE]
[SWITCHER-REFRESH] → [SWITCHER-SORTED]
```

**Analysis commands:**
```bash
# Show full pipeline
grep -E "DISCOVERY|BACKEND|SWITCHER" /tmp/test.log | less

# Find first occurrence of each stage
grep "DISCOVERY-" /tmp/test.log | head -1
grep "BACKEND-" /tmp/test.log | head -1
grep "SWITCHER-" /tmp/test.log | head -1

# Check stage ordering
grep -E "DISCOVERY-DONE|SWITCHER-SORTED" /tmp/test.log | cat -n
```

**When to use this pattern:**
- After Pipeline Completeness Check identifies a broken stage
- When data exists in logs but doesn't reach expected destination
- Debugging "it works everywhere except..." problems

---

### Pattern 8: Log Tag Exploration & Frequency Analysis

**When to use:**
- A log capture exists but you don't know which tags fire the most
- Pipeline scripts report suspicious counts (e.g., "why are there 40 SWITCH events?")
- Need to verify START/DONE pairs complete or confirm a component actually fired
- Comparing baseline vs experiment runs to quantify change

**Requirements:** macOS `python3` (ships with Xcode CLT).

**Exit codes:** `0` success, `1` invalid args or missing log.

**How it works:**
`analyze-tags.sh` parses any transcript-queue monitor log, inventories every `[TAG]`, and reports:
- Sorted frequency table plus first/last occurrence for each tag
- Component breakdown (which subsystems produced the most logs)
- START/DONE imbalance detection across tags that follow that pattern
- Optional diff mode to compare two captures

**Usage:**
```bash
# Basic discovery (supports wildcards)
./scripts/logging/analyze-tags.sh /tmp/transcript-queue-monitor-*.log

# Focus on a single component prefix and limit to top tags
./scripts/logging/analyze-tags.sh /tmp/transcript-queue-monitor-*.log \
  --component SWITCH --top 15

# Compare before/after captures to quantify impact
./scripts/logging/analyze-tags.sh before.log --compare after.log
```

**Interpreting the report:**
- **Tag table** → confirms which instrumentation fired, plus first/last timestamps (helpful for sequencing)
- **Top components** → highlights noisy subsystems and validates whether UI/Hoover/Timeline logs exist
- **START/DONE validation** → surfaces incomplete operations; positive Δ = missing completions, negative Δ = unexpected completions
- **Comparison section** (when `--compare` used) → shows per-tag deltas with ↑/↓ markers

**Follow-ups:**
- Use mismatch data to focus on the failing component and correlate with Pattern 7 traces
- If a component is missing entirely, re-run `monitor-transcript-queues.sh` to ensure predicate captured it
- Pair with `analyze-pipeline.sh` to distinguish "pipeline silent" vs "pipeline noisy but wrong tags"
- **LLM reminder:** Whenever new instrumentation tags are added or renamed, update `analyze-tags.sh` so its START/DONE heuristics and component guidance stay current. Read this script before assuming coverage.

**Troubleshooting:**
- "No tags found" → verify the log has `[TAG]` markers (e.g., `grep -c "\[" log`) and that `monitor-transcript-queues.sh` captured `dev.contextify*` subsystems.
- Large positives for WATCH/MONITOR prefixes → these are long-lived resources and are marked "expected"; filter them via `--component` if you need a tighter view.
- Unicode logs are read as UTF-8 with replacement; visible emoji stay intact even if some counts drop.

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

**analyze-tags.sh** - Inventory instrumentation tags
- **Input:** Log file path (supports globs)
- **Output:** Tag frequency table, component breakdown, START/DONE validation, optional diff vs `--compare`
- **Use:** Quantify instrumentation volume, find missing completions, or compare before/after runs
- **Maintenance reminder:** When documentation or code introduces new tags, review and extend this script accordingly so automated discovery keeps pace.

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

**Format:** `[COMPONENT-ACTION]` or `[COMPONENT-STATE]`

**Component naming:**
- Use the module/feature name (e.g., `HOOVER`, `SWITCHER`, `DISCOVERY`, `BACKEND`)
- Be consistent across related logs
- Keep it short (max 12 chars for grep readability)

**Action/State naming:**
- Lifecycle events: `START`, `DONE`, `ERROR`, `CANCEL`
- State snapshots: `SORTED`, `LOADED`, `RENDERED`, `UPDATED`
- Specific operations: `REFRESH`, `INGEST`, `RESET`, `QUERY`

**Examples:**
```swift
// Lifecycle pair (always log both)
log.info("[HOOVER-START] Processing transcript: \(id, privacy: .public)")
log.info("[HOOVER-DONE] Processed \(count) entries in \(elapsed, privacy: .public)ms")

// State snapshot with data
log.info("[SWITCHER-SORTED] Tab order (first 10): \(projectNames, privacy: .public)")

// Operation with result
log.info("[BACKEND-RESET-DONE] Reset display_order for \(count, privacy: .public) projects")
```

**Anti-patterns to avoid:**
```swift
// ❌ Generic tags (not greppable, not specific)
log.info("[DEBUG] Something happened")
log.info("[INFO] Processing...")

// ❌ Tags without data (can't analyze metrics)
log.info("[HOOVER-DONE]")  // Missing: how many? how long?

// ❌ Inconsistent naming
log.info("[HOOVER-START] ...")
log.info("[HooverComplete] ...")  // Use [HOOVER-DONE] instead

// ❌ Too verbose
log.info("[TRANSCRIPT-HOOVER-ENGINE-PROCESSING-START] ...")  // Use [HOOVER-START]
```

**Tags for cross-component tracing:**
When data flows through multiple components, use consistent event names:
```swift
[DISCOVERY-START] → [DISCOVERY-DONE]
[BACKEND-RESET-START] → [BACKEND-RESET-DONE]
[SWITCHER-REFRESH] → [SWITCHER-SORTED]
[TIMELINE-LOADING] → [TIMELINE-LOADED]
```

This makes it easy to grep the full pipeline:
```bash
grep -E "DISCOVERY|BACKEND|SWITCHER|TIMELINE" /tmp/test.log
```

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

## Commit Strategy for Debugging Sessions

**Pattern:** Make atomic commits for each logical step in the debugging process.

### Why This Matters

- **Easy rollback:** If a fix doesn't work, revert just that commit
- **Clear history:** Each commit documents what was tried and why
- **Reproducible:** Other developers can follow the debugging journey
- **CI-friendly:** Each commit can be tested independently

### The Workflow

```bash
# 1. Add logging
# ... add [COMPONENT-*] tags to source ...
git add -A
git commit -m "debug: add [COMPONENT-*] logging tags"

# 2. Run test to see current behavior
./scripts/logging/monitor-pipeline-check.sh
# ... analyze logs, identify root cause ...

# 3. Fix one component
# ... make targeted fix ...
git add -A
git commit -m "fix(component): correct table name bug

Evidence from logs:
- Before: error 'no such table: entries'
- After: [COMPONENT-DONE] processed 15 items ✓"

# 4. Verify fix works
./scripts/logging/monitor-pipeline-check.sh
# ... test passes ...

# 5. Repeat for next issue
```

### Commit Message Format

**For logging additions:**
```
debug(component): add [TAG-*] instrumentation for debugging

- Add [TAG-START] / [TAG-DONE] lifecycle events
- Add [TAG-STATE] snapshots with data
- Add [TAG-ERROR] for error paths
```

**For fixes:**
```
fix(component): brief description of what was fixed

Root cause: <what was wrong>

Evidence from logs:
- Before: <log showing broken behavior>
- After: <log showing fixed behavior>

Test: <how to reproduce/verify>
```

### Example Session

Real debugging session for tab order issue:

```bash
# Commit 1: Add logging
git commit -m "debug(welcome-modal): add comprehensive OSLog instrumentation

Add [BACKEND-*], [SWITCHER-*], [DISCOVERY-*] tags to trace
project sorting pipeline."

# Commit 2: Fix table name
git commit -m "fix(database): correct table name 'entries' → 'transcript_entries'

Root cause: SQL queries referenced non-existent table

Evidence:
- Before: error 'no such table: entries'
- After: [SWITCHER-SORT-QUERY] Got 15 projects from DB ✓"

# Commit 3: Fix timing
git commit -m "fix(startup): reset display_order AFTER ingestion, not before

Root cause: resetDisplayOrder() ran before projects existed

Evidence:
- Before: [BACKEND-RESET-DONE] Reset 0 projects
- After: [BACKEND-RESET-DONE] Reset 15 projects ✓"

# Commit 4: Fix sorting
git commit -m "feat(discovery): sort projects by newest transcript mtime

Evidence:
- [DISCOVERY-ORDER] contextify (mtime: 2025-11-10 21:10:58) first ✓
- [SWITCHER-SORTED] /Users/rob/code/projects/contextify first ✓"
```

### Benefits

**For debugging:**
- Each commit has clear before/after evidence
- Can bisect to find which commit fixed the issue
- Easy to share "what I tried" with team

**For code review:**
- Reviewer sees logical progression
- Each fix is independently reviewable
- Clear rationale for each change

**For future debugging:**
- Git history becomes a debugging tutorial
- "How was this fixed last time?"
- Commit messages document root causes

### Anti-Patterns

```bash
# ❌ Batch commit at end
git commit -m "fix everything"
# → Can't isolate what fixed what

# ❌ No evidence in commit message
git commit -m "fix sorting"
# → No proof it works, hard to understand later

# ❌ Mixed concerns
git commit -m "fix sorting and add logging and refactor"
# → Can't revert just one change
```

### For LLMs

**After each fix:**
1. Test with automated script
2. Extract evidence from logs
3. Commit with evidence in message
4. Move to next issue

**Do NOT:**
- Wait until all fixes done to commit
- Commit without testing
- Skip commit messages (they document the fix!)

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
