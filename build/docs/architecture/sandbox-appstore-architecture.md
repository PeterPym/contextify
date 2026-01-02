# Sandbox & App Store Architecture

**Status:** Active

## Overview

Contextify supports two distribution modes:

1. **DMG (Unsandboxed)** - Default development builds, full filesystem access
2. **App Store (Sandboxed)** - Required for App Store distribution, restricted filesystem access

This document covers architecture, code paths, and pitfalls specific to sandboxed builds.

---

## Security-Scoped Bookmarks

### What Are They?

**Security-scoped bookmarks** are macOS sandbox tokens that grant persistent filesystem access:

1. User explicitly grants access (file picker, drag-drop, permission dialog)
2. macOS creates opaque bookmark data
3. App persists bookmark (UserDefaults, database)
4. On next launch, app resolves bookmark to restore access **without re-prompting**

### Why Contextify Needs Them

Contextify must access:
- Project folders (anywhere on disk)
- Transcript locations (`~/.claude/projects/`, `~/.codex/sessions/`)
- Custom database locations (Dropbox, iCloud Drive, external drives)
- Git repositories (`.git/` directories for branch monitoring)

Without bookmarks, sandboxed builds can only access:
- App container (`~/Library/Containers/PeterPym.Contextify/`)
- Files from explicit user file picker interactions (single-use, not persisted)

### Implementation

**Key Files:**
- `HUDCore.swift` - `HUDViewModel` class manages security-scoped URLs; `HUDPreferences` enum handles bookmark persistence to UserDefaults
- `DatabaseManager.swift#openDatabase()` - Database location bookmarks and security-scoped access
- `ActiveProjectContext.swift` - Bookmark transport via coordinator (includes `bookmark: Data?` property)
- `SandboxTranscriptAccessProvider.swift` - Transcript directory access with security-scoped bookmarks
- `TranscriptAccessProvider.swift` - Protocol defining `withAccess(for:body:)` pattern

**Core Pattern:**
```swift
// 1. Create bookmark (when user grants access)
let bookmark = try url.bookmarkData(
    options: .withSecurityScope,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)
preferences.storeBookmark(bookmark)

// 2. Resolve bookmark (on app launch or project switch)
var isStale = false
let url = try URL(
    resolvingBookmarkData: bookmark,
    options: .withSecurityScope,
    relativeTo: nil,
    bookmarkDataIsStale: &isStale
)

// 3. Start accessing (REQUIRED before file operations)
guard url.startAccessingSecurityScopedResource() else {
    // Access failed
    return
}
defer { url.stopAccessingSecurityScopedResource() }

// 4. Use URL for filesystem operations
let contents = try FileManager.default.contentsOfDirectory(at: url, ...)
```

---

## Code Paths: Sandboxed vs Unsandboxed

### Git Monitoring (updateHeadWatcher)

**Location:** `HUDCore.swift#HUDViewModel.updateHeadWatcher()`

**DMG (Unsandboxed) Flow:**
Git file watchers are created directly on `.git/HEAD` and related files. No bookmark or security scope required.

**App Store (Sandboxed) Flow:**
Git monitoring is **disabled entirely** in sandboxed builds:

```swift
// HUDViewModel.updateHeadWatcher()
guard !Sandbox.isSandboxed else {
    watcherLog.info("Git monitoring disabled (App Store build)")
    return
}
```

This is a deliberate design choice: git monitoring would require per-project folder access grants from the user, which adds complexity for minimal benefit. App Store builds get branch information from transcript metadata instead (see `handleCoordinatorUpdate()` for fallback logic).

### Startup Flow (DMG and App Store)

**Location:** `HUDCore.swift#HUDViewModel.startup()`

Both builds resolve bookmarks and restore security scope during startup:

```swift
// 1. Resolve bookmark from UserDefaults
let (bookmarkURL, persistedPath) = await Task.detached {
    return (HUDPreferences.resolveBookmark(), HUDPreferences.getPersistedRoot())
}.value

// 2. Validate and restore security scope
if let bookmark = bookmarkURL {
    if SandboxPathFilter.isSandboxContainerPath(canonical.path) {
        // Skip sandbox container paths
    } else {
        updateSecurityScope(for: bookmark, persisted: true)
        updateHeadWatcher()  // No-op in sandboxed builds
    }
}
```

### Coordinator Update Flow

**Location:** `HUDCore.swift#HUDViewModel.handleCoordinatorUpdate()`

When `StartupCoordinator` publishes a new `ActiveProjectContext`:

1. Updates `projectRootURL` and resolves branch (git or transcript metadata)
2. Restores security scope from `context.bookmark` if available
3. Calls `updateHeadWatcher()` (no-op in sandboxed builds)

**Note:** For discovered projects in sandboxed builds, `context.bookmark` is typically `nil` because the app only has access to transcript directories, not project directories. This is expected behavior.

---

## Transcript Access Architecture

### TranscriptAccessProvider Protocol

**Location:** `TranscriptAccessProvider.swift`

All filesystem operations on transcript directories must go through this protocol:

```swift
public protocol TranscriptAccessProvider: Sendable {
    func withAccess<T>(
        for provider: String,  // TranscriptProviderID.claude or .codex
        _ body: @Sendable (URL) throws -> T
    ) throws -> T
}
```

### DMG Builds: PassthroughAccessProvider

**Location:** `TranscriptAccessProvider.swift#PassthroughAccessProvider`

Direct filesystem access. Simply returns the appropriate home directory path:
- Claude: `~/.claude/projects/`
- Codex: `~/.codex/sessions/`

### App Store Builds: SandboxTranscriptAccessProvider

**Location:** `SandboxTranscriptAccessProvider.swift`

Manages security-scoped bookmarks for transcript directories. Key behaviors:

1. **Init:** Receives pre-resolved security-scoped URLs from onboarding
2. **Scope:** Calls `startAccessingSecurityScopedResource()` once during init
3. **Access:** Returns the scoped URL when `withAccess()` is called
4. **Lifetime:** Security scope remains active for the lifetime of the provider

```swift
// Created during app initialization with URLs from onboarding bookmarks
let provider = SandboxTranscriptAccessProvider(
    claudeRoot: resolvedClaudeURL,
    codexRoot: resolvedCodexURL
)
```

---

## Testing Sandbox Builds

### Build Configurations

**DMG (Unsandboxed) - Development Default:**
```bash
bash scripts/xc.sh --dist=dmg Debug build
# No bookmark requirements
# Full filesystem access
```

**App Store (Sandboxed) - Production:**
```bash
bash scripts/xc.sh --dist=appstore Debug build
# Requires bookmarks for all external access
# Restricted to container + granted permissions
```

### First-Run QA Testing

**Full Guide:** `build/docs/testing/first-run-qa-guide.md`

**Quick Test:**
```bash
# Reset sandbox permissions + app state
bash scripts/xc.sh --dist=appstore reset-all

# Launch app
open ".derived-appstore/Build/Products/Debug/Contextify AppStore.app"

# Grant folder permissions in welcome modal
# Verify:
# 1. Projects discovered
# 2. Timeline loads
# 3. Branch shows (from transcript metadata in App Store builds)
```

**Note:** App Store builds get branch information from transcript metadata rather than git file monitoring. This is by design.

### Permission Testing

**Check TCC Database:**
```bash
# App Store build bundle ID
BUNDLE_ID="PeterPym.Contextify.Debug"

# Check folder permissions
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, allowed FROM access WHERE client LIKE '%Contextify%';"
```

**Check Bookmark Persistence:**
```bash
# UserDefaults location (App Store builds)
defaults read dev.contextify dev.contextify.bookmark

# Should return base64 bookmark data
# If empty, bookmark wasn't saved
```

### Log Monitoring

**Git Watcher Errors:**
```bash
log stream --predicate 'subsystem == "dev.contextify" AND category == "GitWatcher"' --level debug
```

**Look for:**
- ✅ "Watching .git/HEAD at ..." (working)
- ❌ "Sandboxed without security scope; skipping watcher arm" (broken)
- ❌ "Operation not permitted" (bookmark not resolved)

---

## Distribution Mode Detection

**Runtime Check:**

**Location:** `HUDCore.swift#Sandbox`

```swift
public enum Sandbox {
    /// Returns true when running in a sandboxed environment.
    /// Uses runtime detection because compile-time flags (#if APPSTORE_BUILD)
    /// don't propagate to Swift package code.
    public static var isSandboxed: Bool {
        #if DEBUG
        if let override = isSandboxedOverrideForTests {
            return override
        }
        #endif
        return isRuntimeSandboxed
    }

    /// Runtime check via environment variables set by macOS for sandboxed apps.
    public static var isRuntimeSandboxed: Bool {
        #if os(macOS)
        if getenv("APP_SANDBOX_CONTAINER_ID") != nil { return true }
        if ProcessInfo.processInfo.environment["__XPC_SANDBOXED"] == "1" { return true }
        #endif
        return false
    }
}
```

**Why Runtime Detection?**
Compile-time flags like `#if APPSTORE_BUILD` don't propagate to Swift package code (ContextifyCore). Using runtime detection via `APP_SANDBOX_CONTAINER_ID` or `__XPC_SANDBOXED` environment variables ensures consistent behavior across both the main app target and the Swift package.

**Build-Time Configuration:**
- DMG: `Contextify/Contextify.entitlements` (no sandbox key)
- App Store: `Contextify/Contextify-AppStore.entitlements` (includes `com.apple.security.app-sandbox = true`)

**Entitlements (App Store):**

From `Contextify/Contextify-AppStore.entitlements`:
- `com.apple.security.app-sandbox` - Enable sandbox
- `com.apple.security.files.user-selected.read-write` - User-selected file access
- `com.apple.security.files.bookmarks.app-scope` - Bookmark creation

**Note:** Network entitlements are not required because Contextify's LLM processing uses Apple Intelligence APIs (macOS 26+) rather than network-based LLM APIs.

---

## Architecture Recommendations

### Principle 1: Bookmark Early, Bookmark Often

**Anti-pattern:**
```swift
// Store path only (no bookmark)
preferences.storeProjectRoot(url.path)
```

**Best practice:**
```swift
// Store path + bookmark atomically
let bookmark = try url.bookmarkData(options: .withSecurityScope, ...)
preferences.storeProjectRoot(url.path)
preferences.storeBookmark(bookmark)
```

### Principle 2: Always Restore Before Access

**Anti-pattern:**
```swift
// Use path from storage (no security scope)
let path = preferences.projectRootPath
let url = URL(fileURLWithPath: path)
updateHeadWatcher()  // ← Fails in sandbox
```

**Best practice:**
```swift
// Restore from bookmark first
if let bookmark = preferences.retrieveBookmark() {
    let url = try URL(resolvingBookmarkData: bookmark, ...)
    await updateSecurityScope(url)  // ← Grants access
}
updateHeadWatcher()  // ← Works
```

### Principle 3: Test Both Modes

Every feature touching the filesystem MUST be tested in both modes:

```bash
# Test DMG flow
bash scripts/xc.sh --dist=dmg Debug cleanrun
# ... manual testing ...

# Test App Store flow
bash scripts/xc.sh --dist=appstore Debug cleanrun
# ... manual testing ...
```

**Common Failures:**
- File operations work in DMG, fail silently in App Store (missing security scope)
- Watchers arm in DMG, disabled by design in App Store
- Database at wrong location if onboarding not completed properly

---

## Future Work

### Per-Project Directory Access (P4)

**Current:** App Store builds only have access to transcript directories (`~/.claude/projects/`, `~/.codex/sessions/`). Project directories are discovered from transcript cwd hints but cannot be accessed directly.

**Impact:** Without project directory access, App Store builds cannot:
- Monitor git branches via file watchers (using transcript metadata instead)
- Perform Finder reveals to project directories
- Access any project files directly

**Proposal:** See ROADMAP.md for P4-PROJECT-DIRECTORY-ACCESS enhancement.

### Stale Bookmark Handling

**Current:** Bookmark staleness is detected during resolution but handling is minimal.

**Implementation:** `HUDPreferences.resolveBookmarkData()` already detects stale bookmarks:
```swift
var stale = false
let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
if stale {
    // Re-store the bookmark to update it
    try? storeBookmark(for: canonical, key: bookmarkKey)
}
```

**Future:** Could prompt user to re-grant access if bookmark resolution fails entirely.

---

## References

**Apple Documentation:**
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [Security-Scoped Bookmarks](https://developer.apple.com/documentation/foundation/url/2143023-bookmarkdata)
- [Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements)

**Contextify Docs:**
- First-run testing: `build/docs/testing/first-run-qa-guide.md`
- Startup coordination: `build/docs/architecture/startup-coordinator.md`
- Transcript access: `build/docs/architecture/transcript-access-security.md`
- Security-scoped bookmarks guide: `build/docs/guides/security-scoped-bookmarks.md`
