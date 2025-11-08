# App Sandbox Implementation Plan

## Overview

This document outlines the implementation needed to enable macOS App Sandbox (`com.apple.security.app-sandbox = true`) for App Store submission while maintaining full functionality.

## Current Status

**Commit `b4b4762`** enabled sandboxing but was **reverted in `b1fe869`** because it broke core functionality:

- ❌ Cannot access `~/.claude/projects` and `~/.codex/projects` for project discovery
- ❌ FSEvents monitoring blocked (cannot watch project directories)
- ❌ Projects window shows 0 projects
- ❌ Database location changed from `~/Library/Application Support/Contextify/` to sandboxed container `~/Library/Containers/PeterPym.Contextify.Debug/Data/Library/Application Support/Contextify/`

## Why Sandbox is Required

Apple App Store requires sandboxing for all macOS apps:
- Limits app's access to user files and system resources
- User explicitly grants access via file picker (creates security-scoped bookmarks)
- Prevents malicious apps from accessing arbitrary files

## Technical Challenges

### 1. File Access Restrictions

**Problem:**
Sandboxed apps cannot access arbitrary file system locations. The app needs:
- `~/.claude/projects/` - Claude Code transcript discovery
- `~/.codex/projects/` - Codex CLI transcript discovery
- User's project root directories - For git operations

**Current code locations:**
- `ContextifyApp.swift:243-248` - Hardcoded paths to `.claude/projects` and `.codex/projects`
- `ProjectDiscoveryService.swift` - Scans these directories for transcripts
- `FSEventsMonitor` - Watches for new project directories

### 2. Database Migration

**Problem:**
Database location changes when sandbox is enabled:

**Non-sandboxed:**
```
~/Library/Application Support/Contextify/contextify.db
```

**Sandboxed:**
```
~/Library/Containers/{BundleID}/Data/Library/Application Support/Contextify/contextify.db
```

Existing users would lose all data on first sandboxed launch.

### 3. FSEvents Monitoring

**Problem:**
`FSEventsMonitor` cannot watch directories the app doesn't have access to.

**Current implementation:**
- `ContextifyApp.swift:267-295` - Monitors `.claude/projects` and `.codex/projects`
- Auto-discovers new projects when directories are created
- Uses `FSEventStreamCreate` which requires file access

## Implementation Plan

### Phase 1: File Access Flow (Core UX Change)

#### 1.1 First Launch Setup Flow

**Create:** `Contextify/Contextify/SandboxSetupFlow.swift`

```swift
import SwiftUI
import ContextifyCore

@MainActor
final class SandboxSetupCoordinator: ObservableObject {
    @Published var setupStep: SetupStep = .welcome
    @Published var claudeProjectsBookmark: Data?
    @Published var codexProjectsBookmark: Data?

    enum SetupStep {
        case welcome
        case grantClaudeAccess
        case grantCodexAccess
        case complete
    }

    func requestClaudeProjectsAccess() {
        // Show file picker for ~/.claude/projects
        // Store security-scoped bookmark
    }

    func requestCodexProjectsAccess() {
        // Show file picker for ~/.codex/projects
        // Store security-scoped bookmark
    }
}
```

**Create:** `Contextify/Contextify/WelcomeView.swift`

Welcome screen explaining:
- Why Contextify needs access to Claude/Codex project directories
- What data is accessed (read-only transcript files)
- Step-by-step setup flow with file pickers

#### 1.2 Security-Scoped Bookmarks

**Modify:** `app/Sources/ContextifyCore/HUDPreferences.swift`

Add bookmark storage:
```swift
public struct HUDPreferences {
    // ... existing code ...

    private static let claudeProjectsBookmarkKey = "claudeProjectsBookmark"
    private static let codexProjectsBookmarkKey = "codexProjectsBookmark"

    public static func saveClaudeProjectsBookmark(_ data: Data) {
        preferences.set(data, forKey: claudeProjectsBookmarkKey)
    }

    public static func loadClaudeProjectsBookmark() -> Data? {
        preferences.data(forKey: claudeProjectsBookmarkKey)
    }

    // Similar for Codex...
}
```

**Modify:** `ContextifyApp.swift`

Use bookmarks instead of hardcoded paths:
```swift
@MainActor
private func resolveProjectsDirectory(bookmark: Data?) -> URL? {
    guard let bookmark = bookmark else { return nil }

    var isStale = false
    guard let url = try? URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        bookmarkDataIsStale: &isStale
    ) else {
        return nil
    }

    // Start accessing security-scoped resource
    guard url.startAccessingSecurityScopedResource() else {
        return nil
    }

    // Store URL to call stopAccessingSecurityScopedResource() later
    return url
}
```

#### 1.3 Graceful Degradation

**Modify:** `ProjectDiscoveryService.swift`

Handle missing access gracefully:
```swift
func discoverProjects() async {
    var discoveredProjects: [ProjectInfo] = []

    // Try Claude projects
    if let claudeURL = resolveClaudeProjectsDirectory() {
        discoveredProjects += await scanDirectory(claudeURL)
        claudeURL.stopAccessingSecurityScopedResource()
    } else {
        log.warning("No access to Claude projects directory")
        // Show in-app prompt to grant access
    }

    // Try Codex projects
    if let codexURL = resolveCodexProjectsDirectory() {
        discoveredProjects += await scanDirectory(codexURL)
        codexURL.stopAccessingSecurityScopedResource()
    } else {
        log.warning("No access to Codex projects directory")
    }

    // ... rest of discovery ...
}
```

### Phase 2: Database Migration

#### 2.1 Migration Detection

**Create:** `app/Sources/ContextifyCore/Database/SandboxMigration.swift`

```swift
import Foundation
import GRDB

enum SandboxMigration {
    static let legacyDatabasePath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Contextify/contextify.db")

    static func needsMigration() -> Bool {
        let sandboxPath = DatabaseManager.databaseURL
        let legacyExists = FileManager.default.fileExists(atPath: legacyDatabasePath.path)
        let sandboxExists = FileManager.default.fileExists(atPath: sandboxPath.path)

        // Need migration if legacy exists and sandbox doesn't (or is empty)
        return legacyExists && (!sandboxExists || isSandboxDatabaseEmpty(sandboxPath))
    }

    static func isSandboxDatabaseEmpty(_ path: URL) -> Bool {
        guard let db = try? DatabaseQueue(path: path.path) else { return true }
        let count = try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM projects") }
        return count == nil || count == 0
    }

    static func performMigration() throws {
        let fm = FileManager.default
        let sandboxPath = DatabaseManager.databaseURL

        log.info("🔄 Migrating database from legacy location to sandbox")

        // Ensure sandbox directory exists
        try fm.createDirectory(
            at: sandboxPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Copy database files
        try fm.copyItem(at: legacyDatabasePath, to: sandboxPath)

        // Copy WAL files if they exist
        let shmPath = legacyDatabasePath.appendingPathExtension("shm")
        let walPath = legacyDatabasePath.appendingPathExtension("wal")

        if fm.fileExists(atPath: shmPath.path) {
            try fm.copyItem(
                at: shmPath,
                to: sandboxPath.appendingPathExtension("shm")
            )
        }

        if fm.fileExists(atPath: walPath.path) {
            try fm.copyItem(
                at: walPath,
                to: sandboxPath.appendingPathExtension("wal")
            )
        }

        log.info("✅ Database migration complete")
    }
}
```

#### 2.2 Run Migration on Startup

**Modify:** `ContextifyApp.swift:init()`

```swift
init() {
    let startupLog = Logger(subsystem: "dev.contextify", category: "Startup")
    startupLog.notice("🚀 Contextify launched")

    // Check for sandbox migration before initializing database
    if SandboxMigration.needsMigration() {
        do {
            try SandboxMigration.performMigration()
        } catch {
            startupLog.error("❌ Database migration failed: \(error.localizedDescription)")
            // Show user-facing error modal
        }
    }

    // ... rest of existing init ...
}
```

### Phase 3: FSEvents Monitoring

#### 3.1 Conditional Monitoring

**Modify:** `ContextifyApp.swift:startProjectDirectoryMonitoring()`

```swift
@MainActor
private func startProjectDirectoryMonitoring(viewModel: ProjectsViewModel) async {
    let log = Logger(subsystem: "dev.contextify", category: "Projects")

    var pathsToWatch: [String] = []

    // Only monitor directories we have access to
    if let claudeURL = resolveClaudeProjectsDirectory() {
        pathsToWatch.append(claudeURL.path)
        log.info("📁 Monitoring Claude Code projects: \(claudeURL.path)")
    } else {
        log.warning("⚠️ No access to Claude Code projects directory")
    }

    if let codexURL = resolveCodexProjectsDirectory() {
        pathsToWatch.append(codexURL.path)
        log.info("📁 Monitoring Codex CLI projects: \(codexURL.path)")
    } else {
        log.warning("⚠️ No access to Codex CLI projects directory")
    }

    guard !pathsToWatch.isEmpty else {
        log.warning("⚠️ No project directories accessible for monitoring")
        // Show in-app banner: "Grant access to monitor for new projects"
        return
    }

    // ... rest of existing monitoring code ...
}
```

### Phase 4: Entitlements Configuration

#### 4.1 Update Entitlements

**Modify:** `Contextify/Contextify.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <!-- File access via user selection (file picker) -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>

    <!-- NOTE: Do NOT add temporary exceptions for home-relative paths -->
    <!-- App Store will reject. Use file picker flow instead. -->
  </dict>
</plist>
```

**Important:** Do NOT use `com.apple.security.temporary-exception.files.home-relative-path.read-only` - this will be rejected by App Store reviewers. The app MUST use file picker to get user consent.

### Phase 5: User Experience Improvements

#### 5.1 Access Status Indicator

**Create:** `Contextify/Contextify/AccessStatusView.swift`

Show banner when project directories aren't accessible:
```swift
struct AccessStatusView: View {
    @ObservedObject var coordinator: SandboxSetupCoordinator

    var body: some View {
        if coordinator.claudeProjectsBookmark == nil {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                Text("Grant access to Claude projects for full functionality")
                Button("Grant Access") {
                    coordinator.requestClaudeProjectsAccess()
                }
            }
            .padding()
            .background(Color.orange.opacity(0.2))
        }
    }
}
```

#### 5.2 Settings Panel

**Create:** Settings tab for managing directory access:
- Show current access status (granted/denied)
- Allow re-granting access if bookmark becomes stale
- Explain what each directory is used for

### Phase 6: Testing Checklist

#### 6.1 Fresh Install Testing

1. Delete `~/Library/Containers/PeterPym.Contextify.Debug/` entirely
2. Launch app
3. Verify welcome flow appears
4. Grant access to `.claude/projects` via file picker
5. Verify projects are discovered
6. Verify Projects window shows all projects
7. Verify FSEvents monitoring works (create new project directory)

#### 6.2 Migration Testing

1. Build non-sandboxed version with data
2. Build sandboxed version
3. Launch sandboxed version
4. Verify migration runs automatically
5. Verify all projects appear
6. Verify transcripts are accessible
7. Verify no data loss

#### 6.3 Degraded Mode Testing

1. Launch sandboxed app
2. Revoke access to `.claude/projects` (remove bookmark)
3. Verify app shows appropriate UI prompts
4. Verify app doesn't crash
5. Verify Projects window explains why no projects shown

## Implementation Order

1. **Phase 2 (Database Migration)** - Required to not lose data
2. **Phase 1 (File Access Flow)** - Core UX for granting access
3. **Phase 3 (FSEvents)** - Make monitoring conditional
4. **Phase 5 (UX Improvements)** - Polish the experience
5. **Phase 4 (Entitlements)** - Enable sandbox
6. **Phase 6 (Testing)** - Comprehensive validation

## Estimated Effort

- **Phase 1:** 4-6 hours (file picker flow, bookmarks, UI)
- **Phase 2:** 2-3 hours (migration logic, testing)
- **Phase 3:** 1-2 hours (conditional monitoring)
- **Phase 4:** 30 minutes (entitlements config)
- **Phase 5:** 2-3 hours (status indicators, settings)
- **Phase 6:** 3-4 hours (comprehensive testing)

**Total:** ~13-19 hours

## Risks & Mitigations

### Risk 1: Bookmark Staleness

**Issue:** Security-scoped bookmarks can become stale if:
- Directory is moved/renamed
- macOS security policies change
- App is reinstalled

**Mitigation:**
- Check `bookmarkDataIsStale` on every access
- Re-prompt user to grant access if bookmark is stale
- Show clear error messages explaining what happened

### Risk 2: App Store Rejection

**Issue:** Apple may still reject if they think the app shouldn't need project directory access.

**Mitigation:**
- Clear App Review notes explaining why access is needed
- Screenshots showing file picker flow
- Emphasize read-only access to transcript files
- Show that app works (degraded) without access

### Risk 3: User Confusion

**Issue:** Users may not understand why they need to grant directory access.

**Mitigation:**
- Clear onboarding explaining Claude/Codex integration
- Visual guides showing where `.claude/projects` is
- FAQ/help documentation
- In-app tooltips and contextual help

## Open Questions

1. **Should we support manual project import?**
   - Allow users to drag-drop individual project directories instead of granting blanket access
   - Pros: More granular control, better privacy
   - Cons: More complex UX, harder to auto-discover new projects

2. **Should we cache project lists?**
   - Store discovered projects in database even if access is later revoked
   - Pros: App remains useful even without directory access
   - Cons: Stale data if transcripts are deleted

3. **Should we prompt for access on demand vs. first launch?**
   - Option A: Welcome flow on first launch (current plan)
   - Option B: Prompt only when user opens Projects window
   - Option C: Hybrid - optional on first launch, required when needed

## References

- Apple Docs: [App Sandbox Design Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/)
- Apple Docs: [Security-Scoped Bookmarks](https://developer.apple.com/documentation/foundation/nsurl/1417051-bookmarkdata)
- App Store Review Guidelines: [2.4.5(vi) - Sandboxing](https://developer.apple.com/app-store/review/guidelines/#sandbox)
- WWDC 2021: [Distribute apps in macOS with App Sandbox](https://developer.apple.com/videos/play/wwdc2021/10211/)

## Related Files

**Core Implementation:**
- `Contextify/Contextify.entitlements` - Sandbox configuration
- `app/Sources/ContextifyCore/HUDPreferences.swift` - Bookmark storage
- `ContextifyApp.swift` - App initialization, migration
- `ProjectDiscoveryService.swift` - Project scanning logic
- `FSEventsMonitor.swift` - Directory monitoring

**New Files Needed:**
- `Contextify/Contextify/SandboxSetupFlow.swift` - Onboarding coordinator
- `Contextify/Contextify/WelcomeView.swift` - First launch UI
- `Contextify/Contextify/AccessStatusView.swift` - Access status banner
- `app/Sources/ContextifyCore/Database/SandboxMigration.swift` - Migration logic

**Testing:**
- Manual test plan (this document, Phase 6)
- Automated tests for bookmark staleness detection
- UI tests for file picker flow
