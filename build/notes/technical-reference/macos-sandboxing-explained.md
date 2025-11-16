# macOS Sandboxing & Security-Scoped Bookmarks

**Date:** 2025-11-15
**Author:** Technical Investigation
**Related:** App Store build security architecture

## Overview

This document explains how macOS sandboxing works, why it exists, and how it affects Contextify's access to user directories like `~/.claude/projects`.

**Key Concepts:**
- Sandboxed apps run in isolated containers
- Security-scoped bookmarks grant temporary access to user-selected directories
- Container paths are virtualized and app-specific
- Access is time-limited and must be explicitly requested

---

## Container Architecture

### What is a Container?

When Contextify runs as an App Store (sandboxed) build, macOS creates an isolated container:

```
~/Library/Containers/dev.contextify.Contextify/
├── Data/                    ← App's virtualized "home" directory
│   ├── Documents/
│   ├── Library/
│   │   ├── Application Support/
│   │   │   └── Contextify/
│   │   │       └── contextify.db    ← Our database lives here
│   │   ├── Caches/
│   │   └── Preferences/
│   │       └── dev.contextify.Contextify.plist
│   ├── Desktop/
│   ├── Downloads/
│   └── tmp/
└── Container.plist          ← Metadata about the container
```

**Important:** This is a **real directory**, not a symlink. It's the app's entire filesystem universe by default.

### Path Virtualization

When sandboxed code calls:
```swift
FileManager.default.homeDirectoryForCurrentUser
```

macOS **rewrites the path at the kernel level**:

```
App thinks:      ~/Documents
Actually uses:   ~/Library/Containers/dev.contextify.Contextify/Data/Documents
```

This happens via the sandbox daemon (`sandboxd`) in the kernel. The app never sees the real path - it's completely transparent.

**Why this matters:** If you store absolute paths (like `/Users/rob/code/projects/contextify`), the virtualization doesn't apply, and you must use security-scoped bookmarks to access them.

---

## Security-Scoped Bookmarks

### What Are They?

A security-scoped bookmark is a **cryptographic token** that grants temporary access to a specific directory outside the sandbox.

**Not symlinks because:**
- Bookmark is an opaque data structure (binary blob), not a filesystem object
- Access is time-limited (token expires when you stop accessing)
- Permissions are enforced by the kernel, not the filesystem
- Works across app updates and system reboots (if stored properly)

### How They Work

```
1. User Action Required
   User clicks "Grant Access" in your app
   ↓
2. System Folder Picker
   macOS shows standard folder picker (not controlled by app)
   ↓
3. User Selection
   User selects ~/.claude/projects
   ↓
4. Bookmark Creation
   System creates security-scoped bookmark (opaque binary data)
   ↓
5. Storage
   App stores bookmark in UserDefaults or file
   ↓
6. Later Access
   bookmark.startAccessingSecurityScopedResource()  ← Acquires token
   // ... perform file operations ...
   bookmark.stopAccessingSecurityScopedResource()   ← Releases token
```

### Bookmark Contents

The bookmark is an opaque binary blob containing:
- Path to the granted directory
- Cryptographic signature
- Permission metadata (read/write/execute)
- Expiration rules
- Bundle identifier of requesting app

**Security:** Only your app (same bundle ID) can use bookmarks it created. Another app can't steal your bookmarks.

---

## Accessing Files Outside the Sandbox

### Without Bookmark (DENIED)

```swift
// App is sandboxed, user hasn't granted permission
let claudeDir = URL(fileURLWithPath: "/Users/rob/.claude/projects")
let files = try FileManager.default.contentsOfDirectory(at: claudeDir, ...)
// ❌ Error: Operation not permitted (errno 1)
```

The app **cannot** access `~/.claude/projects` directly. It's outside the sandbox container.

### With Bookmark (ALLOWED)

```swift
// User previously clicked "Grant Access" and selected ~/.claude/projects
let bookmark = // ... load saved security-scoped bookmark

// Request access
guard bookmark.startAccessingSecurityScopedResource() else {
    logger.error("Failed to gain access to bookmarked folder")
    return
}
defer { bookmark.stopAccessingSecurityScopedResource() }

// NOW the app can access the REAL directory
let files = try FileManager.default.contentsOfDirectory(at: bookmark, ...)
// ✅ Success! Reading from /Users/rob/.claude/projects (real filesystem)
```

### What Happens During Access

```
App calls startAccessingSecurityScopedResource()
    ↓
1. Kernel validates bookmark signature
    ↓
2. Kernel checks bookmark hasn't expired
    ↓
3. Kernel grants temporary access token
    ↓
4. Sandbox rules temporarily relaxed for THAT PATH ONLY
    │
    ├─ Can read files in ~/.claude/projects
    ├─ Can write files (if bookmark has write permission)
    ├─ Can list subdirectories
    └─ Can traverse the directory tree
    ↓
5. App calls stopAccessingSecurityScopedResource()
    ↓
6. Token revoked, sandbox walls restored
```

**Critical:** Access is temporary and **must be active during I/O operations**.

---

## Contextify's Implementation

### FolderAccessController

We use `FolderAccessController` to manage bookmarks:

```swift
// From our codebase
try accessProvider.withAccess(for: TranscriptProviderID.claude) { claudeRoot in
    // Inside this closure, we have REAL access to ~/.claude/projects
    let files = try FileManager.default.contentsOfDirectory(at: claudeRoot, ...)

    // claudeRoot is literally: file:///Users/rob/.claude/projects/
    // We're reading ACTUAL files from the user's real home directory
    // NOT from the container
}
// Outside the closure, access is automatically revoked
```

### Access Patterns

**Correct Pattern:**
```swift
// ✅ Token active during entire I/O operation
let bookmark = getBookmark()
bookmark.startAccessingSecurityScopedResource()
defer { bookmark.stopAccessingSecurityScopedResource() }

let files = try FileManager.default.contentsOfDirectory(...)
let content = try String(contentsOf: files[0])
// All operations complete before token is released
```

**Incorrect Pattern:**
```swift
// ❌ Token released before I/O operation
let bookmark = getBookmark()
bookmark.startAccessingSecurityScopedResource()
bookmark.stopAccessingSecurityScopedResource()  // Released too early!

Task.detached {
    let files = try FileManager.default.contentsOfDirectory(...)
    // ❌ Fails! Token was already released
}
```

**Async Pattern:**
```swift
// ✅ Token kept alive across async boundaries
let bookmark = getBookmark()
bookmark.startAccessingSecurityScopedResource()
defer { bookmark.stopAccessingSecurityScopedResource() }

await withTaskGroup(of: Void.self) { group in
    for file in files {
        group.addTask {
            // Token is still active because defer hasn't run yet
            let content = try? String(contentsOf: file)
        }
    }
}
// Token released after all async work completes
```

---

## Common Pitfalls & Solutions

### Pitfall 1: Storing Container Paths

**Problem:**
```swift
// During sandbox initialization
let cwd = FileManager.default.currentDirectoryPath
// Returns: "/Users/rob/Library/Containers/dev.contextify.Contextify/Data/"

// Code tries to find .claude relative to cwd
let claudePath = cwd + "/.claude/projects"
// Result: "/Users/rob/Library/Containers/.../Data/.claude/projects"

// Store this in database as "project path"
try db.write { db in
    var project = Project(rootPath: claudePath)  // ❌ Storing container path!
    try project.insert(db)
}
```

**Why it fails:**
1. `.claude` doesn't exist inside the container
2. Even if it did, it wouldn't contain user's actual transcripts
3. Container path is app-specific (won't work across reinstalls)

**Solution:**
```swift
// Use SandboxPathFilter to reject container paths
guard !SandboxPathFilter.isSandboxContainerPath(candidatePath) else {
    throw ProjectError.invalidPath("Container paths not allowed")
}

// Only store real filesystem paths
try db.write { db in
    var project = Project(rootPath: "/Users/rob/code/projects/contextify")  // ✅ Real path
    try project.insert(db)
}
```

### Pitfall 2: Token Expiration

**Problem:**
```swift
// Token released before async work completes
bookmark.startAccessingSecurityScopedResource()
bookmark.stopAccessingSecurityScopedResource()

Task {
    // This runs later, token already expired
    let files = try FileManager.default.contentsOfDirectory(...)  // ❌ Fails
}
```

**Solution:**
```swift
// Keep token alive during async work
bookmark.startAccessingSecurityScopedResource()
defer { bookmark.stopAccessingSecurityScopedResource() }

await Task {
    let files = try FileManager.default.contentsOfDirectory(...)  // ✅ Works
}.value
// Token released after Task.value returns
```

### Pitfall 3: Silent Access Failures

**Problem:**
```swift
// No error checking
let files = try? FileManager.default.contentsOfDirectory(...)
if files == nil {
    // Was this because of access denial or other error?
    // Can't tell!
}
```

**Solution:**
```swift
// Explicit error handling
do {
    let files = try FileManager.default.contentsOfDirectory(...)
} catch let error as NSError {
    if error.code == 1 && error.domain == NSCocoaErrorDomain {
        logger.error("Access denied - security-scoped bookmark may have expired")
        Metrics.increment("security_scoped_access_denied")
    } else {
        logger.error("Unexpected error: \(error)")
    }
}
```

---

## Performance Implications

### Latency Costs

**DMG Build (Unsandboxed):**
```
FileManager.contentsOfDirectory() = ~1ms
Total for 16 projects = ~16ms
```

**App Store Build (Sandboxed):**
```
startAccessingSecurityScopedResource() = ~50ms (overhead)
FileManager.contentsOfDirectory() = ~1ms
Total per project = ~51ms
Total for 16 projects (serial) = ~816ms
```

**Optimization:**
```swift
// Serial execution (current)
for project in projects {
    let files = try await withAccess { /* ... */ }  // 51ms each
}
// Total: 16 × 51ms = 816ms

// Parallel execution (optimized)
await withTaskGroup(of: [URL].self) { group in
    for project in projects {
        group.addTask {
            try await withAccess { /* ... */ }
        }
    }
}
// Total: ~51ms (all run concurrently)
```

**Speedup:** 16x faster by parallelizing security-scoped access.

### Memory Impact

Each active security-scoped bookmark consumes:
- ~1KB for bookmark data
- ~4KB for kernel state (access token)
- Minimal overhead (5KB per bookmark)

With 2 bookmarks (Claude Code + Codex): ~10KB total overhead.

---

## Debugging Sandbox Issues

### Check if App is Sandboxed

```swift
import Foundation

func isSandboxed() -> Bool {
    let env = ProcessInfo.processInfo.environment
    return env["APP_SANDBOX_CONTAINER_ID"] != nil
}

// Or check entitlements
#if APPSTORE_BUILD
    print("Compiled with sandbox entitlements")
#else
    print("Compiled without sandbox (DMG build)")
#endif
```

### Identify Container Paths

```swift
func isSandboxContainerPath(_ path: String) -> Bool {
    let components = path.split(separator: "/")
    guard let containersIdx = components.firstIndex(of: "Containers") else {
        return false
    }

    // Pattern: .../Containers/{bundle-id}/Data/...
    guard components.count > containersIdx + 2 else { return false }
    return components[containersIdx + 2] == "Data"
}

// Example usage
let suspiciousPath = "/Users/rob/Library/Containers/dev.contextify.Contextify/Data/.claude"
print(isSandboxContainerPath(suspiciousPath))  // true
```

### Verify Bookmark Validity

```swift
func validateBookmark(_ bookmark: URL) -> Bool {
    var isStale = false

    do {
        let bookmarkData = try bookmark.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let resolved = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            logger.warning("Bookmark is stale for: \(resolved.path)")
            return false
        }

        logger.info("Bookmark is valid for: \(resolved.path)")
        return true

    } catch {
        logger.error("Bookmark validation failed: \(error)")
        return false
    }
}
```

### Log Access Patterns

```swift
func withAccess<T>(for provider: TranscriptProviderID, _ operation: (URL) throws -> T) rethrows -> T {
    let startTime = Date()

    guard let bookmark = getBookmark(for: provider) else {
        logger.error("[ACCESS] No bookmark for \(provider)")
        throw AccessError.noBookmark
    }

    guard bookmark.startAccessingSecurityScopedResource() else {
        logger.error("[ACCESS] Failed to start accessing \(provider)")
        throw AccessError.accessDenied
    }
    defer {
        bookmark.stopAccessingSecurityScopedResource()
        let duration = Date().timeIntervalSince(startTime) * 1000
        logger.debug("[ACCESS] Released \(provider) after \(Int(duration))ms")
    }

    logger.debug("[ACCESS] Granted access to \(provider) at \(bookmark.path)")
    return try operation(bookmark)
}
```

---

## Security Considerations

### Why Sandboxing Exists

macOS sandboxing protects users from:
1. **Malicious apps** accessing personal files without permission
2. **Buggy apps** accidentally deleting important data
3. **Compromised apps** being exploited to steal user data

**Trade-off:** Apps must explicitly request access, adding complexity but improving security.

### What Can Be Accessed Without Bookmarks

**Allowed (no bookmark needed):**
- App's own container (`~/Library/Containers/bundle-id/Data/`)
- Temporary directory (`/tmp/`)
- System frameworks and libraries
- Network access (if entitled)

**Denied (requires bookmark):**
- User's home directory (`~/`)
- Desktop, Documents, Downloads
- Any directory containing user data
- Other apps' containers

### Bookmark Persistence Best Practices

**DO:**
- ✅ Store bookmarks in UserDefaults or secure file
- ✅ Validate bookmarks before use (check for staleness)
- ✅ Request new bookmark if validation fails
- ✅ Use `withSecurityScope` option when creating bookmarks

**DON'T:**
- ❌ Store bookmark data in plain text files accessible to other apps
- ❌ Assume bookmarks are permanent (they can be revoked by user)
- ❌ Share bookmarks across different apps (won't work)
- ❌ Store bookmark URLs as strings (use proper bookmark data)

---

## Comparison: Sandbox vs Docker

Think of sandboxing like Docker containers:

**Docker:**
```bash
docker run -v /host/data:/container/data myapp
```
- Container has its own filesystem
- Volume mounts map external directories
- Container can't access unmapped paths

**macOS Sandbox:**
```
Sandbox Container: ~/Library/Containers/app-id/Data/
Security-scoped bookmark: ~/.claude/projects (like -v mount)
```
- App has virtualized filesystem (container)
- Bookmarks are like volume mounts
- App can't access unbookmarked paths

**Key Difference:** macOS does this **transparently at the kernel level**, so it's invisible to most code. Docker is explicit. But the concept is similar: isolated execution with controlled access to external resources.

---

## References

**Apple Documentation:**
- [App Sandbox Design Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/)
- [Security-Scoped Bookmarks](https://developer.apple.com/documentation/foundation/url/2143023-startaccessingsecurityscopedreso)
- [Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements)

**Contextify Codebase:**
- `app/Sources/ContextifyCore/Security/FolderAccessController.swift` - Bookmark management
- `app/Sources/ContextifyCore/Security/SandboxPathFilter.swift` - Container path detection
- `build/docs/architecture/transcript-access-security.md` - Access architecture

**Related Issues:**
- Issue #1: Project ordering regression (mtime retrieval failures in sandbox)
- Issue #2: Fast-path container access (storing container paths in database)
- Issue #3: Watcher recovery failures (trying to watch container path files)

---

## Quick Reference

### Key Concepts

| Concept | Description | Example |
|---------|-------------|---------|
| **Container** | Isolated directory for app data | `~/Library/Containers/bundle-id/Data/` |
| **Bookmark** | Cryptographic token for external access | Security-scoped URL |
| **Token** | Temporary permission granted by kernel | Active during `startAccessing...stopAccessing` |
| **Path Virtualization** | Kernel rewrites paths transparently | `~/Documents` → `~/Containers/.../Data/Documents` |
| **Container Path** | Path inside app's container | `.../Containers/bundle-id/Data/...` |
| **Real Path** | Path on actual filesystem | `/Users/rob/.claude/projects` |

### Common Errors

| Error | Meaning | Solution |
|-------|---------|----------|
| `Operation not permitted` (errno 1) | No security-scoped access | Request bookmark, call `startAccessingSecurityScopedResource()` |
| `Bookmark is stale` | Bookmark expired or revoked | Request new bookmark from user |
| `Access denied` for container path | Trying to access `.claude` inside container | Use `SandboxPathFilter` to reject container paths |
| Silent failures (try? returns nil) | Access error not caught | Use explicit error handling, log errors |

### Code Patterns

**Get bookmark access:**
```swift
bookmark.startAccessingSecurityScopedResource()
defer { bookmark.stopAccessingSecurityScopedResource() }
// ... perform I/O operations ...
```

**Check for container path:**
```swift
guard !SandboxPathFilter.isSandboxContainerPath(path) else {
    return  // Skip invalid path
}
```

**Validate bookmark:**
```swift
var isStale = false
let resolved = try URL(
    resolvingBookmarkData: bookmarkData,
    bookmarkDataIsStale: &isStale
)
if isStale { /* request new bookmark */ }
```

---

*Last Updated: 2025-11-15*
*Related Investigation: App Store vs DMG Build Comparison Analysis*
