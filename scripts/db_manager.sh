#!/bin/bash
# Database Management Script for Contextify
# Handles backup, restore, and safe deletion of transcript database
# Features:
#   - Automatic discovery of active database location (UserDefaults + default)
#   - Validates recent writes before cleanup (prevents stale DB accidents)
#   - Creates automatic backups before destructive operations
# Usage: ./scripts/db_manager.sh <command> [flags] [db-path]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DB_NAME="contextify.db"
BACKUP_DIR="$(pwd)/build/db-backups"
APP_NAME="Contextify"
FORCE_STALE=false

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Discover active database location
discover_database_path() {
    # Method 1: Check UserDefaults for custom location
    local custom_dir=$(defaults read dev.contextify dev.contextify.customDatabaseLocation 2>/dev/null)
    if [ -n "$custom_dir" ]; then
        echo "$custom_dir/$DB_NAME"
        return 0
    fi

    # Method 2: Default location
    echo "$HOME/Library/Application Support/Contextify/$DB_NAME"
}

# Validate database has recent writes (within last minute)
validate_recent_writes() {
    local db_path="$1"

    if [ ! -f "$db_path" ]; then
        print_error "Database not found: $db_path"
        return 1
    fi

    # Get last modified time (seconds since epoch)
    local last_modified=$(stat -f "%m" "$db_path" 2>/dev/null)
    local current_time=$(date +%s)
    local age_seconds=$((current_time - last_modified))

    # Check if modified within last 60 seconds
    if [ $age_seconds -gt 60 ]; then
        local age_minutes=$((age_seconds / 60))
        print_error "Database has not been written to in the last minute"
        print_info "Last modified: $age_minutes minutes ago"
        print_info "Database path: $db_path"
        echo
        print_warning "This may not be the active database!"
        print_info "Possible reasons:"
        print_info "  1. User has set a custom database location in Settings"
        print_info "  2. App is using a different database (sandboxed container)"
        print_info "  3. Database is genuinely inactive"
        echo
        print_info "To verify the correct database location:"
        print_info "  1. Check: defaults read dev.contextify dev.contextify.customDatabaseLocation"
        print_info "  2. Find all: find ~/Library -name \"contextify.db\" -type f 2>/dev/null"
        print_info "  3. Use --force to clean this database anyway"
        echo
        return 1
    fi

    print_success "Database has recent writes (last modified: $age_seconds seconds ago)"
    return 0
}

# Parse database path argument or discover automatically
DB_PATH=""
parse_db_path_arg() {
    if [ -n "$1" ] && [ -f "$1" ]; then
        DB_PATH="$1"
        DB_DIR=$(dirname "$DB_PATH")
    else
        DB_PATH=$(discover_database_path)
        DB_DIR=$(dirname "$DB_PATH")
    fi

    print_info "Using database: $DB_PATH"
}

# Helper functions
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if app is running
is_app_running() {
    pgrep -x "$APP_NAME" > /dev/null 2>&1
    return $?
}

# Kill app safely
quit_app() {
    if is_app_running; then
        print_info "Quitting $APP_NAME..."
        pkill -TERM "$APP_NAME" 2>/dev/null || true
        sleep 2

        # Force kill if still running
        if is_app_running; then
            print_warning "Force killing $APP_NAME..."
            pkill -9 "$APP_NAME" 2>/dev/null || true
            sleep 1
        fi

        print_success "App closed"
    else
        print_info "App is not running"
    fi
}

# Create backup
backup_database() {
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup_name="${DB_NAME}-${timestamp}"
    local backup_path="$BACKUP_DIR/$backup_name"

    if [ ! -f "$DB_PATH" ]; then
        print_error "Database not found at: $DB_PATH"
        return 1
    fi

    print_info "Creating backup: $backup_name"

    # Quit app first
    quit_app

    # Copy database and WAL files
    cp "$DB_PATH" "$backup_path" 2>/dev/null || {
        print_error "Failed to backup database"
        return 1
    }

    # Copy WAL and SHM files if they exist
    if [ -f "$DB_PATH-wal" ]; then
        cp "$DB_PATH-wal" "$backup_path-wal" 2>/dev/null || true
    fi
    if [ -f "$DB_PATH-shm" ]; then
        cp "$DB_PATH-shm" "$backup_path-shm" 2>/dev/null || true
    fi

    # Get file size
    local size=$(du -h "$backup_path" | cut -f1)

    print_success "Backup created: $backup_name ($size)"
    print_info "Location: $backup_path"

    # Show entry count
    if command -v sqlite3 &> /dev/null; then
        local entry_count=$(sqlite3 "$backup_path" "SELECT COUNT(*) FROM transcript_entries;" 2>/dev/null || echo "unknown")
        local transcript_count=$(sqlite3 "$backup_path" "SELECT COUNT(*) FROM transcripts;" 2>/dev/null || echo "unknown")
        print_info "Contains: $transcript_count transcripts, $entry_count entries"
    fi

    echo "$backup_path"
}

# Clean database (with automatic backup)
clean_database() {
    print_warning "⚠️  DATABASE CLEANUP REQUESTED ⚠️"
    echo

    if [ ! -f "$DB_PATH" ]; then
        print_info "Database does not exist, nothing to clean"
        return 0
    fi

    # Validate recent writes (unless --force flag is set)
    if [ "$FORCE_STALE" != "true" ]; then
        if ! validate_recent_writes "$DB_PATH"; then
            print_error "Aborting cleanup due to stale database"
            print_info "To clean anyway, use: $0 clean --force [db-path]"
            return 1
        fi
        echo
    else
        print_warning "Forcing cleanup of potentially stale database"
        echo
    fi

    # Show current database stats
    if command -v sqlite3 &> /dev/null; then
        local entry_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM transcript_entries;" 2>/dev/null || echo "unknown")
        local transcript_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM transcripts;" 2>/dev/null || echo "unknown")
        print_info "Current database: $transcript_count transcripts, $entry_count entries"
    fi

    # Create backup first
    print_info "Creating automatic backup before cleanup..."
    local backup_path=$(backup_database)
    if [ $? -ne 0 ]; then
        print_error "Backup failed, aborting cleanup"
        return 1
    fi

    echo
    print_warning "This will delete the current database!"
    print_info "A backup has been saved at: $backup_path"

    # Remove database files
    print_info "Removing database files..."
    rm -f "$DB_PATH" "$DB_PATH-wal" "$DB_PATH-shm" 2>/dev/null || true

    print_success "Database cleaned"
    print_info "Next app launch will create a fresh database"
    print_info "To restore this backup, run: ./scripts/db_manager.sh restore latest"
}

# List backups
list_backups() {
    print_info "Available database backups:"
    echo

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        print_warning "No backups found"
        return 0
    fi

    local count=1
    for backup in "$BACKUP_DIR"/${DB_NAME}-*; do
        # Skip WAL and SHM files
        [[ "$backup" =~ -wal$ ]] && continue
        [[ "$backup" =~ -shm$ ]] && continue
        [ ! -f "$backup" ] && continue

        local filename=$(basename "$backup")
        local timestamp=${filename#${DB_NAME}-}
        local size=$(du -h "$backup" | cut -f1)
        local date=$(date -j -f "%Y%m%d-%H%M%S" "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp")

        # Get stats if sqlite3 available
        local stats=""
        if command -v sqlite3 &> /dev/null; then
            local entries=$(sqlite3 "$backup" "SELECT COUNT(*) FROM transcript_entries;" 2>/dev/null || echo "?")
            local transcripts=$(sqlite3 "$backup" "SELECT COUNT(*) FROM transcripts;" 2>/dev/null || echo "?")
            stats=" | $transcripts transcripts, $entries entries"
        fi

        printf "${GREEN}%2d.${NC} %s | %s | %s%s\n" "$count" "$date" "$size" "$filename" "$stats"
        count=$((count + 1))
    done
}

# Restore database
restore_database() {
    local selection="$1"

    if [ -z "$selection" ]; then
        print_error "Please specify which backup to restore (latest, or backup filename)"
        echo "Run './scripts/db_manager.sh list' to see available backups"
        return 1
    fi

    local backup_to_restore=""

    if [ "$selection" = "latest" ]; then
        # Find most recent backup
        backup_to_restore=$(ls -t "$BACKUP_DIR"/${DB_NAME}-* 2>/dev/null | grep -v -- "-wal$" | grep -v -- "-shm$" | head -1)
        if [ -z "$backup_to_restore" ]; then
            print_error "No backups found"
            return 1
        fi
        print_info "Selected latest backup: $(basename "$backup_to_restore")"
    else
        # Use specific backup
        if [[ "$selection" =~ ^${DB_NAME}- ]]; then
            backup_to_restore="$BACKUP_DIR/$selection"
        else
            backup_to_restore="$BACKUP_DIR/${DB_NAME}-${selection}"
        fi

        if [ ! -f "$backup_to_restore" ]; then
            print_error "Backup not found: $backup_to_restore"
            echo "Run './scripts/db_manager.sh list' to see available backups"
            return 1
        fi
    fi

    print_warning "⚠️  DATABASE RESTORE REQUESTED ⚠️"
    echo

    # Backup current database if it exists
    if [ -f "$DB_PATH" ]; then
        print_info "Current database will be backed up before restore"
        backup_database
        echo
    fi

    # Quit app
    quit_app

    # Restore database
    print_info "Restoring from: $(basename "$backup_to_restore")"
    cp "$backup_to_restore" "$DB_PATH" || {
        print_error "Failed to restore database"
        return 1
    }

    # Restore WAL and SHM if they exist
    if [ -f "$backup_to_restore-wal" ]; then
        cp "$backup_to_restore-wal" "$DB_PATH-wal" 2>/dev/null || true
    fi
    if [ -f "$backup_to_restore-shm" ]; then
        cp "$backup_to_restore-shm" "$DB_PATH-shm" 2>/dev/null || true
    fi

    print_success "Database restored"

    # Show restored stats
    if command -v sqlite3 &> /dev/null; then
        local entries=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM transcript_entries;" 2>/dev/null || echo "?")
        local transcripts=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM transcripts;" 2>/dev/null || echo "?")
        print_info "Restored: $transcripts transcripts, $entries entries"
    fi
}

# Force re-ingestion of specific transcript
reingest_transcript() {
    local transcript_id="$1"

    if [ -z "$transcript_id" ]; then
        print_error "Please provide a transcript ID"
        echo "Usage: ./scripts/db_manager.sh reingest <transcript-id>"
        return 1
    fi

    if [ ! -f "$DB_PATH" ]; then
        print_error "Database not found at: $DB_PATH"
        return 1
    fi

    # Create backup first
    print_info "Creating backup before re-ingestion..."
    backup_database > /dev/null
    if [ $? -ne 0 ]; then
        print_error "Backup failed, aborting re-ingestion"
        return 1
    fi

    # Quit app
    quit_app

    # Check if transcript exists
    local exists=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM transcripts WHERE id = '$transcript_id';" 2>/dev/null)
    if [ "$exists" = "0" ]; then
        print_error "Transcript not found: $transcript_id"
        return 1
    fi

    # Get transcript info
    local file_path=$(sqlite3 "$DB_PATH" "SELECT file_path FROM transcripts WHERE id = '$transcript_id';" 2>/dev/null)
    local entry_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id = '$transcript_id';" 2>/dev/null)

    print_info "Transcript: $transcript_id"
    print_info "File: $file_path"
    print_info "Current entries: $entry_count"

    # Reset checkpoint and delete entries
    print_info "Resetting transcript checkpoint..."
    sqlite3 "$DB_PATH" "
        UPDATE transcripts
        SET last_processed_line = 0, line_count = 0, status = 'active'
        WHERE id = '$transcript_id';

        DELETE FROM transcript_entries WHERE transcript_id = '$transcript_id';
    " 2>/dev/null

    print_success "Transcript reset for re-ingestion"
    print_info "Relaunch app to start re-ingestion"
}

# Show usage
show_usage() {
    cat <<EOF
Database Management Script for Contextify

Usage:
  ./scripts/db_manager.sh <command> [flags] [db-path]

Commands:
  backup [db-path]        Create a backup of the database
  clean [db-path]         Delete database (creates backup first, validates recent writes)
  restore <name>          Restore a backup (use 'latest' for most recent)
  reingest <transcript>   Force re-ingestion of a specific transcript
  list                    List all available backups

Flags:
  --force                 Skip recent write validation (for clean command)

Database Path:
  If not specified, automatically discovers active database by checking:
  1. Custom location from UserDefaults (dev.contextify.customDatabaseLocation)
  2. Default location (~/Library/Application Support/Contextify/contextify.db)

Examples:
  # Automatic database discovery (recommended)
  ./scripts/db_manager.sh backup
  ./scripts/db_manager.sh clean

  # Explicit database path
  ./scripts/db_manager.sh clean /path/to/custom/contextify.db

  # Force clean a stale database
  ./scripts/db_manager.sh clean --force /path/to/old/contextify.db

  # Other operations
  ./scripts/db_manager.sh restore latest
  ./scripts/db_manager.sh reingest 6D02C1B5-6F6D-40E0-B550-DC69DFB8BCCF
  ./scripts/db_manager.sh list

Safety Features:
  - Automatic discovery of active database location
  - Validates database has been written to in the last 60 seconds
  - Prevents accidental cleanup of stale/inactive databases
  - Creates automatic backups before destructive operations
  - App is automatically closed before database operations

Notes:
  - Backups are stored in: build/db-backups/
  - Users can set custom database locations in Settings > Database tab
  - Use 'defaults read dev.contextify dev.contextify.customDatabaseLocation' to check

⚠️  IMPORTANT: Always use this script for database operations. Never delete
    database files manually while the app is running.

EOF
}

# Main script
main() {
    local command="$1"
    shift || true

    # Parse flags
    while [[ "$1" == --* ]]; do
        case "$1" in
            --force)
                FORCE_STALE=true
                shift
                ;;
            *)
                print_error "Unknown flag: $1"
                exit 1
                ;;
        esac
    done

    # Parse database path (optional, for clean/backup/restore/reingest)
    local db_path_arg=""
    case "$command" in
        clean|backup|restore|reingest)
            db_path_arg="$1"
            parse_db_path_arg "$db_path_arg"
            shift || true
            ;;
    esac

    case "$command" in
        backup)
            backup_database
            ;;
        clean)
            clean_database
            ;;
        restore)
            restore_database "$@"
            ;;
        reingest)
            reingest_transcript "$@"
            ;;
        list)
            list_backups
            ;;
        --help|help|-h|"")
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            echo
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
