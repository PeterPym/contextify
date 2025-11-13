# Database Location Discovery

**IMPORTANT:** Users can customize the database location via Settings > Database tab. ALWAYS check for custom location before querying the database.

## Location Precedence

1. **Custom location** (if set by user): Check UserDefaults for custom path, or query the running app
2. **Default location**: `~/Library/Application Support/Contextify/contextify.db`
3. **Sandboxed container** (if sandbox enabled): `~/Library/Containers/PeterPym.Contextify*/Data/Library/Application Support/Contextify/contextify.db`

## How to Find the Active Database

### Method 1: Check UserDefaults for Custom Location (RECOMMENDED)

```bash
CUSTOM_DIR=$(defaults read dev.contextify dev.contextify.customDatabaseLocation 2>/dev/null)
if [ -n "$CUSTOM_DIR" ]; then
  DB_PATH="$CUSTOM_DIR/contextify.db"
  echo "Custom location: $DB_PATH"
else
  echo "Default location: ~/Library/Application Support/Contextify/contextify.db"
  DB_PATH="$HOME/Library/Application Support/Contextify/contextify.db"
fi
```

### Method 2: Find All Databases and Use Most Recently Modified

```bash
find ~/Library -name "contextify.db" -type f 2>/dev/null -exec ls -lt {} + | head -1
```

### Method 3: Check All Common Locations

```bash
find ~/Library/Application\ Support/Contextify -name "contextify.db" 2>/dev/null
find ~/Library/Containers -name "contextify.db" 2>/dev/null
find ~/Library/CloudStorage -name "contextify.db" 2>/dev/null  # Dropbox/iCloud
```

## Common Custom Locations

- **Dropbox:** `~/Library/CloudStorage/Dropbox/*/contextify.db`
- **iCloud Drive:** `~/Library/Mobile Documents/com~apple~CloudDocs/*/contextify.db`
- **External drive:** `/Volumes/*/contextify.db`

## Important Notes

**When users change database locations:**
- The old database file remains in place (not deleted)
- Always use the most recently modified database file
- Migration preserves all data (copies db, wal, shm files)
- Multi-machine conflict detection warns of concurrent access

**For database management commands:**
- See `build/docs/guides/DEVELOPMENT.md` (Database Management section)
- Always use `scripts/db_manager.sh` for operations (NEVER manual `rm`)
