# Database Management Guide

## Overview

Contextify uses a SQLite database (`transcripts.db`) to store transcript data, entries, and metadata. This guide covers safe database operations.

## Critical Rules

### ⚠️  NEVER Delete Database Files Manually

**DO NOT** use commands like:
```bash
rm ~/Library/Application\ Support/Contextify/transcripts.db*  # ❌ WRONG
```

**Why?** Deleting database files while the app is running causes:
- `vnode unlinked while in use` errors
- Database corruption
- Loss of data integrity
- SQLite lock file issues

### ✅ ALWAYS Use the Database Manager Script

All database operations MUST go through `scripts/db_manager.sh`, which:
- Automatically quits the app before operations
- Creates backups before any destructive changes
- Handles WAL and SHM files correctly
- Prevents file system race conditions

## Database Manager Commands

### Backup Database

Create a timestamped backup of the current database:

```bash
./scripts/db_manager.sh backup
# or
make db-backup
```

Output:
```
ℹ Creating backup: transcripts.db-20251019-091406
ℹ Quitting Contextify...
✓ App closed
✓ Backup created: transcripts.db-20251019-091406 (3.2M)
ℹ Location: /Users/rob/code/projects/contextify/build/db-backups/transcripts.db-20251019-091406
ℹ Contains: 23 transcripts, 1507 entries
```

### List Backups

View all available database backups:

```bash
./scripts/db_manager.sh list
# or
make db-list
```

Output:
```
ℹ Available database backups:

 1. 2025-10-19 09:14:06 | 3.3M | transcripts.db-20251019-091406 | 23 transcripts, 1507 entries
 2. 2025-10-19 08:30:15 | 2.8M | transcripts.db-20251019-083015 | 22 transcripts, 1463 entries
```

### Clean Database

Delete the current database (creates automatic backup first):

```bash
./scripts/db_manager.sh clean
# or
make clean-db
```

This will:
1. Show current database statistics
2. Create an automatic backup
3. Ask for confirmation (if interactive)
4. Delete all database files
5. Next app launch will create fresh database

**⚠️  Agent Rule:** ALWAYS ask user for approval before running this command.

### Restore Database

Restore from a backup:

```bash
# Restore most recent backup
./scripts/db_manager.sh restore latest
# or
make db-restore

# Restore specific backup
./scripts/db_manager.sh restore transcripts.db-20251019-091406
```

This will:
1. Create backup of current database (if exists)
2. Quit the app
3. Restore selected backup
4. Show restored statistics

## Backup Storage

Backups are stored in: `build/db-backups/`

Example structure:
```
build/db-backups/
├── transcripts.db-20251019-091406     # Main database file
├── transcripts.db-20251019-091406-wal # Write-Ahead Log (if exists)
├── transcripts.db-20251019-091406-shm # Shared Memory (if exists)
├── transcripts.db-20251019-083015
└── transcripts.db-20251018-220000
```

**Note:** `build/` directory is gitignored, so backups are local only.

## Database Location

The transcript database is stored at:
```
~/Library/Application Support/Contextify/transcripts.db
```

Additional files (when database is in use):
- `transcripts.db-wal` - Write-Ahead Log (SQLite WAL mode)
- `transcripts.db-shm` - Shared Memory file

## Common Workflows

### Testing with Fresh Database

```bash
# Create backup first
make db-backup

# Clean database (creates automatic backup)
make clean-db

# Launch app (will create fresh database)
open .derived-dmg/Build/Products/Debug/Contextify.app

# Wait for ingestion...
# If needed, restore backup
make db-restore
```

### Comparing Database States

```bash
# Backup current state
make db-backup

# Make changes (test feature, etc.)
# ...

# Check differences
sqlite3 ~/Library/Application\ Support/Contextify/transcripts.db \
  "SELECT COUNT(*) FROM transcript_entries;"

# Restore if needed
make db-restore
```

### Manual Database Inspection

```bash
# Connect to current database
sqlite3 ~/Library/Application\ Support/Contextify/transcripts.db

# Useful queries
.tables
SELECT COUNT(*) FROM transcripts;
SELECT COUNT(*) FROM transcript_entries;
SELECT id, provider, line_count FROM transcripts LIMIT 5;
.quit
```

## Troubleshooting

### "database is locked" Errors

**Cause:** App is running with database open

**Fix:**
```bash
# Quit app first
pkill -9 Contextify
sleep 2

# Then perform database operation
./scripts/db_manager.sh backup
```

### "vnode unlinked while in use" Errors

**Cause:** Database files were deleted while app was running

**Fix:**
1. Quit app completely: `pkill -9 Contextify`
2. Remove corrupted files: `rm ~/Library/Application\ Support/Contextify/transcripts.db*`
3. Restore from backup: `./scripts/db_manager.sh restore latest`
4. Restart app

### Missing Backups

**Cause:** `build/db-backups/` directory doesn't exist or was deleted

**Fix:**
```bash
# Directory will be created automatically
make db-backup
```

## Agent Guidelines

When working with the database:

1. **NEVER** run `rm` commands on database files
2. **ALWAYS** use `scripts/db_manager.sh` for operations
3. **ALWAYS** ask user before running `clean-db`
4. **ALWAYS** create backups before making significant changes
5. **ALWAYS** quit the app before database operations

### Example Agent Workflow

```
User: "Clean the database for testing"

Agent: "I'll create a backup and clean the database for you.
        This will delete the current database (with automatic backup).

        Shall I proceed with:
        1. Creating backup
        2. Cleaning database

        You can restore anytime with 'make db-restore'"

[User approves]

Agent: [runs: make clean-db]
```

## Technical Details

### Why WAL Mode?

Contextify uses SQLite's Write-Ahead Logging (WAL) mode for:
- Better concurrency (readers don't block writers)
- Crash safety (atomic commits)
- Better performance for concurrent access

This creates additional files (`-wal`, `-shm`) that must be backed up together.

### Backup File Naming

Format: `transcripts.db-YYYYMMDD-HHMMSS`

Example: `transcripts.db-20251019-091406`
- Date: 2025-10-19
- Time: 09:14:06

### Automatic Backup Retention

The script does **not** automatically delete old backups. Manage manually:

```bash
# List all backups
ls -lh build/db-backups/

# Delete old backups (manually)
rm build/db-backups/transcripts.db-20251018-*
```

## See Also

- `CLAUDE.md` - Project instructions (includes database management section)
- `scripts/db_manager.sh` - Database management script source
- `Makefile` - Make targets for database operations
