# Database Migration Runbook

**Status:** Active (2025-11-17)
**Related:** `build/docs/components/database-migration.md`, `DatabaseMigration.swift`
**Purpose:** Step-by-step operational procedures for database migration, rollback, and troubleshooting

---

## Executive Summary

This document provides **operational procedures** for database migration tasks. Use this when:
- Moving database to Dropbox/iCloud/external drive
- Recovering from migration failures
- Troubleshooting multi-machine conflicts
- Performing backup/restore operations
- Investigating corruption issues

**Related Component Doc:** `build/docs/components/database-migration.md` - Read that first for architecture overview.

---

## Prerequisites

### System Requirements

- **macOS:** 14.0+ (minimum deployment target)
- **Disk Space:** 2× current database size at destination
- **Permissions:** Write access to source and destination directories
- **Sandboxed Builds:** Folder authorization for custom locations

### Database State Checks

Before migrating, verify database health:

```bash
# 1. Check database size
ls -lh ~/Library/Application\ Support/Contextify/contextify.db

# 2. Verify database integrity
sqlite3 ~/Library/Application\ Support/Contextify/contextify.db "PRAGMA quick_check"
# Expected output: ok

# 3. Check WAL file size (should be small after checkpoint)
ls -lh ~/Library/Application\ Support/Contextify/contextify.db-wal
```

**Action Required:**
- If `quick_check` returns anything other than "ok" → **DO NOT MIGRATE** → Investigate corruption
- If WAL file >10MB → Close app, reopen, recheck (checkpoint should flush)

---

## Standard Migration Procedure

### Step 1: Choose Destination

**Recommended Locations:**

| Location | Path | Use Case | Pros | Cons |
|----------|------|----------|------|------|
| **Dropbox** | `~/Library/CloudStorage/Dropbox/Apps/Contextify/` | Multi-machine sync | Auto-sync across devices | Requires Dropbox account |
| **iCloud Drive** | `~/Library/Mobile Documents/com~apple~CloudDocs/Contextify/` | Apple ecosystem | Native macOS integration | 5GB free limit |
| **External Drive** | `/Volumes/<DriveName>/Contextify/` | Backup/archival | Large capacity | Not always mounted |
| **Local Custom** | `~/Documents/Contextify/` | Custom workflow | User-controlled | No sync |

**Decision Tree:**

```
Need multi-machine sync?
  ├─ Yes → Already have Dropbox? → Yes → Dropbox
  │                                → No → iCloud Drive
  └─ No  → Need offline access? → Yes → Local custom
                                 → No → External drive (backup)
```

### Step 2: Verify Disk Space

```bash
# Check available space at destination
df -h ~/Library/CloudStorage/Dropbox/Apps/Contextify/

# Compare with database size (need 2× for safety)
du -sh ~/Library/Application\ Support/Contextify/contextify.db
```

**Example:**
```
Database size: 150 MB
Required space: 300 MB (2× buffer)
Available space: 500 MB ✅
```

### Step 3: Close Contextify

**Critical:** App MUST be fully closed before manual migration.

```bash
# Graceful quit
osascript -e 'quit app "Contextify"'

# Verify no processes running
ps aux | grep Contextify
# Should return nothing (except grep itself)
```

**Why:** SQLite locks prevent file copy while connection is active.

### Step 4: Perform Migration (UI Method)

**Recommended:** Use Settings UI for automatic migration with validation.

1. Open Contextify
2. Menu Bar → **Contextify** → **Settings** (⌘,)
3. Click **Database** tab
4. Click **Change Location...**
5. File picker opens → Select destination folder
6. Confirmation dialog appears:
   ```
   Migrate database to:
   ~/Library/CloudStorage/Dropbox/Apps/Contextify/

   Current size: 150 MB
   Available space: 500 MB

   [Cancel] [Migrate]
   ```
7. Click **Migrate**
8. Progress indicator shows:
   - Closing database connection...
   - Copying database file (150 MB)...
   - Validating migrated database...
   - Cleaning up old WAL/SHM files...
9. Success dialog: "Migration complete. Database now at [path]."

**On Success:**
- App reopens database at new location
- Old database kept as backup (NOT deleted)
- WAL/SHM files cleaned up at old location

**On Failure:**
- Error message displayed with specific reason
- Database reverts to original location (automatic rollback)
- See "Troubleshooting" section for recovery

### Step 5: Verify Migration

```bash
# Check new location
ls -lh ~/Library/CloudStorage/Dropbox/Apps/Contextify/contextify.db

# Verify no WAL/SHM at new location initially (created on first write)
ls ~/Library/CloudStorage/Dropbox/Apps/Contextify/contextify.db-wal
# Should not exist immediately after migration

# Check old location (backup should still exist)
ls -lh ~/Library/Application\ Support/Contextify/contextify.db
# Main DB should still exist

ls ~/Library/Application\ Support/Contextify/contextify.db-wal
# WAL/SHM should be DELETED (orphaned files cleaned up)
```

### Step 6: Test App Functionality

**Post-Migration Checklist:**

- [ ] App launches successfully
- [ ] Timeline loads and displays entries
- [ ] Project switcher shows all projects
- [ ] Can create new timeline entries (writes to new DB)
- [ ] Search works
- [ ] Settings → Database shows new location

**Quick Test:**
```bash
# Open timeline and verify entries load
# Create a test project or entry
# Verify written to new location:
ls -lh ~/Library/CloudStorage/Dropbox/Apps/Contextify/contextify.db-wal
# WAL file should now exist and have recent timestamp
```

---

## Manual Migration (CLI Method)

**Use When:** Automation/scripting required, UI not available.

**Danger:** No automatic validation or rollback. Use with caution.

### Procedure

```bash
#!/bin/bash
set -euo pipefail

SOURCE="$HOME/Library/Application Support/Contextify/contextify.db"
DEST_DIR="$HOME/Library/CloudStorage/Dropbox/Apps/Contextify"
DEST="$DEST_DIR/contextify.db"

# 1. Quit Contextify
echo "Closing Contextify..."
osascript -e 'quit app "Contextify"'
sleep 2

# 2. Verify source exists
if [ ! -f "$SOURCE" ]; then
  echo "ERROR: Source database not found at $SOURCE"
  exit 1
fi

# 3. Check destination doesn't exist
if [ -f "$DEST" ]; then
  echo "ERROR: Destination already has a database at $DEST"
  exit 1
fi

# 4. Create destination directory
mkdir -p "$DEST_DIR"

# 5. Check disk space (simplified - manual calculation)
SOURCE_SIZE=$(stat -f%z "$SOURCE")
REQUIRED=$((SOURCE_SIZE * 2))
echo "Database size: $(numfmt --to=iec --suffix=B $SOURCE_SIZE)"
echo "Required space: $(numfmt --to=iec --suffix=B $REQUIRED)"

# 6. Copy main database file
echo "Copying database..."
cp "$SOURCE" "$DEST"

# 7. Validate copy
echo "Validating..."
RESULT=$(sqlite3 "$DEST" "PRAGMA quick_check")
if [ "$RESULT" != "ok" ]; then
  echo "ERROR: Validation failed: $RESULT"
  rm "$DEST"
  exit 1
fi

# 8. Update preference (macOS UserDefaults)
# Canonical key used by the app; legacy key is mirrored automatically on recent builds.
defaults write dev.contextify "dev.contextify.customDatabaseLocation" -string "$DEST_DIR"

# 9. Clean up old WAL/SHM
rm -f "$SOURCE-wal" "$SOURCE-shm"

echo "✅ Migration complete"
echo "   Source (backup): $SOURCE"
echo "   New location: $DEST"
```

**Post-Script:**
1. Launch Contextify
2. Verify opens at new location (check Settings → Database)
3. If problems, restore with rollback procedure

---

## Rollback Procedure

### Scenario: Migration Failed or New Location Problematic

**Symptoms:**
- App fails to launch after migration
- Database corruption detected
- Performance issues at new location

**Rollback Steps:**

```bash
# 1. Quit Contextify
osascript -e 'quit app "Contextify"'

# 2. Clear custom database location preference
defaults delete dev.contextify "dev.contextify.customDatabaseLocation"
defaults delete dev.contextify "dev.contextify.database_location" 2>/dev/null || true

# 3. Verify old database still exists
ls -lh ~/Library/Application\ Support/Contextify/contextify.db
# Should still be there (migration doesn't delete source)

# 4. Delete failed migration (optional)
rm -rf ~/Library/CloudStorage/Dropbox/Apps/Contextify/

# 5. Relaunch Contextify
open -a Contextify
```

**Expected Result:**
- App opens using default location
- All data intact (migration never deleted source)

### Scenario: Accidental Deletion of Source Database

**Critical Recovery:**

If source database was manually deleted after migration:

```bash
# 1. Check if migration target is intact
ls -lh ~/Library/CloudStorage/Dropbox/Apps/Contextify/contextify.db

# 2. If intact, copy back to default location
cp ~/Library/CloudStorage/Dropbox/Apps/Contextify/contextify.db \
   ~/Library/Application\ Support/Contextify/contextify.db

# 3. Clear custom location preference
defaults delete dev.contextify "dev.contextify.customDatabaseLocation"
defaults delete dev.contextify "dev.contextify.database_location" 2>/dev/null || true

# 4. Validate restored database
sqlite3 ~/Library/Application\ Support/Contextify/contextify.db "PRAGMA quick_check"

# 5. Relaunch app
open -a Contextify
```

---

## Multi-Machine Conflict Resolution

### Problem: Database Accessed from Multiple Machines

**Symptoms:**

Settings UI shows warning:
```
⚠️ Database accessed from multiple machines:
   - MacBook Pro (2 minutes ago)
   - Mac Studio (now)

Concurrent access may cause conflicts.
```

**Root Cause:**

SQLite is NOT designed for concurrent multi-writer access over network filesystems (Dropbox, iCloud). Race conditions can cause:
- Write conflicts
- Corruption (rare but possible)
- Data loss

### Solution 1: Sequential Access (Recommended)

**Policy:** Only one machine accesses database at a time.

**Implementation:**

1. **Primary machine:** Keep database at custom location (Dropbox)
2. **Secondary machines:** Use local-only databases

**On Secondary Machine:**
```bash
# Restore default location (don't sync with Dropbox)
defaults delete dev.contextify "dev.contextify.database_location"
# Relaunch → uses local database
```

**Trade-off:** No automatic sync, but no conflicts.

### Solution 2: Separate Databases Per Machine

**Policy:** Each machine has its own database.

**Implementation:**

```bash
# Machine 1: Use Dropbox folder "Mac-Studio"
defaults write dev.contextify "dev.contextify.customDatabaseLocation" \
  -string "$HOME/Library/CloudStorage/Dropbox/Apps/Contextify-MacStudio"
defaults write dev.contextify "dev.contextify.database_location" \
  -string "$HOME/Library/CloudStorage/Dropbox/Apps/Contextify-MacStudio"

# Machine 2: Use Dropbox folder "MacBook-Pro"
defaults write dev.contextify "dev.contextify.customDatabaseLocation" \
  -string "$HOME/Library/CloudStorage/Dropbox/Apps/Contextify-MacBookPro"
defaults write dev.contextify "dev.contextify.database_location" \
  -string "$HOME/Library/CloudStorage/Dropbox/Apps/Contextify-MacBookPro"
```

**Trade-off:** Databases NOT synced, but no conflicts.

### Solution 3: Export/Import Workflow (Manual Sync)

**Policy:** Manually export from primary, import to secondary.

**Not Yet Implemented:** Contextify doesn't have export/import UI (future feature).

**Workaround:** Copy database file manually with care:

```bash
# On primary machine: Copy database to shared folder
cp ~/Library/Application\ Support/Contextify/contextify.db \
   ~/Library/CloudStorage/Dropbox/Contextify-Backup-$(date +%Y%m%d).db

# On secondary machine: Replace local database (DESTRUCTIVE!)
# WARNING: This overwrites local database!
osascript -e 'quit app "Contextify"'
cp ~/Library/CloudStorage/Dropbox/Contextify-Backup-20251117.db \
   ~/Library/Application\ Support/Contextify/contextify.db
open -a Contextify
```

---

## Backup & Restore Operations

### Creating Backup

**Automatic (On Migration):**

Migration ALWAYS keeps source as backup. No action needed.

**Manual (Scheduled):**

```bash
#!/bin/bash
# Daily backup script

BACKUP_DIR="$HOME/Documents/Contextify-Backups"
mkdir -p "$BACKUP_DIR"

CUSTOM_DIR=$(defaults read dev.contextify dev.contextify.customDatabaseLocation 2>/dev/null || true)
LEGACY_DIR=$(defaults read dev.contextify dev.contextify.database_location 2>/dev/null || true)
if [ -n "$CUSTOM_DIR" ]; then
  DB_PATH="$CUSTOM_DIR/contextify.db"
elif [ -n "$LEGACY_DIR" ]; then
  DB_PATH="$LEGACY_DIR/contextify.db"
else
  DB_PATH="$HOME/Library/Application Support/Contextify/contextify.db"
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/contextify-$TIMESTAMP.db"

# Copy database
cp "$DB_PATH" "$BACKUP_FILE"

# Verify backup
RESULT=$(sqlite3 "$BACKUP_FILE" "PRAGMA quick_check")
if [ "$RESULT" = "ok" ]; then
  echo "✅ Backup created: $BACKUP_FILE"
else
  echo "❌ Backup validation failed"
  rm "$BACKUP_FILE"
  exit 1
fi

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "contextify-*.db" -mtime +7 -delete
```

**Schedule with launchd:**

```xml
<!-- ~/Library/LaunchAgents/dev.contextify.backup.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.contextify.backup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/you/Scripts/backup-contextify.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
```

```bash
# Load agent
launchctl load ~/Library/LaunchAgents/dev.contextify.backup.plist
```

### Restoring from Backup

**Procedure:**

```bash
# 1. Quit Contextify
osascript -e 'quit app "Contextify"'

# 2. Locate backup file
ls -lh ~/Documents/Contextify-Backups/

# 3. Validate backup before restore
BACKUP="$HOME/Documents/Contextify-Backups/contextify-20251117-020000.db"
RESULT=$(sqlite3 "$BACKUP" "PRAGMA quick_check")
if [ "$RESULT" != "ok" ]; then
  echo "ERROR: Backup is corrupted!"
  exit 1
fi

# 4. Get current database location
CUSTOM_DIR=$(defaults read dev.contextify dev.contextify.customDatabaseLocation 2>/dev/null || true)
LEGACY_DIR=$(defaults read dev.contextify dev.contextify.database_location 2>/dev/null || true)
if [ -n "$CUSTOM_DIR" ]; then
  DB_PATH="$CUSTOM_DIR/contextify.db"
elif [ -n "$LEGACY_DIR" ]; then
  DB_PATH="$LEGACY_DIR/contextify.db"
else
  DB_PATH="$HOME/Library/Application Support/Contextify/contextify.db"
fi

# 5. Backup current database (double safety)
cp "$DB_PATH" "$DB_PATH.before-restore"

# 6. Restore from backup
cp "$BACKUP" "$DB_PATH"

# 7. Delete WAL/SHM (will be recreated fresh)
rm -f "$DB_PATH-wal" "$DB_PATH-shm"

# 8. Relaunch app
open -a Contextify
```

**Verify Restoration:**

1. Check timeline loads
2. Verify expected projects/entries present
3. Test write operations

---

## Troubleshooting

### Issue: "Source database not found"

**Symptoms:** Migration fails with error: "Source database not found."

**Cause:** Database path changed or file moved.

**Resolution:**

```bash
# 1. Find database
find ~/Library -name "contextify.db" 2>/dev/null

# 2. Check custom location preference
defaults read dev.contextify "dev.contextify.customDatabaseLocation"
defaults read dev.contextify "dev.contextify.database_location"

# 3. If preference is stale, clear it
defaults delete dev.contextify "dev.contextify.customDatabaseLocation"
defaults delete dev.contextify "dev.contextify.database_location"

# 4. Verify default location exists
ls -lh ~/Library/Application\ Support/Contextify/contextify.db
```

### Issue: "Insufficient disk space"

**Symptoms:** Migration fails with error: "Need 300 MB, have 150 MB."

**Cause:** Destination volume doesn't have 2× database size available.

**Resolution:**

**Option 1: Free up space**

```bash
# Check what's using space
du -sh ~/Library/CloudStorage/Dropbox/* | sort -h

# Delete large unneeded files
# Then retry migration
```

**Option 2: Choose different destination**

Use local drive with more space, or external drive.

### Issue: "Database validation failed after migration"

**Symptoms:** Migration fails with error: "Database validation failed."

**Cause:** Corruption during copy (disk error, filesystem issue).

**Resolution:**

**Automatic:** App automatically rolls back to source location.

**Manual Verification:**

```bash
# Check source is intact
sqlite3 ~/Library/Application\ Support/Contextify/contextify.db "PRAGMA quick_check"

# If source is corrupted, restore from backup
# (See "Restoring from Backup" section)
```

### Issue: "A database already exists at the target location"

**Symptoms:** Migration fails with error: "A database already exists at the target location."

**Cause:** Previous migration left database at destination, or multiple machines using same location.

**Resolution:**

**Option 1: Delete existing database (if safe)**

```bash
# DANGER: Only if you're certain it's an old/unused database!
rm ~/Library/CloudStorage/Dropbox/Apps/Contextify/contextify.db*

# Retry migration
```

**Option 2: Choose different destination**

```bash
# Use timestamped subdirectory
~/Library/CloudStorage/Dropbox/Apps/Contextify-20251117/
```

### Issue: App launches but shows empty timeline

**Symptoms:** App opens successfully, but no projects or entries visible.

**Cause:** Database opened at wrong location (empty database created).

**Resolution:**

```bash
# 1. Check current database location in UI
# Settings → Database → Current Location

# 2. Verify database has content
sqlite3 <current-location>/contextify.db "SELECT COUNT(*) FROM projects"
# Should return >0

# 3. If 0, database is empty → restore preference
defaults delete dev.contextify "dev.contextify.database_location"

# 4. Relaunch app
```

### Issue: Performance degraded after migration to cloud storage

**Symptoms:** App is slow, timeline takes long to load.

**Cause:** Network latency for cloud storage (Dropbox/iCloud syncing).

**Resolution:**

**Option 1: Wait for sync to complete**

```bash
# Check Dropbox sync status
ls -l@ ~/Library/CloudStorage/Dropbox/Apps/Contextify/contextify.db
# Extended attributes will show sync status
```

**Option 2: Migrate back to local storage**

Use rollback procedure to return to default local location.

**Option 3: Pause syncing during use**

- Dropbox: Pause Syncing (menu bar icon)
- iCloud: Not supported (always syncs)

---

## Related Documentation

- **Component Architecture:** `build/docs/components/database-migration.md`
- **Source:** `app/Sources/ContextifyCore/Database/DatabaseMigration.swift` (155 lines)
- **Database Manager:** `app/Sources/ContextifyCore/Database/DatabaseManager.swift`
- **Preferences:** `app/Sources/ContextifyCore/HUDPreferences.swift`
- **Database Locations:** `build/docs/operations/DATABASE-LOCATIONS.md`

---

## Changelog

**2025-11-17:**
- Initial runbook created
- Step-by-step migration procedures (UI and CLI methods)
- Rollback procedures for failed migrations
- Multi-machine conflict resolution strategies
- Backup and restore operations with launchd scheduling
- Comprehensive troubleshooting guide for common issues
- Verification checklists for post-migration testing
