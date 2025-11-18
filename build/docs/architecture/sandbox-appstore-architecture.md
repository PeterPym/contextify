# Sandbox & App Store Architecture

**Status:** Active (as of 2025-11-12)
**Relevant Branch:** `feature/appstore-folder-authorization`

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
- `HUDCore.swift` - Main bookmark lifecycle (`updateSecurityScope`, `securityScopedURL`)
- `HUDPreferences.swift` - Bookmark persistence (UserDefaults)
- `DatabaseManager.swift` - Database location bookmarks
- `ActiveProjectContext.swift` - Bookmark transport via coordinator

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

**Location:** `HUDCore.swift:894-1035`

**Unsandboxed Flow:**
```swift
updateHeadWatcher() {
    // isSandboxed = false, skip bookmark check
    // Directly create file watchers on .git/HEAD
}
```

**Sandboxed Flow (REQUIRED):**
```swift
updateHeadWatcher() {
    // Guard: MUST have security-scoped URL
    guard !isSandboxed || securityScopedURL != nil else {
        watcherLog.error("Sandboxed without security scope; skipping watcher arm")
        return  // ← Watchers silently fail
    }

    // Proceed with watcher creation
}
```

**Critical Requirement:** `securityScopedURL` MUST be non-nil before calling `updateHeadWatcher()` in sandbox builds.

### Working Paths (Security Scope Restored)

**1. Startup with Existing Bookmark** (`HUDCore.swift:500-508`)
```swift
Task { @MainActor in
    await startup()
    // ↓
    if let bookmark = preferences.retrieveBookmark() {
        let url = try URL(resolvingBookmarkData: bookmark, ...)
        await updateSecurityScope(url)  // ← Sets securityScopedURL
    }
    updateHeadWatcher()  // ← Works (security scope active)
}
```

**2. User Sets Project Root** (`HUDCore.swift:777-810`)
```swift
func adoptDetectedRoot(_ url: URL, persist: Bool) {
    if persist {
        let bookmark = try url.bookmarkData(...)
        preferences.storeBookmark(bookmark)
    }
    await updateSecurityScope(url)  // ← Sets securityScopedURL
    updateHeadWatcher()  // ← Works (security scope active)
}
```

### Broken Path (Security Scope NOT Restored)

**Coordinator-Driven Updates** (`HUDCore.swift:528-538`)
```swift
private func handleCoordinatorUpdate(_ context: ActiveProjectContext) {
    projectRootURL = URL(fileURLWithPath: context.path)

    // BUG: context.bookmark exists but is NEVER used
    // securityScopedURL remains nil

    updateHeadWatcher()  // ← FAILS in sandbox (guard fires)
}
```

**Impact:**
- All coordinator updates fail to restore security scope
- Affects: startup, project switching, welcome modal completion
- Git watchers never arm in sandboxed builds
- Only manual `setProjectRoot()` works (bypasses coordinator)

**Affected Flows:**
1. `StartupCoordinator.ready()` → `handleCoordinatorUpdate()` → watcher fails
2. `switchProject(to:)` → `handleCoordinatorUpdate()` → watcher fails
3. Welcome modal completion → coordinator update → watcher fails

---

## Bug History & Known Issues

### ✅ Bug 1: Git Watchers Fail in Sandbox (RESOLVED 2025-11-12)

**Status:** FIXED in commit 8cf56b2 (2025-11-12 14:32:34)

**Was:** `handleCoordinatorUpdate()` didn't restore security-scoped access from bookmarks, causing git watchers to fail silently in sandboxed builds.

**Fix Applied:**
`handleCoordinatorUpdate()` now restores security scope from `context.bookmark` before calling `updateHeadWatcher()` (HUDCore.swift:561-578):

```swift
private func handleCoordinatorUpdate(_ context: ActiveProjectContext) async {
    projectRootURL = URL(fileURLWithPath: context.path)

    // Restore security-scoped access from bookmark
    if let bookmark = context.bookmark {
        do {
            var isStale = false
            let scopedURL = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            updateSecurityScope(for: scopedURL, persisted: true)
            // ...
        } catch {
            watcherLog.error("Failed to resolve bookmark: ...")
        }
    }

    updateHeadWatcher()  // Now has valid security scope
}
```

**Note on Git Monitoring:** As of 2025-11-12, git monitoring is **disabled entirely** in App Store builds (HUDCore.swift:963-966):
```swift
guard !Sandbox.isSandboxed else {
    watcherLog.info("Git monitoring disabled (App Store build)")
    return
}
```

This was a deliberate decision to avoid complexity with App Store sandbox restrictions. Even with security-scoped bookmarks restored, git file watchers do not run in sandboxed builds.

### Bug 2: Transcript Hoovering Fails After Welcome Modal (P0)

**See:** `/tmp/contextify-welcome-modal-debug-status.md` for full details.

**Relation to Sandboxing:** Welcome modal uses bookmarks to access `~/.claude/` and `~/.codex/` in sandboxed builds. If bookmarks aren't properly restored during ingestion, hoovering will fail silently.

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
open .derived/Build/Products/Debug/Contextify.app

# Grant folder permissions in welcome modal
# Verify:
# 1. Projects discovered ✓
# 2. Timeline loads ✓
# 3. Git branch shows in header ← This will fail until Bug 1 is fixed
# 4. Branch updates when switching git branches ← This will fail
```

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
```swift
// HUDCore.swift
let isSandboxed: Bool = {
    let env = ProcessInfo.processInfo.environment
    return env["APP_SANDBOX_CONTAINER_ID"] != nil
}()
```

**Build-Time Configuration:**
- DMG: `Contextify/Contextify.entitlements` (no sandbox key)
- App Store: `Contextify/Contextify-AppStore.entitlements` (includes `com.apple.security.app-sandbox = true`)

**Capabilities Required (App Store):**
- `com.apple.security.app-sandbox` - Enable sandbox
- `com.apple.security.files.user-selected.read-write` - User-selected file access
- `com.apple.security.files.bookmarks.app-scope` - Bookmark creation
- `com.apple.security.network.client` - LLM API calls (if applicable)

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
- File operations work in DMG, fail silently in App Store
- Watchers arm in DMG, skip in App Store (current bug)
- Database migrations work in DMG, corrupt in App Store (if paths differ)

---

## Future Work

### Bookmark Refresh Strategy

**Current:** Bookmarks resolved once at startup, held for app lifetime.

**Issue:** Long-running app sessions may lose access if user revokes permissions via System Settings.

**Proposal:** Periodic bookmark validation (every 5 minutes):
```swift
Task {
    while !Task.isCancelled {
        try await Task.sleep(for: .seconds(300))
        await validateBookmark()
    }
}
```

### Bookmark Migration

**Current:** No migration path if bookmark becomes stale (user moved folder, renamed, etc.).

**Proposal:** Detect stale bookmarks and prompt user to re-select:
```swift
var isStale = false
let url = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
if isStale {
    // Prompt user to re-select folder
    // Create new bookmark
}
```

### Multi-Project Bookmark Management

**Current:** Single global bookmark for project root.

**Issue:** Switching between projects in different locations requires re-granting permissions.

**Proposal:** Per-project bookmarks stored in database:
```sql
ALTER TABLE projects ADD COLUMN bookmark BLOB;
```

---

## References

**Apple Documentation:**
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [Security-Scoped Bookmarks](https://developer.apple.com/documentation/foundation/url/2143023-bookmarkdata)
- [Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements)

**Contextify Docs:**
- First-run testing: `build/docs/testing/first-run-qa-guide.md`
- Startup coordination: `build/docs/architecture/startup-coordinator.md`
- Database migration: `build/docs/components/database-migration.md`

**Related Issues:**
- Welcome modal debug status: `/tmp/contextify-welcome-modal-debug-status.md`
- P0 bugs: `build/notes/TODOS.md`
