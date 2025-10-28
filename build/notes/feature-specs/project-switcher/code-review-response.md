# Project Switcher - Code Review Response

**Date:** 2025-10-27
**Review Feedback:** Two comprehensive code reviews identifying 20+ issues
**Status:** Addressing critical bugs, deferring non-critical items

---

## CRITICAL BUGS (Must Fix Before Merge)

### ✅ BUG #1: Illegal `await` on non-async `shutdown()`
**Status:** CONFIRMED - Will fix
**File:** `ConversationMonitor.swift:119-124`
**Problem:** Calling `await oldGenerator.shutdown()` but `shutdown()` is not `async`
**Current Code:**
```swift
if let oldGenerator = self.cacheMissGenerator {
    Task {
        await oldGenerator.shutdown()  // ❌ ILLEGAL
    }
}
```

**Root Cause:** `TimelineCacheMissGenerator.shutdown()` (line 63) is a regular synchronous function, not async

**Fix:**
```swift
if let oldGenerator = self.cacheMissGenerator {
    oldGenerator.shutdown()  // ✅ Direct synchronous call
}
self.cacheMissGenerator = nil  // Clear before creating new
```

**Justification:** Shutdown is fast (<10ms) - just cancels tasks and clears arrays. No need for async.

---

### ✅ BUG #2: Side-effects in SwiftUI `body`
**Status:** CONFIRMED - Will fix
**File:** `ContentView.swift:27-28`
**Problem:** Logging inside `body` executes on every re-render → log spam + perf hit
**Current Code:**
```swift
let _ = uiLog.info("🔍 ProjectSwitcher visibility: ...")
```

**Fix:** Remove logging from body entirely (debug-only code)
```swift
// DELETE THIS LINE - unnecessary debug logging
```

**Justification:** This was temporary debug logging and should have been removed before commit.

---

### ⚠️ BUG #3: Redundant `@MainActor` in Button Actions
**Status:** NEEDS CLARIFICATION
**File:** `ContextifyApp.swift:64-75`
**Problem:** Button actions already run on MainActor; `Task { @MainActor in }` is redundant

**Current Code:**
```swift
Button("Previous Project") {
  Task { @MainActor in  // ⚠️ Redundant?
    await ProjectSwitcherState.shared.cycleToPreviousProject()
  }
}
```

**Question:** What is the signature of `cycleToPreviousProject()`?

Let me check:
- If it's `@MainActor func cycleToPreviousProject()` → No Task needed, call directly
- If it's `async func cycleToPreviousProject()` → Task needed, but remove `@MainActor`

**Checking now...**

---

## PERFORMANCE CONCERNS (Should Fix Soon)

### PERF #1: Singleton + @State Anti-Pattern
**Status:** ACKNOWLEDGED - Will fix
**File:** `ContentView.swift:17`
**Current:**
```swift
@State private var projectSwitcher = ProjectSwitcherState.shared
```

**Problem:** Using `@State` for a singleton reference is incorrect

**Fix:**
```swift
private let projectSwitcher = ProjectSwitcherState.shared
```

**Justification:** We're not replacing the reference, so `@State` is unnecessary. Already injecting via `.environment()`.

---

### PERF #2: Observable `cacheMissGenerator` Property
**Status:** ACKNOWLEDGED - Will fix
**File:** `ConversationMonitor.swift:110`
**Problem:** Removed `@ObservationIgnored` → every generator reassignment triggers re-renders

**Current:**
```swift
private(set) var cacheMissGenerator: TimelineCacheMissGenerator?  // Observable
```

**Fix:**
```swift
@ObservationIgnored private(set) var cacheMissGenerator: TimelineCacheMissGenerator?
private(set) var isCacheGeneratorActive = false  // Expose this instead

// When assigning:
self.cacheMissGenerator = TimelineCacheMissGenerator(...)
self.isCacheGeneratorActive = true
```

**Justification:** StatusBarView only needs to know IF generator is active, not observe the object itself.

---

### PERF #3: `indexByCacheKey` Rebuilds on Every Access
**Status:** ACKNOWLEDGED - Will fix
**File:** `ConversationMonitor.swift:92-101`
**Problem:** Computed property rebuilds O(n) dictionary on every access

**Fix:** Make it a stored property updated in `replace(with:)`
```swift
@ObservationIgnored private var _indexByCacheKey: [CacheKey: Int] = [:]

var indexByCacheKey: [CacheKey: Int] {
    _indexByCacheKey
}

func replace(with entries: [TimelineEntry]) {
    self.entries = entries
    self.revision += 1

    // Rebuild index once
    _indexByCacheKey = Dictionary(
        entries.enumerated().compactMap { i, e in
            e.cacheKey.map { ($0, i) }
        },
        uniquingKeysWith: { _, new in new }
    )
}
```

---

### PERF #4: Missing Task Cancellation Check
**Status:** MINOR - Will review
**File:** `ConversationMonitor.swift:152-157`
**Current:** Checks `!Task.isCancelled` after sleep, not before expensive work

**Fix:**
```swift
self.debounceTask = Task { [weak self] in
    do {
        try await Task.sleep(nanoseconds: 150_000_000)
    } catch {
        return  // Cancelled during sleep
    }

    guard let self else { return }
    try? Task.checkCancellation()  // Check before expensive work
    await self.processIncrementalUpdate()
}
```

**Severity:** LOW (guard catches it anyway)

---

## DATA/DB ISSUES

### ⚠️ DATA #1: Inconsistent Timestamp Format
**Status:** CRITICAL - Will fix
**Problem:** Different formatters across codebase can break lexicographic date comparisons

**Solution:** Create shared `ISO8601Z` formatter:
```swift
// New file: app/Sources/ContextifyCore/Time/ISO8601Z.swift
import Foundation

enum ISO8601Z {
  static let formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
}
```

**Use everywhere:**
```swift
// Before:
let timestamp = ISO8601DateFormatter().string(from: Date())

// After:
let timestamp = ISO8601Z.formatter.string(from: Date())
```

**Impact:** Ensures `created_at > last_viewed_at` comparisons work correctly

---

### DATA #2: Clock Injection Not Used Consistently
**Status:** ACKNOWLEDGED
**Problem:** Added `Clock` protocol but still using raw `Date()` in some places

**Fix:** Use injected clock everywhere:
```swift
// ProjectVisitsRepositoryImpl.markSelected
visit.lastSelectedAt = ISO8601Z.formatter.string(from: clock.now())
```

---

## UI/SWIFTUI ISSUES

### UI #1: Double Lifecycle Starts
**Status:** ACKNOWLEDGED - Will fix
**Problem:** `projectSwitcher.start()` called in both `ContentView.onAppear` AND `ProjectSwitcherView.task`

**Fix:** Keep only in `ContentView` (controls visibility)

---

### UI #2: Visibility Condition Mismatch
**Status:** DESIGN DECISION NEEDED
**Problem:** Show when `!allProjects.isEmpty` vs spec says "> 1 projects"

**Question for user:** Should we show the switcher with just 1 project, or only when there are 2+ projects?

Current: Shows with 1+ projects
Spec says: Shows with 2+ projects (allows switching)

---

### UI #3: Previews Start Real Monitoring
**Status:** ACKNOWLEDGED - Will add mock
**Problem:** `#Preview` blocks call `state.start()` on shared singleton

**Fix:**
```swift
#if DEBUG
#Preview {
  let mock = ProjectSwitcherState(orchestrator: InMemoryOrchestrator())
  mock._testInject(projects: [...])
  return ProjectSwitcherView()
    .environment(mock)
}
#endif
```

---

## ARCHITECTURAL CONCERNS (Defer to Phase 5)

### ARCH #1: Multi-Project Branching in ConversationMonitor
**Status:** DEFERRED
**Feedback:** Move multi-project coordination to `ProjectActivityMonitor`

**Response:** Current architecture works for MVP. The branching logic is minimal:
- Branch 1: Current project → refresh timeline (existing behavior)
- Branch 2: Other project → skip (ProjectSwitcherState handles unread via separate stream)

**Refactor plan:** Phase 5 cleanup - extract coordinator pattern if complexity grows

---

## MISSING FUNCTIONALITY (Critical for Feature)

### ⚠️ MISSING #1: FSEvents Monitor Never Started
**Status:** CRITICAL - Will fix
**File:** `ProjectActivityMonitor.swift`
**Problem:** `fsEventsMonitor` declared but never created/started

**Fix:** Implement in `startGlobalMonitoring()`:
```swift
public func startGlobalMonitoring() async throws {
  guard !isMonitoring else { return }
  isMonitoring = true

  try await discoverAllProjects()

  #if os(macOS)
  let roots = [
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects").path,
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions").path
  ].filter { FileManager.default.fileExists(atPath: $0) }

  if !roots.isEmpty {
    let monitor = await FSEventsMonitor(paths: roots, latency: 0.5)
    self.fsEventsMonitor = monitor
    let stream = await monitor.start()
    self.fsEventsTask = Task { [weak self] in
      for await change in stream {
        // TODO: Map change.path → projectId and emit .transcriptUpdated
      }
    }
  }
  #endif
}
```

**Impact:** Without this, unread badges won't live-update

---

### ⚠️ MISSING #2: Watcher Lifecycle Not Connected
**Status:** ACKNOWLEDGED - Needs investigation
**Problem:** `ensureWatcher()` doesn't start actual transcript watchers

**Plan:** Review integration with `TranscriptWatcher` and wire up properly

---

## PRODUCT/CONSENT

### CONSENT #1: Auto-Opt-In vs Spec
**Status:** DESIGN DECISION
**Current:** Defaults to enabled when unset
**Spec:** Shows consent dialog, default-off

**Question for user:** Should we gate behind explicit consent or keep auto-enabled for internal builds?

**Recommendation:** Add build flag:
```swift
#if DEBUG
  static let defaultEnabled = true  // Auto-on for development
#else
  static let defaultEnabled = false  // Require consent in production
#endif
```

---

## SMALLER FIXES / POLISH

1. **ProjectInfo.transcriptCount = 0**: Will implement actual query or remove field
2. **Accessibility hit target**: Will add `.frame(minHeight: 44)`
3. **Background color**: Will review and use consistent surface color
4. **Notification payload**: Will verify listeners expect string in `object` field

---

## FIXES PRIORITY

### P0 - Critical (Must fix before merge - 2-3 hours)
1. ✅ Remove illegal `await` on `shutdown()`
2. ✅ Remove logging from `body`
3. ✅ Fix timestamp format inconsistency (shared `ISO8601Z`)
4. ⚠️ Implement FSEvents monitoring (unread badges won't work without this)
5. ⚠️ Clarify `cycleToPreviousProject()` signature and fix button actions

### P1 - Performance (Should fix soon - 2-3 hours)
6. ✅ Remove `@State` for singleton
7. ✅ Restore `@ObservationIgnored` on generator
8. ✅ Cache `indexByCacheKey` as stored property
9. ✅ Fix double lifecycle starts

### P2 - Polish (Can defer to follow-up)
10. Missing preview mocks
11. Accessibility improvements
12. Product query for transcriptCount

### P3 - Architectural (Defer to Phase 5)
13. Coordinator pattern refactor
14. Watcher lifecycle integration

---

## NEXT STEPS

**Immediate (today):**
1. Read `ProjectSwitcherState.swift` to check `cycleToPreviousProject()` signature
2. Apply P0 fixes (2-3 hours)
3. Test rapid project switching
4. Apply P1 performance fixes (1-2 hours)

**Follow-up (this week):**
5. Implement FSEvents monitoring properly
6. Add preview mocks
7. Polish UI/accessibility

**Phase 5 (future):**
8. Architectural refactoring if needed
9. Comprehensive testing

---

## QUESTIONS FOR USER

1. **Visibility rule:** Show switcher with 1 project or only 2+ projects?
2. **Consent:** Auto-enable in debug builds or always require explicit consent?
3. **FSEvents:** Should I implement full monitoring now or is partial functionality acceptable for this PR?

---

## ESTIMATED TIME TO FIX

- **Critical bugs (P0):** 2-3 hours
- **Performance issues (P1):** 2-3 hours
- **Total to production-ready:** ~5-6 hours

**Current state:** Feature works but has correctness issues that need fixing before merge.
