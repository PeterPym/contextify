# Custom Database Location - Feature Specification

## Overview

Allow users to configure where Contextify stores its database file, enabling cloud sync via Dropbox, iCloud Drive, or any custom location.

**Current Behavior:**
- Database is hardcoded to `~/Library/Application Support/Contextify/contextify.db`
- No user control over location
- Cannot sync database between machines
- App sandbox migration would move DB to sandboxed container (losing manual access)

**Desired Behavior:**
- User can select custom database location
- Default remains `~/Library/Application Support/Contextify/`
- Support for Dropbox, iCloud Drive, and arbitrary directories
- Seamless migration from default location to custom location
- Multi-machine sync support (conflict detection)

---

## Use Cases

### Primary Use Case: Multi-Machine Sync
**Persona:** Developer working on multiple Macs (work laptop + home desktop)

**Scenario:**
1. User installs Contextify on Mac #1
2. User moves database to `~/Dropbox/Apps/Contextify/`
3. User installs Contextify on Mac #2
4. User points Mac #2 to same Dropbox folder
5. Both machines now share conversation history

**Expected Behavior:**
- Timeline updates reflect across machines (after Dropbox sync completes)
- No data loss or corruption from concurrent access
- Clear indication when database is syncing

### Secondary Use Case: Backup/Portability
**Persona:** User wants manual control over database backups

**Scenario:**
1. User selects external drive as database location
2. Database is accessible even when app is not running
3. User can manually backup/restore database files

---

## Distribution Strategy

**Dual Build Support:** Release (DMG) + App Store (sandboxed)

- **Release/DMG builds:** Direct filesystem access, no bookmarks needed
- **App Store builds:** Sandboxed, requires security-scoped bookmarks
- **Same codebase:** Runtime detection via `isSandboxed()` adapts behavior
- **Two entitlements files:** `Contextify.entitlements` (sandbox=false), `Contextify-AppStore.entitlements` (sandbox=true)

---

## Technical Design

### 0. Runtime Sandbox Detection

```swift
func isSandboxed() -> Bool {
    ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
}
```

All code paths check `isSandboxed()` to determine whether to use direct file access (Release) or bookmarks (App Store).

### 1. Database Location Storage

**Preference Key:**
```swift
// In HUDPreferences.swift
public static let customDatabaseLocationKey = "customDatabaseLocation"
public static let customDatabaseBookmarkKey = "customDatabaseLocationBookmark"
```

**Storage:**
- **Path:** Stored as String in UserDefaults
- **Bookmark:** Security-scoped bookmark for sandboxed access (when sandbox is enabled)
- **Precedence:**
  1. Custom location (if set)
  2. Default: `~/Library/Application Support/Contextify/`

### 2. DatabaseManager Changes

**Current:**
```swift
public func databasePath() throws -> URL {
    let appSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    return appSupport.appendingPathComponent("Contextify/contextify.db")
}
```

**Proposed:**
```swift
public func databasePath() throws -> URL {
    // 1. Check for custom location in preferences
    if let customPath = HUDPreferences.shared.customDatabaseLocation {
        return try resolveCustomDatabasePath(customPath)
    }

    // 2. Fall back to default
    return try defaultDatabasePath()
}

private func resolveCustomDatabasePath(_ path: String) throws -> URL {
    let baseURL = URL(fileURLWithPath: path)

    // Ensure directory exists
    try FileManager.default.createDirectory(
        at: baseURL,
        withIntermediateDirectories: true
    )

    // Return database file path
    return baseURL.appendingPathComponent("contextify.db")
}

private func defaultDatabasePath() throws -> URL {
    let appSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let contextifyDir = appSupport.appendingPathComponent("Contextify", isDirectory: true)
    try FileManager.default.createDirectory(at: contextifyDir, withIntermediateDirectories: true)
    return contextifyDir.appendingPathComponent("contextify.db")
}
```

### 3. Settings UI

**Location:** New Settings window (Cmd+,) or Settings tab in existing preferences

**UI Components:**

```
┌─────────────────────────────────────────────────┐
│ Database Location                               │
├─────────────────────────────────────────────────┤
│                                                 │
│ ⦿ Default Location                              │
│   ~/Library/Application Support/Contextify/     │
│                                                 │
│ ○ Custom Location                               │
│   [~/Dropbox/Apps/Contextify     ] [Choose...] │
│                                                 │
│ ℹ️ Changing location will migrate your database │
│   to the new location. This may take a moment.  │
│                                                 │
│               [Cancel]  [Change Location]       │
└─────────────────────────────────────────────────┘
```

**Quick Access Presets:**
- Dropbox: `~/Dropbox/Apps/Contextify/`
- iCloud Drive: `~/Library/Mobile Documents/com~apple~CloudDocs/Contextify/`
- Custom: File picker

### 4. Migration Process

**When user changes location:**

```swift
func migrateDatabase(from: URL, to: URL) async throws {
    log.info("📦 Migrating database from \(from.path) to \(to.path)")

    // 1. Close existing database connection
    try await DatabaseManager.shared.closePool()

    // 2. Create target directory
    let targetDir = to.deletingLastPathComponent()
    try FileManager.default.createDirectory(
        at: targetDir,
        withIntermediateDirectories: true
    )

    // 3. Copy database files (db, -wal, -shm)
    let fm = FileManager.default
    try fm.copyItem(at: from, to: to)

    if fm.fileExists(atPath: from.appendingPathExtension("wal").path) {
        try fm.copyItem(
            at: from.appendingPathExtension("wal"),
            to: to.appendingPathExtension("wal")
        )
    }

    if fm.fileExists(atPath: from.appendingPathExtension("shm").path) {
        try fm.copyItem(
            at: from.appendingPathExtension("shm"),
            to: to.appendingPathExtension("shm")
        )
    }

    // 4. Update preference
    HUDPreferences.shared.setCustomDatabaseLocation(to.deletingLastPathComponent().path)

    // 5. Reopen database at new location
    _ = try DatabaseManager.shared.pool

    // 6. Verify integrity
    try DatabaseManager.shared.validateDatabase(DatabaseManager.shared.pool)

    log.info("✅ Database migration complete")

    // 7. Optional: Delete old database (with user confirmation)
    // await confirmDeleteOldDatabase(from)
}
```

### 5. Conflict Detection (Multi-Machine Sync)

**Challenge:** Two machines writing to the same database file can cause corruption.

**Solution:** WAL mode + last-write-wins with conflict detection

**Implementation:**

```swift
// Add application_id metadata to database
// Each machine gets a unique ID
let machineID = getMachineID() // e.g., UUID stored in Keychain

// On database open, check for conflicts
func detectConflict() throws {
    let lastMachineID = try pool.read { db in
        try String.fetchOne(db, sql: "PRAGMA application_id")
    }

    if let last = lastMachineID, last != machineID {
        log.warning("⚠️ Database was last written by different machine")
        // Show warning to user if writes are attempted
    }
}
```

**UI Warning:**
```
⚠️ Database Last Modified on Another Machine

This database was last modified by "MacBook Pro" at 3:42 PM.
Contextify will sync changes, but concurrent editing may cause conflicts.

[Refresh Timeline]  [Continue]
```

---

## Implementation Plan

### Phase 1: Basic Custom Location (4 hours)
**Goal:** Allow user to select custom database location with migration

**Tasks:**
1. Add preference keys to `HUDPreferences.swift`
2. Modify `DatabaseManager.databasePath()` to check custom location
3. Create `DatabaseMigration.swift` with migration logic
4. Add basic Settings UI with file picker
5. Test migration flow

**Files to Modify:**
- `app/Sources/ContextifyCore/HUDPreferences.swift`
- `app/Sources/ContextifyCore/Database/DatabaseManager.swift`
- `Contextify/Contextify/SettingsView.swift` (create if doesn't exist)

**Testing:**
- [ ] Migration from default to custom location succeeds
- [ ] Database opens correctly at custom location
- [ ] Timeline loads after migration
- [ ] WAL files are copied correctly

### Phase 2: Quick Access Presets (2 hours)
**Goal:** Add Dropbox/iCloud Drive presets

**Tasks:**
1. Add preset buttons to Settings UI
2. Detect if Dropbox/iCloud is available
3. Show disabled state if not installed
4. Validate cloud storage paths

**Files to Modify:**
- `Contextify/Contextify/SettingsView.swift`

**Testing:**
- [ ] Dropbox preset works if Dropbox is installed
- [ ] iCloud preset works if iCloud Drive is enabled
- [ ] Disabled presets show helpful message

### Phase 3: Conflict Detection (3 hours)
**Goal:** Warn users about multi-machine access

**Tasks:**
1. Add machine ID to database metadata
2. Detect when DB was last written by different machine
3. Show warning UI when conflict detected
4. Add "Refresh Timeline" action to force reload

**Files to Modify:**
- `app/Sources/ContextifyCore/Database/DatabaseManager.swift`
- `Contextify/Contextify/ConversationMonitor.swift` (refresh action)
- `Contextify/Contextify/ContentView.swift` (warning banner)

**Testing:**
- [ ] Machine ID is stored correctly
- [ ] Warning appears when opening DB from different machine
- [ ] Refresh action reloads timeline correctly

### Phase 4: BookmarkManager Foundation (3 hours)
**Goal:** Create unified bookmark infrastructure for all external directories

**Tasks:**
1. Create `BookmarkManager.swift` with runtime sandbox detection
2. Support bookmarks for database location, Claude projects, Codex projects
3. Integrate with `DatabaseManager` for custom DB location
4. Add App Store entitlements file (`Contextify-AppStore.entitlements`)

**Files to Create:**
- `app/Sources/ContextifyCore/BookmarkManager.swift`
- `Contextify/Contextify-AppStore.entitlements`

**Files to Modify:**
- `app/Sources/ContextifyCore/Database/DatabaseManager.swift`
- `Contextify/Contextify/SettingsView.swift`

**Testing:**
- [ ] Runtime sandbox detection works correctly
- [ ] Bookmarks created/resolved in sandboxed builds
- [ ] Direct access works in non-sandboxed builds
- [ ] Database location persists across app restarts

### Phase 5: Project Discovery Sandbox Support (4 hours)
**Goal:** Enable project discovery in App Store builds with bookmarks

**Tasks:**
1. Add first-launch setup wizard for App Store builds
2. Request bookmarks for `~/.claude/projects` and `~/.codex/projects`
3. Integrate `BookmarkManager` with `ProjectDiscoveryService`
4. Integrate `BookmarkManager` with `ProjectActivityMonitor` (FSEvents)
5. Add AppStore build configuration to Xcode project

**Files to Create:**
- `Contextify/Contextify/FirstLaunchSetupView.swift`
- `scripts/xc-appstore.sh`
- `scripts/ExportOptions-AppStore.plist`

**Files to Modify:**
- `Contextify/Contextify/ProjectDiscoveryService.swift`
- `Contextify/Contextify/ProjectActivityMonitor.swift`
- `Contextify/Contextify/ContextifyApp.swift` (show setup on first launch)
- `Contextify/Contextify.xcodeproj/project.pbxproj` (AppStore configuration)
- `Makefile` (add appstore targets)

**Testing:**
- [ ] First launch wizard appears in sandboxed builds
- [ ] Projects discovered after granting bookmarks
- [ ] FSEvents monitoring works with bookmarked directories
- [ ] No wizard appears in non-sandboxed builds
- [ ] Both build types discover projects correctly

---

## Edge Cases & Error Handling

### 1. Invalid Custom Path
**Scenario:** User selects path without write permissions

**Handling:**
- Validate path before migration
- Show error: "Cannot write to selected location. Please choose a different folder."
- Revert to previous location if migration fails

### 2. Insufficient Disk Space
**Scenario:** Target location doesn't have enough space for database

**Handling:**
- Check available space before migration
- Show error with size requirements
- Abort migration if insufficient space

### 3. Database Already Exists at Target
**Scenario:** User selects location that already has a `contextify.db`

**Handling:**
- Detect existing database
- Prompt: "A database already exists at this location. What would you like to do?"
  - **Use Existing:** Switch to existing database
  - **Merge:** Attempt to merge (advanced - Phase 5)
  - **Replace:** Delete existing and migrate current
  - **Cancel:** Keep current location

### 4. Cloud Sync In Progress
**Scenario:** User opens app while Dropbox is syncing database

**Handling:**
- Detect if file is being synced (check for Dropbox/iCloud metadata)
- Show warning: "Database is currently syncing. Please wait..."
- Retry connection after delay

### 5. Network Drive Disconnect
**Scenario:** Database is on network drive that becomes unavailable

**Handling:**
- Detect connection loss (file I/O errors)
- Show: "Database connection lost. Reconnect to [drive] or switch to local database."
- Allow switching to default location as recovery

---

## Security Considerations

### Sandboxed Builds
- Must use security-scoped bookmarks for custom locations
- Prompt user for permission on first access
- Store bookmark in preferences for future launches

### File Permissions
- Validate write access before migration
- Respect macOS file permissions
- Handle permission errors gracefully

### Cloud Storage
- Warn users that cloud-synced databases may expose conversation history
- Recommend encrypted cloud storage if available
- Document security implications in Settings UI

---

## Documentation Updates

### Phase 0: Pre-Implementation Audit (1 hour)
**Validate existing docs reflect recent changes before adding new content**

1. **Release/Signing Documentation**
   - Verify `scripts/RELEASE.md` is current (added in commit 6664f27)
   - Verify `scripts/SIGNING-SETUP.md` is current (added in commit 6664f27)
   - Check `build/notes/release-build-verification.md` is accurate

2. **iTerm2/Terminal Integration Removal**
   - Confirm `build/notes/future-features.md` documents removal (updated in commit 14c0410)
   - Check `CLAUDE.md` doesn't reference removed features
   - Remove/update any permission descriptions for removed entitlements

3. **Technical Reference Updates**
   - `build/notes/technical-reference/sql-backend-architecture.md` - Check database location references
   - Database schema version (currently v16) is documented

### Phase 6: Post-Implementation Documentation (2 hours)

**CLAUDE.md Updates:**
- Add Database Location section under Project Structure
- Document BookmarkManager for App Store builds
- Update build configurations (Debug, Release, AppStore)
- Note dual distribution strategy

**Technical Reference:**
- Create `build/notes/technical-reference/bookmark-manager.md`
- Document runtime sandbox detection pattern
- Security-scoped bookmark lifecycle

**User-Facing (if Settings window exists):**
- In-app help text for database location settings
- Brief migration guide

---

## Success Criteria

**Must Have:**
- [ ] User can select custom database location
- [ ] Migration from default to custom location works reliably
- [ ] Database opens correctly at custom location after app restart
- [ ] Timeline and all features work normally with custom location
- [ ] Dropbox and iCloud Drive presets work

**Nice to Have:**
- [ ] Conflict detection warns about multi-machine access
- [ ] Security-scoped bookmarks work in sandboxed builds
- [ ] Merge capability for existing databases

**Quality Metrics:**
- Migration completes in < 5 seconds for typical database (< 100MB)
- Zero data loss during migration (verified by checksum)
- Settings UI is intuitive (no user confusion in testing)

---

## Related Work

### App Sandbox Implementation
- See: `build/notes/app-store/sandbox-implementation-plan.md`
- Custom database location must be compatible with sandbox
- Security-scoped bookmarks required for sandboxed builds

### Database Schema Migrations
- See: `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`
- Migration process should trigger schema migrations if needed
- Ensure forward compatibility (old app → new DB location)

---

## Open Questions

1. **Should we allow databases on network drives?**
   - Pro: Maximum flexibility
   - Con: Performance issues, connection reliability

2. **Should we support multiple databases (profiles)?**
   - Pro: Separate work/personal conversations
   - Con: Complexity, switching overhead

3. **Should we auto-detect cloud storage paths?**
   - Pro: Better UX, less manual setup
   - Con: Privacy concerns (scanning filesystem)

4. **Should migration delete the old database?**
   - Pro: Save disk space
   - Con: Users may want backup at old location

5. **Should we support database encryption?**
   - Pro: Security for cloud-synced databases
   - Con: Performance overhead, key management complexity
