# Phase 2: LLM Session Management & Safety Optimizations

**Status**: Deferred
**Priority**: High (P1.5)
**Effort**: Medium-Large (3-5 sessions)
**Risk**: Medium (requires careful actor isolation work)

## Context

Following the comprehensive P0/P1 fixes implemented in commits `b375246`, `fbe78a9`, and `4941bdf`, this document captures the second phase of optimizations identified during ultrathink review. These focus on **session lifecycle management**, **resource bounds**, and **safety improvements** for production LLM usage.

**Why defer?** The critical correctness issues (index drift, memory leaks, retry paradoxes, error handling) are now resolved. These remaining items improve **resource efficiency** and **operational resilience** but don't fix observable production bugs.

---

## Deferred Items (12 total)

### **Priority 1: Controller Pool & Lifecycle (Items 1-3, 10)**

#### Problem
Current `FoundationLLM.controllers` dictionary:
- Uses `nonisolated(unsafe) static var` → race conditions
- Unbounded growth (one controller per unique instruction string)
- `actionHint` embedded in instructions → creates per-message keys
- No eviction policy → memory leak in long-running sessions
- Reset APIs only target hardcoded assistant instructions

#### Solution: Actor-Isolated LRU Pool

**Benefits**:
- Thread-safe access (no `nonisolated(unsafe)`)
- Bounded memory (max 4 controllers, LRU eviction)
- Stable keys (no per-request strings)
- Comprehensive reset API

**Implementation**:

```swift
actor FoundationLLM {
    // Stable key type
    private struct ControllerKey: Hashable {
        let fingerprint: String

        init(template: String) {
            let hash = SHA256.hash(data: Data(template.utf8))
            self.fingerprint = hash.hexPrefix(16)
        }
    }

    // Actor-isolated pool
    private var controllers: [ControllerKey: SessionController] = [:]
    private var lru: [ControllerKey] = []
    private let maxControllers = 4

    // Stable instruction templates (no actionHint!)
    private func instructionsTemplate(for kind: TimelineEntryKind) -> String {
        switch kind {
        case .assistant:
            return """
            Summarize an AI assistant message as JSON {summary,isCompletion,disposition,grounding,confidence}.
            Rules:
            - ≤140 chars; start with assistant name if available.
            - Use only message content.
            - Past tense for explicit completions; present continuous for in-progress; simple present otherwise.
            - Mention tools only if explicitly executed.
            """
        default:
            return """
            Summarize a user message as JSON {summary,isCompletion,disposition,grounding,confidence}.
            Rules:
            - ≤140 chars; use only the message; prefer direct intent.
            """
        }
    }

    private func key(for kind: TimelineEntryKind) -> ControllerKey {
        let template = instructionsTemplate(for: kind)
        return ControllerKey(template: template)
    }

    func getController(kind: TimelineEntryKind) async -> SessionController {
        let k = key(for: kind)
        if let controller = controllers[k] {
            touch(k)
            return controller
        }

        let controller = SessionController(instructions: instructionsTemplate(for: kind))
        insert(controller, for: k)
        return controller
    }

    private func insert(_ controller: SessionController, for key: ControllerKey) {
        controllers[key] = controller
        lru.removeAll { $0 == key }
        lru.append(key)

        // LRU eviction
        if controllers.count > maxControllers, let evict = lru.first {
            controllers[evict] = nil
            lru.removeFirst()
        }
    }

    private func touch(_ key: ControllerKey) {
        lru.removeAll { $0 == key }
        lru.append(key)
    }

    /// Public reset API
    func resetSessions(where predicate: (ControllerKey) -> Bool = { _ in true }) async {
        for (key, controller) in controllers where predicate(key) {
            await controller.reset()
            touch(key)
        }
    }
}
```

**Migration Steps**:
1. Delete `buildInstructions(kind:actionHint:)` - move `actionHint` to prompt payload
2. Replace all `await getController(for: instructions)` with `await getController(kind: kind)`
3. Update `TimelineCacheMissGenerator` batch reset:
   ```swift
   await FoundationLLM.shared.resetSessions { _ in true }
   ```
4. Remove `nonisolated(unsafe) static var controllers`
5. Update prompt builder to include `actionHint` in payload, not instructions

**Risk**: Requires touching all LLM call sites. Test thoroughly.

---

### **Priority 2: Session Age & Request Limits (Item 9)**

#### Problem
Sessions never expire, even after hundreds of requests or hours of uptime. This risks:
- Accumulated context pollution
- API rate limit exhaustion
- Stale model state

#### Solution: Per-Session Counters

```swift
@available(macOS 26.0, *)
actor SessionController {
    private var createdAt = Date()
    private var requestCount = 0
    private let maxRequests = 15
    private let maxAge: TimeInterval = 300  // 5 minutes

    func sessionRespond<T: Generable>(
        to prompt: String,
        generating: T.Type,
        options: GenerationOptions
    ) async throws -> T {
        requestCount += 1

        // Auto-reset on limits
        if requestCount > maxRequests || Date().timeIntervalSince(createdAt) > maxAge {
            log.info("Session auto-reset: requests=\(requestCount) age=\(Int(Date().timeIntervalSince(createdAt)))s")
            await reset()
        }

        let session = getOrCreateSession()
        await acquire()
        defer { release() }

        let response = try await session.respond(
            to: prompt,
            generating: T.self,
            includeSchemaInPrompt: true,
            options: options
        )
        return response.content
    }

    func reset() {
        session = nil
        createdAt = Date()
        requestCount = 0
        log.info("Reset session (age/request limit)")
    }
}
```

**Benefits**:
- Automatic resource recycling
- Defense against forgotten resets in upper layers
- Clear operational limits

**Integration**: Update all `controller.generate(...)` calls to `controller.sessionRespond(...)`

---

### **Priority 3: SessionController Cancellation Safety (Item 8)**

#### Problem
Current cancellation handler in `acquire()` tries to mutate actor-isolated `waiters` from a `Sendable` closure:
```swift
onCancel: {
    if let cont = waiters.removeValue(forKey: id) { cont.resume() }  // ❌ Error
}
```

#### Solution: Skip Cancelled Waiters on Release

```swift
private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
private var cancelled: Set<UUID> = []

private func acquire() async {
    if !inFlight { inFlight = true; return }
    let id = UUID()

    try? await withTaskCancellationHandler {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters[id] = cont
        }
    } onCancel: {
        // Mark as cancelled (can't touch actor state here)
        Task { await self.markCancelled(id) }
    }

    // If we got here, we either got the lock or were cancelled
    if !cancelled.contains(id) {
        inFlight = true
    }
}

private func markCancelled(_ id: UUID) {
    cancelled.insert(id)
    if let cont = waiters.removeValue(forKey: id) {
        cont.resume()  // Release the slot
    }
}

private func release() {
    // Skip cancelled waiters
    while let id = waiters.keys.first {
        let cont = waiters.removeValue(forKey: id)
        let wasCancelled = cancelled.remove(id) != nil

        if !wasCancelled, let cont {
            cont.resume()
            return  // Handed off the lock
        }
    }
    inFlight = false
}
```

**Testing**: Verify with concurrent cancellation stress tests.

---

### **Priority 4: Log Sanitization (Items 5, 17)**

#### Problem
Currently logs raw prompts containing user data:
```swift
log.debug("[\(reqNum)] input: \(payloadInput, privacy: .public)")
```

#### Solution: Hash-Based Logging

```swift
// At LLM call site
let inputHash = SHA256.hash(data: Data(payloadInput.utf8)).hexPrefix(12)
log.debug("[\(reqNum)] inputLen=\(payloadInput.count) sha=\(inputHash)")

// For debugging, use a separate debug file with full content (not in prod logs)
if ProcessInfo.processInfo.environment["LLM_DEBUG"] == "1" {
    try? payloadInput.write(to: debugPath, atomically: true, encoding: .utf8)
    log.debug("[\(reqNum)] full input written to \(debugPath.lastPathComponent)")
}
```

**Audit locations**:
- `summarizeTimelineOnce(...)` - line ~408
- `SessionController.generate(...)` - if it logs prompts
- `postProcess(...)` - if it logs raw messages

---

### **Priority 5: Simplify Sort/Trim Sync (Item 13)**

#### Problem
`sortEntriesChronologically()` and `trimEntries()` maintain parallel state:
```swift
entries.sort { ... }
state.sortChronologically()  // duplicates work
```

#### Solution: Single Source of Truth

```swift
private func sortEntriesChronologically() {
    entries.sort { a, b in
        a.timestamp == b.timestamp
            ? a.sourceIdentifier < b.sourceIdentifier
            : a.timestamp < b.timestamp
    }
    state.replace(with: entries)  // Re-sync in one line
}

private func trimEntries() {
    if entries.count > config.maxEntries {
        entries = Array(entries.suffix(config.maxEntries))
    }
    state.replace(with: entries)  // Re-sync
}
```

**Also add**: Call `pruneSeenIDsIfNeeded()` after `trimEntries()` to keep dedupe set bounded.

---

### **Priority 6: Circuit Breaker Enhancement (Item 19)**

#### Problem
Current circuit breaker only checks consecutive failures. High error ratio (50% failures) can still process many bad items.

#### Solution: Ratio-Based Stopping

```swift
// In TimelineCacheMissGenerator.processBatch
let total = batch.count
var errorCount = 0
var consecutiveFailures = 0

for miss in batch {
    // ... existing logic ...

    // Two circuit breakers
    if consecutiveFailures >= 5 {
        log.error("Circuit breaker: 5 consecutive failures")
        break
    }

    if errorCount >= max(5, total / 2) {
        log.error("Circuit breaker: error ratio too high (\(errorCount)/\(total))")
        break
    }
}
```

---

### **Priority 7: Remove Global Counters (Item 20)**

#### Problem
`requestCount` and `failureCount` in `FoundationLLM` conflate unrelated workloads.

#### Solution
Move to `SessionController` (already done in Item 9's `requestCount`). For failure tracking, use a sliding window per-controller:

```swift
actor SessionController {
    private var recentFailures: [Date] = []
    private let failureWindow: TimeInterval = 60  // 1 minute

    func recordFailure() {
        let now = Date()
        recentFailures.append(now)
        recentFailures.removeAll { now.timeIntervalSince($0) > failureWindow }

        if recentFailures.count > 5 {
            log.warning("High failure rate: \(recentFailures.count) in \(Int(failureWindow))s")
        }
    }
}
```

---

### **Lower Priority Items**

**Item 11**: Use `setEntries([])` in `clearTimelineForProjectSwitch()`
**Item 14**: Delete `notificationObserver` property entirely
**Item 15**: Add more `Task.isCancelled` checks in discovery filesystem loops
**Item 16**: Ensure all failure paths use `TimelineError.userMessage` in UI
**Item 18**: Remove `@available` from benchmark test (keep only `#if canImport`)

---

## Prioritization Matrix

| Item | Priority | Effort | Impact | Risk |
|------|----------|--------|--------|------|
| Controller Pool (1-3,10) | P1 | High | High | Medium |
| Session Limits (9) | P1 | Low | Medium | Low |
| Cancellation (8) | P2 | Medium | Medium | Medium |
| Log Sanitization (5,17) | P2 | Low | High (privacy) | Low |
| Sort/Trim Sync (13) | P3 | Low | Low | Low |
| Circuit Breaker (19) | P3 | Low | Low | Low |
| Remove Global (20) | P3 | Medium | Low | Low |
| Cleanup (11,14-16,18) | P4 | Low | Low | Low |

---

## Recommended Approach

### Phase 2a (High ROI, ~1 session)
1. Session age/request limits (Item 9) - immediate safety
2. Log sanitization (Items 5, 17) - privacy compliance
3. Sort/trim simplification (Item 13) - reduces code complexity

### Phase 2b (Architectural, ~2-3 sessions)
4. Controller pool with LRU (Items 1-3, 10) - requires careful testing
5. SessionController cancellation (Item 8) - enables graceful shutdown
6. Circuit breaker ratio (Item 19) - production resilience

### Phase 2c (Cleanup, ~1 session)
7. Remove global counters (Item 20)
8. Misc cleanup (Items 11, 14-16, 18)

---

## Testing Requirements

**Must verify**:
- Controller pool eviction under load
- Session auto-reset after 15 requests or 5 minutes
- Cancellation doesn't leak continuations
- Logs contain no raw user prompts
- Circuit breaker triggers on both consecutive and ratio thresholds

**Acceptance criteria**:
- All builds pass
- No new warnings
- Existing tests continue to pass
- Memory growth bounded in 100+ request sequences

---

## References

- Original P0/P1 fixes: commits `b375246`, `fbe78a9`, `4941bdf`
- Ultrathink feedback: internal review 2025-01-18
- Related: `build/notes/technical-reference/logging-preferences.md`
