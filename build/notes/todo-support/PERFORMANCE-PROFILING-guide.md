---
todo_id: PERFORMANCE-PROFILING
title: Performance Profiling Guide
type: reference
date: 2025-12-10
status: active
description: Comprehensive guide to profiling Contextify using Xcode Instruments, xctrace CLI, and automated performance testing.
---

# Performance Profiling Guide

This document covers tools and techniques for profiling Contextify's performance, with specific focus on the issues identified in log analysis (timeline refresh spam, watcher loops, discovery delays).

## Quick Reference

| Tool | Use Case | Command |
|------|----------|---------|
| Time Profiler | CPU hotspots | `xctrace record --template 'Time Profiler'` |
| Energy Log | Battery drain | `xctrace record --template 'Energy Log'` |
| Allocations | Memory leaks | `xctrace record --template 'Allocations'` |
| XCTest measure | Automated benchmarks | `swift test --filter Performance` |

---

## 1. xctrace CLI (Instruments from Terminal)

### Basic Usage

```bash
# List available templates
xctrace list templates

# Profile app launch for 60 seconds
xctrace record \
  --template 'Time Profiler' \
  --launch .derived/Build/Products/Debug/Contextify.app \
  --time-limit 60s \
  --output build/profiles/profile.trace

# Attach to running app
xctrace record \
  --template 'Time Profiler' \
  --attach "Contextify" \
  --time-limit 30s \
  --output build/profiles/profile.trace

# Open trace in Instruments
open build/profiles/profile.trace
```

### Templates for Common Issues

**CPU/Performance:**
```bash
xctrace record --template 'Time Profiler' --attach "Contextify" --time-limit 60s
```

**Battery/Energy:**
```bash
xctrace record --template 'Energy Log' --attach "Contextify" --time-limit 120s
```

**Memory:**
```bash
xctrace record --template 'Allocations' --attach "Contextify" --time-limit 60s
```

**Threading/Concurrency:**
```bash
xctrace record --template 'System Trace' --attach "Contextify" --time-limit 30s
```

### Automation Script

Create `scripts/profile.sh`:

```bash
#!/bin/bash
# Usage: ./scripts/profile.sh [template] [duration]
# Example: ./scripts/profile.sh "Time Profiler" 60

TEMPLATE="${1:-Time Profiler}"
DURATION="${2:-60}"
APP_PATH=".derived/Build/Products/Debug/Contextify.app"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT="build/profiles/${TIMESTAMP}-$(echo $TEMPLATE | tr ' ' '-').trace"

mkdir -p build/profiles

# Build if app doesn't exist
if [ ! -d "$APP_PATH" ]; then
    echo "Building app..."
    bash scripts/xc.sh build
fi

echo "Profiling with '$TEMPLATE' for ${DURATION}s..."
xctrace record \
  --template "$TEMPLATE" \
  --launch "$APP_PATH" \
  --time-limit "${DURATION}s" \
  --output "$OUTPUT"

echo ""
echo "Trace saved: $OUTPUT"
echo "Open with: open '$OUTPUT'"
```

---

## 2. os_signpost Instrumentation

Add custom markers to code that appear in Instruments' Points of Interest.

### Setup

```swift
import os

// Create signposter for a subsystem
private let signposter = OSSignposter(subsystem: "dev.contextify", category: "Performance")
```

### Marking Intervals

```swift
func loadFeedFromSQL() async {
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("loadFeed", id: signpostID)
    defer { signposter.endInterval("loadFeed", state) }

    // ... existing code
}
```

### Marking Events

```swift
func handleNotification(_ notification: Notification) {
    signposter.emitEvent("notification", "\(notification.name)")
    // ... existing code
}
```

### Recommended Instrumentation Points

For the current performance issues, add signposts to:

**Timeline Refresh (ConversationMonitor.swift):**
```swift
// Around line 1388-1410
private let timelineSignposter = OSSignposter(subsystem: "dev.contextify", category: "Timeline")

func loadFeedFromSQL() async {
    let id = timelineSignposter.makeSignpostID()
    let state = timelineSignposter.beginInterval("loadFeedFromSQL", id: id)
    defer { timelineSignposter.endInterval("loadFeedFromSQL", state) }
    // ...
}

func handleTimelineNotification() {
    timelineSignposter.emitEvent("refresh-trigger", "notification received")
    // ...
}
```

**Watcher Recovery (ConversationMonitor.swift):**
```swift
private let watcherSignposter = OSSignposter(subsystem: "dev.contextify", category: "Watchers")

func attemptWatcherRecovery(for transcript: TranscriptInfo) async {
    let id = watcherSignposter.makeSignpostID()
    let state = watcherSignposter.beginInterval("recovery", id: id, "\(transcript.id)")
    defer { watcherSignposter.endInterval("recovery", state) }
    // ...
}
```

**Discovery Scans (LightweightDiscovery.swift):**
```swift
private let discoverySignposter = OSSignposter(subsystem: "dev.contextify", category: "Discovery")

func performScan() async {
    let id = discoverySignposter.makeSignpostID()
    let state = discoverySignposter.beginInterval("scan", id: id)
    defer { discoverySignposter.endInterval("scan", state) }
    // ...
}
```

### Viewing Signposts

1. Profile with any Instruments template
2. Add "Points of Interest" instrument to the trace
3. Signposts appear as intervals/events on the timeline

---

## 3. XCTest Performance Tests

### Basic Measure Block

```swift
// Tests/ContextifyCoreTests/PerformanceTests.swift

import XCTest
@testable import ContextifyCore

final class PerformanceTests: XCTestCase {

    func testTimelineRefreshPerformance() {
        measure {
            // Code to benchmark
        }
    }
}
```

### With Metrics

```swift
func testTimelineRefreshPerformance() {
    let metrics: [XCTMetric] = [
        XCTCPUMetric(),
        XCTMemoryMetric(),
        XCTClockMetric()
    ]

    measure(metrics: metrics) {
        // Code to benchmark
    }
}
```

### Setting Baselines

After running a test, Xcode shows a baseline button. Click to set expected values. Future runs compare against baseline and fail if regression exceeds threshold.

### Running Performance Tests

```bash
# Run all performance tests
swift test --filter Performance

# Run specific test
swift test --filter testTimelineRefreshPerformance

# With verbose output
swift test --filter Performance -v
```

### Example Test Suite

```swift
final class PerformanceTests: XCTestCase {

    // MARK: - Timeline Performance

    func testTimelineLoadPerformance() {
        // Setup: Create mock database with 1000 entries
        let db = TestDatabase.withEntries(1000)
        let orchestrator = TranscriptOrchestrator(database: db)

        measure(metrics: [XCTCPUMetric(), XCTClockMetric()]) {
            _ = try? orchestrator.getEntriesForProject("test-project", limit: 100)
        }
    }

    func testRapidRefreshHandling() {
        let monitor = ConversationMonitor()

        measure {
            // Simulate rapid refresh requests (the problem scenario)
            for _ in 0..<100 {
                monitor.requestTimelineRefresh()
            }
            // Allow debounce to settle
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    // MARK: - Discovery Performance

    func testDiscoveryScanPerformance() {
        measure(metrics: [XCTCPUMetric(), XCTClockMetric()]) {
            // Scan with varying project counts
            // Baseline: 10 projects should complete < 500ms
        }
    }

    // MARK: - LLM Processing

    func testSummarizationQueueThroughput() {
        measure {
            // Process batch of 50 entries
            // Baseline: Should complete < 5s with mock LLM
        }
    }
}
```

---

## 4. Profiling Workflow

### For Timeline Refresh Spam

1. Add signposts around `loadFeedFromSQL()` and notification handlers
2. Build: `bash scripts/xc.sh build`
3. Launch app, switch between projects rapidly
4. Profile: `xctrace record --template 'Time Profiler' --attach Contextify --time-limit 30s`
5. Open trace, check Points of Interest for refresh frequency
6. Verify debounce fix reduces calls from N to 1 per interaction

### For Watcher Recovery Loop

1. Add signposts around watcher health check and recovery
2. Profile with Energy Log template (longer duration)
3. Look for repeated recovery intervals for same transcript
4. Verify exponential backoff prevents infinite retries

### For Memory Leaks

1. Profile: `xctrace record --template 'Leaks' --attach Contextify --time-limit 120s`
2. Use app normally, switch projects, scroll timeline
3. Check for persistent growth or leaked objects
4. Common culprits: uncancelled Tasks, strong reference cycles in closures

---

## 5. Interpreting Results

### Time Profiler

- **Self Weight %**: Time spent in function itself (not children)
- **Weight %**: Total time including child calls
- Look for unexpected hotspots in our code vs system frameworks

### Energy Log

- **CPU Usage**: Should be near 0% when idle
- **Network**: Spike during LLM calls, then quiet
- **Disk**: Spike during DB writes, then quiet

### Common Issues

| Symptom | Likely Cause | Investigation |
|---------|--------------|---------------|
| CPU never idles | Infinite loop, polling | Time Profiler - find hotspot |
| Memory grows forever | Leak or unbounded cache | Allocations - track persistent objects |
| Battery drain | Background work | Energy Log - find non-idle periods |
| UI jank | Main thread blocking | System Trace - check main thread |

---

## 6. CI Integration (Future)

For automated performance regression detection:

```yaml
# .github/workflows/performance.yml
name: Performance Tests
on:
  pull_request:
    paths: ['app/**', 'Contextify/**']

jobs:
  benchmark:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Run performance tests
        run: swift test --filter Performance
      - name: Compare to baseline
        run: ./scripts/compare-performance.sh
```

---

## 7. Known Performance Issues (Dec 2025)

| Issue | Impact | Root Cause | Fix |
|-------|--------|------------|-----|
| Timeline refresh spam | UI lag, CPU | Multiple notifications trigger redundant refreshes | Debounce with 100ms window |
| Codex watcher loop | Battery drain | Recovery retries every 30s without backoff | Check security scope + exponential backoff |
| Slow discovery | Delayed project detection | 14-29s scan intervals vs expected 5s | Review timer configuration |
| getCWD failures | Missing project names | Codex nests CWD in payload | Check both paths |

---

## References

- [Instruments Help](https://help.apple.com/instruments/mac/current/)
- [xctrace man page](https://keith.github.io/xcode-man-pages/xctrace.1.html)
- [WWDC 2019: Getting Started with Instruments](https://developer.apple.com/videos/play/wwdc2019/411/)
- [WWDC 2021: Detect and diagnose memory issues](https://developer.apple.com/videos/play/wwdc2021/10180/)
