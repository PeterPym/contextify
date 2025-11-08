# Database Migration & Custom Location

**Status:** Shipped (Settings > Database tab)
**Component:** DatabaseMigration.swift (155 lines)
**Related:** DatabaseManager, HUDPreferences, SettingsView

Contextify supports custom database locations for sync via Dropbox, iCloud Drive, or external drives. The migration system handles atomic database movement with validation and rollback.

---

## Overview

**Default Location:**
```
~/Library/Application Support/Contextify/contextify.db
```

**Supported Custom Locations:**
- Dropbox: `~/Library/CloudStorage/Dropbox/Apps/Contextify/`
- iCloud Drive: `~/Library/Mobile Documents/com~apple~CloudDocs/Contextify/`
- External drives: `/Volumes/BackupDrive/Contextify/`
- Any user-selected directory with write permissions

**Key Features:**
- ✅ Atomic migration with validation
- ✅ Disk space pre-check (requires 2× database size)
- ✅ Security-scoped bookmarks for sandboxed access
- ✅ Multi-machine conflict detection
- ✅ Automatic WAL/SHM cleanup
- ✅ Rollback on validation failure

---

## Architecture

### Migration Flow

```
User selects new location
    ↓
Close database connection (checkpoint + release locks)
    ↓
Validate source exists
    ↓
Check target doesn't exist
    ↓
Verify disk space (2× database size)
    ↓
Copy main DB file only (WAL/SHM intentionally skipped)
    ↓
Update UserDefaults with new path
    ↓
Reopen at new location
    ↓
PRAGMA quick_check validation
    ↓
Clean up orphaned WAL/SHM at old location
    ↓
Success (or rollback on failure)
```

### Components

**DatabaseMigration.swift**
- Pure static functions for migration logic
- Handles file operations, validation, cleanup
- Throws typed errors for UI feedback

**DatabaseManager.shared**
- Owns the GRDB connection pool
- Provides migration lock to prevent concurrent opens
- Supports custom locations via HUDPreferences

**HUDPreferences**
- Stores custom database directory path
- Uses UserDefaults with suite fallback
- Security-scoped bookmark persistence for sandbox

**SettingsView**
- File picker UI for location selection
- Multi-machine conflict warnings
- Migration progress/error display

---

## Security-Scoped Bookmarks

**Purpose:** Sandbox-compatible persistent file access

**Lifecycle:**
1. User selects directory via `NSOpenPanel`
2. Bookmark created with `.withSecurityScope` and `.securityScopeAllowOnlyReadAccess` options
3. Stored in UserDefaults as Data blob
4. Restored on app launch via `URL(resolvingBookmarkData:)`
5. Access scoped with `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`

**Fallback:**
- Non-sandboxed builds: Direct file access (no bookmark needed)
- Bookmark creation failure: Migration aborted with error

---

## Multi-Machine Conflict Detection

**Problem:** Multiple machines modifying the same database (via Dropbox/iCloud) causes SQLite corruption or data loss.

**Solution:** `database_access_metadata` table (schema v21)

**Table Schema:**
```sql
CREATE TABLE database_access_metadata (
  machine_id TEXT PRIMARY KEY,
  machine_name TEXT NOT NULL,
  last_access INTEGER NOT NULL,  -- epoch timestamp
  app_version TEXT NOT NULL
);
```

**Detection Algorithm:**
1. On database open, read all `machine_id` rows
2. If multiple machines accessed within 5 minutes → WARNING
3. If current machine is different from last access → INFO
4. Update own `machine_id` row with current timestamp

**User Warning (Settings UI):**
```
⚠️ Database accessed from multiple machines:
   - MacBook Pro (2 minutes ago)
   - Mac Studio (now)

Concurrent access may cause conflicts. Consider using
different databases per machine.
```

---

## Migration Error Handling

**Error Types:**

| Error | Cause | Recovery |
|-------|-------|----------|
| `sourceNotFound` | Database file missing | Check database location setting |
| `targetExists` | Target already has database | Choose different location or delete existing |
| `insufficientSpace` | Not enough disk space | Free up space or choose different volume |
| `copyFailed` | File system error | Check permissions, retry |
| `validationFailed` | Corrupted during copy | Automatic rollback to source location |

**Rollback Behavior:**
- On `validationFailed`: UserDefaults reverted, next open uses source location
- Source database NEVER deleted automatically (kept as backup)
- WAL/SHM files cleaned up at old location (orphaned after checkpoint)

---

## WAL Mode Implications

**Why only copy main DB file:**

SQLite uses Write-Ahead Logging (WAL) mode for concurrent reads:
- `contextify.db` - Main database file (complete after checkpoint)
- `contextify.db-wal` - Write-Ahead Log (uncommitted changes)
- `contextify.db-shm` - Shared memory index for WAL

**Migration Strategy:**
1. Close connection (triggers automatic checkpoint)
2. Checkpoint flushes all WAL changes to main DB
3. Copy only main DB file (now complete)
4. WAL/SHM at new location created fresh on first open
5. Old WAL/SHM deleted (useless without active connection)

**Result:** Clean migration with no orphaned files at target

---

## Usage

### Settings UI (User-Facing)

**Location:**
```
Menu Bar > Contextify > Settings > Database
```

**Workflow:**
1. User clicks "Change Location..."
2. File picker opens (directories only)
3. User selects destination
4. Confirmation dialog with disk space check
5. Migration runs with progress indicator
6. Success: "Migration complete, database now at [path]"
7. Failure: Error message + rollback

**Display:**
- Current location (default or custom)
- Available space at current location
- Multi-machine conflict warnings (if detected)
- "Restore Default Location" button (if custom set)

### Programmatic API

```swift
import ContextifyCore

// Migrate database to custom location
do {
  try await DatabaseMigration.migrateDatabase(
    to: URL(fileURLWithPath: "/Users/rob/Dropbox/Contextify"),
    deleteSource: false  // Keep old DB as backup
  )
  print("Migration successful")
} catch let error as DatabaseMigration.MigrationError {
  switch error {
  case .insufficientSpace(let req, let avail):
    print("Need \(req) bytes, have \(avail)")
  case .targetExists:
    print("Target already has database")
  default:
    print(error.localizedDescription)
  }
}

// Check current location
let currentPath = try DatabaseManager.shared.databasePath()
print("Database at: \(currentPath)")

// Restore default location
HUDPreferences.clearCustomDatabaseLocation()
DatabaseManager.shared.closeDatabase()  // Force reopen at default
```

---

## Testing

### Manual Test Scenarios

**1. Basic Migration:**
```bash
# Start with default location
ls ~/Library/Application\ Support/Contextify/contextify.db

# Change location via Settings UI to ~/Desktop/TestDB
# Verify:
ls ~/Desktop/TestDB/contextify.db  # New location
ls ~/Library/Application\ Support/Contextify/contextify.db  # Still exists (backup)
ls ~/Library/Application\ Support/Contextify/contextify.db-wal  # Deleted
```

**2. Insufficient Space:**
```bash
# Create small RAM disk (10MB)
hdiutil create -size 10m -fs HFS+ -volname SmallDisk /tmp/small.dmg
hdiutil attach /tmp/small.dmg

# Try to migrate 50MB database to SmallDisk
# Expected: Error dialog "Insufficient disk space..."
```

**3. Multi-Machine Conflict:**
```bash
# Machine 1: Migrate to ~/Dropbox/Contextify
# Machine 2: Open app pointing to same Dropbox folder
# Expected: Warning in Settings "Database accessed from multiple machines"
```

**4. Rollback on Corruption:**
```bash
# Manually corrupt target DB mid-migration (requires debugging)
# Expected: Migration fails, UserDefaults reverted, next open uses source
```

---

## Performance Characteristics

| Operation | Timing | Notes |
|-----------|--------|-------|
| Close connection | ~100ms | Checkpoint + release locks |
| Disk space check | <10ms | Volume resource query |
| Copy 100MB DB | ~2s | Local disk → local disk |
| Copy to network | ~30s | Depends on network speed (Dropbox sync) |
| PRAGMA quick_check | ~500ms | Full integrity scan |

**Optimization:**
- Only main DB copied (WAL/SHM recreated fresh)
- Checkpoint during close ensures no uncommitted changes
- 2× disk space requirement prevents mid-copy failures

---

## Known Limitations

1. **Network drives:** Migration may be slow (~30s for 100MB). Progress indicator shown in UI.
2. **Dropbox sync:** Migration completes locally, Dropbox syncs in background. Other machines won't see changes until sync finishes.
3. **iCloud Drive:** Similar to Dropbox - local migration fast, cloud sync async.
4. **Concurrent access:** No locking between machines. Users must manually coordinate (use different databases per machine).
5. **Sandbox restrictions:** Requires security-scoped bookmark. Bookmark invalidated if directory deleted/moved.

---

## Future Enhancements

**Out of Scope (Current Release):**
- Automatic conflict resolution (requires distributed consensus)
- Background sync status monitoring (Dropbox/iCloud API integration)
- Automatic per-machine database splitting
- Cloud-native multi-writer support (requires major architecture change)

**See Also:**
- `build/docs/architecture/sql-backend.md` - Schema and performance
- `build/docs/guides/troubleshooting-database.md` - Common issues (if created)
- Settings UI mockups: `build/assets/settings-database-tab.png` (if exists)
