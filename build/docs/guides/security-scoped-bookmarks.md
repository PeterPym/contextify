# Security-Scoped Bookmark Patterns

**Status:** Active (2025-11-17)
**Related:** `build/docs/architecture/transcript-access-security.md`, `BookmarkStore.swift`
**Purpose:** Practical usage patterns, best practices, and troubleshooting for security-scoped file access

---

## Executive Summary

This document provides **practical implementation patterns** for security-scoped bookmarks in sandboxed (App Store) builds. Use this when:
- Adding new file access features to Contextify
- Debugging "Operation not permitted" errors
- Understanding bookmark lifecycle and caching
- Testing sandbox vs non-sandbox builds
- Investigating performance implications of scoped access

**Related Architecture Doc:** `build/docs/architecture/transcript-access-security.md` - Read that first for design overview.

---

## When to Use Security-Scoped Access

### Decision Tree

```
Does code perform FileManager operations?
│
├─ No  → No security-scoped access needed
│
└─ Yes → Is the path outside app container?
    │
    ├─ No (inside container) → No security-scoped access needed
    │
    └─ Yes (external path) → Is this an App Store build?
        │
        ├─ No (DMG build) → No security-scoped access needed
        │
        └─ Yes (App Store) → ✅ MUST use security-scoped access
```

### Paths Requiring Security-Scoped Access (App Store Builds)

| Path | Access Type | Example |
|------|-------------|---------|
| `~/.claude/projects` | External (user home) | Claude Code transcripts |
| `~/.codex/sessions` | External (user home) | Codex CLI transcripts |
| `~/Dropbox` | External (cloud storage) | Custom database location |
| `~/Library/Mobile Documents` | External (iCloud) | Custom database location |
| `/Volumes/*` | External (mounted drives) | External database backup |

### Paths NOT Requiring Security-Scoped Access

| Path | Access Type | Example |
|------|-------------|---------|
| `~/Library/Containers/<BID>/Data/*` | Inside container | Default database location |
| `~/Library/Application Support/Contextify/` (DMG) | Direct access (unsandboxed) | DMG build database |

---

## Pattern 1: Protocol-Based Provider (Recommended)

### Overview

**Use When:** Core layer needs file access but should remain sandbox-agnostic.

**Benefits:**
- Core layer testable without App layer
- Build-time dependency injection (DMG vs App Store)
- No `#if APPSTORE_BUILD` scattered throughout code

### Implementation

**Step 1: Define Protocol in Core Layer**

```swift
// ContextifyCore/Projects/TranscriptAccessProvider.swift
public protocol TranscriptAccessProvider: Sendable {
    func withAccess<T>(
        for provider: String,
        _ body: @Sendable (URL) throws -> T
    ) throws -> T
}
```

**Step 2: Implement DMG Provider (Passthrough)**

```swift
// ContextifyCore/Projects/PassthroughAccessProvider.swift
public struct PassthroughAccessProvider: TranscriptAccessProvider {
    public func withAccess<T>(
        for provider: String,
        _ body: @Sendable (URL) throws -> T
    ) throws -> T {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root: URL
        switch provider {
        case "claude":
            root = home.appendingPathComponent(".claude/projects")
        case "codex":
            root = home.appendingPathComponent(".codex/sessions")
        default:
            root = home
        }
        return try body(root)
    }
}
```

**Step 3: Implement App Store Provider (Scoped)**

```swift
// Contextify/SandboxTranscriptAccessProvider.swift
struct SandboxTranscriptAccessProvider: TranscriptAccessProvider {
    let claudeRoot: URL?  // Resolved from bookmark
    let codexRoot: URL?

    func withAccess<T>(
        for provider: String,
        _ body: @Sendable (URL) throws -> T
    ) throws -> T {
        let root: URL
        switch provider {
        case "claude":
            guard let url = claudeRoot else {
                throw FolderAccessError.securityScopeAccessDenied(...)
            }
            root = url
        case "codex":
            guard let url = codexRoot else {
                throw FolderAccessError.securityScopeAccessDenied(...)
            }
            root = url
        default:
            assertionFailure("Unknown provider")
            root = FileManager.default.homeDirectoryForCurrentUser
        }

        // ✅ Start security scope
        guard root.startAccessingSecurityScopedResource() else {
            throw FolderAccessError.securityScopeAccessDenied(root)
        }

        // ✅ Guaranteed cleanup via defer
        defer { root.stopAccessingSecurityScopedResource() }

        return try body(root)
    }
}
```

**Step 4: Inject Provider at App Layer**

```swift
// Contextify/ContextifyApp.swift
private func initializeProjectsSystem() async {
    let accessProvider: TranscriptAccessProvider

    #if APPSTORE_BUILD
    // Resolve URLs from FolderAccessController
    let claudeAuth = await folderAccessController.authorization(for: .claude)
    let claudeURL = try? await folderAccessController.resolve(claudeAuth).url

    let codexAuth = await folderAccessController.authorization(for: .codex)
    let codexURL = try? await folderAccessController.resolve(codexAuth).url

    accessProvider = SandboxTranscriptAccessProvider(
        claudeRoot: claudeURL,
        codexRoot: codexURL
    )
    #else
    accessProvider = PassthroughAccessProvider()
    #endif

    orchestrator = try TranscriptOrchestrator(
        dbManager: dbManager,
        accessProvider: accessProvider
    )
}
```

**Step 5: Use in Core Layer**

```swift
// ContextifyCore/Database/TranscriptOrchestrator.swift
public final class TranscriptOrchestrator {
    private let accessProvider: TranscriptAccessProvider?

    public func discoverTranscript(fileURL: URL, provider: String) throws {
        if let accessProvider {
            try accessProvider.withAccess(for: provider) { root in
                // ✅ All FileManager ops happen inside this closure
                let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let data = try Data(contentsOf: fileURL)
                // Process data...
            }
        } else {
            // Direct access (DMG build or no provider)
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let data = try Data(contentsOf: fileURL)
        }
    }
}
```

---

## Pattern 2: Direct Bookmark Management (Low-Level)

### Overview

**Use When:** Need direct control over bookmark creation/resolution (e.g., user selects custom folder).

**Components:**
- `BookmarkStore` - Persists bookmarks to JSON
- `SourceAuthorization` - Represents authorization state
- `FolderAccessController` - High-level coordinator

### Creating Bookmark from User Selection

```swift
// User clicks "Select Folder..." button
func selectCustomDatabaseLocation() async {
    // 1. Show file picker (user grants access)
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let url = panel.url else {
        return
    }

    // 2. Create security-scoped bookmark
    do {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,  // ← Critical for persistence
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // 3. Store bookmark
        let auth = SourceAuthorization(
            id: .customDatabase,
            status: .authorized,
            bookmark: bookmarkData,
            url: url
        )
        try await bookmarkStore.save(auth)

        log.info("Created bookmark for \(url.path)")
    } catch {
        log.error("Failed to create bookmark: \(error)")
    }
}
```

### Resolving Bookmark on App Launch

```swift
// App startup: Restore access from bookmarks
func restoreSecurityScopedAccess() async throws -> URL? {
    // 1. Retrieve bookmark from store
    guard let auth = await bookmarkStore.authorization(for: .customDatabase),
          let bookmarkData = auth.bookmark else {
        return nil
    }

    // 2. Resolve bookmark to URL
    var isStale = false
    let url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    )

    // 3. Check if bookmark is stale
    if isStale {
        log.warning("Bookmark is stale (folder moved/renamed)")
        // Option: Create fresh bookmark and update store
        let freshBookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var updatedAuth = auth
        updatedAuth.bookmark = freshBookmark
        try await bookmarkStore.save(updatedAuth)
    }

    return url
}
```

### Using Resolved URL for File Access

```swift
func accessCustomDatabase() throws {
    // 1. Get URL from bookmark resolution
    guard let url = customDatabaseURL else {
        throw DatabaseError.locationNotSet
    }

    // 2. Start security scope
    guard url.startAccessingSecurityScopedResource() else {
        throw DatabaseError.accessDenied
    }

    // 3. Guaranteed cleanup
    defer { url.stopAccessingSecurityScopedResource() }

    // 4. Perform file operations (MUST complete before defer)
    let dbPath = url.appendingPathComponent("contextify.db")
    let pool = try DatabasePool(path: dbPath.path)
    // Use pool...
}
```

---

## Pattern 3: Actor-Based Async Access (for Discovery)

### Overview

**Use When:** Need to wrap sync FileManager calls in actor for thread safety.

**Example:** `ProjectDiscoveryService` needs secure access to discover projects.

### Implementation

```swift
public actor ProjectDiscoveryService {
    private let folderAccessController: FolderAccessController?

    // Security-scoped access helper
    private func withClaudeRoot<T>(
        _ operation: @Sendable (URL) throws -> T
    ) async throws -> T where T: Sendable {
        guard let controller = folderAccessController else {
            // Non-sandboxed: direct access
            let root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects")
            return try operation(root)
        }

        // Sandboxed: resolve bookmark and use scope
        guard let auth = await controller.authorization(for: .claude),
              auth.status == .authorized else {
            throw FolderAccessError.securityScopeAccessDenied(...)
        }

        return try await controller.withAccess(auth, operation)
    }

    // Usage
    public func discoverClaudeCodeProjects() async throws -> [URL] {
        return try await withClaudeRoot { root in
            // ✅ All FileManager ops must complete inside this closure
            let subdirs = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return subdirs.filter { /* ... */ }
        }
    }
}
```

---

## Common Pitfalls

### Pitfall 1: FileManager Outside Security Scope

**Anti-pattern:**

```swift
// ❌ WRONG - File access outside scope
let url = try withAccess(for: "claude") { $0 }
let files = try FileManager.default.contentsOfDirectory(at: url, ...)  // FAILS!
```

**Why:** Security scope ended when `withAccess` returned. The URL is just a path string now - no active scope.

**Correct:**

```swift
// ✅ CORRECT - File access inside scope
let files = try withAccess(for: "claude") { url in
    try FileManager.default.contentsOfDirectory(at: url, ...)
}
```

### Pitfall 2: Async Operations Outliving Scope

**Anti-pattern:**

```swift
// ❌ WRONG - Task outlives scope
try withAccess(for: "claude") { url in
    Task {
        // This runs AFTER withAccess returns!
        let data = try Data(contentsOf: url)  // FAILS!
    }
}
```

**Why:** `Task` runs asynchronously, but scope ends when `withAccess` returns synchronously.

**Correct Option 1: Await Task**

```swift
// ✅ CORRECT - Await task completion
try withAccess(for: "claude") { url in
    await Task {
        let data = try Data(contentsOf: url)
        // Process data...
    }.value  // ← Waits for task to complete
}
```

**Correct Option 2: Pass Data Out**

```swift
// ✅ CORRECT - Extract data, process outside
let data = try withAccess(for: "claude") { url in
    try Data(contentsOf: url)  // Read inside scope
}

// Process data outside scope (no file access needed)
let parsed = parseJSONL(data)
```

### Pitfall 3: Forgotten defer Cleanup

**Anti-pattern:**

```swift
// ❌ WRONG - No cleanup (leaks security scope)
func accessFile() throws {
    guard url.startAccessingSecurityScopedResource() else {
        throw AccessError.denied
    }

    let data = try Data(contentsOf: url)
    // If Data() throws, stopAccessingSecurityScopedResource() never called!

    url.stopAccessingSecurityScopedResource()
}
```

**Correct:**

```swift
// ✅ CORRECT - defer guarantees cleanup
func accessFile() throws {
    guard url.startAccessingSecurityScopedResource() else {
        throw AccessError.denied
    }

    defer { url.stopAccessingSecurityScopedResource() }  // ← Always runs

    let data = try Data(contentsOf: url)
    // Process data...
}
```

### Pitfall 4: Bookmark Options Mismatch

**Anti-pattern:**

```swift
// ❌ WRONG - Missing .withSecurityScope option
let bookmark = try url.bookmarkData(
    options: [],  // ← Wrong!
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)

// Resolution fails or doesn't grant access:
let resolved = try URL(resolvingBookmarkData: bookmark, ...)
// resolved.startAccessingSecurityScopedResource() returns false
```

**Correct:**

```swift
// ✅ CORRECT - .withSecurityScope for App Store builds
let bookmark = try url.bookmarkData(
    options: .withSecurityScope,  // ← Critical!
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)
```

---

## Performance Implications

### Bookmark Resolution Cost

**Operation:** `URL(resolvingBookmarkData: ...)`

**Latency:**
- First resolution after app launch: ~10-50ms (system validation)
- Cached resolution (same bookmark): ~1-5ms

**Optimization:** Cache resolved URLs at app launch, reuse throughout session.

**Example:**

```swift
// Cache at app init
private var cachedClaudeRoot: URL?

func resolveClaudeRoot() async throws -> URL {
    if let cached = cachedClaudeRoot {
        return cached  // ← Fast path (no re-resolution)
    }

    let auth = await bookmarkStore.authorization(for: .claude)
    guard let bookmarkData = auth?.bookmark else {
        throw AccessError.noBookmark
    }

    let url = try URL(resolvingBookmarkData: bookmarkData, ...)
    cachedClaudeRoot = url  // ← Cache for next call
    return url
}
```

### Security Scope Overhead

**Operation:** `startAccessingSecurityScopedResource()` + `stopAccessingSecurityScopedResource()`

**Latency:** <1ms (negligible)

**Optimization:** No caching needed - start/stop are cheap. Just ensure proper nesting.

### FileManager Call Overhead (Inside Scope)

**No Additional Cost:** FileManager operations have **same performance** inside vs outside security scope.

**Myth:** "Security scopes make file access slow."
**Reality:** Scope just grants permission - file I/O is unchanged.

---

## Testing Strategies

### Unit Testing: DMG Build (Passthrough Provider)

**Approach:** Test core logic with `PassthroughAccessProvider` (no sandbox).

```swift
func testDiscoverTranscripts() throws {
    let provider = PassthroughAccessProvider()
    let orchestrator = try TranscriptOrchestrator(
        dbManager: testDB,
        accessProvider: provider
    )

    // Test transcript discovery (no sandbox, direct access)
    try orchestrator.discoverTranscript(...)

    // Assertions...
}
```

### Integration Testing: App Store Build (Scoped Provider)

**Approach:** Build App Store variant, grant permissions, test real scoped access.

```bash
# Build App Store variant
bash scripts/xc.sh --dist=appstore Debug build

# Launch and grant permissions
open ".derived-appstore/Build/Products/Debug/Contextify AppStore.app"
# Use welcome modal to grant folder access

# Run tests with real bookmarks
xcodebuild test -scheme Contextify -destination "platform=macOS"
```

### Manual Testing: Bookmark Persistence

```bash
# 1. Grant access via UI
# 2. Quit app
osascript -e 'quit app "Contextify"'

# 3. Check bookmark persisted
cat ~/Library/Containers/PeterPym.Contextify.Debug/Data/Library/Application\ Support/Contextify/bookmarks.json

# Expected: JSON with "claude" and "codex" authorizations

# 4. Relaunch app
open -a Contextify

# 5. Verify access works without re-prompting
# (Check logs for "Loaded N bookmark(s)" message)
```

---

## Troubleshooting

### Issue: "Operation not permitted" Error

**Symptoms:** FileManager operations fail with `EPERM` error.

**Diagnosis:**

```bash
# Check if sandboxed build
log stream --predicate 'subsystem BEGINSWITH "dev.contextify"' \
  | grep -i sandbox

# If sandboxed: Check folder authorization
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT * FROM access WHERE client LIKE '%Contextify%'"
```

**Resolution:**

1. **If TCC permission missing:** Grant via welcome modal
2. **If bookmark not found:** Re-grant access via Settings
3. **If bookmark stale:** Delete and re-create

### Issue: "Bookmark resolution failed"

**Symptoms:** `URL(resolvingBookmarkData:)` throws error.

**Diagnosis:**

```bash
# Check bookmark data exists
defaults read dev.contextify

# Check bookmark JSON file
cat ~/Library/Application\ Support/Contextify/bookmarks.json
```

**Resolution:**

```swift
// Delete corrupted bookmark
try await bookmarkStore.remove(.claude)

// Re-grant access via UI
// Fresh bookmark will be created
```

### Issue: "startAccessingSecurityScopedResource returns false"

**Symptoms:** Bookmark resolves but scope activation fails.

**Cause:** Bookmark created without `.withSecurityScope` option.

**Resolution:**

```swift
// Re-create bookmark with correct options
let freshBookmark = try url.bookmarkData(
    options: .withSecurityScope,  // ← Must include this!
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)
```

---

## Related Documentation

- **Architecture:** `build/docs/architecture/transcript-access-security.md`
- **Source (Store):** `app/Sources/ContextifyCore/Security/BookmarkStore.swift`
- **Source (Provider):** `Contextify/Contextify/SandboxTranscriptAccessProvider.swift`
- **FolderAccessController:** `Contextify/Contextify/FolderAccessController.swift`
- **Sandbox Architecture:** `build/docs/architecture/sandbox-appstore-architecture.md`

---

## Changelog

**2025-11-17:**
- Initial patterns guide created
- Decision tree for when to use security-scoped access
- Pattern 1: Protocol-based provider (recommended approach)
- Pattern 2: Direct bookmark management (low-level)
- Pattern 3: Actor-based async access (for discovery)
- Common pitfalls (file access outside scope, async outliving scope, missing defer, bookmark options)
- Performance implications (bookmark resolution caching, scope overhead)
- Testing strategies (unit, integration, manual)
- Troubleshooting guide (EPERM errors, bookmark resolution failures, scope activation failures)
