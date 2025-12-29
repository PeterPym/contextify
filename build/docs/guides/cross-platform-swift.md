# Cross-Platform Swift Development Guide

Reference for building Swift packages that run on both macOS and Linux. Based on lessons learned from the cross-platform ingestion CLI.

## Platform-Specific Imports

### pthread APIs

pthread functions like `pthread_setname_np` have different signatures on Linux vs Darwin.

```swift
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

func setThreadName(_ name: String) {
    #if os(Linux)
    // Linux: pthread_setname_np takes thread handle + name
    pthread_setname_np(pthread_self(), name)
    #else
    // Darwin: pthread_setname_np takes only name (sets current thread)
    pthread_setname_np(name)
    #endif
}
```

### CryptoKit vs swift-crypto

CryptoKit is Darwin-only. Use swift-crypto for cross-platform cryptography.

```swift
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto  // swift-crypto package
#endif

// Both provide identical SHA256 API
let hash = SHA256.hash(data: data)
```

Package.swift dependency:

```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
],
targets: [
    .target(
        name: "MyCLI",
        dependencies: [
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
        ]
    )
]
```

### OSLog Abstraction

OSLog is Darwin-only. Create a cross-platform logger abstraction.

```swift
#if canImport(os)
import os

struct CrossPlatformLogger {
    private let logger: Logger

    init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func info(_ message: String) { logger.info("\(message)") }
    func error(_ message: String) { logger.error("\(message)") }
}
#else
struct CrossPlatformLogger {
    let subsystem: String
    let category: String

    func info(_ message: String) {
        FileHandle.standardError.write("[\(category)] INFO: \(message)\n".data(using: .utf8)!)
    }
    func error(_ message: String) {
        FileHandle.standardError.write("[\(category)] ERROR: \(message)\n".data(using: .utf8)!)
    }
}
#endif
```

## Concurrency Safety

### Avoiding `nonisolated(unsafe)`

`nonisolated(unsafe)` silences compiler warnings but does NOT prevent data races. The compiler trusts you, but runtime crashes can still occur.

```swift
// DANGEROUS: Compiler won't warn, but this can crash
final class ProgressTracker {
    nonisolated(unsafe) var lastUpdate: Date = .distantPast  // Data race risk!
}

// SAFE: Use proper synchronization
final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _lastUpdate: Date = .distantPast

    var lastUpdate: Date {
        get { lock.withLock { _lastUpdate } }
        set { lock.withLock { _lastUpdate = newValue } }
    }
}
```

### `@unchecked Sendable` Requirements

When marking a type `@unchecked Sendable`, YOU must guarantee thread safety:

1. All mutable state protected by locks
2. All reads and writes go through the lock
3. No lock-free "optimizations" that skip protection

### ISO8601DateFormatter Is NOT Thread-Safe

`ISO8601DateFormatter` shares internal state and crashes under concurrent access.

```swift
// WRONG: Shared formatter causes crashes
let formatter = ISO8601DateFormatter()
await withTaskGroup(of: String.self) { group in
    for date in dates {
        group.addTask { formatter.string(from: date) }  // CRASH!
    }
}

// RIGHT: Use value-type formatting (Swift 5.5+)
await withTaskGroup(of: String.self) { group in
    for date in dates {
        group.addTask { date.ISO8601Format() }  // Safe, no shared state
    }
}
```

### Stdout/Stderr Serialization

Concurrent writes to stdout/stderr interleave, producing garbled output.

```swift
// WRONG: Output interleaves
await withTaskGroup(of: Void.self) { group in
    for item in items {
        group.addTask { print("Processing \(item)") }  // Garbled!
    }
}

// RIGHT: Serialize output
actor OutputSerializer {
    func print(_ message: String) {
        Swift.print(message)
    }
}

let output = OutputSerializer()
await withTaskGroup(of: Void.self) { group in
    for item in items {
        group.addTask { await output.print("Processing \(item)") }
    }
}
```

### Throttling State Must Share Lock

When throttling operations, the timestamp check and the operation must be atomic.

```swift
// WRONG: Race between check and update
final class Throttler: @unchecked Sendable {
    private let lock = NSLock()
    private var lastUpdate: Date = .distantPast

    func shouldUpdate() -> Bool {
        lock.withLock { Date().timeIntervalSince(lastUpdate) > 1.0 }
    }

    func performUpdate() {
        // Race! Another thread could have updated between shouldUpdate() and here
        doExpensiveWork()
        lock.withLock { lastUpdate = Date() }
    }
}

// RIGHT: Check and perform under same lock
final class Throttler: @unchecked Sendable {
    private let lock = NSLock()
    private var lastUpdate: Date = .distantPast

    func maybeUpdate(_ work: () -> Void) {
        lock.withLock {
            guard Date().timeIntervalSince(lastUpdate) > 1.0 else { return }
            work()
            lastUpdate = Date()
        }
    }
}
```

## Package.swift Patterns

### Platform Stanza Limitations

The `platforms:` stanza only affects Apple platforms (per SE-0236). Linux ignores it entirely.

```swift
let package = Package(
    name: "MyCLI",
    platforms: [.macOS(.v14)],  // Linux ignores this
    // ...
)
```

### Conditional Target Exposure

Use `#if os()` to conditionally include macOS-only targets:

```swift
var targets: [Target] = [
    .target(name: "SharedCore"),
    .executableTarget(name: "cli", dependencies: ["SharedCore"]),
]

#if os(macOS)
targets.append(.target(name: "MacOSOnlyFeature"))
#endif

let package = Package(
    name: "MyPackage",
    targets: targets
)
```

### Explicit Sources for Linux

Linux builds may fail if they try to compile macOS-only files. Use explicit `sources:` lists:

```swift
.executableTarget(
    name: "cli",
    dependencies: ["SharedCore"],
    sources: [
        "main.swift",
        "Commands/IngestCommand.swift",
        "Services/DatabaseService.swift",
        // Explicitly list files - don't rely on directory scanning
    ]
)
```

Run Linux CI builds to catch missing files in the sources list.

## SQLite/GRDB on Linux

### Missing Compile-Time Features

Ubuntu's SQLite packages may lack features like `SQLITE_ENABLE_SNAPSHOT`:

```
error: use of undeclared identifier 'SQLITE_ENABLE_SNAPSHOT'
```

**Solutions:**

1. **Build SQLite from source** with custom CFLAGS:
   ```bash
   CFLAGS="-DSQLITE_ENABLE_SNAPSHOT=1 -DSQLITE_ENABLE_FTS5=1" \
     ./configure && make && sudo make install
   ```

2. **Use system SQLite with feature checks:**
   ```swift
   func checkSQLiteFeatures() throws {
       let version = sqlite3_libversion_number()
       guard version >= 3035000 else {
           throw CLIError.unsupportedSQLite("Requires SQLite 3.35+, found \(version)")
       }
   }
   ```

### FTS5 Availability

FTS5 (Full-Text Search) may not be available. Add preflight checks:

```swift
func verifyFTS5Available(db: Database) throws {
    do {
        try db.execute(sql: "CREATE VIRTUAL TABLE fts5_test USING fts5(content)")
        try db.execute(sql: "DROP TABLE fts5_test")
    } catch {
        throw CLIError.missingFeature("FTS5 not available in this SQLite build")
    }
}
```

## Docker Build Tips

### Portable GIT_ROOT

Standard `git rev-parse --show-toplevel` fails in worktrees. Use `--git-common-dir`:

```bash
# Works in both regular repos and worktrees
GIT_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
```

### Separate Build Directories

Avoid conflicts between macOS and Linux builds:

```swift
// .gitignore
.build/           # macOS builds
.build-linux/     # Linux/Docker builds
```

Docker build script:

```bash
docker run --rm \
    -v "$PWD:/workspace" \
    -w /workspace \
    swift:5.10 \
    swift build --build-path .build-linux
```

### Docker Multi-Stage Build Example

```dockerfile
FROM swift:5.10 AS builder
WORKDIR /workspace
COPY Package.swift Package.resolved ./
COPY Sources ./Sources
RUN swift build -c release --build-path .build-linux

FROM swift:5.10-slim
COPY --from=builder /workspace/.build-linux/release/cli /usr/local/bin/
ENTRYPOINT ["cli"]
```

## Quick Reference

| Issue | macOS | Linux |
|-------|-------|-------|
| pthread_setname_np | Takes name only | Takes thread + name |
| CryptoKit | Available | Use swift-crypto |
| OSLog | Available | Use custom logger |
| ISO8601DateFormatter | Not thread-safe | Not thread-safe |
| SQLite features | Full | May need source build |
| Platform stanza | Respected | Ignored |

## See Also

- `build/docs/guides/linux-ci-builds.md` - GitHub Actions workflow for Linux CI
- `scripts/docker/` - Docker build scripts (if present)
