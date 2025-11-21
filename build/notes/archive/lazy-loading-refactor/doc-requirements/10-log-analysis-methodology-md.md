# Change Requirements: build/docs/guides/log-analysis-methodology.md

**Document:** `build/docs/guides/log-analysis-methodology.md`
**Priority:** 3 (User Guides)
**Impact:** Low - Log analysis guide
**Estimated Effort:** 1-2 hours

---

## Current State Analysis

**File:** Comprehensive log analysis methodology
**Current Content:**
- General log analysis strategies
- Category patterns
- Performance analysis
- Error tracking

**Issues:**
1. No AppStateOrchestrator log categories
2. No LightweightDiscoveryService patterns
3. Missing [ORCH-*] and [DISC-LIGHT] prefixes
4. Performance analysis doesn't cover Phase 3 targets

---

## Required Changes

### 1. Add Phase 3 Log Categories Section

**Location:** Insert in log categories section

**Content:**

```markdown
## Phase 3 Log Categories (Nov 2025)

### AppStateOrchestrator

**Category:** `AppOrchestrator`
**Subsystem:** `dev.contextify`

**Prefixes:**
- `[ORCH-STARTUP]` - Startup flow
- `[ORCH-SELECT]` - Project selection (JIT ingestion)
- `[ORCH-BACKGROUND]` - Background indexing
- `[ORCH-STATE]` - State machine transitions

**Example Logs:**
```
2025-11-19 10:23:45.123 [ORCH-STARTUP] Beginning lightweight startup...
2025-11-19 10:23:45.156 [ORCH-STARTUP] Discovered 19 projects
2025-11-19 10:23:45.187 [ORCH-STARTUP] Startup complete in 0.187s. UI ready.
2025-11-19 10:23:46.034 [ORCH-SELECT] User selected project: ABC123
2025-11-19 10:23:46.891 [ORCH-SELECT] Project ready in 0.856s
2025-11-19 10:24:12.445 [ORCH-BACKGROUND] Starting background indexing...
```

**What to Look For:**
- Startup duration (target: <200ms)
- JIT ingestion duration (target: <1s)
- Background indexing progress
- State transition sequence

---

### LightweightDiscoveryService

**Category:** `LightweightDiscovery`
**Subsystem:** `dev.contextify`

**Prefixes:**
- `[DISC-LIGHT]` - Stat-only scanning

**Example Logs:**
```
2025-11-19 10:23:45.130 [DISC-LIGHT] Starting lightweight scan...
2025-11-19 10:23:45.145 [DISC-LIGHT] Found 663 Codex transcripts
2025-11-19 10:23:45.156 [DISC-LIGHT] Scan complete in 0.143s. Found 19 projects.
```

**What to Look For:**
- Scan duration (target: <200ms)
- Project count (should match filesystem)
- File count (Codex transcripts)

---

### State Machine Transitions

**Category:** `AppOrchestrator`
**Prefix:** `[ORCH-STATE]`

**Example Sequence (Successful Startup):**
```
[ORCH-STATE] State changed to: discovering
[ORCH-STATE] State changed to: idle(projects: [count=19])
[ORCH-STATE] State changed to: loading(projectId: "ABC123")
[ORCH-STATE] State changed to: active(projectId: "ABC123")
```

**Valid Patterns:**
```
startup → discovering → idle → loading → active  (successful)
startup → discovering → idle → error             (discovery error)
idle → loading → error                           (JIT error)
active → loading → active                        (project switch)
```

**Invalid Patterns (bugs):**
```
startup → loading                                (skipped discovery)
loading → idle                                   (failed without error)
discovering → active                             (skipped idle)
```

---
```

**Estimated Effort:** 30 minutes

---

### 2. Update Performance Analysis Section

**Add Phase 3 Targets:**

```markdown
## Performance Analysis (Phase 3 Targets)

### Startup Performance

**Target:** <200ms from launch to UI ready

**Log Pattern:**
```bash
# Extract startup duration
grep "ORCH-STARTUP.*complete" ~/Library/Logs/Contextify/app.log | \
  awk -F'in ' '{print $2}' | \
  awk -F's' '{print $1}'

# Expected: 0.143-0.200 (seconds)
```

**Analysis:**
```bash
# Breakdown by phase
grep "DISC-LIGHT.*complete" app.log  # Discovery time
grep "ORCH-STARTUP.*complete" app.log  # Total time

# If >200ms, check:
# - File count (too many transcripts?)
# - Filesystem (network drive?)
# - CPU load (other processes?)
```

**Regression Detection:**
```bash
# Compare across runs
grep "ORCH-STARTUP.*complete" app.log | \
  awk -F'in ' '{print $2}' | \
  awk -F's' '{print $1}' | \
  awk '{sum+=$1; count++} END {print "Average:", sum/count "s"}'

# If average >0.250s, investigate regression
```

---

### JIT Ingestion Performance

**Target:** <1s per project

**Log Pattern:**
```bash
# Extract JIT durations
grep "ORCH-SELECT.*ready" ~/Library/Logs/Contextify/app.log | \
  awk -F'in ' '{print $2}' | \
  awk -F's' '{print $1}'

# Expected: 0.500-1.000 (seconds) for typical projects
```

**Analysis:**
```bash
# Identify slow projects
grep "ORCH-SELECT" app.log | \
  grep "ready in" | \
  awk '{print $(NF-1), $(NF-5)}' | \
  sort -rn | \
  head -10

# Shows: duration, project name
# Investigate projects >2s
```

---

### Memory Footprint

**Target:** 30-50 MB at startup, 60-100 MB after first load

**Log Pattern:**
```bash
# Memory logs (if instrumented)
grep "Memory" app.log

# Use Instruments for accurate measurement:
# Instruments -> Allocations -> Contextify.app
```

**Analysis:**
- Startup baseline: Should be ~30-50 MB
- Per project overhead: ~10-20 MB (depending on size)
- Steady state: 80-150 MB (3-5 projects loaded)
- If >200 MB: Potential memory leak

---

### Background Indexing

**Target:** All projects indexed within 5 minutes (idle)

**Log Pattern:**
```bash
# Track background progress
grep "ORCH-BACKGROUND" app.log | \
  grep -E "(Starting|Ingested|complete)"

# Example output:
# [ORCH-BACKGROUND] Starting background indexing...
# [ORCH-BACKGROUND] Ingested project: project1
# [ORCH-BACKGROUND] Ingested project: project2
# ...
# [ORCH-BACKGROUND] Background indexing complete
```

**Analysis:**
```bash
# Count ingested projects
grep "ORCH-BACKGROUND.*Ingested" app.log | wc -l

# Check for cancellations
grep "ORCH-BACKGROUND.*cancel" app.log

# If not completing:
# - Check for user interaction (cancels background work)
# - Check for errors on specific projects
```

---
```

**Estimated Effort:** 45 minutes

---

### 3. Add State Transition Log Examples

**Location:** In examples section

**Content:**

```markdown
## State Transition Log Examples (Phase 3)

### Normal Startup Flow

```
10:23:45.089 [ORCH-STARTUP] Beginning lightweight startup...
10:23:45.092 [ORCH-STATE] State changed to: discovering
10:23:45.130 [DISC-LIGHT] Starting lightweight scan...
10:23:45.145 [DISC-LIGHT] Found 663 Codex transcripts
10:23:45.156 [DISC-LIGHT] Scan complete in 0.143s. Found 19 projects.
10:23:45.162 [ORCH-STARTUP] Discovered 19 projects
10:23:45.180 [ORCH-STARTUP] Updated projects table metadata
10:23:45.185 [ORCH-STATE] State changed to: idle(projects: [count=19])
10:23:45.187 [ORCH-STARTUP] Startup complete in 0.187s. UI ready.
10:23:45.190 [ORCH-STARTUP] Auto-selecting most recent project: ABC123
10:23:45.192 [ORCH-SELECT] User selected project: ABC123
```

**Duration Breakdown:**
- App init to discovering: 3ms
- Discovery scan: 143ms
- Metadata update: 24ms
- State transition: 7ms
- **Total: 187ms** ✅ (under 200ms target)

---

### Normal JIT Ingestion Flow

```
10:23:46.034 [ORCH-SELECT] User selected project: ABC123
10:23:46.038 [ORCH-SELECT] Cancel background work
10:23:46.042 [ORCH-STATE] State changed to: loading(projectId: "ABC123")
10:23:46.125 [HooverEngine] Processing batch 1/5 (1000 lines)
10:23:46.287 [HooverEngine] Processing batch 2/5 (1000 lines)
10:23:46.445 [HooverEngine] Processing batch 3/5 (1000 lines)
10:23:46.603 [HooverEngine] Processing batch 4/5 (1000 lines)
10:23:46.761 [HooverEngine] Processing batch 5/5 (856 lines)
10:23:46.825 [ORCH-SELECT] JIT ingestion complete, DB project ID: ABC123
10:23:46.867 [ORCH-SELECT] StartupCoordinator notified with path: /path/to/repo
10:23:46.889 [ORCH-STATE] State changed to: active(projectId: "ABC123")
10:23:46.891 [ORCH-SELECT] Project ready in 0.856s
```

**Duration Breakdown:**
- State transition: 8ms
- JSONL parsing: 736ms (5 batches × ~150ms)
- DB writes: 64ms
- Legacy notification: 42ms
- State transition: 22ms
- **Total: 856ms** ✅ (under 1s target)

---

### Error: JIT Ingestion Failure

```
10:25:12.456 [ORCH-SELECT] User selected project: DEF456
10:25:12.460 [ORCH-STATE] State changed to: loading(projectId: "DEF456")
10:25:12.523 [HooverEngine] Processing batch 1/3 (1000 lines)
10:25:12.678 [HooverEngine] Parse error at line 523: unexpected tool_use_id
10:25:12.680 [ORCH-SELECT] Failed to load project: Parse error at line 523
10:25:12.682 [ORCH-STATE] State changed to: error("Failed to load project: Parse error")
```

**What Happened:**
- Corrupt JSONL at line 523
- HooverEngine threw parse error
- AppStateOrchestrator caught error
- Transitioned to error state
- User sees error message in UI

**Fix:** Repair transcript (see `transcript-corruption-detection.md`)

---
```

**Estimated Effort:** 30 minutes

---

### 4. Add grep Patterns Section

**Location:** After examples

**Content:**

```markdown
## Useful grep Patterns (Phase 3)

### Track Startup Performance

```bash
# Show all startup times from logs
grep "ORCH-STARTUP.*complete" app.log | \
  awk -F'in ' '{print $2}' | \
  awk -F's' '{print $1}' | \
  sort -n

# Identify slow startups (>200ms)
grep "ORCH-STARTUP.*complete" app.log | \
  awk -F'in ' '{print $0}' | \
  awk '$NF > 0.200'
```

### Monitor State Machine

```bash
# Extract state transition sequence
grep "ORCH-STATE" app.log | \
  awk '{print $1, $2, $NF}' | \
  uniq

# Find invalid transitions (loading without resolution)
grep "ORCH-STATE.*loading" app.log | wc -l
grep -E "ORCH-STATE.*(active|error)" app.log | wc -l
# Counts should match
```

### Analyze JIT Performance

```bash
# Average JIT duration
grep "ORCH-SELECT.*ready" app.log | \
  awk -F'in ' '{print $2}' | \
  awk -F's' '{print $1}' | \
  awk '{sum+=$1; count++} END {print "Avg:", sum/count "s"}'

# Find slow projects
grep "ORCH-SELECT" app.log | \
  grep "ready in" | \
  awk '{print $(NF-1), $(NF-5)}' | \
  sort -rn | \
  head -5
```

### Track Background Indexing

```bash
# Show indexing timeline
grep "ORCH-BACKGROUND" app.log | \
  grep -v "Ingested" | \
  awk '{print $1, $2, $NF}'

# Count indexed projects
grep "ORCH-BACKGROUND.*Ingested" app.log | wc -l

# Check for premature cancellation
grep "ORCH-BACKGROUND.*cancel" app.log
```

---
```

**Estimated Effort:** 15 minutes

---

## Summary of Changes

1. **Add:** Phase 3 log categories section (~80 lines)
2. **Update:** Performance analysis (Phase 3 targets) (~100 lines)
3. **Add:** State transition log examples (~120 lines)
4. **Add:** grep patterns section (~50 lines)

**Total Lines Added/Modified:** ~350 lines
**Estimated Effort:** 1-2 hours

---

## Validation Checklist

After making changes, verify:

- [ ] Log prefixes accurate ([ORCH-*, [DISC-LIGHT])
- [ ] Example logs tested against actual output
- [ ] Performance targets validated
- [ ] grep commands tested and working
- [ ] State transition sequences accurate
- [ ] Duration breakdowns correct
- [ ] Cross-references resolve

---

**Document Version:** 1.0
**Created:** 2025-11-19
**Implements:** Phase 3 documentation update item #10
