# Swift 6 Concurrency Guide

**Last Updated:** 2025-12-29
**Audience:** Developers working on service layers, CLI tools, and cross-platform code
**Related:** `build/docs/design/swiftui-patterns.md` (SwiftUI-specific concurrency)

---

## 1. Sendable Compliance

### Making Structs Sendable

Structs are implicitly Sendable if all stored properties are Sendable. Prefer explicit annotation for public API clarity:

```swift
public struct IngestionSummary: Sendable {
  public let transcriptsProcessed: Int
  public let entriesInserted: Int
}
```

### Making Classes Sendable with @unchecked

Use `@unchecked Sendable` when you guarantee thread safety manually:

```swift
public final class CLIEventSink: @unchecked Sendable {
  private let lock = NSLock()
  private var _state = State()

  private func writeOutput(_ string: String) {
    lock.lock()
    defer { lock.unlock() }
    outputStream.write(Data(string.utf8))
  }
}
```

**File:** `Sources/ContextifyIngestionCLI/CLIEventSink.swift:17`

**The danger:** `@unchecked Sendable` silences the compiler but does NOT prevent races. You are telling the compiler "trust me" - if you're wrong, you get runtime crashes.

**Checklist before using @unchecked Sendable:**
- [ ] Class is `final` (prevents subclassing that could break invariants)
- [ ] All mutable state protected by locks
- [ ] All reads AND writes go through the lock
- [ ] Document thread-safety guarantees in doc comments

---

## 2. Lock Patterns

### OSAllocatedUnfairLock on Darwin (Preferred)

```swift
import os.lock
private let lock = OSAllocatedUnfairLock(initialState: State())

func update() {
  lock.withLock { state in state.counter += 1 }
}
```

### NSLock on Linux (Fallback)

```swift
private let lock = NSLock()
private var _state = State()

func update() {
  lock.lock()
  defer { lock.unlock() }
  _state.counter += 1
}
```

### CrossPlatformLock Abstraction

This codebase provides a unified abstraction that uses `OSAllocatedUnfairLock` on Darwin and `NSLock` on Linux:

```swift
private let primerStatusLock = CrossPlatformLock(initialState: PrimerTrackerState())

func resetTracking() {
  primerStatusLock.withLock { state in
    state.statuses.removeAll()
    state.readyCount = 0
  }
}
```

**File:** `app/Sources/ContextifyCore/Platform/CrossPlatformLock.swift:65`
**Usage:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift:159`

### Lock Usage Rules

1. **No async work inside lock body** - Never `await` inside `withLock`
2. **Keep locked sections small** - Target <1ms lock hold time
3. **Non-reentrant** - Do not call `withLock` from within a `withLock` closure
4. **Atomic operations** - Check-then-act must happen under the same lock:

```swift
// WRONG: Race between check and update
func shouldUpdate() -> Bool { lock.withLock { ... } }
func doUpdate() { lock.withLock { ... } }  // Race!

// RIGHT: Check and perform under same lock
func maybeUpdate(_ work: () -> Void) {
  lock.withLock {
    guard Date().timeIntervalSince(_state.lastUpdate) > 1.0 else { return }
    work()
    _state.lastUpdate = Date()
  }
}
```

---

## 3. ThreadSanitizer (TSAN)

### When to Use

- All `@unchecked Sendable` classes
- Code using manual lock synchronization
- Before merging concurrency changes

### Command

```bash
swift test --sanitize=thread
```

### Limitations

- **Slow** - Expect 5-10x slowdown
- **False positives** - Benign races occasionally flagged
- **macOS only** - TSAN requires Darwin

---

## 4. Common Pitfalls

### ISO8601DateFormatter Is NOT Thread-Safe

```swift
// WRONG: Crashes under concurrent access
let formatter = ISO8601DateFormatter()
group.addTask { formatter.string(from: date) }  // CRASH!

// RIGHT: Use value-type formatting
group.addTask { date.ISO8601Format() }  // Safe
```

**File:** `Sources/ContextifyIngestionCLI/CLIEventSink.swift:57-59`

### FileHandle.write Can Interleave

Serialize through a lock:

```swift
private func writeOutput(_ string: String) {
  lock.lock()
  defer { lock.unlock() }
  outputStream.write(Data(string.utf8))
}
```

**File:** `Sources/ContextifyIngestionCLI/CLIEventSink.swift:43-47`

### Static let vs Static var

- **`static let`** - Thread-safe (Swift guarantees atomic lazy initialization)
- **`static var`** - NOT thread-safe, requires synchronization

### nonisolated(unsafe) - Last Resort

Use only when:
1. Type is immutable after initialization
2. Interfacing with non-Sendable SDK types documented as thread-safe
3. Property only accessed in controlled contexts (e.g., deinit for NotificationCenter observers)

**Valid - immutable formatter:**
```swift
/// Thread safety: Formatter is immutable after initialization.
nonisolated(unsafe) private let iso8601Formatter: ISO8601DateFormatter = {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f
}()
```

**File:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift:25`

**Valid - NotificationCenter observers in deinit:**
```swift
// NSObjectProtocol is not Sendable, but must be accessed in nonisolated deinit
@ObservationIgnored nonisolated(unsafe) private var observer: NSObjectProtocol?
```

**File:** `Contextify/Contextify/ConversationMonitor.swift:229-234`

**Invalid - mutable state:**
```swift
nonisolated(unsafe) private static var hasWarned = false  // BAD! Data race!
```

---

## 5. Actor vs Lock Decision

| Criterion | Actor | Lock |
|-----------|-------|------|
| Async methods needed | Yes | No |
| Compiler safety | Full | Manual |
| Performance overhead | Minimal (non-zero) | Zero |
| Code invasiveness | High (async callers) | Low |
| Nesting | Cannot nest | Can nest (carefully) |

**Use Actors when:**
- Methods need to be `async`
- Building new async service layers
- Want compiler-enforced isolation

**Use Locks when:**
- Cannot make methods `async`
- Retrofitting existing synchronous code
- Inside withLock closures (locks nest, actors don't)

**Rule of thumb:** Prefer actors for new async service layers. Use locks for synchronous state protection.

---

## Quick Reference

| Pattern | When to Use |
|---------|-------------|
| `struct: Sendable` | Value types with Sendable properties |
| `@unchecked Sendable` | Manual lock protection |
| `CrossPlatformLock` | Cross-platform state protection |
| `nonisolated(unsafe)` | Immutable singletons, SDK interop |
| Actor | Async service layers |
| `Date().ISO8601Format()` | Thread-safe date formatting |

---

## See Also

- `build/docs/design/swiftui-patterns.md` - SwiftUI concurrency (@MainActor, .task)
- `build/docs/guides/cross-platform-swift.md` - Linux/Darwin platform differences
- `app/Sources/ContextifyCore/Platform/CrossPlatformLock.swift` - Lock abstraction source
